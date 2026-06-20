import XCTest
@testable import PokerEngine

final class RelativeEdgeTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    /// `boardTexture` buckets the bare-board shape behind a kicker chop.
    func testBoardTextureClassification() {
        let run = hand("As Ks Qs Js Ts")               // straight flush on the board
        XCTAssertEqual(boardTexture(run, evaluate5(run)), ChopTexture.boardRun.rawValue)

        let highPair = hand("Ks Kd 7c 4h 2s")          // pairs a rank >= 10
        XCTAssertEqual(boardTexture(highPair, evaluate5(highPair)), ChopTexture.boardPairHigh.rawValue)

        let lowPair = hand("7s 7d Kc 4h 2s")           // pairs a rank < 10
        XCTAssertEqual(boardTexture(lowPair, evaluate5(lowPair)), ChopTexture.boardPairLow.rawValue)

        let unpaired = hand("Ks Qd 9c 4h 2s")          // no pair, no run
        XCTAssertEqual(boardTexture(unpaired, evaluate5(unpaired)), ChopTexture.other.rawValue)
    }

    /// The mechanism split must reconstruct the `ownEdge` row exactly, and the
    /// chop-texture split must reconstruct the `(kicker, tie)` cell.
    func testSubSplitsReconstructTheirCells() {
        let rel = RelativeAnalyzer.analyze(hands: [hand("Tc 2d"), hand("Td 7h")], board: [])
        for a in rel {
            for o in RelOutcome.allCases {
                let mechSum = EdgeMechanism.allCases.reduce(0.0) {
                    $0 + a.edgeMechanism[$1.rawValue][o.rawValue]
                }
                XCTAssertEqual(mechSum, a.p(.ownEdge, o), accuracy: 1e-9,
                               "edge mechanisms reconstruct ownEdge \(o)")
            }
            let texSum = a.kickerChopTexture.reduce(0, +)
            XCTAssertEqual(texSum, a.p(.kicker, .tie), accuracy: 1e-9,
                           "chop textures reconstruct the kicker-tie cell")
        }
    }

    /// `leafKey` must agree with the keys produced internally during the pass,
    /// so every printed cell is addressable.
    func testLeafKeyFormat() {
        XCTAssertEqual(
            RelativeAnalysis.leafKey(source: .ownEdge, outcome: .win, mechanism: .sharedRank),
            "edge-\(EdgeMechanism.sharedRank.rawValue)-\(RelOutcome.win.rawValue)")
        XCTAssertEqual(
            RelativeAnalysis.leafKey(source: .kicker, outcome: .tie, texture: .boardPairLow),
            "kicker-tie-\(ChopTexture.boardPairLow.rawValue)")
        XCTAssertEqual(
            RelativeAnalysis.leafKey(source: .kicker, outcome: .win),
            "kicker-\(RelOutcome.win.rawValue)")
        XCTAssertEqual(
            RelativeAnalysis.leafKey(source: .playsBoard, outcome: .lose),
            "board-\(RelOutcome.lose.rawValue)")
    }
}
