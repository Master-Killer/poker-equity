import XCTest
@testable import PokerEngine

/// Covers the reworked relative examples: validity, the "combination vs kicker"
/// reclassification, and the decisive-card highlighting.
final class RelativeExampleTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    /// `combinationScore` keeps the combination, drops the kickers.
    func testCombinationScoreIgnoresKickers() {
        let a = evaluate5(hand("Ks Kd Qh 7c 2s"))   // pair of kings, kicker Q
        let b = evaluate5(hand("Ks Kd Jh 7c 2s"))   // pair of kings, kicker J
        XCTAssertNotEqual(a.score, b.score)          // full scores differ (kicker)
        XCTAssertEqual(combinationScore(a.score, a.category),
                       combinationScore(b.score, b.category), "same pair → same combination")

        let c = evaluate5(hand("Qs Qd Ah 7c 2s"))    // pair of queens
        XCTAssertNotEqual(combinationScore(a.score, a.category),
                          combinationScore(c.score, c.category), "different pair → different combination")

        // A flush has no kicker: a higher flush is a higher combination.
        let f1 = evaluate5(hand("As 8s 6s 4s 2s"))
        let f2 = evaluate5(hand("Ks 8s 6s 4s 2s"))
        XCTAssertGreaterThan(combinationScore(f1.score, f1.category),
                             combinationScore(f2.score, f2.category))
    }

    /// `combinationCards` returns the paired part (or whole made hand), no kickers,
    /// for every category.
    func testCombinationCardsExcludeKickers() {
        XCTAssertTrue(combinationCards(hand("As Kd 9h 6c 2s")).isEmpty, "high card: no combination")
        XCTAssertEqual(Set(combinationCards(hand("9h 9s Kc 6d 2s"))),
                       Set(hand("9h 9s")), "one pair: only the pair")
        XCTAssertEqual(Set(combinationCards(hand("9h 9s 3c 3d Kc"))),
                       Set(hand("9h 9s 3c 3d")), "two pair: kicker K excluded")
        XCTAssertEqual(Set(combinationCards(hand("9h 9s 9c Kd 2s"))),
                       Set(hand("9h 9s 9c")), "trips: only the trips")
        XCTAssertEqual(Set(combinationCards(hand("5h 6s 7c 8d 9h"))),
                       Set(hand("5h 6s 7c 8d 9h")), "straight: all five")
        XCTAssertEqual(Set(combinationCards(hand("As 8s 6s 4s 2s"))),
                       Set(hand("As 8s 6s 4s 2s")), "flush: no kicker")
        XCTAssertEqual(Set(combinationCards(hand("2h 2s 2c Qd Qh"))),
                       Set(hand("2h 2s 2c Qd Qh")), "full house: all five")
        XCTAssertEqual(Set(combinationCards(hand("9h 9s 9c 9d Ks"))),
                       Set(hand("9h 9s 9c 9d")), "quads: kicker K excluded")
        XCTAssertEqual(Set(combinationCards(hand("5h 6h 7h 8h 9h"))),
                       Set(hand("5h 6h 7h 8h 9h")), "straight flush: all five")
    }

    /// Every stored example is well-formed: valid distinct decisive indices, a
    /// positive combo count, an absolute share in ]0,1], and decisive cards that
    /// are genuinely part of the player's combination on that board.
    func testExamplesAreWellFormed() {
        let hands = [hand("As Ah"), hand("Qs 9s")]
        let rel = EquityCalculator.compute(hands: hands, board: []).relative
        for (p, a) in rel.enumerated() {
            let oppHand = hands[1 - p]
            for (key, examples) in a.examples {
                // A loss highlights the opponent's winning combination, not mine.
                let winnerHand = key.hasPrefix("lose") ? oppHand : a.hand
                for ex in examples {
                    XCTAssertEqual(ex.board.count, 5)
                    XCTAssertGreaterThanOrEqual(ex.count, 1)
                    XCTAssertGreaterThan(ex.share, 0)
                    XCTAssertLessThanOrEqual(ex.share, 1)
                    XCTAssertEqual(Set(ex.decisive).count, ex.decisive.count, "no duplicate indices")
                    XCTAssertTrue(ex.decisive.allSatisfy { ex.board.indices.contains($0) })

                    let combo = Set(combinationCards(bestFive(winnerHand + ex.board)))
                    for i in ex.decisive {
                        XCTAssertTrue(combo.contains(ex.board[i]),
                                      "decisive card \(ex.board[i]) must be in the winner's combination")
                    }
                }
            }
        }
    }

    /// The examples kept for a leaf are distinct scenarios, not near-identical
    /// adjacent boards (the bug the rework fixed).
    func testExamplesInALeafAreDistinct() {
        let hands = [hand("As Ah"), hand("Qs 9s")]
        for a in EquityCalculator.compute(hands: hands, board: []).relative {
            for (_, examples) in a.examples where examples.count > 1 {
                let boards = examples.map { ex in ex.board.map { $0.description }.sorted().joined() }
                XCTAssertEqual(Set(boards).count, boards.count, "example boards must differ")
            }
        }
    }

    /// Every example's actual showdown verdict must match its leaf — so "le kicker
    /// tranche" only ever holds genuine kicker duels, symmetrically for both hands.
    func testVerdictMatchesLeaf() {
        let hands = [hand("Ks Qs"), hand("7c 7d")]
        let board = hand("Js 6s 2c")            // flop: quick to enumerate
        let rel = EquityCalculator.compute(hands: hands, board: board).relative
        for (p, a) in rel.enumerated() {
            let oppHand = hands[1 - p]
            for (key, examples) in a.examples {
                for ex in examples {
                    let verdict = showdownVerdict(bestFive(a.hand + ex.board), bestFive(oppHand + ex.board))
                    if key.hasPrefix("wincombo") {
                        XCTAssertTrue(verdict == .higherCategory || verdict == .betterCombination,
                                      "wincombo leaf must be a combination win, got \(verdict)")
                    } else if key == RelativeAnalysis.winKickerKey {
                        XCTAssertEqual(verdict, .kickerWin)
                    } else if key.hasPrefix("chop") {
                        XCTAssertEqual(verdict, .chop)
                    } else if key == RelativeAnalysis.loseComboKey {
                        XCTAssertTrue(verdict == .lowerCategory || verdict == .worseCombination,
                                      "losecombo leaf must be a combination loss, got \(verdict)")
                    } else if key == RelativeAnalysis.loseKickerKey {
                        XCTAssertEqual(verdict, .kickerLose)
                    }
                }
            }
        }
    }

    /// A pocket pair that wins by out-ranking the board is labelled `pocketPair`.
    func testServedPocketPairMechanism() {
        // AA over a paired low board makes the better hand with no ace on the board
        // and no straight/flush — a served pocket pair.
        let hands = [hand("As Ah"), hand("Ks Qd")]
        let board = hand("7c 7d 2s")
        let a = EquityCalculator.compute(hands: hands, board: board).relative[0]
        XCTAssertGreaterThan(a.winCombination[EdgeMechanism.pocketPair.rawValue], 0,
                             "AA over a paired low board wins via a served pocket pair")
    }
}
