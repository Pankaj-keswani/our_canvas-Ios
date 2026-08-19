import SwiftUI

struct DrawingEngineView: View {
    @Binding var strokeRecords: [StrokeRecord]
    @Binding var currentBrush: BrushType
    @Binding var strokeColor: Color
    @Binding var strokeWidth: CGFloat
    @Binding var isEraser: Bool
    
    @State private var currentPoints: [PointRecord] = []
    @State private var currentStrokeSize: CGSize = .zero
    
    var onStrokeFinished: (() -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    for stroke in strokeRecords {
                        drawStroke(stroke, in: &context, size: size)
                    }
                    
                    if !currentPoints.isEmpty {
                        let activeColor = isEraser ? UIColor.clear.rgb() : UIColor(strokeColor).rgb()
                        let activeStroke = StrokeRecord(points: currentPoints, color: activeColor, strokeWidth: strokeWidth, brushType: isEraser ? .eraser : currentBrush)
                        drawStroke(activeStroke, in: &context, size: size)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let pt = PointRecord(x: value.location.x, y: value.location.y)
                            currentPoints.append(pt)
                            currentStrokeSize = geometry.size
                        }
                        .onEnded { value in
                            if currentPoints.count == 1 {
                                let pt = currentPoints[0]
                                currentPoints.append(PointRecord(x: pt.x + 0.1, y: pt.y))
                            }
                            if !currentPoints.isEmpty {
                                let activeColor = isEraser ? UIColor.clear.rgb() : UIColor(strokeColor).rgb()
                                let record = StrokeRecord(
                                    points: currentPoints,
                                    color: activeColor,
                                    strokeWidth: strokeWidth,
                                    brushType: isEraser ? .eraser : currentBrush
                                )
                                strokeRecords.append(record)
                                currentPoints.removeAll()
                                onStrokeFinished?()
                            }
                        }
                )
            }
        }
    }
    
    private func drawStroke(_ stroke: StrokeRecord, in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        guard let first = stroke.points.first else { return }
        path.move(to: CGPoint(x: first.x, y: first.y))
        
        var lastPt = CGPoint(x: first.x, y: first.y)
        for i in 1..<stroke.points.count {
            let pt = CGPoint(x: stroke.points[i].x, y: stroke.points[i].y)
            let mid = CGPoint(x: (pt.x + lastPt.x) / 2, y: (pt.y + lastPt.y) / 2)
            path.addQuadCurve(to: mid, control: lastPt)
            lastPt = pt
        }
        path.addLine(to: lastPt)
        
        let strokeColor = Color(uiColor: UIColor(rgb: stroke.color))
        var style = StrokeStyle(lineWidth: stroke.strokeWidth, lineCap: .round, lineJoin: .round)
        
        if stroke.brushType == .eraser {
            context.blendMode = .destinationOut
            context.stroke(path, with: .color(.black), style: style)
            context.blendMode = .normal
            return
        }
        
        switch stroke.brushType {
        case .basic:
            context.stroke(path, with: .color(strokeColor), style: style)
        case .pencil:
            style.lineWidth *= 0.6
            context.opacity = 0.43 // 110/255
            context.stroke(path, with: .color(strokeColor), style: style)
        case .marker:
            style.lineCap = .square
            context.opacity = 0.55 // 140/255
            context.stroke(path, with: .color(strokeColor), style: style)
        case .neon:
            var glowStyle = style
            glowStyle.lineWidth *= 2.0
            context.opacity = 0.35 // 90/255
            context.stroke(path, with: .color(strokeColor), style: glowStyle)
            
            var coreStyle = style
            coreStyle.lineWidth *= 0.35
            context.opacity = 1.0
            context.stroke(path, with: .color(.white), style: coreStyle)
        // Add other brush styles here to match Android...
        default:
            context.stroke(path, with: .color(strokeColor), style: style)
        }
    }
}

extension UIColor {
    func rgb() -> Int {
        var fRed: CGFloat = 0
        var fGreen: CGFloat = 0
        var fBlue: CGFloat = 0
        var fAlpha: CGFloat = 0
        if self.getRed(&fRed, green: &fGreen, blue: &fBlue, alpha: &fAlpha) {
            let iRed = Int(fRed * 255.0)
            let iGreen = Int(fGreen * 255.0)
            let iBlue = Int(fBlue * 255.0)
            let iAlpha = Int(fAlpha * 255.0)
            let rgb = (iAlpha << 24) + (iRed << 16) + (iGreen << 8) + iBlue
            return rgb
        } else {
            return 0
        }
    }
    
    convenience init(rgb: Int) {
        let iAlpha = (rgb >> 24) & 0xFF
        let iRed = (rgb >> 16) & 0xFF
        let iGreen = (rgb >> 8) & 0xFF
        let iBlue = rgb & 0xFF
        self.init(red: CGFloat(iRed) / 255.0, green: CGFloat(iGreen) / 255.0, blue: CGFloat(iBlue) / 255.0, alpha: CGFloat(iAlpha) / 255.0)
    }
}
