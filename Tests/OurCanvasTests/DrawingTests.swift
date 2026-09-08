import XCTest
import UIKit
@testable import OurCanvas

// MARK: - A. Cross-platform stroke serialization

final class StrokeSerializationTests: XCTestCase {
    func testAllFourteenBrushIDsMatchAndroidOrder() {
        let expected: [(BrushType, Int)] = [
            (.basic, 0), (.pencil, 1), (.marker, 2), (.neon, 3),
            (.rainbow, 4), (.glow, 5), (.calligraphy, 6), (.watercolor, 7),
            (.crayon, 8), (.airbrush, 9), (.pixel, 10), (.glitter, 11),
            (.sketch, 12), (.eraser, 13),
        ]
        for (brush, id) in expected {
            XCTAssertEqual(brush.androidID, id, "\(brush.displayName) must serialize as Android id \(id)")
            XCTAssertEqual(BrushType.from(androidID: id), brush)
        }
        XCTAssertEqual(BrushType.allCases.count, 14)
    }

    func testUnknownAndroidIDFallsBackToBasic() {
        XCTAssertEqual(BrushType.from(androidID: 99), .basic)
        XCTAssertEqual(BrushType.from(androidID: -1), .basic)
    }

    func testFullRoundTripAllBrushes() {
        var strokes: [Stroke] = []
        for brush in BrushType.allCases {
            strokes.append(Stroke(points: [CGPoint(x: 100, y: 150), CGPoint(x: 200, y: 250)],
                                  color: 0xFF00FF00,
                                  width: 24,
                                  brush: brush))
        }
        let json = StrokeSerializer.encode(strokes: strokes,
                                           background: DrawingBackground(template: .dots, colorHex: "#FDF6E3"),
                                           canvasSize: CGSize(width: 1080, height: 1080))
        let parsed = StrokeSerializer.decode(json)

        XCTAssertEqual(parsed.strokes.count, 14)
        XCTAssertEqual(parsed.background.template, .dots)
        XCTAssertEqual(parsed.background.colorHex, "#FDF6E3")
        XCTAssertEqual(parsed.canvasWidth, 1080)
        XCTAssertEqual(parsed.canvasHeight, 1080)
        for (index, stroke) in parsed.strokes.enumerated() {
            XCTAssertEqual(stroke.brush, BrushType.allCases[index])
            XCTAssertEqual(stroke.color, 0xFF00FF00)
            XCTAssertEqual(stroke.width, 24)
            XCTAssertEqual(stroke.points.count, 2)
            XCTAssertEqual(stroke.points[1].x, 200)
        }
    }

    func testEraserRepresentationIsBrushID13() {
        let stroke = Stroke(points: [CGPoint(x: 1, y: 1)], color: 0, width: 40, brush: .eraser)
        let json = StrokeSerializer.encode(strokes: [stroke], background: .default, canvasSize: CGSize(width: 1080, height: 1080))
        XCTAssertTrue(json.contains("\"b\":13"))
        let parsed = StrokeSerializer.decode(json)
        XCTAssertEqual(parsed.strokes[0].brush, .eraser)
        XCTAssertTrue(parsed.strokes[0].isEraser)
    }

    func testDecodeToleratesLegacyDocuments() {
        // No bg, no cw/ch, dict-shaped points — nothing may throw.
        let legacy = "{\"strokes\":[{\"c\":-16777216,\"w\":8,\"b\":0,\"p\":[{\"x\":5,\"y\":10}]}]}"
        let parsed = StrokeSerializer.decode(legacy)
        XCTAssertEqual(parsed.canvasWidth, 1080)
        XCTAssertEqual(parsed.background, DrawingBackground.default)
        XCTAssertEqual(parsed.strokes.count, 1)
        XCTAssertEqual(parsed.strokes[0].points.first?.x ?? 0, 5)
    }

    func testColorEncodingHelpers() {
        XCTAssertEqual(StrokeColor.hexString(fromARGB: 0xFFFF0000), "#FF0000")
        XCTAssertEqual(StrokeColor.argbInt(fromHex: "#ff0000"), 0xFFFF0000)
        XCTAssertEqual(StrokeColor.argbInt(fromHex: "invalid"), 0xFF000000)
    }
}

// MARK: - B/C. Rendering: non-blank exports + eraser layer semantics

