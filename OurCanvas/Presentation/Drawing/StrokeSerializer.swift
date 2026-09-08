import Foundation
import CoreGraphics

/// Parsed result of a drawing's serialized stroke data.
struct ParsedDrawing {
    var strokes: [Stroke] = []
    var background: DrawingBackground = .default
    var canvasWidth: CGFloat = 1080
    var canvasHeight: CGFloat = 1080
}

/// Cross-platform stroke/element serialization.
///
/// Stroke envelope VERIFIED against the Android `SketchCanvasView.exportStrokeData`
/// fixture (workspace artifact, Phase 2 §0):
/// `{"cw":1080,"ch":1080,"strokes":[{"c":<argb-int>,"w":<double>,"b":<brush-ordinal>,"p":[[x,y],...]}]}`
///
/// Stickers (verified): `[{"id":"<uuid>","t":"⭐️","x":<abs-canvas>,"y":<abs>,"s":<scale>,"r":<degrees>}]`
/// Text (verified): `[{"id":"<uuid>","txt":"hi","x":..,"y":..,"s":..,"r":<deg>,"sz":<fontSize>,"c":<argb>,"fn":"Sans","b":false,"i":false,"a":"Center","o":1.0,"e":"Normal"}]`
///
/// - Color: ARGB integer (Android Color-int parity).
/// - Width/coordinates: canvas units; element rotation: degrees.
/// - Eraser: brush id 13; color irrelevant.
/// - `bg` is an iOS extension on the root (older Android documents omit it; decoders ignore it).
/// - Decoding tolerates missing keys, unknown fields, blank/"[]"/"{}" inputs.
enum StrokeSerializer {

    // MARK: - Stroke data

