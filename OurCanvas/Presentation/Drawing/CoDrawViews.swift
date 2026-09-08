import SwiftUI

/// "Co-Draw (N) · BETA" chip shown in the drawing composer. Opens the live-session
/// dialog with join/leave and the Android beta self-heal note.
struct CoDrawChip: View {
    @ObservedObject var viewModel: CoDrawViewModel
    @State private var showingDialog = false

    var body: some View {
        Button {
            showingDialog = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(viewModel.isActive ? "Co-Draw (\(viewModel.participantCount))" : "Co-Draw")
                    .font(.system(size: 12, weight: .semibold))
                Text("BETA")
                    .font(.system(size: 8, weight: .black))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(BrandColor.warning))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(viewModel.isActive ? BrandColor.primary.opacity(0.2) : Color(.systemGray5)))
            .foregroundColor(viewModel.isActive ? BrandColor.primary : .primary)
        }
        .sheet(isPresented: $showingDialog) {
            CoDrawDialogView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }
}

/// "Live Co-Draw Active" dialog — join/leave + beta warning (Android copy parity).
struct CoDrawDialogView: View {
    @ObservedObject var viewModel: CoDrawViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text(viewModel.isActive ? "Live Co-Draw Active" : "Start a Live Co-Draw?")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("BETA")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(BrandColor.warning))
                        .foregroundColor(.black)
                    Text("Beta feature")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isActive {
                VStack(spacing: 6) {
                    Label("\(viewModel.participantCount) drawing together right now", systemImage: "person.2.fill")
                        .font(.subheadline)
                    ForEach(viewModel.participantNames, id: \.self) { name in
                        Text("• \(name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            // Android beta note: leaving + rejoining self-heals sync issues.
            Text("If strokes look out of sync, leaving and rejoining the Co-Draw usually fixes it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if let error = viewModel.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if viewModel.isActive {
                Button(role: .destructive) {
                    viewModel.leave()
                    dismiss()
                } label: {
                    Text("Leave Co-Draw")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
            } else {
                if viewModel.isJoining {
                    ProgressView("Connecting…")
                } else {
                    PrimaryGradientButton(title: "Join Live Session") {
                        viewModel.join()
                    }
                    .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 8)
        }
    }
}
