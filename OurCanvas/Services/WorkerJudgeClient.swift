import Foundation

/// Cloudflare Worker judge client (spec A5.1/A9.2). The deployed worker is
/// AUTHORITATIVE — this client never judges guesses locally and never touches the
/// secret before the round ends.
///
/// Configuration lives in Info.plist (`GuessWorkerBaseURL` / `GuessWorkerApiKey`) so
/// real credentials are never committed to source control. Fill them in the Xcode
/// project (or project.yml locally) before TestFlight builds.
struct WorkerConfig {
    var baseURL: URL?
    var apiKey: String

    static let baseURLKey = "GuessWorkerBaseURL"
    static let apiKeyKey = "GuessWorkerApiKey"

    static func from(infoPlist: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> WorkerConfig {
        let urlString = infoPlist[baseURLKey] as? String ?? ""
        let key = infoPlist[apiKeyKey] as? String ?? ""
        let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        return WorkerConfig(baseURL: url, apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var isConfigured: Bool {
        baseURL != nil && !apiKey.isEmpty
    }
}

/// Judge response contract (worker → client).
struct JudgeResult: Equatable {
    var correct: Bool = false
    var word: String? = nil
    var gaveUp: Bool = false
    var roundOver: Bool = false
    var lostRace: Bool = false
    var winnerName: String? = nil
}

protocol GuessJudging {
    func judge(action: String,
               gameId: String,
               userId: String,
               userName: String,
               guess: String) async throws -> JudgeResult
}

/// Pure payload/response helpers (unit-tested) + the URLSession transport.
final class WorkerJudgeClient: GuessJudging {
    let config: WorkerConfig
    private let urlSession: URLSession

    init(config: WorkerConfig = WorkerConfig.from(), urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    // MARK: - Request/response contract (pure, tested)

    static func requestPayload(action: String,
                               gameId: String,
                               userId: String,
                               userName: String,
                               guess: String) -> [String: Any] {
        [
            "action": action,
            "gameId": gameId,
            "userId": userId,
            "userName": userName,
            "guess": guess,
        ]
    }

    static func parseResponse(_ data: Data) -> JudgeResult? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        var result = JudgeResult()
        result.correct = FieldCast.bool(json["correct"]) ?? false
        result.word = FieldCast.string(json["word"])
        result.gaveUp = FieldCast.bool(json["gaveUp"]) ?? false
        result.roundOver = FieldCast.bool(json["roundOver"]) ?? false
        result.lostRace = FieldCast.bool(json["lostRace"]) ?? false
        result.winnerName = FieldCast.string(json["winnerName"])
        return result
    }

    // MARK: - Transport

    func judge(action: String,
               gameId: String,
               userId: String,
               userName: String,
               guess: String) async throws -> JudgeResult {
        guard let url = config.baseURL, config.isConfigured else {
            throw AppError.underlying("Guess judging isn't configured for this build yet. Coming soon!")
        }

        let payload = Self.requestPayload(action: action,
                                          gameId: gameId,
                                          userId: userId,
                                          userName: userName,
                                          guess: guess)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.network
        }
        guard let result = Self.parseResponse(data) else {
            throw AppError.decodingFailed
        }
        return result
    }
}
