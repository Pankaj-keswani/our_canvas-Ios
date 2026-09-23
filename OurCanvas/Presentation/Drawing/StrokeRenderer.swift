import Foundation
import UIKit
import CoreGraphics

/// CoreGraphics renderer for strokes, backgrounds and element compositing.
///
/// LAYER ARCHITECTURE (mandatory per spec):
///   BACKGROUND (color/template)  ←  never touched by the eraser
///   INK (strokes, transparent bitmap; eraser composites .destinationOut HERE only)
///   ELEMENTS (stickers/text)    ←  never touched by the eraser
///
/// The same `draw(stroke:)` code path is used for live preview, committed ink,
/// replay and final export, so what you draw is exactly what is sent.
///
/// Brush approximations are deterministic; where CoreGraphics has no direct
/// equivalent of an Android Paint effect the closest stable implementation is used
/// and documented at each brush.
enum StrokeRenderer {

    // MARK: - Public entry points

    /// Renders a single stroke into a transparent bitmap (used for live preview).
    static func renderStrokeImage(_ stroke: Stroke, canvasSize: CGSize, outputPixels: Int) -> UIImage? {
        let size = CGSize(width: outputPixels, height: outputPixels)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { uiContext in
            let ctx = uiContext.cgContext
            draw(stroke: stroke, in: ctx, canvasSize: canvasSize, outputSize: size)
        }
    }

    /// Renders the full ink layer (all strokes, eraser applied within the layer only).
    static func renderInkImage(strokes: [Stroke], canvasSize: CGSize, outputPixels: Int) -> UIImage? {
        let size = CGSize(width: outputPixels, height: outputPixels)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { uiContext in
            let ctx = uiContext.cgContext
            for stroke in strokes {
                draw(stroke: stroke, in: ctx, canvasSize: canvasSize, outputSize: size)
            }
        }
    }

    /// Renders the background layer.
    static func renderBackgroundImage(_ background: DrawingBackground, canvasSize: CGSize, outputPixels: Int) -> UIImage {
        let size = CGSize(width: outputPixels, height: outputPixels)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { uiContext in
            let ctx = uiContext.cgContext
            drawBackground(background, in: ctx, canvasRect: CGRect(origin: .zero, size: size))
        }
    }

    /// Full composite for export: background + ink + elements, in that order.
    static func renderComposite(background: DrawingBackground,
                                strokes: [Stroke],
                                stickers: [StickerElement],
                                texts: [TextElement],
                                canvasSize: CGSize,
                                outputPixels: Int) -> UIImage {
        let size = CGSize(width: outputPixels, height: outputPixels)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { uiContext in
            let ctx = uiContext.cgContext
            drawBackground(background, in: ctx, canvasRect: CGRect(origin: .zero, size: size))

            if let ink = renderInkImage(strokes: strokes, canvasSize: canvasSize, outputPixels: outputPixels) {
                ink.draw(in: CGRect(origin: .zero, size: size))
            }

            let scale = size.width / max(canvasSize.width, 1)
            for sticker in stickers {
                drawSticker(sticker, ctx: ctx, scale: scale)
            }
            for text in texts {
                drawText(text, ctx: ctx, scale: scale)
            }
        }
    }

    // MARK: - Stroke drawing (all 14 brushes)

    static func draw(stroke: Stroke, in ctx: CGContext, canvasSize: CGSize, outputSize: CGSize) {
        guard stroke.points.count > 0 else { return }
        let scale = min(outputSize.width / max(canvasSize.width, 1),
                        outputSize.height / max(canvasSize.height, 1))

        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        defer { ctx.restoreGState() }

        if stroke.points.count == 1 {
            // Dots: render as a tiny two-point stroke so single taps leave a mark.
            var dot = stroke
            dot.points = [stroke.points[0],
                          CGPoint(x: stroke.points[0].x + 0.5, y: stroke.points[0].y + 0.5)]
            drawStrokeBody(dot, in: ctx)
            return
        }
        drawStrokeBody(stroke, in: ctx)
    }

