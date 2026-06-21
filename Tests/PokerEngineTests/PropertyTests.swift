import XCTest
import SwiftCheck
@testable import PokerEngine

/// A randomly dealt situation: each player's two hole cards plus a board.
/// All cards are guaranteed distinct because they are taken from one shuffled deck.
private struct Deal {
    let hands: [[Card]]
    let board: [Card]
}

/// Deal `players` hands and a `boardSize`-card board from a deck shuffled with the
/// engine's own deterministic RNG. Using `SplitMix64` (exposed via `@testable`)
/// keeps deals uniform and fully reproducible from `seed`.
private func makeDeal(players: Int, boardSize: Int, seed: UInt64) -> Deal {
    var deck = Card.fullDeck
    var rng = SplitMix64(seed: seed)
    // Fisher–Yates.
    for i in 0..<(deck.count - 1) {
        let j = Int.random(in: i..<deck.count, using: &rng)
        deck.swapAt(i, j)
    }
    var hands = [[Card]]()
    var idx = 0
    for _ in 0..<players {
        hands.append([deck[idx], deck[idx + 1]])
        idx += 2
    }
    let board = Array(deck[idx ..< idx + boardSize])
    return Deal(hands: hands, board: board)
}

// A bounded range avoids overflow inside SwiftCheck's `choose`; a billion distinct
// seeds is ample entropy for the deal shuffler across a property run.
private let seedGen: Gen<UInt64> =
    Gen<Int>.choose((0, 1_000_000_000)).map { UInt64($0) }

/// Any street, 2–4 players. For properties that never enumerate runouts.
private let anyDealGen: Gen<Deal> =
    Gen<Int>.choose((2, 4)).flatMap { players in
        Gen<Int>.choose((0, 5)).flatMap { boardSize in
            seedGen.map { makeDeal(players: players, boardSize: boardSize, seed: $0) }
        }
    }

/// Post-flop (board 3–5), 2–3 players, so every equity enumeration is cheap
/// (at most C(45,2) = 990 runouts) and the whole suite stays fast in CI.
private let postflopDealGen: Gen<Deal> =
    Gen<Int>.choose((2, 3)).flatMap { players in
        Gen<Int>.choose((3, 5)).flatMap { boardSize in
            seedGen.map { makeDeal(players: players, boardSize: boardSize, seed: $0) }
        }
    }

/// Cards "simpler" than `c`, for shrinking: lower ranks (toward the 2) then
/// lower suits (toward spades). Bigger reductions are offered first.
private func simplerCards(_ c: Card) -> [Card] {
    var out = [Card]()
    for r in [2, (c.rank + 2) / 2, c.rank - 1] where r >= 2 && r < c.rank {
        out.append(Card(rank: r, suit: c.suit))
    }
    for s in 0..<c.suit.rawValue {
        out.append(Card(rank: c.rank, suit: Suit(rawValue: s)!))
    }
    return out
}

extension Deal: Arbitrary {
    /// Used only as the default generator; every property passes an explicit,
    /// cost-bounded generator and reuses this `shrink` for minimisation.
    static var arbitrary: Gen<Deal> { anyDealGen }

    /// Shrink toward a minimal failing deal while preserving every invariant:
    /// all cards stay distinct, hands keep two cards, the board keeps its size
    /// (so a shrunk deal never costs more to enumerate than the original).
    static func shrink(_ deal: Deal) -> [Deal] {
        var candidates = [Deal]()

        // 1) Fewer players (never below the two compute() requires).
        if deal.hands.count > 2 {
            for i in deal.hands.indices {
                var hands = deal.hands
                hands.remove(at: i)
                candidates.append(Deal(hands: hands, board: deal.board))
            }
        }

        // 2) Simplify one card at a time toward the 2 of spades.
        let flat = deal.hands.flatMap { $0 } + deal.board
        for i in flat.indices {
            var others = Set(flat)
            others.remove(flat[i])
            for replacement in simplerCards(flat[i]) where !others.contains(replacement) {
                var copy = flat
                copy[i] = replacement
                candidates.append(rebuild(copy, like: deal))
            }
        }
        return candidates
    }

    /// Reassemble a flat card list into the hand/board shape of `template`.
    private static func rebuild(_ flat: [Card], like template: Deal) -> Deal {
        var hands = [[Card]]()
        var idx = 0
        for hand in template.hands {
            hands.append(Array(flat[idx ..< idx + hand.count]))
            idx += hand.count
        }
        let board = Array(flat[idx ..< idx + template.board.count])
        return Deal(hands: hands, board: board)
    }
}

