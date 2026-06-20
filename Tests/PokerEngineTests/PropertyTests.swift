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

final class PropertyTests: XCTestCase {

    // MARK: - Evaluator

    func testEvaluateMatchesBestFive() {
        property("evaluate(5...7) == evaluate5(bestFive)") <- forAllNoShrink(postflopDealGen) { deal in
            for hand in deal.hands {
                let cards = hand + deal.board
                if evaluate(cards).score != evaluate5(bestFive(cards)).score { return false }
            }
            return true
        }
    }

    func testHigherCategoryAlwaysOutranks() {
        property("a stronger category always packs a higher score") <- forAllNoShrink(postflopDealGen) { deal in
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
        property("equities lie in [0,1] and sum to 1") <- forAllNoShrink(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            let sum = r.players.reduce(0.0) { $0 + $1.equity }
            guard abs(sum - 1.0) <= 1e-9 else { return false }
            return r.players.allSatisfy { $0.equity >= -1e-12 && $0.equity <= 1 + 1e-12 }
        }
    }

    func testCoWinDiagonalEqualsWinPlusTie() {
        property("coWinMatrix diagonal == win + tie probability") <- forAllNoShrink(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            for p in r.players.indices {
                let expected = r.players[p].winProb + r.players[p].tieProb
                if abs(r.coWinMatrix[p][p] - expected) > 1e-9 { return false }
            }
            return true
        }
    }

    func testBreakdownPartitionsRunouts() {
        property("per-player category breakdown totals to 1") <- forAllNoShrink(postflopDealGen) { deal in
            let r = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            for player in r.players {
                let total = player.breakdown.values.reduce(0.0) { $0 + $1.total }
                if abs(total - 1.0) > 1e-9 { return false }
            }
            return true
        }
    }

    func testAttributionMatchesBreakdown() {
        property("winVs/loseVs sum back to the breakdown cells") <- forAllNoShrink(postflopDealGen) { deal in
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
        property("relative buckets partition runouts and sub-splits stay consistent")
            <- forAllNoShrink(postflopDealGen) { deal in
                let rel = EquityCalculator.compute(hands: deal.hands, board: deal.board).relative
                for a in rel {
                    // The 3×3 grid partitions every runout.
                    let sum = a.prob.flatMap { $0 }.reduce(0, +)
                    if abs(sum - 1.0) > 1e-9 { return false }
                    // edgeMechanism splits the ownEdge row, outcome by outcome.
                    for o in RelOutcome.allCases {
                        let mechSum = EdgeMechanism.allCases.reduce(0.0) {
                            $0 + a.edgeMechanism[$1.rawValue][o.rawValue]
                        }
                        if abs(mechSum - a.p(.ownEdge, o)) > 1e-9 { return false }
                    }
                    // kickerChopTexture splits the (kicker, tie) cell.
                    let texSum = a.kickerChopTexture.reduce(0, +)
                    if abs(texSum - a.p(.kicker, .tie)) > 1e-9 { return false }
                }
                return true
            }
    }

    func testRelativeOutcomesMatchEquity() {
        property("relative win/tie totals equal the equity engine") <- forAllNoShrink(postflopDealGen) { deal in
            let result = EquityCalculator.compute(hands: deal.hands, board: deal.board)
            let rel = result.relative
            for p in deal.hands.indices {
                let win = RelSource.allCases.reduce(0.0) { $0 + rel[p].prob[$1.rawValue][RelOutcome.win.rawValue] }
                let tie = RelSource.allCases.reduce(0.0) { $0 + rel[p].prob[$1.rawValue][RelOutcome.tie.rawValue] }
                if abs(win - result.players[p].winProb) > 1e-9 { return false }
                if abs(tie - result.players[p].tieProb) > 1e-9 { return false }
            }
            return true
        }
    }

    // MARK: - Cards

    func testCardDescriptionRoundTrips() {
        property("Card.description parses back to the same card") <- forAllNoShrink(anyDealGen) { deal in
            let cards = deal.hands.flatMap { $0 } + deal.board
            return cards.allSatisfy { Card($0.description) == $0 }
        }
    }

    func testDealtCardsAreDistinct() {
        property("a single deal never repeats a card") <- forAllNoShrink(anyDealGen) { deal in
            let cards = deal.hands.flatMap { $0 } + deal.board
            return Set(cards).count == cards.count
        }
    }
}
