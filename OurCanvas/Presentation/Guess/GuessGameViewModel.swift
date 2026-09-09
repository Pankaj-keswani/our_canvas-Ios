import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
final class GuessGameViewModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var game: GuessGame?
    @Published private(set) var cardState: GuessCardState = .noGame
    @Published var letterBank = LetterBankModel(bank: [], maxSlots: 0)
    @Published private(set) var isChecking = false
    @Published private(set) var guessFeedback: String?
    @Published private(set) var drawerSecretWord: String?
    @Published private(set) var lastJudgeResult: JudgeResult?
    @Published var errorText: String?
    @Published private(set) var isLoading = true
    @Published var showGameCanvas = false

    // MARK: Dependencies

    let group: Group
    private let repository: GuessGameRepository
    private var listener: ListenerRegistration?
    private let userScopedStore: UserScopedStore

    var currentUID: String? { Auth.auth().currentUser?.uid }
    var currentUserName: String {
        UserRepository.shared.currentUserProfile?.displayName
            ?? Auth.auth().currentUser?.displayName
            ?? "Someone"
    }

    init(group: Group, repository: GuessGameRepository = GuessGameRepository()) {
        self.group = group
        self.repository = repository
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"
        self.userScopedStore = UserScopedStore(uid: uid)
        startListening()
    }

    deinit {
        listener?.remove()
    }

    func startListening() {
        listener?.remove()
        listener = repository.listenToLatestGame(groupId: group.groupId) { [weak self] game in
            DispatchQueue.main.async {
                self?.applyGame(game)
            }
        }
    }

    // MARK: - State derivation

    private func applyGame(_ game: GuessGame?) {
        self.game = game
        let uid = currentUID ?? ""
        cardState = GuessCardState.derive(
            game: game,
            uid: uid,
            localRevealedWord: revealedWord(for: game)
        )
        if let game, letterBank.maxSlots != game.wordLength || letterBank.bank != game.letterBank {
            letterBank = LetterBankModel(bank: game.letterBank, maxSlots: game.wordLength)
        }
        isLoading = false

        // Drawer word recall: fetch the sealed secret (drawer-only read).
        if case .drawingAsDrawer(let current, _) = cardState, current.id != lastSecretFetchGameId {
            lastSecretFetchGameId = current.id
            Task { await fetchDrawerWord(gameId: current.id) }
        }
    }

    private var lastSecretFetchGameId: String?

    private func fetchDrawerWord(gameId: String) async {
        guard let word = try? await repository.fetchSecretWord(gameId: gameId) else { return }
        drawerSecretWord = word
        refreshCardState()
    }

    private func refreshCardState() {
        let uid = currentUID ?? ""
        cardState = GuessCardState.derive(
            game: game,
            uid: uid,
            localRevealedWord: revealedWord(for: game)
        )
    }

    // MARK: - Reveal storage (Android key format: {gameId}_{uid} per user)

    private func revealedWord(for game: GuessGame?) -> String? {
        guard let game else { return nil }
        return userScopedStore.revealedWord(gameId: game.id)
    }

    // MARK: - Round actions

    func startNewRound() {
        guard let uid = currentUID else { return }
        Task {
            do {
                let created = try await repository.createRound(groupId: group.groupId,
                                                               memberIds: group.memberIds,
                                                               drawerId: uid,
                                                               drawerName: currentUserName)
                await MainActor.run {
                    drawerSecretWord = GuessNormalizer.normalize(created.pair.word)
                    showGameCanvas = true
                }
            } catch {
                await MainActor.run { errorText = AppError.from(error).message }
            }
        }
    }

    func openCanvasAsDrawer() {
        showGameCanvas = true
    }

    func publishDrawing(strokeData: String) {
        guard let game else { return }
        Task {
            do {
                try await repository.publishDrawing(gameId: game.id, strokeData: strokeData)
            } catch {
                await MainActor.run { errorText = AppError.from(error).message }
            }
        }
    }

    func shuffleWord() {
        guard let game else { return }
        Task {
            do {
                let pair = try await repository.shuffleWord(gameId: game.id)
                await MainActor.run {
                    drawerSecretWord = GuessNormalizer.normalize(pair.word)
                }
            } catch {
                await MainActor.run { errorText = AppError.from(error).message }
            }
        }
    }

    // MARK: - Guessing

    func submitLetterSelection() {
        guard case .guessing(let game, _) = cardState else { return }
        let answer = letterBank.currentAnswer
        guard !answer.isEmpty, !isChecking, let uid = currentUID else { return }

        isChecking = true
        guessFeedback = nil
        Task {
            do {
                let result = try await repository.checkGuess(
                    gameId: game.id,
                    userId: uid,
                    userName: currentUserName,
                    guess: answer
                )
                await MainActor.run { handleJudgeResult(result, correctCopy: answer) }
            } catch {
                await MainActor.run {
                    isChecking = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }

    func submitLegacyGuess(_ guess: String) {
        guard case .legacyGuessing(let game) = cardState else { return }
        let normalized = GuessNormalizer.normalize(guess)
        guard !normalized.isEmpty, !isChecking, let uid = currentUID else { return }

        isChecking = true
        Task {
            do {
                let result = try await repository.checkGuess(
                    gameId: game.id,
                    userId: uid,
                    userName: currentUserName,
                    guess: normalized
                )
                await MainActor.run { handleJudgeResult(result, correctCopy: normalized) }
            } catch {
                await MainActor.run {
                    isChecking = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }

    private func handleJudgeResult(_ result: JudgeResult, correctCopy: String) {
        isChecking = false
        lastJudgeResult = result

        switch GuessOutcomeAction.action(for: result) {
        case .correct:
            guessFeedback = nil
            letterBank.reset()
            // Round finished — listener flips the card to FinishedCard.
        case .lostRace(let winnerName):
            guessFeedback = "So close — \(winnerName) got it first! ⚡"
            letterBank.reset()
        case .revealed(let word):
            userScopedStore.setRevealedWord(word, gameId: game?.id ?? "")
            guessFeedback = nil
            refreshCardState()
        case .wrong:
            // Plain wrong guess: slots clear, round continues.
            guessFeedback = "Not quite — try again!"
            letterBank.reset()
        case .none:
            break
        }
    }

    func revealWord() {
        guard case .guessing(let game, _) = cardState else { return }
        guard let uid = currentUID, !isChecking else { return }

        isChecking = true
        Task {
            do {
                let result = try await repository.giveUp(
                    gameId: game.id,
                    userId: uid,
                    userName: currentUserName
                )
                await MainActor.run {
                    isChecking = false
                    // Worker replays {gaveUp:true, word} on retries after a lost
                    // response — persisting it here is what keeps the reveal card
                    // from ever showing a blank word.
                    if let word = result.word, !word.isEmpty {
                        userScopedStore.setRevealedWord(word, gameId: game.id)
                    }
                    refreshCardState()
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    errorText = AppError.from(error).message
                }
            }
        }
    }

    // MARK: - Takeover

    var canTakeOver: Bool {
        guard let game else { return false }
        return GuessTakeover.canTakeOver(game: game, uid: currentUID ?? "")
    }

    func takeOverDrawing() {
        guard let game, let uid = currentUID else { return }
        Task {
            do {
                try await repository.takeOverDrawing(gameId: game.id, userId: uid, userName: currentUserName)
                await MainActor.run { showGameCanvas = true }
            } catch {
                await MainActor.run { errorText = AppError.from(error).message }
            }
        }
    }

    // MARK: - Letter bank passthroughs (view intents)

    func selectLetter(index: Int) {
        letterBank.select(index: index)
    }

    func deleteLastLetter() {
        guard !isChecking else { return }
        letterBank.deleteLast()
    }
}
