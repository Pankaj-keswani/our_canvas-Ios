import Foundation

/// Pure letter-bank selection model (Android A5.1 interaction contract):
/// - letters are never removed from the source pool permanently — selection only
///   marks tiles used;
/// - Delete returns the MOST RECENTLY selected letter to the available bank;
/// - at most `maxSlots` letters may be selected (one per answer slot).
struct LetterBankModel: Equatable {
    let bank: [String]
    let maxSlots: Int
    private(set) var usedIndices: [Int] = []

    init(bank: [String], maxSlots: Int) {
        self.bank = bank
        self.maxSlots = max(0, maxSlots)
    }

    var isFull: Bool { usedIndices.count >= maxSlots }

    var canDelete: Bool { !usedIndices.isEmpty }

    var currentAnswer: String {
        usedIndices.compactMap { bank.indices.contains($0) ? bank[$0] : nil }.joined()
    }

    var availableIndices: [Int] {
        bank.indices.filter { !usedIndices.contains($0) }
    }

    mutating func select(index: Int) {
        guard bank.indices.contains(index),
              !usedIndices.contains(index),
              !isFull else { return }
        usedIndices.append(index)
    }

    /// Removes the most recently selected letter and returns its bank index
    /// (so callers can restore the tile to the available bank).
    @discardableResult
    mutating func deleteLast() -> Int? {
        usedIndices.popLast()
    }

    mutating func reset() {
        usedIndices.removeAll()
    }

    func isSelected(_ index: Int) -> Bool {
        usedIndices.contains(index)
    }

    /// Order in which tiles were picked (slot content), used to render answer slots.
    var slotLetters: [String] {
        usedIndices.compactMap { bank.indices.contains($0) ? bank[$0] : nil }
    }
}