final class RenderingTests: XCTestCase {
    private func centerPixel(of image: UIImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bytesPerRow = cgImage.bytesPerRow
        let offset = (height / 2) * bytesPerRow + (width / 2) * 4
        for i in 0..<4 {
            pixel[i] = ptr[offset + i]
        }
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    func testExportedDrawingIsNotBlankWhenStrokesExist() {
        let stroke = Stroke(points: (0...40).map { CGPoint(x: 540 - 200 + CGFloat($0) * 10, y: 540) },
                            color: 0xFF000000,
                            width: 40,
                            brush: .basic)
        let image = StrokeRenderer.renderComposite(background: .default,
                                                   strokes: [stroke],
                                                   stickers: [],
                                                   texts: [],
                                                   canvasSize: CGSize(width: 1080, height: 1080),
                                                   outputPixels: 512)
        let pixel = centerPixel(of: image)
        XCTAssertNotNil(pixel)
        // A black stroke across the center on a white background must not be white.
        if let p = pixel {
            XCTAssertLessThan(p.r, 200, "Center pixel should contain ink, got r=\(p.r)")
        }
    }

    func testBlankCanvasHasNoInk() {
        let image = StrokeRenderer.renderComposite(background: .default,
                                                   strokes: [],
                                                   stickers: [],
                                                   texts: [],
                                                   canvasSize: CGSize(width: 1080, height: 1080),
                                                   outputPixels: 256)
        let pixel = centerPixel(of: image)
        if let p = pixel {
            XCTAssertGreaterThan(p.r, 240, "Empty white background should stay white")
        }
    }

    func testEraserAffectsInkOnlyBackgroundSurvives() {
        // Navy background + thick white ink stroke through the center…
        let inkStroke = Stroke(points: (0...40).map { CGPoint(x: 140 + CGFloat($0) * 20, y: 540) },
                               color: 0xFFFFFFFF,
                               width: 120,
                               brush: .basic)
        // …then an eraser stroke over exactly the same path.
        let eraser = Stroke(points: (0...40).map { CGPoint(x: 140 + CGFloat($0) * 20, y: 540) },
                            color: 0,
                            width: 120,
                            brush: .eraser)

        let background = DrawingBackground(template: .plain, colorHex: "#1A2035")

        // Ink layer alone: eraser punched through the ink → center transparent.
        guard let inkOnly = StrokeRenderer.renderInkImage(strokes: [inkStroke, eraser],
                                                           canvasSize: CGSize(width: 1080, height: 1080),
                                                           outputPixels: 256) else {
            return XCTFail("Ink bitmap rendering failed")
        }
        let inkPixel = centerPixel(of: inkOnly)
        if let p = inkPixel {
            XCTAssertEqual(p.a, 0, "Eraser must remove ink at the stroke path (got a=\(p.a))")
        }

        // Full composite: the navy BACKGROUND must be visible through the erased ink.
        // Byte-order-agnostic: navy is dark, so the darkest channel must be well under
        // white and alpha must be fully opaque.
        let composite = StrokeRenderer.renderComposite(background: background,
                                                       strokes: [inkStroke, eraser],
                                                       stickers: [],
                                                       texts: [],
                                                       canvasSize: CGSize(width: 1080, height: 1080),
                                                       outputPixels: 256)
        let compositePixel = centerPixel(of: composite)
        if let p = compositePixel {
            XCTAssertEqual(p.a, 255, "Composite must be opaque")
            let darkest = min(p.r, p.g, p.b)
            XCTAssertLessThan(darkest, 60, "Background must survive the eraser (darkest channel=\(darkest))")
            let brightest = max(p.r, p.g, p.b)
            XCTAssertLessThan(brightest, 110, "Erased area must show the dark background, not white ink")
        }
    }
}

// MARK: - D. Undo / redo + tool state machine

@MainActor
final class UndoRedoTests: XCTestCase {
    private func makeStroke(x: CGFloat) -> Stroke {
        Stroke(points: [CGPoint(x: x, y: 100), CGPoint(x: x + 50, y: 150)],
               color: 0xFF000000, width: 10, brush: .basic)
    }

    func testUndoRedoStroke() {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10))
        engine.extendStroke(to: CGPoint(x: 60, y: 60))
        engine.endStroke()
        XCTAssertEqual(engine.strokes.count, 1)

        engine.undo()
        XCTAssertEqual(engine.strokes.count, 0)
        XCTAssertTrue(engine.canRedo)

