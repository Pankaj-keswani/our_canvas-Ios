import Foundation

/// Firestore `groups/{gid}` model. Field names match the Android schema (spec A14).
/// `groupType` is a legacy iOS-only field, tolerated on read but not written anymore.
struct Group: Identifiable {
    var id: String? = nil
    var groupId: String = ""
    var groupName: String = ""
    var groupType: String = ""
    var createdBy: String = ""
    var createdAt: Int64? = nil
    var inviteCode: String = ""
    var memberIds: [String] = []
}

extension Group {
    /// Tolerant decoding; unknown Android-written fields are ignored.
    static func from(documentID: String?, data: [String: Any]) -> Group {
        var group = Group()
        group.id = documentID ?? FieldCast.string(data["groupId"])
        group.groupId = FieldCast.string(data["groupId"]) ?? documentID ?? ""
        group.groupName = FieldCast.string(data["groupName"]) ?? ""
        group.groupType = FieldCast.string(data["groupType"]) ?? ""
        group.createdBy = FieldCast.string(data["createdBy"]) ?? ""
        group.createdAt = FieldCast.int64(data["createdAt"])
        group.inviteCode = FieldCast.string(data["inviteCode"]) ?? ""
        group.memberIds = FieldCast.stringArray(data["memberIds"]) ?? []
        return group
    }

    /// Field set used ONLY when creating a brand-new group document (Android schema keys).
    static func creationFields(groupName: String,
                               createdBy: String,
                               inviteCode: String,
                               memberIds: [String],
                               createdAtMs: Int64) -> [String: Any] {
        [
            "groupName": groupName,
            "createdBy": createdBy,
            "inviteCode": inviteCode,
            "memberIds": memberIds,
            "createdAt": createdAtMs,
        ]
    }
}

/// Owner-only circle rename rules (UI + write validation, Android parity).
/// The deployed Firestore rules stay authoritative — these mirror them client-side.
enum CircleRenameRules {
    static let maxLength = 30

    /// Input clamp for the text field (typing beyond 30 is cut off).
    static func clamped(_ text: String) -> String {
        String(text.prefix(maxLength))
    }

    /// A saveable name: non-blank after trimming and within the limit.
    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    /// Save button gate: valid AND actually different from the current name.
    static func canSave(newName: String, currentName: String) -> Bool {
        guard isValidName(newName) else { return false }
        return newName.trimmingCharacters(in: .whitespacesAndNewlines)
            != currentName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
