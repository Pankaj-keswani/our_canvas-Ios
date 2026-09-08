import Foundation
import SwiftUI
import UIKit
import CoreGraphics

/// One logical undoable editing operation.
enum DrawingOperation {
    case addStroke(Stroke)
    case addElement(CanvasElement)
    case removeElement(CanvasElement)
    case updateElement(before: CanvasElement, after: CanvasElement)
    case clearAll(strokes: [Stroke], elements: [CanvasElement])
}

/// The drawing document engine: single source of truth for tool state, strokes,
/// elements, background, undo/redo and the committed ink bitmap.
///
/// Rendering model (layer architecture):
///   background image  ←  ink bitmap (transparent; eraser is destination-out here only)
///   ← live stroke preview  ← element overlay (SwiftUI)
@MainActor
final class DrawingEngine: ObservableObject {

    // MARK: Configuration

    let canvasSize: CGSize
    var inkPixelSize: Int
    var previewPixelSize: Int

    // MARK: Tool state (SINGLE source of truth)

    @Published var tool: Tool = .brush(.basic)
    @Published var strokeColorARGB: Int = 0xFF000000
    @Published var strokeWidth: CGFloat = 12

    // MARK: Document

    @Published private(set) var strokes: [Stroke] = []
    @Published private(set) var stickers: [StickerElement] = []
    @Published private(set) var texts: [TextElement] = []
    @Published var background: DrawingBackground = .default
    @Published var selectedElementID: UUID?

    // MARK: Derived rendering state

    @Published private(set) var inkImage: UIImage?
    @Published private(set) var liveStrokeImage: UIImage?
    @Published private(set) var backgroundImage: UIImage

    private(set) var liveStroke: Stroke?

    /// Live stroke observer (Co-Draw streaming): fired on every point batch and once
    /// on completion with `finished == true`.
    var onStrokeProgress: ((Stroke, Bool) -> Void)?

    private var ink: InkCanvas
    private var undoStack: [DrawingOperation] = []
    private var redoStack: [DrawingOperation] = []
    private var lastSelectedBrush: BrushType = .basic

    init(canvasSize: CGSize = CGSize(width: 1080, height: 1080),
         inkPixelSize: Int = 1080,
         previewPixelSize: Int = 720) {
        self.canvasSize = canvasSize
        self.inkPixelSize = inkPixelSize
        self.previewPixelSize = previewPixelSize
        self.ink = InkCanvas(pixelSize: inkPixelSize, canvasSize: canvasSize)
        self.backgroundImage = StrokeRenderer.renderBackgroundImage(.default,
                                                                    canvasSize: canvasSize,
                                                                    outputPixels: previewPixelSize)
    }

    // MARK: - Tool state helpers (regression-tested against the Android bug class)

    var selectedBrush: BrushType? { tool.selectedBrush }
    var isEraserActive: Bool { tool.isEraser }

    func selectBrush(_ brush: BrushType) {
        lastSelectedBrush = brush
        tool = .brush(brush)
    }

    func setEraser(active: Bool) {
        if active {
            tool = .eraser
        } else if case .eraser = tool {
            // Restore the brush that was active before erasing (never a contradictory state).
            tool = .brush(lastSelectedBrush)
        }
    }

    func toggleEraser() {
        setEraser(active: !tool.isEraser)
    }

    // MARK: - Stroke input

    func beginStroke(at point: CGPoint) {
        var stroke = Stroke()
        stroke.points = [point]
        stroke.brush = tool.brushForStroke
        stroke.width = strokeWidth
        stroke.color = strokeColorARGB
        liveStroke = stroke
        renderLiveStroke()
    }

    func extendStroke(to point: CGPoint) {
        guard var stroke = liveStroke, let last = stroke.points.last else { return }
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard sqrt(dx * dx + dy * dy) > 2 else { return }
        stroke.points.append(point)
        liveStroke = stroke
        renderLiveStroke()
        onStrokeProgress?(stroke, false)
    }

    func endStroke() {
        guard let stroke = liveStroke else { return }
        liveStroke = nil
        liveStrokeImage = nil
        onStrokeProgress?(stroke, true)
        apply(.addStroke(stroke))
    }

    func cancelStroke() {
        liveStroke = nil
        liveStrokeImage = nil
    }

