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
    
    var body: some View {
        NavigationView {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Send") { saveDrawing() }
                            .fontWeight(.bold)
                    }
                }
            }
        }
    }
    
    private func saveDrawing() {
        guard let currentUser = Auth.auth().currentUser else { return }
        isSaving = true
        
        let jsonStr = StrokeSerializer.exportStrokeData(records: strokeRecords, width: 1080, height: 1080)
        
        // In a real app we render the drawing to a UIImage to encode to base64.
        // For this implementation, we will use a blank white square as a fallback if rendering fails.
        let base64Image = createBlankImageBase64() 
        
        let newDrawing = Drawing(
            groupId: group.groupId,
            senderId: currentUser.uid,
            drawingData: base64Image,
            isFavorite: false,
            strokeData: jsonStr,
            reaction: "",
            reactionSenderName: "",
            reactionSenderId: "",
            reactions: [:],
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
                    print("Error saving drawing: \(error)")
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
