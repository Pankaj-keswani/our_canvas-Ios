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
