import XCTest
@testable import PokerEngine

final class OutsEdgeTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    /// When two players share the lead, `currentLeader` is -1 and nobody is the
    /// sole leader, so there are no direct outs to compute.
    func testTiedLeadHasNoSoleLeader() {
        // Both players hold pocket kings (all four kings are dealt); the board's
        // A-Q-J kickers are shared, so the two hands are exactly tied.
        let hands = [hand("Ks Kd"), hand("Kh Kc")]
        let board = hand("Ah Qh Jc")
        let result = OutsAnalyzer.analyze(hands: hands, board: board)

        XCTAssertEqual(result.currentLeader, -1, "the lead is tied")
        XCTAssertTrue(result.players.allSatisfy { $0.isTrailing }, "nobody is the sole leader")
        XCTAssertTrue(result.players.allSatisfy { $0.directOuts.isEmpty },
                      "no single card hands either tied hand a sole lead")
    }

    /// Runner-runner draws are only reported for the trailing player(s) on the flop.
    func testRunnerRunnerOnlyForTrailingPlayerOnFlop() {
        let hands = [hand("As Ks"), hand("9h 9d")]
        let board = hand("Qs 7s 2h")
        let result = OutsAnalyzer.analyze(hands: hands, board: board)

        let leader = result.players[result.currentLeader]
        XCTAssertTrue(leader.runnerRunner.isEmpty, "the current leader has no runner-runner draws")
    }
}