    private static func drawStrokeBody(_ stroke: Stroke, in ctx: CGContext) {
        let comps = StrokeColor.components(ofARGB: stroke.color)

        switch stroke.brush {
        case .eraser:
            // destination-out on the INK layer only — never background/elements,
            // because those live in separate bitmaps/layers.
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
            strokePath(stroke, in: ctx)
            ctx.restoreGState()

        case .basic:
            setStroke(comps, alpha: 1, ctx: ctx, cap: .round)
            strokePath(stroke, in: ctx)

        case .pencil:
            // Android: 60% width, alpha 110.
            setStroke(comps, alpha: 110.0 / 255.0, ctx: ctx, cap: .round)
            strokePath(stroke, in: ctx, widthFactor: 0.6)

        case .marker:
            // Android: square cap, alpha 140.
            setStroke(comps, alpha: 140.0 / 255.0, ctx: ctx, cap: .square)
            strokePath(stroke, in: ctx)

        case .neon:
            // Android: glow pass at 2× width alpha 90 + bright 0.35× core.
            setStroke(comps, alpha: 90.0 / 255.0, ctx: ctx, cap: .round)
            strokePath(stroke, in: ctx, widthFactor: 2.0)
            ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
            strokePath(stroke, in: ctx, widthFactor: 0.35)

        case .rainbow:
            // Android: per-segment hue via bounds. Approximation: hue progresses
            // along cumulative path length.
            drawRainbow(stroke, in: ctx)

        case .glow:
            // Android: 3-pass glow.
            setStroke(comps, alpha: 0.16, ctx: ctx, cap: .round)
            strokePath(stroke, in: ctx, widthFactor: 2.2)
            setStroke(comps, alpha: 0.32, ctx: ctx, cap: .round)
            strokePath(stroke, in: ctx, widthFactor: 1.2)
            setStroke(comps, alpha: 0.95, ctx: ctx, cap: .round)
            strokePath(stroke, in: ctx, widthFactor: 0.5)

        case .calligraphy:
            // Android: nib-like directional width. Approximation: per-segment
            // thickness varies with the segment angle relative to a 45° nib.
            drawCalligraphy(stroke, in: ctx)

        case .watercolor:
            // Android: translucent layered appearance. Approximation: three
            // perpendicularly-offset translucent passes.
            drawWatercolor(stroke, in: ctx, comps: comps)

        case .crayon:
            // Android: DiscretePathEffect texture. Approximation: dashed stroke
            // with a faint offset second pass.
            ctx.saveGState()
            setStroke(comps, alpha: 0.8, ctx: ctx, cap: .round)
            ctx.setLineDash(phase: 0, lengths: [max(1, stroke.width * 0.12), max(1, stroke.width * 0.18)])
            strokePath(stroke, in: ctx, widthFactor: 0.95)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.restoreGState()

        case .airbrush:
            // Android: soft diffuse spray. Approximation: concentric low-alpha
            // circles stamped along the path.
            drawAirbrush(stroke, in: ctx, comps: comps)

        case .pixel:
            // Android: no AA, square. Approximation: square fills with
            // antialiasing disabled.
            drawPixel(stroke, in: ctx, comps: comps)

        case .glitter:
            // Android: PathMeasure sparkles. Approximation: sparkles stamped at
            // fixed arc-length intervals with seeded deterministic jitter.
            drawGlitter(stroke, in: ctx, comps: comps)

        case .sketch:
            // Android: sketch texture. Approximation: several thin, slightly
            // offset passes (hand-drawn look).
            drawSketch(stroke, in: ctx, comps: comps)

        case .fire:
            // Tier 1 Coin brush: Multi-layer fiery flame stroke with golden core and glowing embers.
            drawFire(stroke, in: ctx)

        case .aurora:
            // Tier 2 Coin brush: Chromatic dual-tone celestial ribbon (cyan to magenta) with stardust.
            drawAurora(stroke, in: ctx)

        case .velvetRibbon:
            drawVelvetRibbon(stroke, in: ctx, comps: comps)

        case .fireEngine:
            drawFireEngine(stroke, in: ctx)

        case .pastel:
            // 3-Day Streak Unlock: Soft chalk/pastel look with dual passes (outer diffusion halo with slight blur/feathering and a solid matte core).
            drawPastel(stroke, in: ctx, comps: comps)
        }
    }

    // MARK: Shared path helpers

    private static func quadPath(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        var last = first
        for i in 1..<points.count {
            let current = points[i]
            let mid = CGPoint(x: (current.x + last.x) / 2, y: (current.y + last.y) / 2)
            path.addQuadCurve(to: mid, control: last)
            last = current
        }
        path.addLine(to: last)
        return path
    }

    private static func setStroke(_ c: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
                                  alpha: CGFloat,
                                  ctx: CGContext,
                                  cap: CGLineCap) {
        ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
        ctx.setLineCap(cap)
        ctx.setLineJoin(.round)
        ctx.setBlendMode(.normal)
    }

    private static func strokePath(_ stroke: Stroke, in ctx: CGContext, widthFactor: CGFloat = 1.0) {
        ctx.setLineWidth(max(0.5, stroke.width * widthFactor))
        ctx.addPath(quadPath(for: stroke.points))
        ctx.strokePath()
    }