    private func renderLiveStroke() {
        guard let stroke = liveStroke else {
            liveStrokeImage = nil
            return
        }
        // Android parity: eraser strokes are NOT live-previewed.
        if stroke.isEraser {
            liveStrokeImage = nil
            return
        }
        liveStrokeImage = StrokeRenderer.renderStrokeImage(stroke,
                                                           canvasSize: canvasSize,
                                                           outputPixels: previewPixelSize)
    }

    // MARK: - Elements

    func addSticker(_ sticker: StickerElement) {
        apply(.addElement(.sticker(sticker)))
        selectedElementID = sticker.id
    }

    func addText(_ text: TextElement) {
        apply(.addElement(.text(text)))
        selectedElementID = text.id
    }

    func selectElement(id: UUID?) {
        selectedElementID = id
    }

    func updateElement(_ updated: CanvasElement) {
        guard let before = element(id: updated.id) else { return }
        apply(.updateElement(before: before, after: updated))
    }

    /// Live (no-undo-yet) element mutation during an active gesture; the engine
    /// remembers the pre-gesture element so `commitElementUpdate()` can record
    /// one logical undo operation for the whole gesture.
    func liveUpdateElement(_ updated: CanvasElement) {
        if pendingElementBefore == nil, let current = element(id: updated.id) {
            pendingElementBefore = current
        }
        replaceElement(updated)
    }

    func commitElementUpdate() {
        guard let before = pendingElementBefore else { return }
        pendingElementBefore = nil
        if let after = element(id: before.id), before != after {
            apply(.updateElement(before: before, after: after))
        }
    }

    private var pendingElementBefore: CanvasElement?

    func deleteElement(id: UUID) {
        guard let element = element(id: id) else { return }
        apply(.removeElement(element))
        if selectedElementID == id {
            selectedElementID = nil
        }
    }

    func element(id: UUID) -> CanvasElement? {
        if let sticker = stickers.first(where: { $0.id == id }) {
            return .sticker(sticker)
        }
        if let text = texts.first(where: { $0.id == id }) {
            return .text(text)
        }
        return nil
    }

    var allElements: [CanvasElement] {
        stickers.map { CanvasElement.sticker($0) } + texts.map { CanvasElement.text($0) }
    }

    /// Hit-test an element near a CANVAS-UNIT point (used to avoid starting strokes on elements).
    func element(at canvasPoint: CGPoint) -> CanvasElement? {
        let threshold: CGFloat = 140
        for element in allElements.reversed() {
            let position = element.canvasPosition
            let dx = canvasPoint.x - position.x
            let dy = canvasPoint.y - position.y
            if sqrt(dx * dx + dy * dy) < threshold {
                return element
            }
        }
        return nil
    }

    // MARK: - Co-Draw remote stroke integration
    // Remote strokes join the document WITHOUT local undo entries — synchronized
    // undo/clear arrive as broadcast operations instead.

    func appendRemoteStroke(_ stroke: Stroke) {
        strokes.append(stroke)
        ink.add(stroke)
        inkImage = ink.image
    }

    /// Removes the latest stroke owned by `ownerId` (nil owner = any) — used when a
    /// remote participant broadcasts an undo. No local undo entry is recorded.
    func removeLastStroke(ownerId: String?) {
        guard let index = strokes.lastIndex(where: { $0.ownerId == ownerId }) else { return }
        strokes.remove(at: index)
        rebuildInkAfterModelChange()
    }

    /// Applies a remote clear broadcast without touching the local undo history.
    func applyRemoteClear() {
        strokes.removeAll()
        rebuildInkAfterModelChange()
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let operation = undoStack.popLast() else { return }
        revert(operation)
        redoStack.append(operation)
        rebuildInkAfterModelChange()
    }

    func redo() {
        guard let operation = redoStack.popLast() else { return }
        perform(operation)
        undoStack.append(operation)
        publishInk(after: operation)
    }

    func clearAll() {
        guard !strokes.isEmpty || !stickers.isEmpty || !texts.isEmpty else { return }
        apply(.clearAll(strokes: strokes, elements: allElements))
    }

    private func apply(_ operation: DrawingOperation) {
        perform(operation)
        undoStack.append(operation)
        redoStack.removeAll()
        publishInk(after: operation)
    }

