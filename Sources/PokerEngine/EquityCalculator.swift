import Foundation

/// How often a player ends up in a given hand category, split by the outcome
/// against the *specific* opposing hands. All values are fractions of all runouts.
///
/// - `winProb` + `tieProb` + `loseProb` == `total`, the marginal probability of
///   reaching this category (the number generic calculators show).
/// - The sum of `winProb` across categories is the player's win probability;
///   add the tie share to get full equity.
public struct CategoryBreakdown: Sendable {
    public var winProb: Double
    public var tieProb: Double
    public var loseProb: Double
    public var total: Double { winProb + tieProb + loseProb }
}

public struct PlayerEquity: Sendable {
    public let hand: [Card]
    /// Win probability + share of ties. Fraction 0...1.
    public let equity: Double
    /// Probability of being the sole winner.
    public let winProb: Double
    /// Probability of chopping.
    public let tieProb: Double
    /// Per-category win/lose/tie decomposition.
    public let breakdown: [HandCategory: CategoryBreakdown]
}

public struct EquityResult: Sendable {
    public let players: [PlayerEquity]
    public let totalRunouts: Int
}

public enum EquityCalculator {

    /// Exact equity by enumerating every remaining board runout.
    ///
    /// - Parameters:
    ///   - hands: each player's two hole cards.
    ///   - board: 0...5 community cards already known.
    public static func compute(hands: [[Card]], board: [Card]) -> EquityResult {
        precondition(hands.count >= 2, "need at least two hands")
        let playerCount = hands.count
        let categoryCount = HandCategory.allCases.count

        let known = Set(hands.flatMap { $0 } + board)
        let remaining = Card.fullDeck.filter { !known.contains($0) }
        let missing = 5 - board.count
        precondition(missing >= 0, "board has more than 5 cards")

        var winCat = Array(repeating: [Double](repeating: 0, count: categoryCount), count: playerCount)
        var tieCat = Array(repeating: [Double](repeating: 0, count: categoryCount), count: playerCount)
        var loseCat = Array(repeating: [Double](repeating: 0, count: categoryCount), count: playerCount)
        var equityPoints = [Double](repeating: 0, count: playerCount)
        var totalRunouts = 0

        var ranks = [HandRank](repeating: evaluate5([Card](repeating: remaining[0], count: 5)),
                               count: playerCount)
        var sevenCards = [Card](repeating: remaining[0], count: 7)

        forEachCombination(remaining, choose: missing) { fill in
            // Build the full board once, then evaluate each player's 7 cards.
            // sevenCards = 2 hole + 5 board (board.count + fill.count == 5).
            var bestScore = Int.min
            for p in 0..<playerCount {
                sevenCards[0] = hands[p][0]
                sevenCards[1] = hands[p][1]
                var idx = 2
                for c in board { sevenCards[idx] = c; idx += 1 }
                for c in fill { sevenCards[idx] = c; idx += 1 }
                let r = evaluate(sevenCards)
                ranks[p] = r
                if r.score > bestScore { bestScore = r.score }
            }

            // Count winners at the best score.
            var winnerCount = 0
            for p in 0..<playerCount where ranks[p].score == bestScore { winnerCount += 1 }

            totalRunouts += 1
            if winnerCount == 1 {
                for p in 0..<playerCount {
                    let cat = ranks[p].category.rawValue
                    if ranks[p].score == bestScore {
                        winCat[p][cat] += 1
                        equityPoints[p] += 1
                    } else {
                        loseCat[p][cat] += 1
                    }
                }
            } else {
                let share = 1.0 / Double(winnerCount)
                for p in 0..<playerCount {
                    let cat = ranks[p].category.rawValue
                    if ranks[p].score == bestScore {
                        tieCat[p][cat] += 1
                        equityPoints[p] += share
                    } else {
                        loseCat[p][cat] += 1
                    }
                }
            }
        }

        let total = Double(max(totalRunouts, 1))
        var players = [PlayerEquity]()
        players.reserveCapacity(playerCount)
        for p in 0..<playerCount {
            var breakdown = [HandCategory: CategoryBreakdown]()
            var winSum = 0.0
            var tieSum = 0.0
            for cat in HandCategory.allCases {
                let i = cat.rawValue
                let b = CategoryBreakdown(winProb: winCat[p][i] / total,
                                          tieProb: tieCat[p][i] / total,
                                          loseProb: loseCat[p][i] / total)
                if b.total > 0 { breakdown[cat] = b }
                winSum += winCat[p][i]
                tieSum += tieCat[p][i]
            }
            players.append(PlayerEquity(hand: hands[p],
                                        equity: equityPoints[p] / total,
                                        winProb: winSum / total,
                                        tieProb: tieSum / total,
                                        breakdown: breakdown))
        }

        return EquityResult(players: players, totalRunouts: totalRunouts)
    }
}
