import SwiftUI

/// The Guess tab: renders whichever card the state machine derives — no business
/// logic lives in the cards themselves.
struct GuessGameTabView: View {
    @StateObject private var viewModel: GuessGameViewModel
    @State private var legacyGuess = ""

    init(group: Group) {
        _viewModel = StateObject(wrappedValue: GuessGameViewModel(group: group))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top coin action row
                HStack {
                    Spacer()
                    Button {
                        viewModel.showCoinWallet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("🪙")
                                .font(.caption)
                            Text("\(viewModel.userCoins)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.yellow.opacity(0.3)))
                        .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.6), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 4)

                if viewModel.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    card
                }

                if let error = viewModel.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .sheet(isPresented: $viewModel.showCoinWallet) {
            CoinWalletSheet()
        }
        .fullScreenCover(isPresented: $viewModel.showGameCanvas) {
            NavigationStack {
                GameDrawingScreen(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch viewModel.cardState {
        case .noGame:
            StartCard(onStart: { viewModel.startNewRound() })
        case .drawingAsDrawer(let game, let word):
            GameInfoCard(game: game,
                         word: word ?? viewModel.drawerSecretWord,
                         onOpenCanvas: { viewModel.openCanvasAsDrawer() },
                         onShuffle: { viewModel.shuffleWord() })
        case .drawingWaiting(let game):
            if viewModel.canTakeOver {
                TakeoverCard(drawerName: game.drawerName,
                             onTakeOver: { viewModel.takeOverDrawing() })
            } else {
                WaitingCard(game: game)
            }
        case .turnExpiredDrawer(let game):
            TurnExpiredDrawerCard(game: game)
        case .turnExpiredOthers(_, let drawerName):
            TurnExpiredOthersCard(drawerName: drawerName,
                                  onClaim: { viewModel.claimTurn() })
        case .guessing(let game, _):
            GuessingCard(viewModel: viewModel, game: game)
        case .gaveUpSpectate(let game, let revealedWord):
            GaveUpCard(game: game, revealedWord: revealedWord)
        case .legacyGuessing(let game):
            LegacyGuessingCard(game: game,
                               guess: $legacyGuess,
                               isChecking: viewModel.isChecking,
                               feedback: viewModel.guessFeedback,
                               onSubmit: { viewModel.submitLegacyGuess(legacyGuess); legacyGuess = "" })
        case .legacySpectator(let game):
            LegacySpectatorCard(game: game)
        case .finished(let game):
            FinishedCard(viewModel: viewModel, game: game)
        }
    }
}

// MARK: - StartCard

private struct StartCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 44))
                .foregroundStyle(BrandGradient.primary)
            Text("Guess My Doodle")
                .font(.headline)
            Text("Draw a mystery doodle and let your whole circle race to guess it — first correct answer wins and draws next!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            PrimaryGradientButton(title: "Start New Round", action: onStart)
        }
        .glassCard()
    }
}

// MARK: - GameInfoCard (drawer)

private struct GameInfoCard: View {
    let game: GuessGame
    let word: String?
    let onOpenCanvas: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Label("You're drawing this round 🎨", systemImage: "paintbrush.pointed.fill")
                .font(.headline)

            if let word, !word.isEmpty {
                // Drawer word recall — visible to the drawer only (secret is rules-protected).
                Text("Your word was \(word)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BrandColor.primary.opacity(0.15)))
                Text("Hint — category: \(game.wordHint)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Hint — category: \(game.wordHint)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onShuffle) {
                Label("Shuffle word 🔄", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
            }

            PrimaryGradientButton(title: "Open Canvas", action: onOpenCanvas)
        }
        .glassCard()
    }
}

// MARK: - WaitingCard

private struct WaitingCard: View {
    let game: GuessGame

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("\(game.drawerName) is drawing…")
                .font(.headline)
            Text("The race starts as soon as their doodle lands. Get those guessing fingers ready! ⚡")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .glassCard()
    }
}

// MARK: - TakeoverCard (24h legacy)

private struct TakeoverCard: View {
    let drawerName: String
    let onTakeOver: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass.bottomhalf.fill")
                .font(.system(size: 36))
                .foregroundColor(BrandColor.warning)
            Text("\(drawerName) hasn't drawn for over 24 hours")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("You can take over the pen and draw this round yourself.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            PrimaryGradientButton(title: "Take Over Drawing", action: onTakeOver)
        }
        .glassCard()
    }
}

// MARK: - Turn Expired Cards (24h Auto-pass)

private struct TurnExpiredDrawerCard: View {
    let game: GuessGame

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(BrandColor.warning)

            Text("Your 24h turn window expired ⏳")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Your turn to draw passed because 24 hours elapsed. Anyone in the circle can now claim the pen!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .glassCard()
    }
}

private struct TurnExpiredOthersCard: View {
    let drawerName: String
    let onClaim: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(BrandColor.warning)

