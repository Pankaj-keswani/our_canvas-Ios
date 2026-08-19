import SwiftUI
import FirebaseAuth

struct FeedView: View {
    let group: Group
    @StateObject private var viewModel: FeedViewModel
    @State private var showingDrawingSheet = false
    
    init(group: Group) {
        self.group = group
        _viewModel = StateObject(wrappedValue: FeedViewModel(group: group))
    }
    
    var body: some View {
        ZStack {
            Color(red: 247/255, green: 249/255, blue: 251/255).ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView("Loading Feed...")
            } else if viewModel.drawings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.3))
                    Text("No drawings yet in this circle.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button(action: { showingDrawingSheet = true }) {
                        Text("Create the first drawing")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.pink)
                            .cornerRadius(12)
                    }
                    .padding(.top, 16)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(viewModel.drawings) { drawing in
                            DrawingCard(
                                drawing: drawing,
                                onFavorite: { viewModel.toggleFavorite(drawing: drawing) },
                                onReact: { emoji in viewModel.addReaction(drawing: drawing, emoji: emoji) }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showingDrawingSheet = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.pink)
                            .clipShape(Circle())
                            .shadow(color: Color.pink.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(group.groupName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDrawingSheet) {
            DrawingComposerView(group: group)
        }
    }
}
