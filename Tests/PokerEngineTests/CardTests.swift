import XCTest
@testable import PokerEngine

final class CardTests: XCTestCase {

    func testFullDeckIsComplete() {
        XCTAssertEqual(Card.fullDeck.count, 52)
        XCTAssertEqual(Set(Card.fullDeck).count, 52, "no duplicate cards")
        XCTAssertEqual(Set(Card.fullDeck.map { $0.index }), Set(0..<52), "indices cover 0...51")
    }

    func testIndexLayout() {
        // index = (rank - 2) * 4 + suit.rawValue
        XCTAssertEqual(Card(rank: 2, suit: .spades).index, 0)
        XCTAssertEqual(Card(rank: 2, suit: .diamonds).index, 3)
        XCTAssertEqual(Card(rank: 14, suit: .diamonds).index, 51)
    }

    func testRankLetterAndDescription() {
        XCTAssertEqual(Card(rank: 14, suit: .spades).description, "As")
        XCTAssertEqual(Card(rank: 10, suit: .hearts).description, "Th")
        XCTAssertEqual(Card(rank: 2, suit: .clubs).description, "2c")
        XCTAssertEqual(Card(rank: 13, suit: .diamonds).rankLetter, "K")
        XCTAssertEqual(Card(rank: 12, suit: .diamonds).rankLetter, "Q")
        XCTAssertEqual(Card(rank: 11, suit: .diamonds).rankLetter, "J")
        XCTAssertEqual(Card(rank: 9, suit: .diamonds).rankLetter, "9")
    }

    func testSuitProperties() {
        XCTAssertEqual(Suit.spades.symbol, "♠")
        XCTAssertEqual(Suit.hearts.symbol, "♥")
        XCTAssertEqual(Suit.clubs.symbol, "♣")
        XCTAssertEqual(Suit.diamonds.symbol, "♦")
        XCTAssertEqual(Suit.spades.letter, "s")
        XCTAssertEqual(Suit.hearts.letter, "h")
        XCTAssertEqual(Suit.clubs.letter, "c")
        XCTAssertEqual(Suit.diamonds.letter, "d")
        XCTAssertTrue(Suit.hearts.isRed)
        XCTAssertTrue(Suit.diamonds.isRed)
        XCTAssertFalse(Suit.spades.isRed)
        XCTAssertFalse(Suit.clubs.isRed)
    }

    func testParseValidNotations() {
        XCTAssertEqual(Card("As"), Card(rank: 14, suit: .spades))
        XCTAssertEqual(Card("td"), Card(rank: 10, suit: .diamonds), "lower-case rank")
        XCTAssertEqual(Card("9C"), Card(rank: 9, suit: .clubs), "upper-case suit")
        XCTAssertEqual(Card("2h"), Card(rank: 2, suit: .hearts))
        XCTAssertEqual(Card("Kd"), Card(rank: 13, suit: .diamonds))
    }

    func testParseRejectsInvalidInput() {
        XCTAssertNil(Card("A"), "too short")
        XCTAssertNil(Card("Ass"), "too long")
        XCTAssertNil(Card("1s"), "rank 1 is out of range")
        XCTAssertNil(Card("0d"), "rank 0 is out of range")
        XCTAssertNil(Card("Xs"), "unknown rank letter")
        XCTAssertNil(Card("Ak"), "unknown suit letter")
    }

    func testParseList() {
        XCTAssertEqual(Card.parse("Ks Qs").count, 2)
        XCTAssertEqual(Card.parse("Js,6s,2c").count, 3, "comma-separated")
        XCTAssertEqual(Card.parse("As Xx 7d").count, 2, "invalid tokens are skipped")
        XCTAssertTrue(Card.parse("").isEmpty)
        XCTAssertEqual(Card.parse("Ks Qs"), [Card(rank: 13, suit: .spades), Card(rank: 12, suit: .spades)])
    }
}
