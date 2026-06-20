import XCTest
@testable import PokerEngine

/// Targeted examples for evaluator branches not covered by `EvaluatorTests`:
/// the two-trips full house, standalone trips/high-card/one-pair kicker chains,
/// and the combinatorics helpers the equity counts depend on.
final class EvaluatorEdgeTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    func testFullHouseFromTwoTrips() {
        // Two trips in seven cards must read as the higher trip full of the lower.
        let acesFull = evaluate(hand("As Ah Ac Ks Kh Kc 2d"))
        XCTAssertEqual(acesFull.category, .fullHouse)
        let kingsFull = evaluate5(hand("Ks Kh Kc As Ah"))
        XCTAssertEqual(kingsFull.category, .fullHouse)
        XCTAssertGreaterThan(acesFull, kingsFull, "aces full beats kings full")
    }

    func testTripsKicker() {
        let higher = evaluate5(hand("7s 7h 7d Ks 2c"))
        XCTAssertEqual(higher.category, .trips)
        let lower = evaluate5(hand("7s 7h 7d Qs 2c"))
        XCTAssertGreaterThan(higher, lower, "king kicker beats queen kicker")
    }

    func testHighCardKicker() {
        let higher = evaluate5(hand("As Kh 9d 7c 4s"))
        XCTAssertEqual(higher.category, .highCard)
        let lower = evaluate5(hand("As Kh 9d 7c 3s"))
        XCTAssertGreaterThan(higher, lower, "fifth card breaks the tie")
    }

    func testOnePairKickerOrder() {
        let higher = evaluate5(hand("9s 9h As Kd 5c"))
        XCTAssertEqual(higher.category, .onePair)
        let lower = evaluate5(hand("9s 9h As Qd 5c"))
        XCTAssertGreaterThan(higher, lower, "second kicker decides")
    }

    func testFlushBeatsPairWhenFiveSuited() {
        // A pair of aces is present, but five spades make a flush.
        let r = evaluate(hand("As Ks 9s 4s 2s Ah"))
        XCTAssertEqual(r.category, .flush)
    }

    func testCombinationCountMatchesRunoutTotals() {
        XCTAssertEqual(combinationCount(45, 2), 990, "flop runouts, two cards to come")
        XCTAssertEqual(combinationCount(48, 5), 1_712_304, "preflop heads-up runouts")
        XCTAssertEqual(combinationCount(5, 0), 1, "no cards to come")
        XCTAssertEqual(combinationCount(3, 5), 0, "k greater than n")
    }

    func testBestFiveReturnsAllFiveWhenGivenFive() {
        let five = hand("As Ks Qs Js Ts")
        XCTAssertEqual(bestFive(five).count, 5)
        XCTAssertEqual(evaluate5(bestFive(five)).category, .straightFlush)
    }
}
