import SwiftUI
import UIKit

/// The editor canvas: background + committed ink + live stroke preview + element overlay.
/// All drawing state lives in `DrawingEngine`; this view only projects it and routes gestures.
struct DrawingCanvasView: View {
    @ObservedObject var engine: DrawingEngine
    var onElementTapped: ((UUID) -> Void)?

    @State private var draggingElementID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image(uiImage: engine.backgroundImage)
                    .resizable()
                    .scaledToFit()

                SwiftUI.Group {
                    if let ink = engine.inkImage {
                        Image(uiImage: ink)
                            .resizable()
                            .scaledToFit()
                    }
                    if let live = engine.liveStrokeImage {
                        Image(uiImage: live)
                            .resizable()
                            .scaledToFit()
                    }
                }

                elementOverlay(size: size)
            }
            .contentShape(Rectangle())
            .gesture(canvasDragGesture(size: size))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white)
        .clipped()
    }

    // MARK: - Canvas stroke gesture

    private func canvasDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let canvasPoint = toCanvasUnits(value.location, size: size)
                // Never start a stroke on top of an element (element gestures own it).
                if engine.liveStroke == nil, engine.element(at: canvasPoint) != nil {
                    return
                }
                if engine.liveStroke == nil {
                    engine.beginStroke(at: canvasPoint)
                } else {
                    engine.extendStroke(to: canvasPoint)
                }
            }
            .onEnded { _ in
                engine.endStroke()
            }
    }

    private func toCanvasUnits(_ point: CGPoint, size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = engine.canvasSize.width / size.width
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    // MARK: - Element overlay

    @ViewBuilder
    private func elementOverlay(size: CGSize) -> some View {
        let side = min(size.width, size.height)
        ForEach(engine.stickers) { sticker in
            StickerElementView(sticker: sticker,
                               displaySize: side,
                               isSelected: engine.selectedElementID == sticker.id)
                .modifier(ElementGestureModifier(engine: engine,
                                                 element: .sticker(sticker),
                                                 displaySize: side,
                                                 isDragging: $draggingElementID))
                .onTapGesture { onElementTapped?(sticker.id) }
        }
        ForEach(engine.texts) { text in
            TextElementView(text: text,
                            displaySize: side,
                            isSelected: engine.selectedElementID == text.id)
                .modifier(ElementGestureModifier(engine: engine,
                                                 element: .text(text),
                                                 displaySize: side,
                                                 isDragging: $draggingElementID))
                .onTapGesture { onElementTapped?(text.id) }
        }
    }
}

// MARK: - Element views

struct StickerElementView: View {
    let sticker: StickerElement
    let displaySize: CGFloat
    let isSelected: Bool

    var body: some View {
        let fontPointSize = StrokeRenderer.stickerBaseFontSize * sticker.scale * (displaySize / 1080.0)
        return Text(sticker.emoji)
            .font(.system(size: max(8, fontPointSize)))
            .rotationEffect(.radians(sticker.rotation))
            .selectionOverlay(isSelected: isSelected)
            .position(x: sticker.x * displaySize, y: sticker.y * displaySize)
    }
}

struct TextElementView: View {
    let text: TextElement
    let displaySize: CGFloat
    let isSelected: Bool

    var body: some View {
        let fontPointSize = text.fontSize * text.scale * (displaySize / 1080.0)
        let comps = StrokeColor.components(ofARGB: text.color)
        return Text(text.text)
            .font(.system(size: max(8, fontPointSize), weight: .semibold))
            .foregroundColor(Color(red: comps.r, green: comps.g, blue: comps.b))
            .rotationEffect(.radians(text.rotation))
            .selectionOverlay(isSelected: isSelected)
            .position(x: text.x * displaySize, y: text.y * displaySize)
    }
}

private extension View {
    func selectionOverlay(isSelected: Bool) -> some View {
        self
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? BrandColor.primary : .clear, lineWidth: 2)
            )
    }
}

// MARK: - Element gestures (drag / pinch / rotate + delete handle)

private struct ElementGestureModifier: ViewModifier {
    @ObservedObject var engine: DrawingEngine
    let element: CanvasElement
    let displaySize: CGFloat
    @Binding var isDragging: UUID?

    @State private var dragStart: CGPoint = .zero
    @State private var elementStart: CGPoint = .zero
    @State private var pinchStartScale: CGFloat = 0
    @State private var rotationStartAngle: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if engine.selectedElementID == element.id {
                    Button {
                        engine.deleteElement(id: element.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .offset(x: 14, y: -14)
                }
            }
            .gesture(dragGesture.simultaneously(with: magnifyGesture)
                .simultaneously(with: rotateGesture))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if isDragging == nil {
                    isDragging = element.id
                    engine.selectElement(id: element.id)
                    dragStart = value.startLocation
                    elementStart = element.normalizedPosition
                }
                guard isDragging == element.id else { return }
                let dx = (value.location.x - dragStart.x) / displaySize
                let dy = (value.location.y - dragStart.y) / displaySize
                updatePosition(x: elementStart.x + dx, y: elementStart.y + dy)
            }
            .onEnded { _ in
                if isDragging == element.id {
                    isDragging = nil
                    engine.commitElementUpdate()
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchStartScale == 0 {
                    pinchStartScale = elementScale
                }
                updateScale(pinchStartScale * value)
            }
            .onEnded { _ in
                pinchStartScale = 0
                engine.commitElementUpdate()
            }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                if rotationStartAngle < 0 {
                    rotationStartAngle = elementRotation
                }
                updateRotation(rotationStartAngle + value.radians)
            }
            .onEnded { _ in
                rotationStartAngle = -1
                engine.commitElementUpdate()
            }
    }

    // MARK: live transform updates (undo recorded once per gesture by the engine)

    private var elementScale: CGFloat {
        switch element {
        case .sticker(let s): return s.scale
        case .text(let t): return t.scale
        }
    }

    private var elementRotation: CGFloat {
        switch element {
        case .sticker(let s): return s.rotation
        case .text(let t): return t.rotation
        }
    }

    private func updatePosition(x: CGFloat, y: CGFloat) {
        let clampedX = min(max(x, 0.02), 0.98)
        let clampedY = min(max(y, 0.02), 0.98)
        switch element {
        case .sticker(let sticker):
            var updated = sticker
            updated.x = clampedX
            updated.y = clampedY
            engine.liveUpdateElement(.sticker(updated))
        case .text(let text):
            var updated = text
            updated.x = clampedX
            updated.y = clampedY
            engine.liveUpdateElement(.text(updated))
        }
    }

    private func updateScale(_ scale: CGFloat) {
        let clamped = min(max(scale, 0.25), 5)
        switch element {
        case .sticker(let sticker):
            var updated = sticker
            updated.scale = clamped
            engine.liveUpdateElement(.sticker(updated))
        case .text(let text):
            var updated = text
            updated.scale = clamped
            engine.liveUpdateElement(.text(updated))
        }
    }

    private func updateRotation(_ radians: CGFloat) {
        switch element {
        case .sticker(let sticker):
            var updated = sticker
            updated.rotation = radians
            engine.liveUpdateElement(.sticker(updated))
        case .text(let text):
            var updated = text
            updated.rotation = radians
            engine.liveUpdateElement(.text(updated))
        }
    }
}
