import SwiftUI

/// Bottom toolbar for the drawing composer: panel switcher (Brush / Background /
/// Stickers / Text / Settings), direct eraser toggle, size slider, color row.
struct DrawingToolbar: View {
    @ObservedObject var engine: DrawingEngine
    let gate: PremiumGate
    var onUpgradeTapped: () -> Void
    var onSaveToDevice: () -> Void
    var onShare: () -> Void
    /// When a live Co-Draw is active the composer routes undo/clear through these so
    /// the operation is broadcast; nil falls back to local engine calls.
    var onUndo: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil

    enum Panel: String, CaseIterable, Identifiable {
        case brush, background, stickers, text, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .brush: return "Brush"
            case .background: return "Background"
            case .stickers: return "Stickers"
            case .text: return "Text"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .brush: return "paintbrush"
            case .background: return "rectangle.on.rectangle"
            case .stickers: return "face.smiling"
            case .text: return "textformat"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @State private var selectedPanel: Panel = .brush
    @State private var newText = ""
    @State private var newTextFontSize: Double = 72

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            panelContent
                .frame(maxHeight: 210)

            Divider()

            // Panel switcher + eraser
            HStack(spacing: 4) {
                ForEach(Panel.allCases) { panel in
                    panelButton(panel)
                }
                Button {
                    engine.toggleEraser()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: engine.isEraserActive ? "eraser.fill" : "eraser")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Eraser")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(engine.isEraserActive ? BrandColor.primary.opacity(0.2) : .clear)
                    .foregroundStyle(engine.isEraserActive ? BrandColor.primary : Color.primary)
                    .cornerRadius(8)
                }
                .accessibilityLabel("Eraser")
            }

            // Size slider (label switches with tool)
            VStack(spacing: 2) {
                Text(engine.isEraserActive ? "Eraser Size" : "Brush Size")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(value: $engine.strokeWidth, in: 2...60)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground).opacity(0.95))
    }

    // MARK: - Panel button

    private func panelButton(_ panel: Panel) -> some View {
        Button {
            selectedPanel = panel
        } label: {
            VStack(spacing: 2) {
                Image(systemName: panel.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(panel.title)
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selectedPanel == panel ? BrandColor.primary.opacity(0.2) : .clear)
            .foregroundStyle(selectedPanel == panel ? BrandColor.primary : Color.primary)
            .cornerRadius(8)
        }
    }

    // MARK: - Panels

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .brush: brushPanel
        case .background: backgroundPanel
        case .stickers: stickerPanel
        case .text: textPanel
        case .settings: settingsPanel
        }
    }

    private var brushPanel: some View {
        VStack(spacing: 8) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(BrushType.allCases, id: \.self) { brush in
                        brushButton(brush)
                    }
                }
            }
            .frame(maxHeight: 96)

            // Color row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DrawingPalette.entries) { entry in
                        colorSwatch(entry)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func brushButton(_ brush: BrushType) -> some View {
        let isLocked = !gate.canUseBrush(brush)
        let isSelected = engine.selectedBrush == brush
        return Button {
            if isLocked {
                onUpgradeTapped()
            } else {
                engine.selectBrush(brush)
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: brush.systemImageName)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? BrandColor.primary : Color.primary)
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(BrandColor.warning)
                    }
                }
                Text(brush.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? BrandColor.primary.opacity(0.18) : Color(.secondarySystemBackground).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? BrandColor.primary : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ entry: DrawingPalette.Entry) -> some View {
        let isLocked = !gate.canUseColor(entry.hex)
        let isSelected = StrokeColor.hexString(fromARGB: engine.strokeColorARGB).uppercased() == entry.hex.uppercased()
        return Button {
            if isLocked {
                onUpgradeTapped()
            } else {
                engine.strokeColorARGB = StrokeColor.argbInt(fromHex: entry.hex)
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(hexString: entry.hex))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(isSelected ? BrandColor.primary : Color.black.opacity(0.15), lineWidth: isSelected ? 3 : 1))
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.black)
                        .padding(2)
                        .background(Circle().fill(BrandColor.warning))
                        .offset(x: 4, y: 4)
                }
            }
        }
        .accessibilityLabel(entry.name)
    }

    private var backgroundPanel: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DrawingBackground.Template.allCases, id: \.self) { template in
                        Button {
                            engine.updateBackground(DrawingBackground(template: template,
                                                                     colorHex: engine.background.colorHex))
                        } label: {
                            Text(template.displayName)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(engine.background.template == template ? BrandColor.primary.opacity(0.2) : Color(.secondarySystemBackground).opacity(0.5))
                                .foregroundStyle(engine.background.template == template ? BrandColor.primary : Color.primary)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DrawingPalette.backgroundHexes) { entry in
                        let isLocked = !gate.canUseColor(entry.hex)
                        Button {
                            if isLocked {
                                onUpgradeTapped()
                            } else {
                                engine.updateBackground(DrawingBackground(template: engine.background.template,
                                                                         colorHex: entry.hex))
                            }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color(hexString: entry.hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
                                if isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.black)
                                        .padding(2)
                                        .background(Circle().fill(BrandColor.warning))
                                        .offset(x: 4, y: 4)
                                }
                            }
                        }
                        .accessibilityLabel(entry.name)
                    }
                }
            }
        }
    }

    private var stickerPanel: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 10) {
                ForEach(DrawingPalette.stickerEmojis, id: \.self) { emoji in
                    Button {
                        let sticker = StickerElement(emoji: emoji, x: 540, y: 432, scale: 1.0, rotationDegrees: 0)
                        engine.addSticker(sticker)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                    }
                }
            }
        }
    }

    private var textPanel: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Type something…", text: $newText)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newText.trimmed
                    guard !trimmed.isEmpty else { return }
                    let element = TextElement(text: trimmed,
                                              color: engine.strokeColorARGB,
                                              fontSize: CGFloat(newTextFontSize),
                                              x: 540, y: 540, scale: 1.0, rotationDegrees: 0)
                    engine.addText(element)
                    newText = ""
                }
                .buttonStyle(.borderedProminent)
            }
            VStack(spacing: 2) {
                Text("Text Size: \(Int(newTextFontSize))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(value: $newTextFontSize, in: 32...160, step: 4)
            }
            Text("Tip: double-tap a text on the canvas to edit it.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ToolbarActionButton(systemImage: "arrow.uturn.backward", title: "Undo") {
                    if let onUndo {
                        onUndo()
                    } else {
                        engine.undo()
                    }
                }
                .disabled(!engine.canUndo)

                ToolbarActionButton(systemImage: "arrow.uturn.forward", title: "Redo") {
                    engine.redo()
                }
                .disabled(!engine.canRedo)

                ToolbarActionButton(systemImage: "trash", title: "Clear") {
                    if let onClear {
                        onClear()
                    } else {
                        engine.clearAll()
                    }
                }
                .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                ToolbarActionButton(systemImage: gate.canSaveToDevice ? "square.and.arrow.down" : "lock",
                                    title: "Save PNG") {
                    if gate.canSaveToDevice {
                        onSaveToDevice()
                    } else {
                        onUpgradeTapped()
                    }
                }
                ToolbarActionButton(systemImage: "square.and.arrow.up", title: "Share") {
                    onShare()
                }
            }
        }
    }
}

struct ToolbarActionButton: View {
    let systemImage: String
    let title: String
    var foregroundColor: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground).opacity(0.6))
            .foregroundColor(foregroundColor)
            .cornerRadius(10)
        }
    }
}
