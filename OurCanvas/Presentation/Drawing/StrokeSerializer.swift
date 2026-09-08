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
/// Logical format (Android-compatible):
/// `{"cw":1080,"ch":1080,"bg":{"t":"plain","c":"#FFFFFF"},"strokes":[{"c":<argb-int>,"w":<double>,"b":<android-brush-id>,"p":[[x,y],...]}]}`
///
/// - Color: ARGB integer (Android Color-int parity).
/// - Width: canvas units.
/// - Points: ordered [x, y] pairs in canvas units, y-down.
/// - Eraser: brush id 13; color irrelevant.
/// - `bg` is optional on decode (older documents).
///
/// Stickers: `[{"id":"uuid","e":"⭐️","x":0.5,"y":0.5,"s":1,"r":0}]`
/// Text:     `[{"id":"uuid","t":"hi","c":-16777216,"f":72,"x":0.5,"y":0.5,"s":1,"r":0}]`
/// Decoding tolerates missing keys and unknown fields.
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
        guard let data = json.data(using: .utf8),
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
            stroke.color = FieldCast.int(strokeRaw["c"]) ?? 0xFF000000
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

    // MARK: - Sticker data

    static func encodeStickers(_ stickers: [StickerElement]) -> String {
        let array: [[String: Any]] = stickers.map { sticker in
            [
                "id": sticker.id.uuidString,
                "e": sticker.emoji,
                "x": Double(sticker.x),
                "y": Double(sticker.y),
                "s": Double(sticker.scale),
                "r": Double(sticker.rotation),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decodeStickers(_ json: String) -> [StickerElement] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { raw in
            guard let emoji = FieldCast.string(raw["e"]) else { return nil }
            var sticker = StickerElement()
            if let idString = FieldCast.string(raw["id"]), let uuid = UUID(uuidString: idString) {
                sticker.id = uuid
            }
            sticker.emoji = emoji
            sticker.x = CGFloat(FieldCast.double(raw["x"]) ?? 0.5)
            sticker.y = CGFloat(FieldCast.double(raw["y"]) ?? 0.5)
            sticker.scale = CGFloat(FieldCast.double(raw["s"]) ?? 1.0)
            sticker.rotation = CGFloat(FieldCast.double(raw["r"]) ?? 0.0)
            return sticker
        }
    }

    // MARK: - Text data

    static func encodeTexts(_ texts: [TextElement]) -> String {
        let array: [[String: Any]] = texts.map { text in
            [
                "id": text.id.uuidString,
                "t": text.text,
                "c": text.color,
                "f": Double(text.fontSize),
                "x": Double(text.x),
                "y": Double(text.y),
                "s": Double(text.scale),
                "r": Double(text.rotation),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decodeTexts(_ json: String) -> [TextElement] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { raw in
            guard let text = FieldCast.string(raw["t"]) else { return nil }
            var element = TextElement()
            if let idString = FieldCast.string(raw["id"]), let uuid = UUID(uuidString: idString) {
                element.id = uuid
            }
            element.text = text
            element.color = FieldCast.int(raw["c"]) ?? 0xFF000000
            element.fontSize = CGFloat(FieldCast.double(raw["f"]) ?? 72)
            element.x = CGFloat(FieldCast.double(raw["x"]) ?? 0.5)
            element.y = CGFloat(FieldCast.double(raw["y"]) ?? 0.5)
            element.scale = CGFloat(FieldCast.double(raw["s"]) ?? 1.0)
            element.rotation = CGFloat(FieldCast.double(raw["r"]) ?? 0.0)
            return element
        }
    }
}

// MARK: - Color helpers (ARGB int <-> hex <-> components)

enum StrokeColor {
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