            Text("Turn passed ⏳")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("\(drawerName) didn't draw within 24 hours.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            PrimaryGradientButton(title: "Claim Pen & Draw 🎨", action: onClaim)
        }
        .glassCard()
    }
}

// MARK: - GuessingCard (race mode + progressive letter hints)

private struct GuessingCard: View {
    @ObservedObject var viewModel: GuessGameViewModel
    let game: GuessGame

    var body: some View {
        VStack(spacing: 14) {
            // ⚡ Race mode banner
            HStack(spacing: 8) {
                Text("⚡")
                Text("Race mode — everyone's guessing at once!")
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(BrandColor.secondary.opacity(0.18)))
            .foregroundColor(BrandColor.secondary)

            // Hint line
            Text("Hint — category: \(game.wordHint)")
                .font(.caption)
                .foregroundColor(.secondary)

            // The doodle everyone's guessing at
            if !game.strokeData.isEmpty {
                DoodlePreviewView(strokeData: game.strokeData, height: 220)
            }

            // Answer slots (wrapped rows with locked reveal styling)
            AnswerSlotsView(letterBank: viewModel.letterBank,
                            totalSlots: max(game.wordLength, viewModel.letterBank.maxSlots))

            // Letter bank (wrapped rows, no horizontal scrolling)
            LetterBankGridView(bank: viewModel.letterBank.bank,
                               usedIndices: viewModel.letterBank.usedIndices,
                               disabled: viewModel.isChecking || viewModel.letterBank.isFull,
                               onSelect: { viewModel.selectLetter(index: $0) })

            if viewModel.isChecking || viewModel.isRevealingLetter {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.isRevealingLetter ? "Revealing letter…" : "Checking…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let feedback = viewModel.guessFeedback {
                Text(feedback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(BrandColor.warning)
                    .multilineTextAlignment(.center)
            }

            // Previous tries
            if !game.recentAttempts.isEmpty {
                VStack(spacing: 4) {
                    Text("Previous tries: \(game.recentAttempts.map { $0.guess }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 12) {
                Button(action: { viewModel.deleteLastLetter() }) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
                // Delete disabled at ~30% alpha when empty or judging.
                .opacity(viewModel.letterBank.canDelete && !viewModel.isChecking && !viewModel.isRevealingLetter ? 1.0 : 0.3)
                .disabled(!viewModel.letterBank.canDelete || viewModel.isChecking || viewModel.isRevealingLetter)
                .accessibilityLabel("Delete letter")

                Button(action: { viewModel.submitLetterSelection() }) {
                    Text("Guess!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(BrandGradient.primary))
                        .foregroundColor(.black)
                }
                .disabled(!viewModel.letterBank.isFull || viewModel.isChecking || viewModel.isRevealingLetter)
                .opacity(viewModel.letterBank.isFull && !viewModel.isChecking && !viewModel.isRevealingLetter ? 1.0 : 0.5)
            }

            // Progressive Letter Reveal Hint Action
            if !viewModel.canRevealMoreLetters {
                Text("Final letter! Solve it! 🎯")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else if viewModel.hasEnoughCoinsForHint {
                Button {
                    viewModel.revealLetterHint()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("✨ Reveal Letter (\(viewModel.hintCost) 🪙)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(BrandColor.primary)
                }
                .disabled(viewModel.isChecking || viewModel.isRevealingLetter)
            } else {
                Button {
                    viewModel.showCoinWallet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                        Text("🎬 Get Coins (Watch Ad)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.orange)
                }
                .disabled(viewModel.isChecking || viewModel.isRevealingLetter)
            }
        }
        .glassCard()
    }
}

// MARK: - Letter bank grid (wrapped, adaptive, 6-per-row look)

struct LetterBankGridView: View {
    let bank: [String]
    let usedIndices: [Int]
    let disabled: Bool
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 46, maximum: 54), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(bank.enumerated()), id: \.offset) { index, letter in
                let used = usedIndices.contains(index)
                Button {
                    onSelect(index)
                } label: {
                    Text(letter)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(used ? Color(.systemGray4) : BrandColor.surface))
                        .foregroundColor(used ? Color(.systemGray3) : BrandColor.textPrimary)
                        .overlay(Circle().strokeBorder(used ? Color.clear : BrandColor.primary.opacity(0.5), lineWidth: 1.5))
                }
                .disabled(used || disabled)
                .opacity(used ? 0.35 : 1.0)
                .accessibilityLabel("Letter \(letter)")
            }
        }
    }
}

// MARK: - Answer slots (wrapped rows with locked reveal styling)

struct AnswerSlotsView: View {
    let letterBank: LetterBankModel
    let totalSlots: Int

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<max(totalSlots, letterBank.maxSlots), id: \.self) { slot in
                let detail = letterBank.slotDetail(at: slot)
                let letter = detail?.letter ?? ""
                let isLocked = detail?.isLocked ?? false

                RoundedRectangle(cornerRadius: 8)
                    .fill(isLocked ? Color.yellow.opacity(0.25) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isLocked ? Color.yellow : BrandColor.primary.opacity(0.6), lineWidth: isLocked ? 2 : 1.5)
                    )
                    .frame(height: 42)
                    .overlay(
                        Text(letter)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(isLocked ? Color.yellow.opacity(0.95) : BrandColor.textPrimary)
                    )
            }
        }
    }
}