        engine.redo()
        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertFalse(engine.canRedo)
    }

    func testNewStrokeAfterUndoClearsRedo() {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10))
        engine.endStroke()
        engine.undo()
        XCTAssertTrue(engine.canRedo)

        engine.beginStroke(at: CGPoint(x: 100, y: 100))
        engine.endStroke()
        XCTAssertFalse(engine.canRedo, "New drawing after undo must clear redo history")
        XCTAssertEqual(engine.strokes.count, 1)
    }

    func testUndoEraserRestoresInk() {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10))
        engine.extendStroke(to: CGPoint(x: 100, y: 100))
        engine.endStroke()

        engine.tool = .eraser
        engine.beginStroke(at: CGPoint(x: 10, y: 10))
        engine.extendStroke(to: CGPoint(x: 100, y: 100))
        engine.endStroke()
        XCTAssertEqual(engine.strokes.count, 2)
        XCTAssertTrue(engine.strokes[1].isEraser)

        engine.undo()
        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertFalse(engine.strokes[0].isEraser)
    }

    func testClearAllIsUndoable() {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10))
        engine.endStroke()
        engine.clearAll()
        XCTAssertEqual(engine.strokes.count, 0)

        engine.undo()
        XCTAssertEqual(engine.strokes.count, 1)
    }

    func testStickerAddRemoveUndo() {
        let engine = DrawingEngine()
        let sticker = StickerElement(emoji: "⭐️", x: 0.5, y: 0.5)
        engine.addSticker(sticker)
        XCTAssertEqual(engine.stickers.count, 1)

        engine.deleteElement(id: sticker.id)
        XCTAssertEqual(engine.stickers.count, 0)

        engine.undo() // undo the removal
        XCTAssertEqual(engine.stickers.count, 1)
        engine.undo() // undo the addition
        XCTAssertEqual(engine.stickers.count, 0)
    }

    // MARK: Tool state machine (Android eraser-bug regression class)

    func testBrushToEraserToBrushB() {
        let engine = DrawingEngine()
        engine.selectBrush(.pencil)
        XCTAssertEqual(engine.tool, .brush(.pencil))

        engine.toggleEraser()
        XCTAssertEqual(engine.tool, .eraser)
        XCTAssertTrue(engine.isEraserActive)
        XCTAssertNil(engine.selectedBrush)

        // Selecting any brush MUST exit eraser mode (the Android bug class).
        engine.selectBrush(.neon)
        XCTAssertEqual(engine.tool, .brush(.neon))
        XCTAssertFalse(engine.isEraserActive)

        engine.toggleEraser()
        XCTAssertTrue(engine.isEraserActive)

        engine.setEraser(active: false)
        XCTAssertEqual(engine.tool, .brush(.neon),
                       "Exiting eraser restores the previously selected brush, never a contradictory state")
    }

    func testRepeatedTogglingKeepsStateConsistent() {
        let engine = DrawingEngine()
        engine.selectBrush(.marker)
        for _ in 0..<10 {
            engine.toggleEraser()
            XCTAssertTrue(engine.isEraserActive)
            XCTAssertEqual(engine.tool, .eraser)
            engine.toggleEraser()
            XCTAssertFalse(engine.isEraserActive)
        }
        XCTAssertEqual(engine.tool, .brush(.marker))
    }

    func testStrokeRecordsEraserToolAndBrushTool() {
        let engine = DrawingEngine()
        engine.tool = .eraser
        engine.beginStroke(at: CGPoint(x: 5, y: 5))
        engine.endStroke()
        XCTAssertEqual(engine.strokes.last?.brush, .eraser)

        engine.tool = .brush(.glitter)
        engine.beginStroke(at: CGPoint(x: 5, y: 5))
        engine.endStroke()
        XCTAssertEqual(engine.strokes.last?.brush, .glitter)
    }
}

// MARK: - E. Element serialization