    private static func segmentLengths(_ points: [CGPoint]) -> (cumulative: [CGFloat], total: CGFloat) {
        var cumulative: [CGFloat] = [0]
        var total: CGFloat = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            total += sqrt(dx * dx + dy * dy)
            cumulative.append(total)
        }
        return (cumulative, total)
    }

    // MARK: - Brush-specific renderers

    private static func drawRainbow(_ stroke: Stroke, in ctx: CGContext) {
        let (cumulative, total) = segmentLengths(stroke.points)
        guard total > 0 else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(0.5, stroke.width))
        for i in 1..<stroke.points.count {
            let fraction = cumulative[i] / total
            let color = UIColor(hue: fraction, saturation: 0.85, brightness: 1.0, alpha: 1.0)
            ctx.setStrokeColor(color.cgColor)
            let path = CGMutablePath()
            path.move(to: stroke.points[i - 1])
            path.addLine(to: stroke.points[i])
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func drawCalligraphy(_ stroke: Stroke, in ctx: CGContext) {
        let nibAngle: CGFloat = .pi / 4
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let comps = StrokeColor.components(ofARGB: stroke.color)
        ctx.setStrokeColor(red: comps.r, green: comps.g, blue: comps.b, alpha: 1)
        for i in 1..<stroke.points.count {
            let dx = stroke.points[i].x - stroke.points[i - 1].x
            let dy = stroke.points[i].y - stroke.points[i - 1].y
            let angle = atan2(dy, dx)
            let thickness = stroke.width * (0.25 + 0.75 * abs(sin(angle - nibAngle)))
            ctx.setLineWidth(max(0.5, thickness))
            let mid1 = CGPoint(x: (stroke.points[i].x + stroke.points[i - 1].x) / 2,
                               y: (stroke.points[i].y + stroke.points[i - 1].y) / 2)
            let path = CGMutablePath()
            path.move(to: stroke.points[i - 1])
            path.addQuadCurve(to: mid1, control: stroke.points[i - 1])
            path.addLine(to: stroke.points[i])
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func drawWatercolor(_ stroke: Stroke, in ctx: CGContext, comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        let (cumulative, total) = segmentLengths(stroke.points)
        guard total > 0 else { return }
        let direction: CGFloat = cumulative.count > 1 ? atan2(stroke.points.last!.y - stroke.points.first!.y,
                                                             stroke.points.last!.x - stroke.points.first!.x) : 0
        let perpendicular = direction + .pi / 2
        ctx.setStrokeColor(red: comps.r, green: comps.g, blue: comps.b, alpha: 0.12)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(0.5, stroke.width * 1.15))
        for offsetFactor in [CGFloat(0), 0.18, -0.18] {
            let offset = stroke.width * offsetFactor
            let dx = cos(perpendicular) * offset
            let dy = sin(perpendicular) * offset
            let shifted = stroke.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            ctx.addPath(quadPath(for: shifted))
            ctx.strokePath()
        }
    }

    private static func drawAirbrush(_ stroke: Stroke, in ctx: CGContext, comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        let comps2 = comps
        ctx.setFillColor(red: comps2.r, green: comps2.g, blue: comps2.b, alpha: 0.05)
        let step = max(2, stroke.width * 0.5)
        var accumulated: CGFloat = 0
        var lastPoint = stroke.points.first!
        stampAirbrush(at: lastPoint, stroke: stroke, ctx: ctx)
        for point in stroke.points.dropFirst() {
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            let distance = sqrt(dx * dx + dy * dy)
            accumulated += distance
            while accumulated >= step {
                let t = (accumulated / max(distance, 0.0001))
                let clamped = min(max(t, 0), 1)
                let stamp = CGPoint(x: lastPoint.x + dx * clamped, y: lastPoint.y + dy * clamped)
                stampAirbrush(at: stamp, stroke: stroke, ctx: ctx)
                accumulated -= step
            }
            lastPoint = point
        }
    }

    private static func stampAirbrush(at point: CGPoint, stroke: Stroke, ctx: CGContext) {
        for (radiusFactor, alpha) in [(1.3, 0.05), (0.85, 0.06), (0.45, 0.08)] {
            let radius = stroke.width * radiusFactor / 2
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            ctx.setAlpha(alpha)
            ctx.fillEllipse(in: rect)
        }
        ctx.setAlpha(1)
    }

    private static func drawPixel(_ stroke: Stroke, in ctx: CGContext, comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.setFillColor(red: comps.r, green: comps.g, blue: comps.b, alpha: 1)
        let side = max(1, stroke.width)
        var lastPlaced = CGPoint(x: -.infinity, y: -.infinity)
        for point in stroke.points {
            let dx = point.x - lastPlaced.x
            let dy = point.y - lastPlaced.y
            if sqrt(dx * dx + dy * dy) < side * 0.5 { continue }
            let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
            ctx.fill(rect)
            lastPlaced = point
        }
        ctx.restoreGState()
    }

    private static func drawGlitter(_ stroke: Stroke, in ctx: CGContext, comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        var random = SeededRandom(seed: UInt64(bitPattern: Int64(stroke.color &+ stroke.points.count &+ Int(stroke.points.first?.x ?? 0))))
        let (cumulative, total) = segmentLengths(stroke.points)
        guard total > 0 else { return }
        let step = max(6, stroke.width * 0.9)

        // Faint continuous base so the path reads as a line.
        ctx.setStrokeColor(red: comps.r, green: comps.g, blue: comps.b, alpha: 0.35)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(0.5, stroke.width * 0.3))
        ctx.addPath(quadPath(for: stroke.points))
        ctx.strokePath()

        var target = step
        var index = 0
        for i in 1..<stroke.points.count {
            while target <= cumulative[i] {
                let segmentLength = cumulative[i] - cumulative[i - 1]
                let t = segmentLength > 0 ? (target - cumulative[i - 1]) / segmentLength : 0
                let clamped = min(max(t, 0), 1)
                let x = stroke.points[i - 1].x + (stroke.points[i].x - stroke.points[i - 1].x) * clamped
                let y = stroke.points[i - 1].y + (stroke.points[i].y - stroke.points[i - 1].y) * clamped
                stampGlitter(at: CGPoint(x: x, y: y), stroke: stroke, ctx: ctx, random: &random, index: index, comps: comps)
                target += step
                index += 1
            }
        }
    }

    private static func stampGlitter(at point: CGPoint, stroke: Stroke, ctx: CGContext,
                                     random: inout SeededRandom, index: Int,
                                     comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        let jitterX = (random.next() - 0.5) * stroke.width * 0.8
        let jitterY = (random.next() - 0.5) * stroke.width * 0.8
        let center = CGPoint(x: point.x + jitterX, y: point.y + jitterY)
        let size = stroke.width * (0.25 + 0.35 * random.next())

        // Sparkle: two crossed lines through the stamp point.
        ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        ctx.setLineWidth(max(0.5, stroke.width * 0.08))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - size, y: center.y))
        path.addLine(to: CGPoint(x: center.x + size, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - size))
        path.addLine(to: CGPoint(x: center.x, y: center.y + size))
        ctx.addPath(path)
        ctx.strokePath()

        // Color dot in the middle.
        ctx.setFillColor(red: comps.r, green: comps.g, blue: comps.b, alpha: 0.9)
        let dotRadius = max(0.5, stroke.width * 0.12)
        ctx.fillEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                   width: dotRadius * 2, height: dotRadius * 2))
    }

    private static func drawSketch(_ stroke: Stroke, in ctx: CGContext, comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        var random = SeededRandom(seed: UInt64(bitPattern: Int64(stroke.color &+ stroke.points.count)))
        let direction: CGFloat = stroke.points.count > 1 ? atan2(stroke.points.last!.y - stroke.points.first!.y,
                                                                stroke.points.last!.x - stroke.points.first!.x) : 0
        let perpendicular = direction + .pi / 2
        ctx.setStrokeColor(red: comps.r, green: comps.g, blue: comps.b, alpha: 0.55)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(0.5, stroke.width * 0.35))
        for _ in 0..<3 {
            let offset = (random.next() - 0.5) * stroke.width * 0.5
            let dx = cos(perpendicular) * offset
            let dy = sin(perpendicular) * offset
            let shifted = stroke.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            ctx.addPath(quadPath(for: shifted))
            ctx.strokePath()
        }
    }

    private static func drawFire(_ stroke: Stroke, in ctx: CGContext) {
        // Outer warm orange-red flame glow
        ctx.saveGState()
        setStroke((r: 1.0, g: 0.20, b: 0.0, a: 1.0), alpha: 0.32, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 2.4)

        // Central fiery flame layer
        setStroke((r: 1.0, g: 0.42, b: 0.0, a: 1.0), alpha: 0.75, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 1.25)

        // Golden core highlight
        setStroke((r: 1.0, g: 0.88, b: 0.22, a: 1.0), alpha: 0.95, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.45)

        // Hot center white/yellow highlight
        setStroke((r: 1.0, g: 1.0, b: 0.90, a: 1.0), alpha: 0.90, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.18)
        ctx.restoreGState()

        // Glowing ember particles along the stroke path
        let (cumulative, total) = segmentLengths(stroke.points)
        guard total > 0 else { return }
        var random = SeededRandom(seed: UInt64(bitPattern: Int64(stroke.color &+ stroke.points.count &+ 777)))
        let step = max(8, stroke.width * 0.85)
        var target = step

        for i in 1..<stroke.points.count {
            while target <= cumulative[i] {
                let segmentLength = cumulative[i] - cumulative[i - 1]
                let t = segmentLength > 0 ? (target - cumulative[i - 1]) / segmentLength : 0
                let clamped = min(max(t, 0), 1)
                let px = stroke.points[i - 1].x + (stroke.points[i].x - stroke.points[i - 1].x) * clamped
                let py = stroke.points[i - 1].y + (stroke.points[i].y - stroke.points[i - 1].y) * clamped

                let jitterX = (random.next() - 0.5) * stroke.width * 1.2
                let jitterY = (random.next() - 0.5) * stroke.width * 1.2
                let center = CGPoint(x: px + jitterX, y: py + jitterY)
                let emberRadius = max(1.0, stroke.width * (0.08 + 0.14 * random.next()))

                // Glow ring
                ctx.setFillColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 0.4)
                ctx.fillEllipse(in: CGRect(x: center.x - emberRadius * 1.8, y: center.y - emberRadius * 1.8,
                                           width: emberRadius * 3.6, height: emberRadius * 3.6))

                // Bright core
                ctx.setFillColor(red: 1.0, green: 0.92, blue: 0.3, alpha: 0.95)
                ctx.fillEllipse(in: CGRect(x: center.x - emberRadius, y: center.y - emberRadius,
                                           width: emberRadius * 2, height: emberRadius * 2))

                target += step
            }
        }
    }

    private static func drawAurora(_ stroke: Stroke, in ctx: CGContext) {
        let (cumulative, total) = segmentLengths(stroke.points)
        guard total > 0 else { return }

        // Outer ethereal violet glow
        ctx.saveGState()
        ctx.setStrokeColor(red: 0.60, green: 0.10, blue: 0.95, alpha: 0.28)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        strokePath(stroke, in: ctx, widthFactor: 2.4)
        ctx.restoreGState()

        // Main chromatic ribbon: Cyan (#00FFA3) -> Magenta (#DC00FF)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(0.5, stroke.width * 1.15))

        for i in 1..<stroke.points.count {
            let fraction = cumulative[i] / total
            let r = (1.0 - fraction) * 0.0 + fraction * 0.86
            let g = (1.0 - fraction) * 1.0 + fraction * 0.0
            let b = (1.0 - fraction) * 0.64 + fraction * 1.0
            let color = UIColor(red: r, green: g, blue: b, alpha: 0.85)

            ctx.setStrokeColor(color.cgColor)
            let path = CGMutablePath()
            path.move(to: stroke.points[i - 1])
            path.addLine(to: stroke.points[i])
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Bright core highlight
        ctx.saveGState()
        setStroke((r: 0.8, g: 1.0, b: 1.0, a: 1.0), alpha: 0.75, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.35)
        ctx.restoreGState()

        // Crystalline stardust sparkles
        var random = SeededRandom(seed: UInt64(bitPattern: Int64(stroke.color &+ stroke.points.count &+ 999)))
        let step = max(10, stroke.width * 1.1)
        var target = step

        for i in 1..<stroke.points.count {
            while target <= cumulative[i] {
                let segmentLength = cumulative[i] - cumulative[i - 1]
                let t = segmentLength > 0 ? (target - cumulative[i - 1]) / segmentLength : 0
                let clamped = min(max(t, 0), 1)
                let px = stroke.points[i - 1].x + (stroke.points[i].x - stroke.points[i - 1].x) * clamped
                let py = stroke.points[i - 1].y + (stroke.points[i].y - stroke.points[i - 1].y) * clamped

                let jitterX = (random.next() - 0.5) * stroke.width * 0.8
                let jitterY = (random.next() - 0.5) * stroke.width * 0.8
                let center = CGPoint(x: px + jitterX, y: py + jitterY)
                let size = stroke.width * (0.30 + 0.40 * random.next())

                // 4-point cross stardust
                ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
                ctx.setLineWidth(max(0.5, stroke.width * 0.08))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x - size, y: center.y))
                path.addLine(to: CGPoint(x: center.x + size, y: center.y))
                path.move(to: CGPoint(x: center.x, y: center.y - size))
                path.addLine(to: CGPoint(x: center.x, y: center.y + size))
                ctx.addPath(path)
                ctx.strokePath()

                // Center diamond/dot
                ctx.setFillColor(red: 0.4, green: 1.0, blue: 0.9, alpha: 0.95)
                let dotRadius = max(0.5, stroke.width * 0.10)
                ctx.fillEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                           width: dotRadius * 2, height: dotRadius * 2))

                target += step
            }
        }
    }

    private static func drawVelvetRibbon(_ stroke: Stroke,
                                         in ctx: CGContext,
                                         comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        guard stroke.points.count >= 2 else { return }

        // Outer soft velvet sheen / shadow
        ctx.saveGState()
        setStroke(comps, alpha: 0.35, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 1.25)
        ctx.restoreGState()

        // Main rich velvet body
        ctx.saveGState()
        setStroke(comps, alpha: 0.90, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 1.0)
        ctx.restoreGState()

        // Silky center ribbon highlight
        let highlightR = min(CGFloat(1.0), comps.r * 1.35 + 0.15)
        let highlightG = min(CGFloat(1.0), comps.g * 1.35 + 0.15)
        let highlightB = min(CGFloat(1.0), comps.b * 1.35 + 0.15)
        let highlight: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (r: highlightR, g: highlightG, b: highlightB, a: 1.0)
        ctx.saveGState()
        setStroke(highlight, alpha: 0.65, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.35)
        ctx.restoreGState()
    }

    private static func drawFireEngine(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count >= 2 else { return }

        // Bold fire-engine scarlet body (#D32F2F)
        ctx.saveGState()
        setStroke((r: 0.83, g: 0.18, b: 0.18, a: 1.0), alpha: 0.95, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 1.1)
        ctx.restoreGState()

        // Vibrant high-gloss crimson core (#FF3D00)
        ctx.saveGState()
        setStroke((r: 1.0, g: 0.24, b: 0.0, a: 1.0), alpha: 0.85, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.6)
        ctx.restoreGState()

        // Gleaming reflective white-hot center streak
        ctx.saveGState()
        setStroke((r: 1.0, g: 0.9, b: 0.85, a: 1.0), alpha: 0.70, ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.2)
        ctx.restoreGState()
    }

    private static func drawPastel(_ stroke: Stroke,
                                   in ctx: CGContext,
                                   comps: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) {
        guard stroke.points.count >= 2 else { return }

        // Pass 1: Outer diffusion halo (chalk dust / feathering effect)
        ctx.saveGState()
        setStroke(comps, alpha: min(CGFloat(1.0), comps.a * 0.30), ctx: ctx, cap: .round)
        ctx.setShadow(offset: .zero, blur: max(2.0, stroke.width * 0.35), color: UIColor(red: comps.r, green: comps.g, blue: comps.b, alpha: min(CGFloat(1.0), comps.a * 0.40)).cgColor)
        strokePath(stroke, in: ctx, widthFactor: 1.45)
        ctx.restoreGState()

        // Pass 2: Solid matte core
        ctx.saveGState()
        setStroke(comps, alpha: min(CGFloat(1.0), comps.a * 0.95), ctx: ctx, cap: .round)
        strokePath(stroke, in: ctx, widthFactor: 0.90)
        ctx.restoreGState()
    }

    // MARK: - Background

    static func drawBackground(_ background: DrawingBackground, in ctx: CGContext, canvasRect: CGRect) {
        let baseComponents = StrokeColor.components(ofARGB: StrokeColor.argbInt(fromHex: background.colorHex))
        ctx.setFillColor(red: baseComponents.r, green: baseComponents.g, blue: baseComponents.b, alpha: 1)
        ctx.fill(canvasRect)

        let spacing: CGFloat = max(24, canvasRect.width / 12)
        switch background.template {
        case .plain:
            break
        case .dots:
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.12)
            var y = spacing / 2
            while y < canvasRect.height {
                var x = spacing / 2
                while x < canvasRect.width {
                    let dotRect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                    ctx.fillEllipse(in: dotRect)
                    x += spacing
                }
                y += spacing
            }
        case .grid:
            ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 0.10)
            ctx.setLineWidth(0.5)
            ctx.beginPath()
            var x: CGFloat = spacing
            while x < canvasRect.width {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: canvasRect.height))
                x += spacing
            }
            var y: CGFloat = spacing
            while y < canvasRect.height {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: canvasRect.width, y: y))
                y += spacing
            }
            ctx.strokePath()
        case .gradient:
            let colors = [UIColor(red: baseComponents.r, green: baseComponents.g, blue: baseComponents.b, alpha: 1).cgColor,
                          UIColor(red: min(1, baseComponents.r * 0.82 + 0.02),
                                  green: min(1, baseComponents.g * 0.82 + 0.02),
                                  blue: min(1, baseComponents.b * 0.82 + 0.02),
                                  alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0, 1]) {
                ctx.drawLinearGradient(gradient,
                                       start: .zero,
                                       end: CGPoint(x: 0, y: canvasRect.height),
                                       options: [])
            }
        case .midnightRose:
            // Velvety midnight plum/black gradient: #140810 to #2A0818 to #0D0308
            let topColor = UIColor(red: 0x14 / 255.0, green: 0x08 / 255.0, blue: 0x10 / 255.0, alpha: 1.0).cgColor
            let midColor = UIColor(red: 0x2A / 255.0, green: 0x08 / 255.0, blue: 0x18 / 255.0, alpha: 1.0).cgColor
            let bottomColor = UIColor(red: 0x0D / 255.0, green: 0x03 / 255.0, blue: 0x08 / 255.0, alpha: 1.0).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [topColor, midColor, bottomColor] as CFArray,
                                         locations: [0.0, 0.5, 1.0]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvasRect.height), options: [])
            }

            // Floating rose petal accents (subtle soft crimson petals)
            var petalRandom = SeededRandom(seed: 12345678)
            let petalCount = 14
            for _ in 0..<petalCount {
                let px = canvasRect.width * petalRandom.next()
                let py = canvasRect.height * petalRandom.next()
                let petalWidth = canvasRect.width * (0.025 + 0.035 * petalRandom.next())
                let petalHeight = petalWidth * (1.6 + 0.5 * petalRandom.next())
                let angle = petalRandom.next() * .pi * 2

                ctx.saveGState()
                ctx.translateBy(x: px, y: py)
                ctx.rotate(by: angle)
                ctx.setFillColor(red: 0.90, green: 0.15, blue: 0.35, alpha: 0.18)
                ctx.fillEllipse(in: CGRect(x: -petalWidth / 2, y: -petalHeight / 2, width: petalWidth, height: petalHeight))
                ctx.restoreGState()
            }

        case .auroraBorealis:
            // Deep polar midnight sky: #030B1E to #07203A to #020914
            let topSky = UIColor(red: 0x03 / 255.0, green: 0x0B / 255.0, blue: 0x1E / 255.0, alpha: 1.0).cgColor
            let midSky = UIColor(red: 0x07 / 255.0, green: 0x20 / 255.0, blue: 0x3A / 255.0, alpha: 1.0).cgColor
            let bottomSky = UIColor(red: 0x02 / 255.0, green: 0x09 / 255.0, blue: 0x14 / 255.0, alpha: 1.0).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [topSky, midSky, bottomSky] as CFArray,
                                         locations: [0.0, 0.55, 1.0]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvasRect.height), options: [])
            }

            // Starfield
            var starRandom = SeededRandom(seed: 87654321)
            let starCount = 35
            for _ in 0..<starCount {
                let sx = canvasRect.width * starRandom.next()
                let sy = canvasRect.height * starRandom.next()
                let starRadius = 0.8 + 1.2 * starRandom.next()
                let alpha = 0.3 + 0.6 * starRandom.next()
                ctx.setFillColor(red: 0.9, green: 0.95, blue: 1.0, alpha: alpha)
                ctx.fillEllipse(in: CGRect(x: sx - starRadius, y: sy - starRadius, width: starRadius * 2, height: starRadius * 2))
            }

            // Emerald-teal Northern Lights wave
            ctx.saveGState()
            let wavePath = CGMutablePath()
            let waveY = canvasRect.height * 0.35
            wavePath.move(to: CGPoint(x: 0, y: waveY))
            var x: CGFloat = 0
            while x <= canvasRect.width {
                let y = waveY + sin(x / canvasRect.width * .pi * 3) * (canvasRect.height * 0.08)
                wavePath.addLine(to: CGPoint(x: x, y: y))
                x += 10
            }
            ctx.addPath(wavePath)
            ctx.setStrokeColor(red: 0.0, green: 1.0, blue: 0.64, alpha: 0.25)
            ctx.setLineWidth(canvasRect.height * 0.16)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.restoreGState()

        case .midnightGalaxy:
            // Deep cosmic indigo/navy to dark violet gradient: #050515 to #100826 to #02020A
            let top = UIColor(red: 0x05 / 255.0, green: 0x05 / 255.0, blue: 0x15 / 255.0, alpha: 1.0).cgColor
            let mid = UIColor(red: 0x10 / 255.0, green: 0x08 / 255.0, blue: 0x26 / 255.0, alpha: 1.0).cgColor
            let bot = UIColor(red: 0x02 / 255.0, green: 0x02 / 255.0, blue: 0x0A / 255.0, alpha: 1.0).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [top, mid, bot] as CFArray,
                                         locations: [0.0, 0.5, 1.0]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvasRect.height), options: [])
            }

            // Scattered glowing galaxy starfield
            var starRandom = SeededRandom(seed: 987654321)
            let starCount = 65
            for _ in 0..<starCount {
                let sx = canvasRect.width * starRandom.next()
                let sy = canvasRect.height * starRandom.next()
                let radius = max(0.5, canvasRect.width * (0.0015 + 0.0035 * starRandom.next()))
                let alpha = 0.35 + 0.65 * starRandom.next()
                let isVioletStar = starRandom.next() > 0.6
                if isVioletStar {
                    ctx.setFillColor(red: 0.85, green: 0.65, blue: 1.0, alpha: alpha)
                } else {
                    ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha)
                }
                ctx.fillEllipse(in: CGRect(x: sx - radius, y: sy - radius, width: radius * 2, height: radius * 2))
            }

        case .parchment:
            // Warm antique aged parchment gradient: #F4ECD8 to #E6D5B8 to #D8C29D
            let top = UIColor(red: 0xF4 / 255.0, green: 0xEC / 255.0, blue: 0xD8 / 255.0, alpha: 1.0).cgColor
            let mid = UIColor(red: 0xE6 / 255.0, green: 0xD5 / 255.0, blue: 0xB8 / 255.0, alpha: 1.0).cgColor
            let bot = UIColor(red: 0xD8 / 255.0, green: 0xC2 / 255.0, blue: 0x9D / 255.0, alpha: 1.0).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [top, mid, bot] as CFArray,
                                         locations: [0.0, 0.6, 1.0]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvasRect.height), options: [])
            }

            // Subtle aged vignette border
            ctx.saveGState()
            ctx.setStrokeColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 0.15)
            ctx.setLineWidth(canvasRect.width * 0.04)
            ctx.stroke(canvasRect)
            ctx.restoreGState()

        case .lavenderMist:
            // 3-Day Streak Unlock: Twilight lavender-to-blush linear gradient from top-left (#F1EBFD) to bottom-right (#FCEEF8) with subtle rounded inner vignette/mist accents
            let startColor = UIColor(red: 0xF1 / 255.0, green: 0xEB / 255.0, blue: 0xFD / 255.0, alpha: 1.0).cgColor
            let endColor = UIColor(red: 0xFC / 255.0, green: 0xEE / 255.0, blue: 0xF8 / 255.0, alpha: 1.0).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [startColor, endColor] as CFArray,
                                         locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: canvasRect.width, y: canvasRect.height),
                                       options: [])
            }

            // Subtle rounded inner mist/vignette accents
            ctx.saveGState()
            let mistColor = UIColor(red: 0xDF / 255.0, green: 0xD0 / 255.0, blue: 0xF8 / 255.0, alpha: 0.18).cgColor
            ctx.setFillColor(mistColor)
            let mistRadius = canvasRect.width * 0.45
            ctx.fillEllipse(in: CGRect(x: canvasRect.width * 0.1, y: -mistRadius * 0.4, width: mistRadius * 2, height: mistRadius * 1.5))
            ctx.fillEllipse(in: CGRect(x: canvasRect.width * 0.4, y: canvasRect.height - mistRadius * 0.8, width: mistRadius * 1.8, height: mistRadius * 1.4))
            ctx.restoreGState()
        }
    }

    // MARK: - Elements (UIKit string drawing, inside UIGraphicsImageRenderer contexts)

    static let stickerBaseFontSize: CGFloat = 140

    private static func drawSticker(_ sticker: StickerElement, ctx: CGContext, scale: CGFloat) {
        let fontSize = stickerBaseFontSize * sticker.scale * scale
        guard fontSize > 1 else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize)]
        let text = sticker.emoji as NSString
        let textSize = text.size(withAttributes: attributes)
        ctx.saveGState()
        ctx.translateBy(x: sticker.x * scale, y: sticker.y * scale)
        ctx.rotate(by: sticker.rotationDegrees * .pi / 180)
        UIGraphicsPushContext(ctx)
        text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attributes)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    private static func drawText(_ element: TextElement, ctx: CGContext, scale: CGFloat) {
        let fontSize = element.fontSize * element.scale * scale
        guard fontSize > 1 else { return }
        let comps = StrokeColor.components(ofARGB: element.color)
        let weight: UIFont.Weight = element.isBold ? .bold : .semibold
        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let font = element.isItalic ? UIFont.italicSystemFont(ofSize: fontSize) : baseFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: comps.r, green: comps.g, blue: comps.b, alpha: comps.a),
        ]
        let text = element.text as NSString
        let textSize = text.size(withAttributes: attributes)
        ctx.saveGState()
        ctx.setAlpha(element.opacity)
        ctx.translateBy(x: element.x * scale, y: element.y * scale)
        ctx.rotate(by: element.rotationDegrees * .pi / 180)
        UIGraphicsPushContext(ctx)
        text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attributes)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }
}

