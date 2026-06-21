import XCTest
@testable import PokerEngine

final class RelativeEdgeTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    /// `boardTexture` buckets the bare-board shape behind a chop.
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

    /// The leaves reconstruct the win / chop / lose totals exactly.
    func testLeavesReconstructTotals() {
        let rel = EquityCalculator.compute(hands: [hand("Tc 2d"), hand("Td 7h")], board: []).relative
        for a in rel {
            XCTAssertEqual(a.winCombination.reduce(0, +) + a.winKicker, a.winTotal, accuracy: 1e-9,
                           "combination wins + kicker wins == win total")
            XCTAssertEqual(a.chop.reduce(0, +), a.tieTotal, accuracy: 1e-9,
                           "chop textures == tie total")
            XCTAssertEqual(a.loseCombination + a.loseKicker, a.loseTotal, accuracy: 1e-9,
                           "lose by combination + lose by kicker == lose total")
            XCTAssertEqual(a.winTotal + a.tieTotal + a.loseTotal, 1.0, accuracy: 1e-9)
        }
    }

    /// Leaf-key helpers produce the keys the pass uses internally.
    func testLeafKeyFormat() {
        XCTAssertEqual(RelativeAnalysis.winComboKey(.pocketPair), "wincombo-\(EdgeMechanism.pocketPair.rawValue)")
        XCTAssertEqual(RelativeAnalysis.winKickerKey, "winkicker")
        XCTAssertEqual(RelativeAnalysis.chopKey(.boardPairLow), "chop-\(ChopTexture.boardPairLow.rawValue)")
        XCTAssertEqual(RelativeAnalysis.loseComboKey, "losecombo")
        XCTAssertEqual(RelativeAnalysis.loseKickerKey, "losekicker")
    }
}
