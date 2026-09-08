import SwiftUI
import FirebaseAuth
import UIKit

struct DrawingComposerView: View {
    let group: Group
    @Environment(\.dismiss) var dismiss

    @StateObject private var engine = DrawingEngine()
    @StateObject private var coDraw: CoDrawViewModel
    @State private var isSending = false
    @State private var activeAlert: ComposerAlert?
    @State private var shareItem: SharedImage?
    @State private var editingText: TextElement?

    private let drawingRepo = DrawingRepository()

    init(group: Group) {
        self.group = group
        _coDraw = StateObject(wrappedValue: CoDrawViewModel(group: group))
    }

    private var gate: PremiumGate {
        PremiumGate(isPro: UserRepository.shared.currentUserProfile?.isPro ?? false)
    }

    enum ComposerAlert: Identifiable {
        case error(String)
        case freeLimit
        case upgradeStub

        var id: String {
            switch self {
            case .error: return "error"
            case .freeLimit: return "freeLimit"
            case .upgradeStub: return "upgradeStub"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Co-Draw entry point (chip with live participant count + BETA badge).
            HStack {
                CoDrawChip(viewModel: coDraw)
                Spacer()
                if coDraw.isActive {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(BrandColor.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            ZStack {
                DrawingCanvasView(engine: engine) { tappedID in
                    handleElementTap(tappedID)
                }
                .padding(.horizontal, 8)

                // Progressive remote-stroke preview layer (live Co-Draw).
                if let remoteInk = coDraw.remoteInkImage {
                    Image(uiImage: remoteInk)
                        .resizable()
                        .scaledToFit()
                        .allowsHitTesting(false)
                        .padding(.horizontal, 8)
                }
            }

            DrawingToolbar(engine: engine,
                           gate: gate,
                           onUpgradeTapped: { activeAlert = .upgradeStub },
                           onSaveToDevice: { saveToDevice() },
                           onShare: { share() },
                           onUndo: { coDraw.localUndo() },
                           onClear: { coDraw.localClear() })
        }
        .onAppear {
            coDraw.connect(engine: engine)
        }
        .onDisappear {
            coDraw.leave()
        }
        .navigationTitle("Drawing for \(group.groupName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button("Send") { sendDrawing() }
                        .fontWeight(.bold)
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .error(let message):
                return Alert(title: Text("Couldn't send your drawing"),
                             message: Text(message),
                             dismissButton: .default(Text("OK")))
            case .freeLimit:
                return Alert(title: Text("Free plan limit reached"),
                             message: Text("You've sent \(DrawingLimits.freeDrawingsPerCircle) drawings in this circle on the free plan. Upgrade to Pro to keep the doodles flowing."),
                             primaryButton: .default(Text("Upgrade to Pro")) { activeAlert = .upgradeStub },
                             secondaryButton: .cancel(Text("Maybe later")))
            case .upgradeStub:
                return Alert(title: Text("Lifetime Pro"),
                             message: Text("Upgrades arrive with the Premium phase. Everything you draw is saved meanwhile."),
                             dismissButton: .default(Text("OK")))
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .sheet(item: $editingText) { element in
            TextEditSheet(element: element) { updated in
                engine.updateElement(.text(updated))
            }
        }
    }

    // MARK: - Element interaction

    private func handleElementTap(_ id: UUID) {
        // Select on tap; double-tap on text opens the editor.
        if engine.selectedElementID == id, case .text(let text)? = engine.element(id: id) {
            editingText = text
        } else {
            engine.selectElement(id: id)
        }
    }

    // MARK: - Send (renders the REAL drawing)

    private func sendDrawing() {
        guard let currentUser = Auth.auth().currentUser else { return }
        guard !engine.strokes.isEmpty || !engine.stickers.isEmpty || !engine.texts.isEmpty else {
            activeAlert = .error("Draw something first — the canvas is empty!")
            return
        }

        isSending = true
        // Android parity (fixture-verified): recipients = ALL circle memberIds;
        // drawingData = PNG base64.
        let recipients = group.memberIds
        let sentStrokes = engine.strokes

        Task {
            do {
                // Free-plan limit: 15 drawings per circle per sender.
                let sentCount = try await drawingRepo.countDrawingsBySender(
                    groupId: group.groupId,
                    senderId: currentUser.uid
                )
                let isPro = UserRepository.shared.currentUserProfile?.isPro ?? false
                if DrawingLimits.sendBlocked(sentCount: sentCount, isPro: isPro) {
                    await MainActor.run {
                        isSending = false
                        activeAlert = .freeLimit
                    }
                    return
                }

                // Render background + ink + stickers + text into the exported bitmap (PNG,
                // matching the Android send path).
                guard let base64Image = engine.exportCompositePNGBase64() else {
                    throw AppError.underlying("We couldn't render your drawing. Please try again.")
                }

                let drawing = Drawing(
                    groupId: group.groupId,
                    senderId: currentUser.uid,
                    recipientIds: recipients,
                    drawingData: base64Image,
                    isFavorite: false,
                    strokeData: engine.encodedStrokeData,
                    stickerData: engine.encodedStickerData,
                    textData: engine.encodedTextData
                )

                try await drawingRepo.saveDrawing(drawing: drawing)

                // Analytics/streak updates are best-effort — a failure must not fail the send.
                try? await UserRepository.shared.recordDrawingSent(uid: currentUser.uid, strokes: sentStrokes)

                await MainActor.run {
                    isSending = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    activeAlert = .error(AppError.from(error).message)
                }
            }
        }
    }

    // MARK: - Export

    private func saveToDevice() {
        let image = engine.exportCompositePNG()
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    private func share() {
        shareItem = SharedImage(image: engine.exportCompositePNG())
    }
}

/// Identifiable wrapper so a rendered image can drive `sheet(item:)`.
struct SharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Share sheet bridge

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Text editing

struct TextEditSheet: View {
    let element: TextElement
    let onSave: (TextElement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var colorHex: String
    @State private var fontSize: Double

    init(element: TextElement, onSave: @escaping (TextElement) -> Void) {
        self.element = element
        self.onSave = onSave
        _text = State(initialValue: element.text)
        _colorHex = State(initialValue: StrokeColor.hexString(fromARGB: element.color))
        _fontSize = State(initialValue: Double(element.fontSize))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Text")) {
                    TextField("Type something…", text: $text)
                }
                Section(header: Text("Color")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(DrawingPalette.entries.filter { !$0.isPremium }) { entry in
                                Button {
                                    colorHex = entry.hex
                                } label: {
                                    Circle()
                                        .fill(Color(hexString: entry.hex))
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(
                                            colorHex.uppercased() == entry.hex.uppercased() ? BrandColor.primary : Color.black.opacity(0.15),
                                            lineWidth: colorHex.uppercased() == entry.hex.uppercased() ? 3 : 1))
                                }
                                .accessibilityLabel(entry.name)
                            }
                        }
                    }
                }
                Section(header: Text("Size")) {
                    Slider(value: $fontSize, in: 32...200, step: 4)
                    Text("Size: \(Int(fontSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = element
                        updated.text = text.trimmed
                        updated.color = StrokeColor.argbInt(fromHex: colorHex)
                        updated.fontSize = CGFloat(fontSize)
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