// MARK: - GaveUp spectate

private struct GaveUpCard: View {
    let game: GuessGame
    let revealedWord: String

    var body: some View {
        VStack(spacing: 12) {
            Label("You revealed the word", systemImage: "eye.fill")
                .font(.headline)
            if !revealedWord.isEmpty {
                Text("The word was \(revealedWord)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BrandColor.warning.opacity(0.2)))
            }
            Text("The round continues for everyone else — enjoy the show! 🍿")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if !game.strokeData.isEmpty {
                DoodlePreviewView(strokeData: game.strokeData, height: 200)
            }
        }
        .glassCard()
    }
}

// MARK: - Legacy 1v1

private struct LegacyGuessingCard: View {
    let game: GuessGame
    @Binding var guess: String
    let isChecking: Bool
    let feedback: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label("You're the guesser!", systemImage: "person.questionmark.fill")
                .font(.headline)
            Text("Hint — category: \(game.wordHint)")
                .font(.caption)
                .foregroundColor(.secondary)
            if !game.strokeData.isEmpty {
                DoodlePreviewView(strokeData: game.strokeData, height: 200)
            }
            HStack {
                TextField("Type your guess…", text: $guess)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSubmit)
                Button("Guess", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking || guess.trimmed.isEmpty)
            }
            if isChecking { ProgressView() }
            if let feedback {
                Text(feedback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(BrandColor.warning)
            }
        }
        .glassCard()
    }

    private var doodleDrawing: Drawing {
        var drawing = Drawing()
        drawing.strokeData = game.strokeData
        return drawing
    }
}

private struct LegacySpectatorCard: View {
    let game: GuessGame

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("\(game.drawerName) drew a doodle for \(game.guesserId ?? "the guesser") to solve")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("You're spectating this classic 1v1 round.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !game.strokeData.isEmpty {
                DoodlePreviewView(strokeData: game.strokeData, height: 200)
            }
        }
        .glassCard()
    }
}

// MARK: - FinishedCard (CTA ABOVE the replay)

private struct FinishedCard: View {
    @ObservedObject var viewModel: GuessGameViewModel
    let game: GuessGame

    var body: some View {
        VStack(spacing: 14) {
            // Status + next-round CTA come FIRST (above the tall replay).
            if game.result == .gaveUp {
                Label("Nobody cracked it — the drawer keeps the pen! ✏️", systemImage: "face.dashed")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else if let winnerName = game.winnerName, !winnerName.isEmpty {
                Label("🏆 \(winnerName) cracked the doodle!", systemImage: "trophy.fill")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

            if let word = game.revealedWord, !word.isEmpty {
                Text("The word was \(word)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BrandColor.primary.opacity(0.15)))
            }

            if !game.recentAttempts.isEmpty {
                Text("Tries: \(game.recentAttempts.map { $0.guess }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Next-round CTA (winner gets the action; others see who draws next).
            if viewModel.currentUID == game.nextDrawerId {
                PrimaryGradientButton(title: game.result == .gaveUp
                                      ? "You keep the pen — draw again 🎨"
                                      : "You draw the next round 🎨") {
                    viewModel.startNewRound()
                }
            } else {
                Text("\(game.nextDrawerName) draws the next round 🎨")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Tall doodle replay LAST so the CTA stays above the fold.
            if !game.strokeData.isEmpty {
                ReplayView(drawing: doodleDrawing)
                    .frame(height: 260)
            }
        }
        .glassCard()
    }

    private var doodleDrawing: Drawing {
        var drawing = Drawing()
        drawing.strokeData = game.strokeData
        return drawing
    }
}


// MARK: - Static doodle preview (lightweight, used while guessing)

struct DoodlePreviewView: View {
    let strokeData: String
    var height: CGFloat = 220

    @State private var image: UIImage?

    var body: some View {
        SwiftUI.Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .frame(maxHeight: height)
        .background(Color.white)
        .cornerRadius(12)
        .onAppear { render() }
    }

    private func render() {
        let parsed = StrokeSerializer.decode(strokeData)
        image = StrokeRenderer.renderComposite(background: parsed.background,
                                               strokes: parsed.strokes,
                                               stickers: [],
                                               texts: [],
                                               canvasSize: CGSize(width: parsed.canvasWidth, height: parsed.canvasHeight),
                                               outputPixels: 440)
    }
}
