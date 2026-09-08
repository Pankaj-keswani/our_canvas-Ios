import Foundation
import UIKit
import Photos

/// Photo-library save with real error surfacing (permission denials, write failures).
enum PhotoLibrarySaver {
    /// Pure permission decision (tested).
    enum Decision: Equatable {
        case allowed
        case denied
        case undetermined
    }

    static func decision(for status: PHAuthorizationStatus) -> Decision {
        switch status {
        case .authorized, .limited:
            return .allowed
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }

    static func friendlyMessage(for decision: Decision) -> String {
        switch decision {
        case .allowed:
            return "Saved to Photos!"
        case .denied:
            return "Photo access is off. Enable it in Settings → Our Canvas → Photos to save doodles."
        case .undetermined:
            return "Photo permission is needed to save doodles."
        }
    }

    /// Saves with completion; never throws — errors come back as friendly messages.
    static func save(image: UIImage, completion: @escaping (String) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let decision = decision(for: status)
        guard decision == .allowed || decision == .undetermined else {
            completion(friendlyMessage(for: decision))
            return
        }

        let request: (Bool) -> Void = { granted in
            guard granted else {
                DispatchQueue.main.async {
                    completion(friendlyMessage(for: .denied))
                }
                return
            }
            UIImageWriteToSavedPhotosAlbum(image,
                                           PhotoSaveReporter.shared,
                                           #selector(PhotoSaveReporter.image(_:didFinishSavingWithError:contextInfo:)),
                                           nil)
            PhotoSaveReporter.shared.onComplete = { message in
                DispatchQueue.main.async {
                    completion(message)
                }
            }
        }

        if decision == .undetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                request(Self.decision(for: newStatus) == .allowed)
            }
        } else {
            request(true)
        }
    }
}

/// NSObject bridge for UIImageWriteToSavedPhotosAlbum's target-selector callback.
final class PhotoSaveReporter: NSObject {
    static let shared = PhotoSaveReporter()
    var onComplete: ((String) -> Void)?

    @objc func image(_ image: UIImage,
                     didFinishSavingWithError error: Error?,
                     contextInfo: UnsafeRawPointer) {
        if let error {
            onComplete?("Couldn't save the doodle: \(error.localizedDescription)")
        } else {
            onComplete?("Saved to Photos!")
        }
        onComplete = nil
    }
}
