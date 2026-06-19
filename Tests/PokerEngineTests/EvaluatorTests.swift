import XCTest
@testable import PokerEngine

final class EvaluatorTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    func testCategoryOrdering() {
        XCTAssertLessThan(HandCategory.highCard, HandCategory.onePair)
        XCTAssertLessThan(HandCategory.fullHouse, HandCategory.quads)
        XCTAssertLessThan(HandCategory.quads, HandCategory.straightFlush)
    }

    func testStraightFlushBeatsQuads() {
        let straightFlush = evaluate5(hand("9s 8s 7s 6s 5s"))
        let quads = evaluate5(hand("As Ah Ac Ad Kd"))
        XCTAssertEqual(straightFlush.category, .straightFlush)
        XCTAssertEqual(quads.category, .quads)
        XCTAssertGreaterThan(straightFlush, quads)
    }

    func testRoyalFlushDetected() {
        let royal = evaluate5(hand("As Ks Qs Js Ts"))
        XCTAssertEqual(royal.category, .straightFlush)
        XCTAssertTrue(royal.isRoyalFlush)

        let lowerStraightFlush = evaluate5(hand("Ks Qs Js Ts 9s"))
        XCTAssertFalse(lowerStraightFlush.isRoyalFlush)
        XCTAssertGreaterThan(royal, lowerStraightFlush)
    }

    func testWheelIsAFiveHighStraight() {
        let wheel = evaluate5(hand("Ah 5d 4c 3s 2h"))
        XCTAssertEqual(wheel.category, .straight)
        let sixHigh = evaluate5(hand("6h 5d 4c 3s 2h"))
        XCTAssertEqual(sixHigh.category, .straight)
        XCTAssertGreaterThan(sixHigh, wheel) // 6-high straight beats the wheel
    }

    func testFlushBeatsStraight() {
        let flush = evaluate5(hand("Ah Jh 8h 5h 2h"))
        let straight = evaluate5(hand("9c 8d 7h 6s 5c"))
        XCTAssertGreaterThan(flush, straight)
    }

    func testTwoPairKicker() {
        let higherKicker = evaluate5(hand("Ks Kd 7c 7h Ah"))
        let lowerKicker = evaluate5(hand("Ks Kd 7c 7h Qh"))
        XCTAssertEqual(higherKicker.category, .twoPair)
        XCTAssertGreaterThan(higherKicker, lowerKicker)
    }

    func testSevenCardPicksBestFive() {
        // Hole As Ks + three more spades on board => five spades => flush,
        // which must beat the pair of aces (As, Ad) also present.
        let r = evaluate(hand("As Ks Qs 2s 9s Ad 3c"))
        XCTAssertEqual(r.category, .flush)
    }

    func testSixCardEvaluation() {
        let r = evaluate(hand("As Ah Ac 5d 5s 9h"))
        XCTAssertEqual(r.category, .fullHouse)
    }
}
