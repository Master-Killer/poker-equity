import XCTest
@testable import PokerEngine

final class EquityTests: XCTestCase {

    private func hand(_ s: String) -> [Card] { Card.parse(s) }

    /// Reproduces the reference screenshot: KQ♠ vs 7♣7♦ on J♠ 6♠ 2♣.
    /// The app reported 55.7% / 44.3%.
    func testReferenceFlopScenario() {
        let result = EquityCalculator.compute(
            hands: [hand("Ks Qs"), hand("7c 7d")],
            board: hand("Js 6s 2c")
        )

        XCTAssertEqual(result.totalRunouts, 990) // C(45,2)
        printBreakdown(result)

        XCTAssertEqual(result.players[0].equity, 0.557, accuracy: 0.01, "KQ equity")
        XCTAssertEqual(result.players[1].equity, 0.443, accuracy: 0.01, "77 equity")
    }

    func testEquitiesSumToOne() {
        let result = EquityCalculator.compute(
            hands: [hand("Ks Qs"), hand("7c 7d")],
            board: hand("Js 6s 2c")
        )
        let sum = result.players.reduce(0.0) { $0 + $1.equity }
        XCTAssertEqual(sum, 1.0, accuracy: 1e-9)
    }

    func testBreakdownTotalsAreMarginalProbabilities() {
        let result = EquityCalculator.compute(
            hands: [hand("Ks Qs"), hand("7c 7d")],
            board: hand("Js 6s 2c")
        )
        for player in result.players {
            let totalAllCategories = player.breakdown.values.reduce(0.0) { $0 + $1.total }
            XCTAssertEqual(totalAllCategories, 1.0, accuracy: 1e-9, "category totals must cover all runouts")

            // Sum of win column == win probability; equity == win + tie share.
            let winColumn = player.breakdown.values.reduce(0.0) { $0 + $1.winProb }
            XCTAssertEqual(winColumn, player.winProb, accuracy: 1e-9)
            XCTAssertEqual(player.equity, player.winProb + player.tieProb / 2.0, accuracy: 1e-9)
        }
    }

    /// Classic benchmark: AA vs KK preflop ≈ 81.9% / 18.1% (exact enumeration).
    func testAcesVsKingsPreflop() {
        let result = EquityCalculator.compute(
            hands: [hand("As Ah"), hand("Ks Kh")],
            board: []
        )
        XCTAssertEqual(result.totalRunouts, 1_712_304) // C(48,5)
        XCTAssertEqual(result.players[0].equity, 0.8197, accuracy: 0.01, "AA equity")
    }

    // MARK: - Helpers

    private func printBreakdown(_ result: EquityResult) {
        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }
        func rpad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
        }
        for player in result.players {
            let name = player.hand.map { $0.description }.joined(separator: " ")
            print("\n=== \(name) — equity \(pct(player.equity)) "
                  + "(win \(pct(player.winProb)), tie \(pct(player.tieProb))) ===")
            print(pad("Category", 16) + rpad("Win", 8) + rpad("Lose", 8) + rpad("Tie", 8) + rpad("Total", 9))
            for cat in HandCategory.allCases {
                guard let b = player.breakdown[cat], b.total > 0 else { continue }
                print(pad(cat.label, 16) + rpad(pct(b.winProb), 8) + rpad(pct(b.loseProb), 8)
                      + rpad(pct(b.tieProb), 8) + rpad(pct(b.total), 9))
            }
        }
    }

    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
}
