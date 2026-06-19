import SwiftUI
import PokerEngine

@MainActor
final class GameViewModel: ObservableObject {
    /// Each player's two (optional) hole cards. Two players by default.
    @Published var playerCards: [[Card?]] = [[nil, nil], [nil, nil]]
    /// Five (optional) community card slots.
    @Published var board: [Card?] = Array(repeating: nil, count: 5)
    /// The slot the picker currently writes to.
    @Published var focusedSlot: Slot? = .hole(player: 0, index: 0)

    @Published private(set) var equity: EquityResult?
    @Published private(set) var outs: OutsResult?
    @Published private(set) var isCalculating = false

    private var calcTask: Task<Void, Never>?

    // MARK: Derived

    /// Focus traversal order: hands first, then the board.
    var orderedSlots: [Slot] {
        var slots: [Slot] = []
        for p in playerCards.indices {
            slots.append(.hole(player: p, index: 0))
            slots.append(.hole(player: p, index: 1))
        }
        for b in board.indices { slots.append(.board(b)) }
        return slots
    }

    var usedCards: Set<Card> {
        var set = Set<Card>()
        for hand in playerCards { for case let card? in hand { set.insert(card) } }
        for case let card? in board { set.insert(card) }
        return set
    }

    func card(at slot: Slot) -> Card? {
        switch slot {
        case .hole(let p, let i): return playerCards[safe: p]?[safe: i] ?? nil
        case .board(let b): return board[safe: b] ?? nil
        }
    }

    // MARK: Mutation

    private func set(_ card: Card?, at slot: Slot) {
        switch slot {
        case .hole(let p, let i):
            guard playerCards.indices.contains(p), playerCards[p].indices.contains(i) else { return }
            playerCards[p][i] = card
        case .board(let b):
            guard board.indices.contains(b) else { return }
            board[b] = card
        }
    }

    func focus(_ slot: Slot) { focusedSlot = slot }

    /// A tap in the picker grid: place the card at the focus, or remove it if it
    /// is already in play (and move the focus to the freed slot).
    func tapPickerCard(_ card: Card) {
        if let existing = slotContaining(card) {
            set(nil, at: existing)
            focusedSlot = existing
        } else {
            guard let slot = focusedSlot else { return }
            set(card, at: slot)
            advanceFocus()
        }
        recompute()
    }

    func clearCard(at slot: Slot) {
        set(nil, at: slot)
        focusedSlot = slot
        recompute()
    }

    func addPlayer() {
        guard playerCards.count < 9 else { return }
        playerCards.append([nil, nil])
        recompute()
    }

    func removePlayer(_ p: Int) {
        guard playerCards.count > 2, playerCards.indices.contains(p) else { return }
        playerCards.remove(at: p)
        if !orderedSlots.contains(where: { $0 == focusedSlot }) {
            focusedSlot = firstEmptySlot()
        }
        recompute()
    }

    func reset() {
        calcTask?.cancel()
        playerCards = [[nil, nil], [nil, nil]]
        board = Array(repeating: nil, count: 5)
        focusedSlot = .hole(player: 0, index: 0)
        equity = nil
        outs = nil
    }

    // MARK: Focus

    private func slotContaining(_ card: Card) -> Slot? {
        orderedSlots.first { self.card(at: $0) == card }
    }

    private func firstEmptySlot() -> Slot? {
        orderedSlots.first { card(at: $0) == nil }
    }

    private func advanceFocus() {
        let slots = orderedSlots
        guard let current = focusedSlot, let idx = slots.firstIndex(of: current) else {
            focusedSlot = firstEmptySlot()
            return
        }
        let next = slots[(idx + 1)...].first { card(at: $0) == nil }
        focusedSlot = next ?? firstEmptySlot()
    }

    // MARK: Calculation

    private func completeHands() -> [[Card]]? {
        var hands: [[Card]] = []
        for hand in playerCards {
            guard let c0 = hand[0], let c1 = hand[1] else { return nil }
            hands.append([c0, c1])
        }
        return hands.count >= 2 ? hands : nil
    }

    func recompute() {
        calcTask?.cancel()
        guard let hands = completeHands() else {
            equity = nil
            outs = nil
            isCalculating = false
            return
        }
        let boardCards = board.compactMap { $0 }
        isCalculating = true
        calcTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                EquityCalculator.compute(hands: hands, board: boardCards)
            }.value
            let outsResult: OutsResult? = (boardCards.count == 3 || boardCards.count == 4)
                ? await Task.detached(priority: .userInitiated) {
                    OutsAnalyzer.analyze(hands: hands, board: boardCards)
                }.value
                : nil
            guard let self, !Task.isCancelled else { return }
            self.equity = result
            self.outs = outsResult
            self.isCalculating = false
        }
    }
}