final class ElementSerializationTests: XCTestCase {
    func testStickerRoundTrip() {
        var sticker = StickerElement(emoji: "🌈", x: 0.25, y: 0.75)
        sticker.scale = 1.75
        sticker.rotation = 0.6
        let json = StrokeSerializer.encodeStickers([sticker])
        let decoded = StrokeSerializer.decodeStickers(json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].emoji, "🌈")
        XCTAssertEqual(decoded[0].id, sticker.id)
        XCTAssertEqual(decoded[0].x, 0.25, accuracy: 0.001)
        XCTAssertEqual(decoded[0].y, 0.75, accuracy: 0.001)
        XCTAssertEqual(decoded[0].scale, 1.75, accuracy: 0.001)
        XCTAssertEqual(decoded[0].rotation, 0.6, accuracy: 0.001)
    }

    func testTextRoundTrip() {
        var text = TextElement(text: "Hello doodle!", color: 0xFF3B82F6, fontSize: 88)
        text.x = 0.4
        text.y = 0.6
        text.rotation = -0.3
        let json = StrokeSerializer.encodeTexts([text])
        let decoded = StrokeSerializer.decodeTexts(json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].text, "Hello doodle!")
        XCTAssertEqual(decoded[0].color, 0xFF3B82F6)
        XCTAssertEqual(decoded[0].fontSize, 88, accuracy: 0.001)
        XCTAssertEqual(decoded[0].id, text.id)
    }

    func testDecodeToleratesUnknownFieldsAndMissingKeys() {
        let json = """
        [{"e":"⭐️","futureField":true,"x":0.5},{"t":"hi","c":1}]
        """
        let stickers = StrokeSerializer.decodeStickers(json)
        XCTAssertEqual(stickers.count, 1)
        XCTAssertEqual(stickers[0].y, 0.5, accuracy: 0.001, "missing y falls back to default")

        let texts = StrokeSerializer.decodeTexts(json)
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts[0].fontSize, 72, accuracy: 0.001)
    }

    func testEmptyArraysRoundTrip() {
        XCTAssertEqual(StrokeSerializer.encodeStickers([]), "[]")
        XCTAssertEqual(StrokeSerializer.encodeTexts([]), "[]")
        XCTAssertTrue(StrokeSerializer.decodeStickers("").isEmpty)
        XCTAssertTrue(StrokeSerializer.decodeTexts("not json").isEmpty)
    }
}

// MARK: - F. Firestore schema compatibility

final class DrawingSchemaTests: XCTestCase {
    func testSentDrawingFieldsIncludeRecipientIdsAndAndroidSchema() {
        var drawing = Drawing()
        drawing.drawingId = "d1"
        drawing.groupId = "g1"
        drawing.senderId = "u1"
        drawing.recipientIds = ["u2", "u3"]
        drawing.drawingData = "aGVsbG8="
        drawing.strokeData = "{}"
        drawing.stickerData = "[]"
        drawing.textData = "[]"

        let fields = DrawingFieldBuilder.fields(for: drawing)
        XCTAssertEqual(fields["drawingId"] as? String, "d1")
        XCTAssertEqual(fields["groupId"] as? String, "g1")
        XCTAssertEqual(fields["senderId"] as? String, "u1")
        XCTAssertEqual((fields["recipientIds"] as? [String]) ?? [], ["u2", "u3"])
        XCTAssertEqual(Set(fields.keys),
                       ["drawingId", "groupId", "senderId", "recipientIds", "drawingData",
                        "strokeData", "stickerData", "textData", "sentAt", "isFavorite"])
    }

    func testAndroidDrawingDecodesAndReplayParses() {
        // Android-shaped document with recipientIds, array sticker data and reactions.
        let data: [String: Any] = [
            "drawingId": "d9",
            "groupId": "g1",
            "senderId": "u2",
            "recipientIds": ["u1"],
            "drawingData": "aGVsbG8=",
            "strokeData": StrokeSerializer.encode(
                strokes: [Stroke(points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)],
                                 color: 0xFF000000, width: 9, brush: .glitter)],
                background: .default,
                canvasSize: CGSize(width: 1080, height: 1080)),
            "stickerData": [["e": "⭐️", "x": 0.5, "y": 0.5]],
            "unknownField": 42,
        ]
        let drawing = Drawing.from(documentID: "d9", data: data)
        XCTAssertEqual(drawing.recipientIds, ["u1"])
        XCTAssertEqual(drawing.stickerData.contains("⭐️"), true)

        let parsed = StrokeSerializer.decode(drawing.strokeData)
        XCTAssertEqual(parsed.strokes.count, 1)
        XCTAssertEqual(parsed.strokes[0].brush, .glitter)
    }
}

// MARK: - G. Replay

