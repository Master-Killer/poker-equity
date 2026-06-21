import XCTest
@testable import PokerEngine

final class RelativeTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }
    private func pct(_ x: Double) -> String { String(format: "%6.2f%%", x * 100) }

    /// Prints the showdown decomposition for the 10-2 vs 10-7 example, and asserts
    /// the win/chop/lose leaves partition 100% of runouts for each player.
    func testRelativeDecomposition_T2_vs_T7() {
        let result = EquityCalculator.compute(hands: [hand("Tc 2d"), hand("Td 7h")], board: []).relative

        for a in result {
            let name = a.hand.map { $0.description }.joined(separator: " ")
            print("\n=== \(name) ===")
            print("GAGNE \(pct(a.winTotal))")
            for m in EdgeMechanism.allCases where a.winCombination[m.rawValue] > 0 {
                print("    \(m.label):  \(pct(a.winCombination[m.rawValue]))")
            }
            if a.winKicker > 0 { print("    mon kicker:  \(pct(a.winKicker))") }
            print("PARTAGE \(pct(a.tieTotal))")
            print("PERD \(pct(a.loseTotal))  (combinaison \(pct(a.loseCombination)) · kicker \(pct(a.loseKicker)))")

            let sum = a.winTotal + a.tieTotal + a.loseTotal
            XCTAssertEqual(sum, 1.0, accuracy: 1e-9, "win/chop/lose leaves must partition all runouts")
        }
    }

    /// Concrete example boards for a few leaves, with what each player plays.
    func testExplainLeaves() {
        let p = hand("Tc 2d"); let q = hand("Td 7h")
        let me = EquityCalculator.compute(hands: [p, q], board: []).relative[0]

        func desc(_ cards: [Card]) -> String {
            let five = bestFive(cards)
            return "\(evaluate(five).category.label): " + five.map { $0.description }.joined(separator: " ")
        }
        func show(_ key: String, _ title: String) {
            print("\n\(title)")
            guard let exs = me.examples[key], !exs.isEmpty else { print("  (aucun exemple)"); return }
            for ex in exs.prefix(2) {
                let b = ex.board
                print("  tableau \(b.map { $0.description }.joined(separator: " ")) — \(pct(ex.share)) des donnes")
                print("    10-2 → \(desc(p + b))")
                print("    10-7 → \(desc(q + b))")
            }
        }
        show(RelativeAnalysis.winComboKey(.unsharedCard), "[GAGNE · combinaison via carte non partagée]")
        show(RelativeAnalysis.winKickerKey, "[GAGNE · mon kicker]")
        show(RelativeAnalysis.loseComboKey, "[PERD · l'adversaire a une meilleure combinaison]")
    }

    /// The relative win/chop/lose totals must match the equity engine.
    func testRelativeOutcomesMatchEquity() {
        let hands = [hand("Ks Qs"), hand("7c 7d")]
        let board = hand("Js 6s 2c")
        let eq = EquityCalculator.compute(hands: hands, board: board)
        for p in hands.indices {
            let a = eq.relative[p]
            XCTAssertEqual(a.winTotal, eq.players[p].winProb, accuracy: 1e-9)
            XCTAssertEqual(a.tieTotal, eq.players[p].tieProb, accuracy: 1e-9)
        }
    }
}
