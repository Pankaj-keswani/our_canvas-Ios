import Foundation
import CoreGraphics

/// Brush types with an EXPLICIT, stable mapping to the Android serialized brush IDs.
/// Never rely on Swift declaration order — the mapping below is the cross-platform contract.
///
/// Android reference ordering (ANDROID_TO_IOS_MIGRATION_SPEC Phase 1):
/// 0 BASIC · 1 PENCIL · 2 MARKER · 3 NEON · 4 RAINBOW · 5 GLOW · 6 CALLIGRAPHY
/// 7 WATERCOLOR · 8 CRAYON · 9 AIRBRUSH · 10 PIXEL · 11 GLITTER · 12 SKETCH · 13 ERASER
enum BrushType: String, CaseIterable, Hashable {
    case basic
    case pencil
    case marker
    case neon
    case rainbow
    case glow
    case calligraphy
    case watercolor
    case crayon
    case airbrush
    case pixel
    case glitter
    case sketch
    case eraser

    var androidID: Int {
        switch self {
        case .basic: return 0
        case .pencil: return 1
        case .marker: return 2
        case .neon: return 3
        case .rainbow: return 4
        case .glow: return 5
        case .calligraphy: return 6
        case .watercolor: return 7
        case .crayon: return 8
        case .airbrush: return 9
        case .pixel: return 10
        case .glitter: return 11
        case .sketch: return 12
        case .eraser: return 13
        }
    }

    static func from(androidID: Int) -> BrushType {
        switch androidID {
        case 0: return .basic
        case 1: return .pencil
        case 2: return .marker
        case 3: return .neon
        case 4: return .rainbow
        case 5: return .glow
        case 6: return .calligraphy
        case 7: return .watercolor
        case 8: return .crayon
        case 9: return .airbrush
        case 10: return .pixel
        case 11: return .glitter
        case 12: return .sketch
        case 13: return .eraser
        default: return .basic
        }
    }

    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .pencil: return "Pencil"
        case .marker: return "Marker"
        case .neon: return "Neon"
        case .rainbow: return "Rainbow"
        case .glow: return "Glow"
        case .calligraphy: return "Calligraphy"
        case .watercolor: return "Watercolor"
        case .crayon: return "Crayon"
        case .airbrush: return "Airbrush"
        case .pixel: return "Pixel"
        case .glitter: return "Glitter"
        case .sketch: return "Sketch"
        case .eraser: return "Eraser"
        }
    }

    var systemImageName: String {
        switch self {
        case .basic: return "paintbrush.pointed"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .neon: return "lightbulb"
        case .rainbow: return "rainbow"
        case .glow: return "sparkles"
        case .calligraphy: return "scribble.variable"
        case .watercolor: return "drop"
        case .crayon: return "pencil.tip"
        case .airbrush: return "cloud.fill"
        case .pixel: return "squareshape.split.3x3"
        case .glitter: return "star.bubble.fill"
        case .sketch: return "pencil.and.outline"
        case .eraser: return "eraser"
        }
    }
}

/// A single stroke. Coordinates are in CANVAS UNITS (the document coordinate space,
/// e.g. 0..1080), y grows downward. Color is an ARGB integer (Android Color-int parity).
struct Stroke: Equatable {
    var points: [CGPoint] = []
    var color: Int = 0xFF000000
    var width: CGFloat = 12
    var brush: BrushType = .basic

    var isEraser: Bool { brush == .eraser }
}

/// Single source of truth for the active drawing tool. Assigning a brush exits eraser
/// mode and vice versa — this struct makes the contradictory-state bug class impossible.
enum Tool: Equatable {
    case brush(BrushType)
    case eraser

    var isEraser: Bool { self == .eraser }

    var brushForStroke: BrushType {
        switch self {
        case .brush(let brush): return brush
        case .eraser: return .eraser
        }
    }

    var selectedBrush: BrushType? {
        switch self {
        case .brush(let brush): return brush
        case .eraser: return nil
        }
    }
}

// MARK: - Persistent elements

/// Sticker element. Position is normalized (0...1) relative to the canvas so it scales
/// across devices; `scale` multiplies a base size; `rotation` is radians.
struct StickerElement: Identifiable, Equatable {
    var id: UUID = UUID()
    var emoji: String = "⭐️"
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
}

/// Text element. `fontSize` is in canvas units; color is ARGB int; position normalized.
struct TextElement: Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = "Hello!"
    var color: Int = 0xFF000000
    var fontSize: CGFloat = 72
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
}

enum CanvasElement: Equatable {
    case sticker(StickerElement)
    case text(TextElement)

    var id: UUID {
        switch self {
        case .sticker(let s): return s.id
        case .text(let t): return t.id
        }
    }

    var normalizedPosition: CGPoint {
        switch self {
        case .sticker(let s): return CGPoint(x: s.x, y: s.y)
        case .text(let t): return CGPoint(x: t.x, y: t.y)
        }
    }
}

// MARK: - Background / templates

struct DrawingBackground: Equatable {
    enum Template: String, CaseIterable {
        case plain
        case dots
        case grid
        case gradient

        var displayName: String {
            switch self {
            case .plain: return "Plain"
            case .dots: return "Dots"
            case .grid: return "Grid"
            case .gradient: return "Gradient"
            }
        }
    }

    var template: Template = .plain
    var colorHex: String = "#FFFFFF"

    static let `default` = DrawingBackground()
}

// MARK: - Free-plan limits (Android A7.3)

enum DrawingLimits {
    static let freeDrawingsPerCircle = 15
    static let freeVisibleRecentDrawings = 3
    static let proVisibleRecentDrawings = 5

    /// Pure limit check used by the send flow (unit tested).
    static func sendBlocked(sentCount: Int, isPro: Bool) -> Bool {
        !isPro && sentCount >= freeDrawingsPerCircle
    }
}