/// Deterministic seeded pseudo-random generator (LCG) for reproducible
/// glitter/sketch/watercolor jitter — same input, same output on every platform run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
    }
}

/// Incremental transparent ink bitmap used by the editor and the replay engine.
/// Eraser strokes composite destination-out WITHIN this bitmap only.
final class InkCanvas {
    let pixelSize: Int
    let canvasSize: CGSize
    private let context: CGContext

    init(pixelSize: Int, canvasSize: CGSize) {
        self.pixelSize = pixelSize
        self.canvasSize = canvasSize
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(data: nil,
                            width: pixelSize,
                            height: pixelSize,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: space,
                            bitmapInfo: bitmapInfo) ?? CGContext(data: nil,
                                                                  width: 1,
                                                                  height: 1,
                                                                  bitsPerComponent: 8,
                                                                  bytesPerRow: 0,
                                                                  space: space,
                                                                  bitmapInfo: bitmapInfo)!
        // Flip to y-down (UIKit) coordinates so ink matches SwiftUI/Unity-style points.
        ctx.translateBy(x: 0, y: CGFloat(pixelSize))
        ctx.scaleBy(x: 1, y: -1)
        context = ctx
    }

    func add(_ stroke: Stroke) {
        StrokeRenderer.draw(stroke: stroke,
                            in: context,
                            canvasSize: canvasSize,
                            outputSize: CGSize(width: pixelSize, height: pixelSize))
    }

    func reset(with strokes: [Stroke]) {
        // clear() honors the CTM, and the CTM is never modified outside balanced
        // save/restore pairs, so the y-flip transform stays intact.
        context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        for stroke in strokes {
            add(stroke)
        }
    }

    var image: UIImage? {
        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