    private func perform(_ operation: DrawingOperation) {
        switch operation {
        case .addStroke(let stroke):
            strokes.append(stroke)
            ink.add(stroke)
        case .addElement(let element):
            insertElement(element)
        case .removeElement(let element):
            removeElement(element)
        case .updateElement(_, let after):
            replaceElement(after)
        case .clearAll:
            strokes.removeAll()
            stickers.removeAll()
            texts.removeAll()
        }
    }

    private func revert(_ operation: DrawingOperation) {
        switch operation {
        case .addStroke(let stroke):
            if let index = strokes.firstIndex(where: { $0 == stroke }) {
                strokes.remove(at: index)
            } else {
                strokes.removeLast()
            }
        case .addElement(let element):
            removeElement(element)
        case .removeElement(let element):
            insertElement(element)
        case .updateElement(let before, _):
            replaceElement(before)
        case .clearAll(let previousStrokes, let previousElements):
            strokes = previousStrokes
            stickers = []
            texts = []
            for element in previousElements {
                insertElement(element)
            }
        }
    }

    /// Ink compositing policy: addStroke is incremental (already drawn in `perform`);
    /// any other model mutation rebuilds the ink layer from the model so undo/redo/clear
    /// stay exactly consistent with the data.
    private func publishInk(after operation: DrawingOperation) {
        if case .addStroke = operation {
            inkImage = ink.image
        } else {
            rebuildInkAfterModelChange()
        }
    }

    private func rebuildInkAfterModelChange() {
        ink.reset(with: strokes)
        inkImage = ink.image
    }

    private func insertElement(_ element: CanvasElement) {
        switch element {
        case .sticker(let sticker): stickers.append(sticker)
        case .text(let text): texts.append(text)
        }
    }

    private func removeElement(_ element: CanvasElement) {
        switch element {
        case .sticker(let sticker):
            if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
                stickers.remove(at: index)
            }
        case .text(let text):
            if let index = texts.firstIndex(where: { $0.id == text.id }) {
                texts.remove(at: index)
            }
        }
    }

    private func replaceElement(_ element: CanvasElement) {
        switch element {
        case .sticker(let sticker):
            if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
                stickers[index] = sticker
            }
        case .text(let text):
            if let index = texts.firstIndex(where: { $0.id == text.id }) {
                texts[index] = text
            }
        }
    }

    // MARK: - Background

    func updateBackground(_ newBackground: DrawingBackground) {
        background = newBackground
        backgroundImage = StrokeRenderer.renderBackgroundImage(newBackground,
                                                               canvasSize: canvasSize,
                                                               outputPixels: previewPixelSize)
    }

    // MARK: - Serialization

    var encodedStrokeData: String {
        StrokeSerializer.encode(strokes: strokes, background: background, canvasSize: canvasSize)
    }

    var encodedStickerData: String {
        StrokeSerializer.encodeStickers(stickers)
    }

    var encodedTextData: String {
        StrokeSerializer.encodeTexts(texts)
    }

    // MARK: - Export

    func exportCompositePNG() -> UIImage {
        StrokeRenderer.renderComposite(background: background,
                                       strokes: strokes,
                                       stickers: stickers,
                                       texts: texts,
                                       canvasSize: canvasSize,
                                       outputPixels: Int(canvasSize.width))
    }

    /// Android send-path parity: PNG base64 (fixture-verified against DrawingRepository.kt).
    func exportCompositePNGBase64() -> String? {
        let image = exportCompositePNG()
        guard let data = image.pngData() else { return nil }
        return data.base64EncodedString()
    }

    func exportCompositeJPEGBase64(quality: CGFloat = 0.85) -> String? {
        let image = exportCompositePNG()
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        return data.base64EncodedString()
    }

    // MARK: - Restoration (edit existing drawing)

    func load(strokes newStrokes: [Stroke],
              stickers newStickers: [StickerElement],
              texts newTexts: [TextElement],
              background newBackground: DrawingBackground,
              canvasSize newCanvasSize: CGSize) {
        cancelStroke()
        undoStack.removeAll()
        redoStack.removeAll()
        strokes = newStrokes
        stickers = newStickers
        texts = newTexts
        updateBackground(newBackground)
        ink.reset(with: newStrokes)
        inkImage = ink.image
    }
}
