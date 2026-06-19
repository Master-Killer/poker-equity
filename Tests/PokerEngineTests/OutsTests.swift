import XCTest
@testable import PokerEngine

final class OutsTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    /// Textbook 15-out monster draw: nut flush draw + two overcards.
    /// A♠K♠ vs 9♥9♦ on Q♠ 7♠ 2♥.
    /// 99 currently leads. AK is drawing to: 9 spades + 3 aces + 3 kings = 15.
    func testNutFlushDrawPlusOvercards() {
        let hands = [hand("As Ks"), hand("9h 9d")]
        let board = hand("Qs 7s 2h")
        let result = OutsAnalyzer.analyze(hands: hands, board: board)

        XCTAssertEqual(result.currentLeader, 1, "pair of nines leads on the flop")

        let drawer = result.players[0]
        XCTAssertTrue(drawer.isTrailing)
        XCTAssertEqual(drawer.directOuts.count, 15, "9 flush + 3 aces + 3 kings")

        let flushOuts = drawer.directOuts.filter { $0.resultingCategory == .flush }
        XCTAssertEqual(flushOuts.count, 9)
        let pairOuts = drawer.directOuts.filter { $0.resultingCategory == .onePair }
        XCTAssertEqual(pairOuts.count, 6, "ace or king pairs an overcard")
    }

    /// The current leader has no direct outs to compute (it is already ahead).
    func testLeaderHasNoDirectOuts() {
        let hands = [hand("As Ks"), hand("9h 9d")]
        let board = hand("Qs 7s 2h")
        let result = OutsAnalyzer.analyze(hands: hands, board: board)

        let leader = result.players[1]
        XCTAssertFalse(leader.isTrailing)
    }

    /// On the turn (one card to come) there is no runner-runner.
    func testNoRunnerRunnerOnTheTurn() {
        let hands = [hand("As Ks"), hand("9h 9d")]
        let board = hand("Qs 7s 2h 3d")
        let result = OutsAnalyzer.analyze(hands: hands, board: board)
        XCTAssertTrue(result.players.allSatisfy { $0.runnerRunner.isEmpty })
    }
}
