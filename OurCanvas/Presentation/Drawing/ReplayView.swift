import SwiftUI
import UIKit

/// Stroke-by-stroke doodle replay. Reuses the same `StrokeRenderer` as the editor and
/// export, so replay is visually identical to what was drawn. The Guess My Doodle phase
/// will reuse this exact controller — do not build a second renderer.
@MainActor
final class ReplayController: ObservableObject {

    @Published private(set) var inkImage: UIImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var isFinished = false

    let backgroundImage: UIImage
    let stickers: [StickerElement]
    let texts: [TextElement]
    let strokeCount: Int

    private let strokes: [Stroke]
    private let canvasSize: CGSize
    private let ink: InkCanvas

    init(drawing: Drawing) {
        let parsed = StrokeSerializer.decode(drawing.strokeData)
        strokes = parsed.strokes
        canvasSize = CGSize(width: parsed.canvasWidth, height: parsed.canvasHeight)
        stickers = StrokeSerializer.decodeStickers(drawing.stickerData)
        texts = StrokeSerializer.decodeTexts(drawing.textData)
        strokeCount = strokes.count
        ink = InkCanvas(pixelSize: 720, canvasSize: canvasSize)
        backgroundImage = StrokeRenderer.renderBackgroundImage(parsed.background,
                                                               canvasSize: canvasSize,
                                                               outputPixels: 720)
        inkImage = ink.image
    }

    func play() async {
        guard !isPlaying else { return }
        isPlaying = true
        isFinished = false
        ink.reset(with: [])
        inkImage = ink.image

        for stroke in strokes {
            if Task.isCancelled { break }
            ink.add(stroke)
            inkImage = ink.image
            // Per-stroke pacing proportional to point count (clamped) keeps replays
            // feeling hand-drawn without dragging on long strokes.
            let milliseconds = min(400, max(90, stroke.points.count * 12))
            try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        }

        isPlaying = false
        isFinished = !Task.isCancelled
    }

    func replay() async {
        await play()
    }
}

/// Feed replay sheet: background + progressive ink + static elements on top.
struct ReplayView: View {
    let drawing: Drawing
    @StateObject private var controller: ReplayController

    init(drawing: Drawing) {
        self.drawing = drawing
        _controller = StateObject(wrappedValue: ReplayController(drawing: drawing))
    }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Image(uiImage: controller.backgroundImage)
                        .resizable()
                        .scaledToFit()
                    Group {
                        if let ink = controller.inkImage {
                            Image(uiImage: ink)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    ForEach(controller.stickers) { sticker in
                        StickerElementView(sticker: sticker, displaySize: size, isSelected: false)
                            .allowsHitTesting(false)
                    }
                    ForEach(controller.texts) { text in
                        TextElementView(text: text, displaySize: size, isSelected: false)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(1, contentMode: .fit)

            Button {
                Task { await controller.play() }
            } label: {
                Label(controller.isPlaying ? "Replaying…" : (controller.isFinished ? "Replay Again" : "Play Replay"),
                      systemImage: "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isPlaying)
        }
        .padding()
        .navigationTitle("Doodle Replay")
        .navigationBarTitleDisplayMode(.inline)
    }
}