final class PropertyTests: XCTestCase {

    // MARK: - Evaluator

    func testEvaluateMatchesBestFive() {
        property("evaluate(5...7) == evaluate5(bestFive)") <- forAll(postflopDealGen) { deal in
            for hand in deal.hands {
                let cards = hand + deal.board
                if evaluate(cards).score != evaluate5(bestFive(cards)).score { return false }
            }
            return true
        }
    }

    func testHigherCategoryAlwaysOutranks() {
        property("a stronger category always packs a higher score") <- forAll(postflopDealGen) { deal in
            let ranks = deal.hands.map { evaluate($0 + deal.board) }
            for a in ranks {
                for b in ranks where a.category > b.category {
                    if a.score <= b.score { return false }
                }
            }
            return true
        }
    }

    // MARK: - Equity

    func testEquityIsAProbabilityDistribution() {
        property("equities lie in [0,1] and sum to 1") <- forAll(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            let sum = r.players.reduce(0.0) { $0 + $1.equity }
            guard abs(sum - 1.0) <= 1e-9 else { return false }
            return r.players.allSatisfy { $0.equity >= -1e-12 && $0.equity <= 1 + 1e-12 }
        }
    }

    func testCoWinDiagonalEqualsWinPlusTie() {
        property("coWinMatrix diagonal == win + tie probability") <- forAll(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            for p in r.players.indices {
                let expected = r.players[p].winProb + r.players[p].tieProb
                if abs(r.coWinMatrix[p][p] - expected) > 1e-9 { return false }
            }
            return true
        }
    }

    func testBreakdownPartitionsRunouts() {
        property("per-player category breakdown totals to 1") <- forAll(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            for player in r.players {
                let total = player.breakdown.values.reduce(0.0) { $0 + $1.total }
                if abs(total - 1.0) > 1e-9 { return false }
            }
            return true
        }
    }

    func testAttributionMatchesBreakdown() {
        property("winVs/loseVs sum back to the breakdown cells") <- forAll(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            for player in r.players {
                for (cat, b) in player.breakdown {
                    let winSum = player.winVs[cat]?.values.reduce(0, +) ?? 0
                    if abs(winSum - b.winProb) > 1e-9 { return false }
                    let loseSum = player.loseVs[cat]?.values.reduce(0, +) ?? 0
                    if abs(loseSum - b.loseProb) > 1e-9 { return false }
                }
            }
            return true
        }
    }

    // MARK: - Relative decomposition

    func testRelativeDecompositionInvariants() {
        property("relative leaves partition runouts and reconstruct their totals")
            <- forAll(postflopDealGen) { deal in
                let rel = EquityCalculator.compute(hands: deal.hands, board: deal.board).relative
                for a in rel {
                    // Win / chop / lose leaves partition every runout.
                    if abs(a.winTotal + a.tieTotal + a.loseTotal - 1.0) > 1e-9 { return false }
                    // The win-by-combination mechanisms + the kicker win reconstruct the win total.
                    if abs(a.winCombination.reduce(0, +) + a.winKicker - a.winTotal) > 1e-9 { return false }
                    // The chop textures reconstruct the tie total.
                    if abs(a.chop.reduce(0, +) - a.tieTotal) > 1e-9 { return false }
                    // Combination loss + kicker loss reconstruct the lose total.
                    if abs(a.loseCombination + a.loseKicker - a.loseTotal) > 1e-9 { return false }
                }
                return true
            }
    }

    func testRelativeOutcomesMatchEquity() {
        property("relative win/tie totals equal the equity engine") <- forAll(postflopDealGen) { deal in
            let result = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            for p in deal.hands.indices {
                if abs(result.relative[p].winTotal - result.players[p].winProb) > 1e-9 { return false }
                if abs(result.relative[p].tieTotal - result.players[p].tieProb) > 1e-9 { return false }
            }
            return true
        }
    }

    // MARK: - Cards

    func testCardDescriptionRoundTrips() {
        property("Card.description parses back to the same card") <- forAll(anyDealGen) { deal in
            let cards = deal.hands.flatMap { $0 } + deal.board
            return cards.allSatisfy { Card($0.description) == $0 }
        }
    }

    func testDealtCardsAreDistinct() {
        property("a single deal never repeats a card") <- forAll(anyDealGen) { deal in
            let cards = deal.hands.flatMap { $0 } + deal.board
            return Set(cards).count == cards.count
        }
    }
}
