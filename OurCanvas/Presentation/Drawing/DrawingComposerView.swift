import SwiftUI
import FirebaseAuth

struct DrawingComposerView: View {
    let group: Group
    @Environment(\.dismiss) var dismiss

    @State private var strokeRecords: [StrokeRecord] = []
    @State private var currentBrush: BrushType = .basic
    @State private var strokeColor: Color = .black
    @State private var strokeWidth: CGFloat = 8
    @State private var isEraser = false
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            // Canvas Area
            DrawingEngineView(
                strokeRecords: $strokeRecords,
                currentBrush: $currentBrush,
                strokeColor: $strokeColor,
                strokeWidth: $strokeWidth,
                isEraser: $isEraser,
                onStrokeFinished: {
                    // Analytics or undo state update
                }
            )
            .background(Color.white)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.1), radius: 5)
            .padding()

            // Toolbar
            HStack(spacing: 20) {
                Button(action: { isEraser.toggle() }) {
                    Image(systemName: isEraser ? "eraser.fill" : "eraser")
                        .foregroundColor(isEraser ? .pink : .gray)
                        .font(.title2)
                }

                ColorPicker("", selection: $strokeColor)
                    .labelsHidden()
                    .disabled(isEraser)

                Slider(value: $strokeWidth, in: 2...40)
                    .disabled(isEraser)

                Button(action: { strokeRecords.removeAll() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.title2)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            Spacer()
        }
        .navigationTitle("New Sketch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Send") { saveDrawing() }
                        .fontWeight(.bold)
                }
            }
        }
        .alert("Couldn't send your drawing", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func saveDrawing() {
        guard let currentUser = Auth.auth().currentUser else { return }
        isSaving = true
        errorText = nil

        let jsonStr = StrokeSerializer.exportStrokeData(records: strokeRecords, width: 1080, height: 1080)

        // TODO(Drawing engine phase): render strokes into the exported bitmap. The blank
        // placeholder below is a known pre-existing gap tracked in IOS_PARITY_AUDIT.md (CB-2).
        let base64Image = createBlankImageBase64()

        // recipientIds feeds the shared Android Cloud Function push fan-out; without it
        // recipients get no notification.
        let recipients = group.memberIds.filter { $0 != currentUser.uid }

        let newDrawing = Drawing(
            groupId: group.groupId,
            senderId: currentUser.uid,
            recipientIds: recipients,
            drawingData: base64Image,
            isFavorite: false,
            strokeData: jsonStr,
            stickerData: "[]",
            textData: "[]"
        )

        Task {
            do {
                try await DrawingRepository().saveDrawing(drawing: newDrawing)
                DispatchQueue.main.async {
                    isSaving = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isSaving = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }

    private func createBlankImageBase64() -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        return image.pngData()?.base64EncodedString() ?? ""
    }
}