@MainActor
final class ReplayTests: XCTestCase {
    func testReplayControllerParsesAndAdvances() async {
        var drawing = Drawing()
        drawing.strokeData = StrokeSerializer.encode(
            strokes: [
                Stroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 50, y: 50)], color: 0xFF000000, width: 8, brush: .basic),
                Stroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 150)], color: 0xFF000000, width: 8, brush: .neon),
            ],
            background: .default,
            canvasSize: CGSize(width: 1080, height: 1080))
        drawing.stickerData = StrokeSerializer.encodeStickers([StickerElement(emoji: "⭐️")])

        let controller = ReplayController(drawing: drawing)
        XCTAssertEqual(controller.strokeCount, 2)
        XCTAssertFalse(controller.isPlaying)

        await controller.play()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(controller.isFinished)
        XCTAssertNotNil(controller.inkImage)
    }

    func testReplayEmptyDrawingFinishesImmediately() async {
        var drawing = Drawing()
        drawing.strokeData = ""
        let controller = ReplayController(drawing: drawing)
        XCTAssertEqual(controller.strokeCount, 0)
        await controller.play()
        XCTAssertTrue(controller.isFinished)
    }
}

// MARK: - H. Premium gating hooks

final class PremiumGateTests: XCTestCase {
    func testFreePlanLocksPremiumFeatures() {
        let gate = PremiumGate(isPro: false)
        XCTAssertTrue(gate.canUseBrush(.basic))
        XCTAssertTrue(gate.canUseBrush(.pencil))
        XCTAssertFalse(gate.canUseBrush(.neon))
        XCTAssertFalse(gate.canUseBrush(.rainbow))
        XCTAssertFalse(gate.canUseBrush(.glow))
        XCTAssertFalse(gate.canUseColor("#FACC15"))
        XCTAssertFalse(gate.canUseColor("#facc15"))
        XCTAssertTrue(gate.canUseColor("#000000"))
        XCTAssertFalse(gate.canSaveToDevice)
    }

    func testProPlanUnlocksEverything() {
        let gate = PremiumGate(isPro: true)
        for brush in BrushType.allCases {
            XCTAssertTrue(gate.canUseBrush(brush), "\(brush.displayName) should be unlocked for Pro")
        }
        XCTAssertTrue(gate.canUseColor("#FACC15"))
        XCTAssertTrue(gate.canSaveToDevice)
    }
}

// MARK: - I. Drawing limit + typed send errors

final class DrawingLimitTests: XCTestCase {
    func testFreePlanLimitBoundary() {
        XCTAssertFalse(DrawingLimits.sendBlocked(sentCount: 14, isPro: false))
        XCTAssertTrue(DrawingLimits.sendBlocked(sentCount: 15, isPro: false))
        XCTAssertTrue(DrawingLimits.sendBlocked(sentCount: 99, isPro: false))
        XCTAssertFalse(DrawingLimits.sendBlocked(sentCount: 99, isPro: true))
    }

    func testLimitErrorCarriesUpgradeFriendlyCopy() {
        XCTAssertEqual(AppError.drawingLimitReached.title, "Free Plan Limit Reached")
        XCTAssertTrue(AppError.drawingLimitReached.message.contains("Upgrade to Pro"))
    }

    func testNetworkErrorMapsToTypedAppError() {
        let error = NSError(domain: NSURLErrorDomain, code: -1009)
        XCTAssertEqual(AppError.from(error), .network)
        XCTAssertFalse(AppError.from(error).message.isEmpty)
    }
}

// MARK: - Engine export sanity

@MainActor
final class EngineExportTests: XCTestCase {
    func testEngineExportsRealDrawingNotBlank() {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 340, y: 540))
        engine.extendStroke(to: CGPoint(x: 740, y: 540))
        engine.endStroke()

        let base64 = engine.exportCompositeJPEGBase64()
        XCTAssertNotNil(base64)
        let data = Data(base64Encoded: base64 ?? "")
        XCTAssertNotNil(data)
        let image = data.flatMap { UIImage(data: $0) }
        XCTAssertNotNil(image)
        if let image {
            XCTAssertGreaterThan(image.size.width, 100)
        }

        // Serialized stroke data must contain the committed stroke.
        let parsed = StrokeSerializer.decode(engine.encodedStrokeData)
        XCTAssertEqual(parsed.strokes.count, 1)
        XCTAssertEqual(parsed.strokes[0].brush, .basic)
    }
}
