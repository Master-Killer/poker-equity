import SwiftUI
import PokerEngine

@MainActor
final class GameViewModel: ObservableObject {
    /// Each player's two (optional) hole cards. Two players by default.
    @Published var playerCards: [[Card?]] = [[nil, nil], [nil, nil]]
    /// Stable identity per player (kept in lock-step with `playerCards`) so the
    /// SwiftUI rows keep their own @State across insertions/removals.
    @Published private(set) var playerIDs: [UUID] = [UUID(), UUID()]
    /// Five (optional) community card slots.
    @Published var board: [Card?] = Array(repeating: nil, count: 5)
    /// The slot the picker currently writes to.
    @Published var focusedSlot: Slot? = .hole(player: 0, index: 0)
    /// Whether the 52-card picker is expanded (collapsible to free up space).
    @Published var isPickerVisible = true

    @Published private(set) var equity: EquityResult?
    @Published private(set) var outs: OutsResult?
    @Published private(set) var isCalculating = false

    private var calcTask: Task<Void, Never>?
    /// Signals the in-flight background enumeration to stop (Task.detached does
    /// not inherit calcTask's cancellation, and `compute` runs synchronously).
    private var cancelFlag: CancelFlag?

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

    func focus(_ slot: Slot) {
        focusedSlot = slot
        isPickerVisible = true // reopen the picker when a slot is selected
    }

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
        isPickerVisible = true // rouvrir le picker pour reposer une carte
        recompute()
    }

    /// Tap sur un emplacement (main ou tableau) : s'il contient une carte, on la
    /// retire (désélection) ; sinon on place le focus dessus.
    func tapSlot(_ slot: Slot) {
        if card(at: slot) != nil {
            clearCard(at: slot)
        } else {
            focus(slot)
        }
    }

    func addPlayer() {
        guard playerCards.count < 9 else { return }
        playerCards.append([nil, nil])
        playerIDs.append(UUID())
        recompute()
    }

    func removePlayer(_ p: Int) {
        guard playerCards.count > 2, playerCards.indices.contains(p) else { return }
        playerCards.remove(at: p)
        playerIDs.remove(at: p)
        // Keep the focus on the same logical card after the index shift.
        if case .hole(let q, let i) = focusedSlot {
            if q == p {
                focusedSlot = firstEmptySlot()
            } else if q > p {
                focusedSlot = .hole(player: q - 1, index: i)
            }
        }
        recompute()
    }

    func reset() {
        calcTask?.cancel()
        cancelFlag?.cancel()
        playerCards = [[nil, nil], [nil, nil]]
        playerIDs = [UUID(), UUID()]
        board = Array(repeating: nil, count: 5)
        focusedSlot = .hole(player: 0, index: 0)
        equity = nil
        outs = nil
        isCalculating = false
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
        cancelFlag?.cancel() // stop the previous background enumeration
        guard let hands = completeHands() else {
            equity = nil
            outs = nil
            isCalculating = false
            return
        }
        let boardCards = board.compactMap { $0 }
        let flag = CancelFlag()
        cancelFlag = flag
        isCalculating = true
        calcTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                // Exact enumeration everywhere (including preflop). Slower on
                // device for large spaces, but precise to the last decimal.
                EquityCalculator.compute(hands: hands, board: boardCards,
                                         shouldCancel: { flag.isCancelled })
            }.value
            if flag.isCancelled { return }
            let outsResult: OutsResult? = (boardCards.count == 3 || boardCards.count == 4)
                ? await Task.detached(priority: .userInitiated) {
                    OutsAnalyzer.analyze(hands: hands, board: boardCards)
                }.value
                : nil
            guard let self, !Task.isCancelled, !flag.isCancelled else { return }
            self.equity = result
            self.outs = outsResult
            self.isCalculating = false
        }
    }
}

/// Thread-safe one-shot cancellation flag shared with a background computation.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
