import Foundation

/// Deep-link routes shared by push payloads, invite links and widget URLs.
/// Phase 0: parse + persist. Navigation wiring for each destination lands in later phases.
enum AppRoute: Equatable {
    case drawingFeed(groupId: String, groupName: String?)
    case drawing(groupId: String, drawingId: String, groupName: String?)
    case guessGame(gameId: String)
    case circleInvite(code: String)

    /// Accepts:
    /// - custom scheme: `ourcanvas://feed?groupId=..&groupName=..`, `ourcanvas://invite?code=..`,
    ///   `ourcanvas://invite/ABC123`, `ourcanvas://game?gameId=..`
    /// - https links with Android push-payload style params:
    ///   `https://host?route=drawing_feed&groupId=..&groupName=..&drawingId=..`
    /// Unknown or malformed links return nil (fail gracefully).
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                params[item.name] = value
            }
        }

        // Path-style invite: ourcanvas://invite/CODE
        if url.scheme?.lowercased() == "ourcanvas",
           url.host?.lowercased() == "invite",
           params["code"] == nil {
            let pathCode = components.path
                .split(separator: "/")
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let pathCode, !pathCode.isEmpty {
                params["code"] = pathCode
            }
        }

        let routeName = (params["route"] ?? "").lowercased()

        if let gameId = params["gameId"], !gameId.isEmpty {
            self = .guessGame(gameId: gameId)
            return
        }

        if let code = params["code"] ?? params["inviteCode"], !code.isEmpty {
            self = .circleInvite(code: code)
            return
        }

        guard let groupId = params["groupId"], !groupId.isEmpty else {
            return nil
        }
        let groupName = params["groupName"]

        if let drawingId = params["drawingId"], !drawingId.isEmpty {
            self = .drawing(groupId: groupId, drawingId: drawingId, groupName: groupName)
            return
        }

        if routeName.isEmpty || routeName == "drawing_feed" {
            self = .drawingFeed(groupId: groupId, groupName: groupName)
            return
        }

        return nil
    }
}
