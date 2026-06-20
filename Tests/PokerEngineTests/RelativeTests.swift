import XCTest
@testable import PokerEngine

final class RelativeTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }
    private func pct(_ x: Double) -> String { String(format: "%6.2f%%", x * 100) }

    /// Prints the relative decomposition for the user's 10-2 vs 10-7 example,
    /// and asserts the 9 buckets partition 100% of runouts for each player.
    func testRelativeDecomposition_T2_vs_T7() {
        let result = EquityCalculator.compute(hands: [hand("Tc 2d"), hand("Td 7h")], board: []).relative

        for a in result {
            let name = a.hand.map { $0.description }.joined(separator: " ")
            print("\n=== \(name) ===")
            for s in RelSource.allCases {
                print(String(format: "%-18@", s.label as NSString)
                      + "  gagne \(pct(a.p(s, .win)))   partage \(pct(a.p(s, .tie)))   perd \(pct(a.p(s, .lose)))")
                if s == .ownEdge {
                    for m in EdgeMechanism.allCases {
                        let g = a.edgeMechanism[m.rawValue]
                        if g.reduce(0,+) > 0 {
                            print("    \(m.label):  gagne \(pct(g[0]))  partage \(pct(g[1]))  perd \(pct(g[2]))")
                        }
                    }
                }
                if s == .kicker {
                    let chop = a.kickerChopTexture
                    if chop.reduce(0,+) > 0 {
                        print("    [partage par texture] "
                              + ChopTexture.allCases.map { "\($0.label) \(pct(chop[$0.rawValue]))" }.joined(separator: " · "))
                    }
                }
            }
            let sum = a.prob.flatMap { $0 }.reduce(0, +)
            XCTAssertEqual(sum, 1.0, accuracy: 1e-9, "buckets must partition all runouts")
        }
    }

    /// Prints a concrete example board (and what each player plays) for the
    /// counter-intuitive tiny cells the user asked about.
    func testExplainWeirdCells() {
        let p = hand("Tc 2d"); let q = hand("Td 7h")
        let me = EquityCalculator.compute(hands: [p, q], board: []).relative[0]

        func desc(_ cards: [Card]) -> String {
            let five = bestFive(cards)
            return "\(evaluate(five).category.label): " + five.map { $0.description }.joined(separator: " ")
        }
        func show(_ key: String, _ title: String) {
            print("\n\(title)")
            guard let boards = me.examples[key], !boards.isEmpty else { print("  (aucun exemple)"); return }
            for b in boards.prefix(2) {
                print("  tableau \(b.map { $0.description }.joined(separator: " "))")
                print("    10-2 → \(desc(p + b))")
                print("    10-7 → \(desc(q + b))")
            }
        }
        show(RelativeAnalysis.leafKey(source: .kicker, outcome: .win),
             "[KICKER · GAGNE 0,04%]  le 2 me ferait gagner ?")
        show(RelativeAnalysis.leafKey(source: .ownEdge, outcome: .win, mechanism: .sharedRank),
             "[EDGE via rang partagé · GAGNE 0,07%]")
        show(RelativeAnalysis.leafKey(source: .ownEdge, outcome: .tie, mechanism: .unsharedCard),
             "[EDGE via carte non partagée · PARTAGE 0,71%]")
    }

    /// The relative outcome (win/tie/lose vs the field) must match the equity engine.
    func testRelativeOutcomesMatchEquity() {
        let hands = [hand("Ks Qs"), hand("7c 7d")]
        let board = hand("Js 6s 2c")
        let rel = EquityCalculator.compute(hands: hands, board: board).relative
        let eq = EquityCalculator.compute(hands: hands, board: board)

        for p in hands.indices {
            let win = RelSource.allCases.reduce(0.0) { $0 + rel[p].prob[$1.rawValue][RelOutcome.win.rawValue] }
            let tie = RelSource.allCases.reduce(0.0) { $0 + rel[p].prob[$1.rawValue][RelOutcome.tie.rawValue] }
            XCTAssertEqual(win, eq.players[p].winProb, accuracy: 1e-9)
            XCTAssertEqual(tie, eq.players[p].tieProb, accuracy: 1e-9)
        }
    }
}
