import XCTest
@testable import PokerEngine

/// `showdownVerdict` — the rule behind the synthesis phrases. "Kicker" must apply
/// ONLY to identical combinations; made hands never have a kicker.
final class ShowdownTests: XCTestCase {

    private func v(_ mine: String, _ opp: String) -> ShowdownVerdict {
        showdownVerdict(Card.parse(mine), Card.parse(opp))
    }

    func testCategoryDifferenceWins() {
        XCTAssertEqual(v("As Ad Ah 2c 2d", "Ks Kd Qh Qc 2s"), .higherCategory) // full vs two pair
        XCTAssertEqual(v("Ks Kd Qh Qc 2s", "As Ad Ah 2c 2d"), .lowerCategory)
    }

    /// A better hand of the SAME category is a better combination, never a kicker.
    func testBetterCombinationIsNotAKicker() {
        // Two pair: aces-up beats threes-up by the pairs, not the kicker.
        XCTAssertEqual(v("As Ad 3c 3h Kd", "3s 3d 2c 2h Kc"), .betterCombination)
        XCTAssertEqual(v("3s 3d 2c 2h Kc", "As Ad 3c 3h Kd"), .worseCombination)
        // François' flush case: K-high vs Q-high → better COULEUR, not a kicker.
        XCTAssertEqual(v("Ks Js 9s 5s 3s", "Qh Jh 9h 5h 3h"), .betterCombination)
        // Full house vs lower full house → better combination.
        XCTAssertEqual(v("As Ad Ah Kc Kd", "Qs Qd Qh 2c 2d"), .betterCombination)
        // Higher straight → better combination (no kicker on a straight).
        XCTAssertEqual(v("6h 7s 8c 9d Ts", "5h 6s 7c 8d 9h"), .betterCombination)
    }

    /// A kicker decides only between identical combinations.
    func testGenuineKicker() {
        // 88 66 + A vs 88 66 + J → kicker ace (François' example).
        XCTAssertEqual(v("8h 8s 6h 6s Ad", "8d 8c 6d 6c Jh"), .kickerWin)
        // KK 8 6 4 vs KK 8 5 2 → kicker 6 (François' example).
        XCTAssertEqual(v("Kh Ks 8h 6c 4d", "Kd Kc 8s 5h 2c"), .kickerWin)
        XCTAssertEqual(v("Kd Kc 8s 5h 2c", "Kh Ks 8h 6c 4d"), .kickerLose)
        // Quads share the four-of-a-kind on the board; the fifth card is a kicker.
        XCTAssertEqual(v("2h 2s 2c 2d Ah", "2h 2s 2c 2d Kh"), .kickerWin)
    }

    func testChop() {
        XCTAssertEqual(v("5h 6s 7c 8d 9h", "5d 6c 7h 8s 9c"), .chop)       // same straight
        XCTAssertEqual(v("Ah Kh Qh Jh 9h", "As Ks Qs Js 9s"), .chop)       // same flush ranks
    }

    /// The verdict's win/lose orientation must agree with the raw scores.
    func testVerdictAgreesWithScore() {
        let cases = [("As Ad Ah 2c 2d", "Ks Kd Qh Qc 2s"),
                     ("As Ad 3c 3h Kd", "3s 3d 2c 2h Kc"),
                     ("8h 8s 6h 6s Ad", "8d 8c 6d 6c Jh"),
                     ("Ks Js 9s 5s 3s", "Qh Jh 9h 5h 3h")]
        for (a, b) in cases {
            let mine = evaluate(Card.parse(a)).score
            let opp = evaluate(Card.parse(b)).score
            let win: Set<ShowdownVerdict> = [.higherCategory, .betterCombination, .kickerWin]
            XCTAssertTrue(win.contains(v(a, b)), "\(a) beats \(b)")
            XCTAssertGreaterThan(mine, opp)
        }
    }
}