    static func encode(strokes: [Stroke], background: DrawingBackground, canvasSize: CGSize) -> String {
        var strokesArray: [[String: Any]] = []
        for stroke in strokes {
            let points = stroke.points.map { [Double($0.x), Double($0.y)] as [Any] }
            strokesArray.append([
                "c": stroke.color,
                "w": Double(stroke.width),
                "b": stroke.brush.androidID,
                "p": points,
            ])
        }
        let document: [String: Any] = [
            "cw": Int(canvasSize.width),
            "ch": Int(canvasSize.height),
            "bg": [
                "t": background.template.rawValue,
                "c": background.colorHex,
            ],
            "strokes": strokesArray,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: document),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"cw\":\(Int(canvasSize.width)),\"ch\":\(Int(canvasSize.height)),\"strokes\":[]}"
        }
        return json
    }

    static func decode(_ json: String) -> ParsedDrawing {
        var parsed = ParsedDrawing()
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]", trimmed != "{}" else { return parsed }
        guard let data = trimmed.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return parsed
        }

        parsed.canvasWidth = CGFloat(FieldCast.int(root["cw"]) ?? 1080)
        parsed.canvasHeight = CGFloat(FieldCast.int(root["ch"]) ?? 1080)

        if let bg = root["bg"] as? [String: Any] {
            let templateName = FieldCast.string(bg["t"]) ?? "plain"
            parsed.background = DrawingBackground(
                template: DrawingBackground.Template(rawValue: templateName) ?? .plain,
                colorHex: FieldCast.string(bg["c"]) ?? "#FFFFFF"
            )
        }

        guard let strokesRaw = root["strokes"] as? [[String: Any]] else { return parsed }
        for strokeRaw in strokesRaw {
            var stroke = Stroke()
            stroke.color = StrokeColor.canonical(FieldCast.int(strokeRaw["c"]) ?? 0xFF000000)
            stroke.width = CGFloat(FieldCast.double(strokeRaw["w"]) ?? 12)
            stroke.brush = BrushType.from(androidID: FieldCast.int(strokeRaw["b"]) ?? 0)
            stroke.points = decodePoints(strokeRaw["p"])
            parsed.strokes.append(stroke)
        }
        return parsed
    }

    private static func decodePoints(_ raw: Any?) -> [CGPoint] {
        var points: [CGPoint] = []
        if let pairs = raw as? [[Any]] {
            for pair in pairs {
                let x = FieldCast.double(pair.count > 0 ? pair[0] : nil) ?? 0
                let y = FieldCast.double(pair.count > 1 ? pair[1] : nil) ?? 0
                points.append(CGPoint(x: x, y: y))
            }
        } else if let dicts = raw as? [[String: Any]] {
            for dict in dicts {
                let x = FieldCast.double(dict["x"]) ?? 0
                let y = FieldCast.double(dict["y"]) ?? 0
                points.append(CGPoint(x: x, y: y))
            }
        }
        return points
    }

    // MARK: - Sticker data (Android field names: id/t/x/y/s/r — absolute coords, degrees)

    static func encodeStickers(_ stickers: [StickerElement]) -> String {
        let array: [[String: Any]] = stickers.map { sticker in
            [
                "id": sticker.id.uuidString,
                "t": sticker.emoji,
                "x": Double(sticker.x),
                "y": Double(sticker.y),
                "s": Double(sticker.scale),
                "r": Double(sticker.rotationDegrees),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decodeStickers(_ json: String) -> [StickerElement] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { raw in
            // Android field "t"; legacy iOS field "e" tolerated.
            guard let emoji = FieldCast.string(raw["t"]) ?? FieldCast.string(raw["e"]) else { return nil }
            var sticker = StickerElement()
            if let idString = FieldCast.string(raw["id"]), let uuid = UUID(uuidString: idString) {
                sticker.id = uuid
            }
            sticker.emoji = emoji
            sticker.x = CGFloat(FieldCast.double(raw["x"]) ?? 540)
            sticker.y = CGFloat(FieldCast.double(raw["y"]) ?? 540)
            sticker.scale = CGFloat(FieldCast.double(raw["s"]) ?? 1.0)
            sticker.rotationDegrees = CGFloat(FieldCast.double(raw["r"]) ?? 0.0)
            return sticker
        }
    }

    // MARK: - Text data (Android field names: id/txt/x/y/s/r/sz/c + style extras)

    static func encodeTexts(_ texts: [TextElement]) -> String {
        let array: [[String: Any]] = texts.map { element in
            [
                "id": element.id.uuidString,
                "txt": element.text,
                "x": Double(element.x),
                "y": Double(element.y),
                "s": Double(element.scale),
                "r": Double(element.rotationDegrees),
                "sz": Double(element.fontSize),
                "c": element.color,
                "fn": "Sans",
                "b": element.isBold,
                "i": element.isItalic,
                "a": "Center",
                "o": element.opacity,
                "e": "Normal",
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decodeTexts(_ json: String) -> [TextElement] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { raw in
            // Android field "txt"; legacy iOS field "t" tolerated.
            guard let text = FieldCast.string(raw["txt"]) ?? FieldCast.string(raw["t"]) else { return nil }
            var element = TextElement()
            if let idString = FieldCast.string(raw["id"]), let uuid = UUID(uuidString: idString) {
                element.id = uuid
            }
            element.text = text
            element.color = StrokeColor.canonical(FieldCast.int(raw["c"]) ?? 0xFF000000)
            element.fontSize = CGFloat(FieldCast.double(raw["sz"]) ?? 48)
            element.x = CGFloat(FieldCast.double(raw["x"]) ?? 540)
            element.y = CGFloat(FieldCast.double(raw["y"]) ?? 540)
            element.scale = CGFloat(FieldCast.double(raw["s"]) ?? 1.0)
            element.rotationDegrees = CGFloat(FieldCast.double(raw["r"]) ?? 0.0)
            element.isBold = FieldCast.bool(raw["b"]) ?? false
            element.isItalic = FieldCast.bool(raw["i"]) ?? false
            element.opacity = FieldCast.double(raw["o"]) ?? 1.0
            return element
        }
    }
}

// MARK: - Color helpers (ARGB int <-> hex <-> components)

enum StrokeColor {
    /// Canonical unsigned 32-bit ARGB form. Android colors arrive as signed Int32
    /// (e.g. -65536 == 0xFFFF0000); JSON round-trips may flip the sign either way,
    /// so decoding normalizes to the unsigned representation and encoding keeps it.
    static func canonical(_ value: Int) -> Int {
        value < 0 ? Int(UInt32(bitPattern: Int32(truncatingIfNeeded: value))) : value
    }

    static func hexString(fromARGB value: Int) -> String {
        let r = (value >> 16) & 0xFF
        let g = (value >> 8) & 0xFF
        let b = value & 0xFF
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func argbInt(fromHex hex: String) -> Int {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return 0xFF000000
        }
        return Int(0xFF000000 | value)
    }

    static func components(ofARGB value: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        let a = CGFloat((value >> 24) & 0xFF) / 255.0
        return (r, g, b, a)
    }
}
