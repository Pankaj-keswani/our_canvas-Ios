import SwiftUI
import FirebaseAuth

/// Focused mini-canvas for the drawer (Android A5.3 GameDrawingActivity equivalent).
/// Reuses DrawingEngine/StrokeRenderer/StrokeSerializer — no second canvas system.
struct GameDrawingScreen: View {
    @ObservedObject var viewModel: GuessGameViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var engine = DrawingEngine()
    @State private var isSending = false
    @State private var errorText: String?

    /// Android parity: 7 ink colors on the game canvas.
    private static let inkColors: [String] = ["#000000", "#EF4444", "#F97316", "#22C55E", "#3B82F6", "#8B5CF6", "#EC4899"]

    var body: some View {
        VStack(spacing: 0) {
            wordHeader

            DrawingCanvasView(engine: engine) { _ in }

            controls
        }
        .navigationTitle("Guess My Doodle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button("Send Doodle") { sendDoodle() }
                        .fontWeight(.bold)
                        .disabled(engine.strokes.isEmpty)
                }
            }
        }
        .alert("Couldn't send your doodle", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: - Persistent word header + shuffle

    private var wordHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Draw this for them to guess:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.drawerSecretWord ?? "• • •")
                    .font(.title3.weight(.bold).monospaced())
            }
            Spacer()
            Button {
                viewModel.shuffleWord()
            } label: {
                Label("Shuffle", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    // MARK: - Controls (7 colors, size, undo, clear)

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.inkColors, id: \.self) { hex in
                        let isSelected = StrokeColor.hexString(fromARGB: engine.strokeColorARGB).uppercased() == hex.uppercased()
                        Button {
                            engine.strokeColorARGB = StrokeColor.argbInt(fromHex: hex)
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(isSelected ? BrandColor.primary : Color.black.opacity(0.15),
                                                               lineWidth: isSelected ? 3 : 1))
                        }
                        .accessibilityLabel("Ink color \(hex)")
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 12) {
                ToolbarActionButton(systemImage: "arrow.uturn.backward", title: "Undo") {
                    engine.undo()
                }
                .disabled(!engine.canUndo)

                ToolbarActionButton(systemImage: "trash", title: "Clear") {
                    engine.clearAll()
                }
                .foregroundColor(.red)
            }

            VStack(spacing: 2) {
                Text("Brush Size")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(value: $engine.strokeWidth, in: 2...60)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground).opacity(0.95))
    }

    // MARK: - Publish

    private func sendDoodle() {
        guard let game = viewModel.game else { return }
        guard !engine.strokes.isEmpty else { return }
        isSending = true
        errorText = nil
        let strokeData = engine.encodedStrokeData

        Task {
            do {
                try await GuessGameRepository().publishDrawing(gameId: game.id, strokeData: strokeData)
                await MainActor.run {
                    isSending = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }
}
