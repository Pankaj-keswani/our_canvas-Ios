import Foundation
import CoreGraphics
import SwiftUI

enum BrushType: Int, Codable {
    case basic = 0, neon, rainbow, glow, eraser,
         pencil, marker, calligraphy, watercolorBrush, crayon,
         airbrush, pixel, glitter, sketch
}

struct PointRecord {
    var x: CGFloat
    var y: CGFloat
}

struct StrokeRecord {
    var points: [PointRecord]
    var color: Int
    var strokeWidth: CGFloat
    var brushType: BrushType
}

struct ParsedStrokeData {
    var records: [StrokeRecord]
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
}

class StrokeSerializer {
    static func exportStrokeData(records: [StrokeRecord], width: CGFloat, height: CGFloat) -> String {
        let cw = width > 0 ? width : 1080
        let ch = height > 0 ? height : 1080
        
        var json = "{\"cw\":\(cw),\"ch\":\(ch),\"strokes\":["
        
        for (i, stroke) in records.enumerated() {
            if i > 0 { json += "," }
            json += "{"
            json += "\"c\":\(stroke.color),"
            json += "\"w\":\(stroke.strokeWidth),"
            json += "\"b\":\(stroke.brushType.rawValue),"
            json += "\"p\":["
            
            for (j, pt) in stroke.points.enumerated() {
                if j > 0 { json += "," }
                let rx = String(format: "%.1f", pt.x)
                let ry = String(format: "%.1f", pt.y)
                json += "[\(rx),\(ry)]"
            }
            json += "]}"
        }
        json += "]}"
        return json
    }
    
    static func importStrokeData(jsonStr: String) -> ParsedStrokeData {
        var records: [StrokeRecord] = []
        var cw: CGFloat = 0
        var ch: CGFloat = 0
        
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedStrokeData(records: [], canvasWidth: 0, canvasHeight: 0)
        }
        
        cw = json["cw"] as? CGFloat ?? 0
        ch = json["ch"] as? CGFloat ?? 0
        
        if let strokesArray = json["strokes"] as? [[String: Any]] {
            for strokeDict in strokesArray {
                let color = strokeDict["c"] as? Int ?? 0
                let width = strokeDict["w"] as? CGFloat ?? 12
                let bOrdinal = strokeDict["b"] as? Int ?? 0
                let brushType = BrushType(rawValue: bOrdinal) ?? .basic
                
                var points: [PointRecord] = []
                if let pArray = strokeDict["p"] as? [[CGFloat]] {
                    for pt in pArray {
                        if pt.count >= 2 {
                            points.append(PointRecord(x: pt[0], y: pt[1]))
                        }
                    }
                }
                records.append(StrokeRecord(points: points, color: color, strokeWidth: width, brushType: brushType))
            }
        }
        
        return ParsedStrokeData(records: records, canvasWidth: cw, canvasHeight: ch)
    }
}
