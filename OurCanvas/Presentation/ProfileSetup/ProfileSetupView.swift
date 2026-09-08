import SwiftUI
import PhotosUI

/// First-login profile initialization: display name + avatar, saved with field-level
/// Firestore updates. The polished profile screen arrives in a later phase.
struct ProfileSetupView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var displayName = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarPreview: UIImage?
    @State private var avatarBase64: String?
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Set up your profile")
                .font(BrandFont.title())
                .foregroundColor(BrandColor.textPrimary)
            Text("Pick a name your circle will recognize.")
                .font(BrandFont.body())
                .foregroundColor(BrandColor.textSecondary)

            ZStack(alignment: .bottomTrailing) {
                avatarView
                    .frame(width: 120, height: 120)

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(BrandGradient.primary)
                        .background(Circle().fill(BrandColor.backgroundTop))
                }
                .offset(x: 4, y: 4)
            }

            TextField("Display name", text: $displayName)
                .textContentType(.name)
                .font(BrandFont.body())
                .foregroundStyle(BrandColor.textPrimary)
                .padding(14)
                .background(BrandColor.surface.opacity(0.7))
                .cornerRadius(12)
                .autocorrectionDisabled()

            if let errorText {
                Text(errorText)
                    .font(BrandFont.caption())
                    .foregroundColor(.red)
            }

            PrimaryGradientButton(title: "Continue", isLoading: isSaving) {
                save()
            }
            .opacity(displayName.trimmed.isEmpty ? 0.5 : 1.0)
            .disabled(displayName.trimmed.isEmpty || isSaving)

            Spacer()
        }
        .padding(.horizontal, 24)
        .onChange(of: avatarItem) { newItem in
            loadAvatar(newItem)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarPreview {
            Image(uiImage: avatarPreview)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(BrandColor.primary.opacity(0.5), lineWidth: 2))
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(BrandColor.textSecondary)
        }
    }

    private func loadAvatar(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let scaled = Self.downscaled(image, maxDimension: 512)
                if let jpeg = scaled.jpegData(compressionQuality: 0.6) {
                    let base64 = jpeg.base64EncodedString()
                    await MainActor.run {
                        avatarPreview = scaled
                        avatarBase64 = base64
                    }
                }
            }
        }
    }

    private func save() {
        let name = displayName.trimmed
        guard !name.isEmpty, let uid = router.currentUID else { return }
        var fields = UserFieldUpdate.displayName(name)
        if let base64 = avatarBase64 {
            fields.merge(UserFieldUpdate.profilePicture(base64)) { current, _ in current }
        }

        isSaving = true
        errorText = nil
        Task {
            do {
                try await UserRepository.shared.updateFields(uid: uid, fields)
                await MainActor.run {
                    isSaving = false
                    router.refreshSession()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }

    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct ProfileSetupView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileSetupView()
            .environmentObject(AppRouter())
    }
}
