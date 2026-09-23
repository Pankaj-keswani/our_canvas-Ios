import SwiftUI

/// Bottom toolbar for the drawing composer: panel switcher (Brush / Background /
/// Stickers / Text / Settings), direct eraser toggle, size slider, color row.
struct DrawingToolbar: View {
    @ObservedObject var engine: DrawingEngine
    @ObservedObject private var userRepo: UserRepository = .shared
    let gate: PremiumGate
    var onUpgradeTapped: () -> Void
    var onOpenCoinWallet: () -> Void = {}
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

    // MARK: Coin-unlock alert state
    @State private var pendingCoinUnlockBrush: BrushType? = nil
    @State private var pendingCoinUnlockBackground: DrawingBackground.Template? = nil
    @State private var showInsufficientCoins = false
    @State private var isUnlocking = false

    // MARK: Streak-unlock alert state
    @State private var showStreakLockedAlert = false
    @State private var streakAlertTitle = ""
    @State private var streakAlertMessage = ""

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
        // MARK: Coin unlock confirmation alert — Brush
        .alert(
            pendingCoinUnlockBrush.map { "Unlock \($0.displayName)?" } ?? "Unlock Brush?",
            isPresented: Binding(
                get: { pendingCoinUnlockBrush != nil && !showInsufficientCoins },
                set: { if !$0 { pendingCoinUnlockBrush = nil } }
            )
        ) {
            let cost = pendingCoinUnlockBrush?.coinCost ?? 0
            let balance = userRepo.currentUserProfile?.coins ?? 0
            if balance >= cost {
                Button("Unlock (\(cost) 🪙)") {
                    if let brush = pendingCoinUnlockBrush,
                       let uid = userRepo.currentUserProfile?.uid {
                        isUnlocking = true
                        Task {
                            do {
                                _ = try await CoinManager.shared.unlockBrush(
                                    userId: uid,
                                    brushName: brush.coinUnlockId,
                                    cost: brush.coinCost
                                )
                                await MainActor.run {
                                    engine.selectBrush(brush)
                                    isUnlocking = false
                                }
                            } catch {
                                await MainActor.run { isUnlocking = false }
                            }
                        }
                    }
                    pendingCoinUnlockBrush = nil
                }
            } else {
                Button("Get Coins 🪙") {
                    pendingCoinUnlockBrush = nil
                    onOpenCoinWallet()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCoinUnlockBrush = nil
            }
        } message: {
            let cost = pendingCoinUnlockBrush?.coinCost ?? 0
            let balance = userRepo.currentUserProfile?.coins ?? 0
            if balance >= cost {
                Text("Spend \(cost) 🪙 to permanently unlock this brush. You have \(balance) coins.")
            } else {
                Text("You need \(cost) 🪙 but only have \(balance). Earn more coins!")
            }
        }
        // MARK: Coin unlock confirmation alert — Background
        .alert(
            pendingCoinUnlockBackground.map { "Unlock \($0.displayName)?" } ?? "Unlock Background?",
            isPresented: Binding(
                get: { pendingCoinUnlockBackground != nil && !showInsufficientCoins },
                set: { if !$0 { pendingCoinUnlockBackground = nil } }
            )
        ) {
            let cost = pendingCoinUnlockBackground?.coinCost ?? 0
            let balance = userRepo.currentUserProfile?.coins ?? 0
            if balance >= cost {
                Button("Unlock (\(cost) 🪙)") {
                    if let template = pendingCoinUnlockBackground,
                       let uid = userRepo.currentUserProfile?.uid {
                        isUnlocking = true
                        Task {
                            do {
                                _ = try await CoinManager.shared.unlockBackground(
                                    userId: uid,
                                    templateName: template.coinUnlockId,
                                    cost: template.coinCost
                                )
                                await MainActor.run {
                                    engine.updateBackground(DrawingBackground(
                                        template: template,
                                        colorHex: engine.background.colorHex
                                    ))
                                    isUnlocking = false
                                }
                            } catch {
                                await MainActor.run { isUnlocking = false }
                            }
                        }
                    }
                    pendingCoinUnlockBackground = nil
                }
            } else {
                Button("Get Coins 🪙") {
                    pendingCoinUnlockBackground = nil
                    onOpenCoinWallet()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCoinUnlockBackground = nil
            }
        } message: {
            let cost = pendingCoinUnlockBackground?.coinCost ?? 0
            let balance = userRepo.currentUserProfile?.coins ?? 0
            if balance >= cost {
                Text("Spend \(cost) 🪙 to permanently unlock this background. You have \(balance) coins.")
            } else {
                Text("You need \(cost) 🪙 but only have \(balance). Earn more coins!")
            }
        }
        // MARK: 3-Day Streak unlock requirement alert
        .alert(streakAlertTitle, isPresented: $showStreakLockedAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text(streakAlertMessage)
        }
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
        let coins = userRepo.currentUserProfile?.coins ?? 0
        return VStack(spacing: 8) {
            // Coin balance pill at top right
            HStack {
                Spacer()
                Button {
                    onOpenCoinWallet()
                } label: {
                    Label("\(coins) 🪙", systemImage: "")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.18))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
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
        let isPremiumLocked = !gate.canUseBrush(brush)
        let isStreakLocked = brush.isStreakUnlockable && !(userRepo.currentUserProfile?.isBrushUnlocked(brush) ?? false)
        let isCoinLocked = brush.isCoinUnlockable && !(userRepo.currentUserProfile?.isBrushUnlocked(brush) ?? false)
        let isSelected = engine.selectedBrush == brush
        return Button {
            if isPremiumLocked {
                onUpgradeTapped()
            } else if isStreakLocked {
                let currentStreak = userRepo.currentUserProfile?.currentStreak ?? 0
                let itemName = (brush == .pastel) ? "Pastel Brush" : brush.displayName
                streakAlertTitle = "🔥 3-Day Streak Required"
                streakAlertMessage = "Build a streak of 3 consecutive days by drawing in your circle to unlock the \(itemName) forever! Current streak: \(currentStreak) / 3 days."
                showStreakLockedAlert = true
            } else if isCoinLocked {
                pendingCoinUnlockBrush = brush
            } else {
                engine.selectBrush(brush)
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: brush.systemImageName)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? BrandColor.primary : Color.primary)
                    if isPremiumLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(BrandColor.warning)
                    } else if isStreakLocked {
                        // Orange/red fire gradient streak badge
                        Text("🔥 3d")
                            .font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .offset(x: 4, y: -4)
                    } else if isCoinLocked {
                        // Golden coin-unlock badge
                        Text("🪙 \(brush.coinCost)")
                            .font(.system(size: 7, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(4)
                            .offset(x: 4, y: -4)
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
                    .strokeBorder(
                        isStreakLocked ? Color.orange.opacity(0.7) :
                        (isCoinLocked ? Color.yellow.opacity(0.6) :
                        (isSelected ? BrandColor.primary : .clear)),
                        lineWidth: 1.5
                    )
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
                        backgroundTemplateButton(template)
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

    private func backgroundTemplateButton(_ template: DrawingBackground.Template) -> some View {
        let isStreakLocked = template.isStreakUnlockable && !(userRepo.currentUserProfile?.isBackgroundUnlocked(template) ?? false)
        let isCoinLocked = template.isCoinUnlockable && !(userRepo.currentUserProfile?.isBackgroundUnlocked(template) ?? false)
        let isSelected = engine.background.template == template
        return Button {
            if isStreakLocked {
                let currentStreak = userRepo.currentUserProfile?.currentStreak ?? 0
                let itemName = (template == .lavenderMist) ? "Lavender Mist Background" : template.displayName
                streakAlertTitle = "🔥 3-Day Streak Required"
                streakAlertMessage = "Build a streak of 3 consecutive days by drawing in your circle to unlock the \(itemName) forever! Current streak: \(currentStreak) / 3 days."
                showStreakLockedAlert = true
            } else if isCoinLocked {
                pendingCoinUnlockBackground = template
            } else {
                engine.updateBackground(DrawingBackground(template: template,
                                                          colorHex: engine.background.colorHex))
            }
        } label: {
            HStack(spacing: 4) {
                Text(template.displayName)
                    .font(.caption)
                if isStreakLocked {
                    Text("🔥 3d")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(4)
                } else if isCoinLocked {
                    Text("🪙 \(template.coinCost)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? BrandColor.primary.opacity(0.2) : Color(.secondarySystemBackground).opacity(0.5))
            .foregroundStyle(isSelected ? BrandColor.primary : Color.primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isStreakLocked ? Color.orange.opacity(0.7) :
                        (isCoinLocked ? Color.yellow.opacity(0.6) : .clear),
                        lineWidth: 1.2
                    )
            )
        }
        .buttonStyle(.plain)
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
