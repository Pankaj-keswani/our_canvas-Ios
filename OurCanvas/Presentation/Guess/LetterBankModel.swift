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
    private(set) var lockedReveals: [Int: String] = [:] // slotIndex (0..<maxSlots) -> Character string

    init(bank: [String], maxSlots: Int, lockedReveals: [Int: String] = [:]) {
        self.bank = bank
        self.maxSlots = max(0, maxSlots)
        self.lockedReveals = lockedReveals
    }

    var unrevealedSlotCount: Int {
        max(0, maxSlots - lockedReveals.count)
    }

    var isFull: Bool {
        usedIndices.count >= unrevealedSlotCount
    }

    var canDelete: Bool {
        !usedIndices.isEmpty
    }

    var currentAnswer: String {
        var result = ""
        var userPickIter = usedIndices.compactMap { bank.indices.contains($0) ? bank[$0] : nil }.makeIterator()
        for i in 0..<maxSlots {
            if let locked = lockedReveals[i] {
                result.append(locked)
            } else if let userLetter = userPickIter.next() {
                result.append(userLetter)
            }
        }
        return result
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

    /// Removes the most recently selected user letter and returns its bank index.
    /// Locked reveals are never deleted.
    @discardableResult
    mutating func deleteLast() -> Int? {
        usedIndices.popLast()
    }

    /// Resets only the user-selected tiles; locked reveals are preserved.
    mutating func reset() {
        usedIndices.removeAll()
    }

    mutating func addLockedReveal(slotIndex: Int, letter: String) {
        lockedReveals[slotIndex] = letter
        while usedIndices.count > unrevealedSlotCount {
            usedIndices.popLast()
        }
    }

    func isSelected(_ index: Int) -> Bool {
        usedIndices.contains(index)
    }

    /// Detail for an answer slot at `index` (0..<maxSlots).
    func slotDetail(at index: Int) -> (letter: String, isLocked: Bool)? {
        if let locked = lockedReveals[index] {
            return (locked, true)
        }
        var userSlotCount = 0
        for i in 0..<index {
            if lockedReveals[i] == nil {
                userSlotCount += 1
            }
        }
        if userSlotCount < usedIndices.count {
            let bankIndex = usedIndices[userSlotCount]
            if bank.indices.contains(bankIndex) {
                return (bank[bankIndex], false)
            }
        }
        return nil
    }

    /// Letters in slot order (0..<maxSlots).
    var slotLetters: [String] {
        (0..<maxSlots).compactMap { slotDetail(at: $0)?.letter }
    }
}
