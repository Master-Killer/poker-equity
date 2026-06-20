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
    /// `winVs[ownCategory][beatenCategory]` — when this player wins with
    /// `ownCategory`, the probability the best opponent held `beatenCategory`.
    /// Summing the inner values gives the category's win probability.
    public let winVs: [HandCategory: [HandCategory: Double]]
    /// `loseVs[ownCategory][winnerCategory]` — when this player loses while
    /// holding `ownCategory`, the probability the winner held `winnerCategory`.
    public let loseVs: [HandCategory: [HandCategory: Double]]
}

public struct EquityResult: Sendable {
    public let players: [PlayerEquity]
    public let totalRunouts: Int
    /// `coWinMatrix[i][j]` = fraction of runouts where players i and j are both
    /// among the winners. The diagonal is each player's win-or-tie probability;
    /// off-diagonal entries reveal who splits with whom (pairwise).
    public let coWinMatrix: [[Double]]
    /// "How do I improve relative to the field" decomposition, one per player.
    public let relative: [RelativeAnalysis]
}

public enum EquityCalculator {

    /// Equity over the remaining board runouts.
    ///
    /// - Parameters:
    ///   - hands: each player's two hole cards.
    ///   - board: 0...5 community cards already known.
    ///   - maxRunouts: if the number of exact runouts exceeds this, the result
    ///     is estimated by Monte-Carlo sampling with `maxRunouts` random runouts
    ///     instead. Defaults to exact (unbounded) enumeration.
    ///   - shouldCancel: polled periodically during enumeration; when it returns
    ///     true the loop bails out early (the partial result should be discarded).
    public static func compute(hands: [[Card]], board: [Card], maxRunouts: Int = .max,
                               shouldCancel: () -> Bool = { false }) -> EquityResult {
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
        var coWin = Array(repeating: [Double](repeating: 0, count: playerCount), count: playerCount)
        // [player][ownCategory][opponentCategory]
        var winSrc = Array(repeating: Array(repeating: [Double](repeating: 0, count: categoryCount), count: categoryCount), count: playerCount)
        var loseSrc = Array(repeating: Array(repeating: [Double](repeating: 0, count: categoryCount), count: categoryCount), count: playerCount)
        var totalRunouts = 0

        // Relative ("how I improve") accumulators + per-player rank bitmasks.
        var relProb = Array(repeating: Array(repeating: [Double](repeating: 0, count: 3), count: 3), count: playerCount)
        var relEdge = Array(repeating: Array(repeating: [Double](repeating: 0, count: 3), count: 3), count: playerCount)
        var relChop = Array(repeating: [Double](repeating: 0, count: 4), count: playerCount)
        var relExamples = Array(repeating: [String: [[Card]]](), count: playerCount)
        var unsharedMask = [Int](repeating: 0, count: playerCount)
        var sharedMask = [Int](repeating: 0, count: playerCount)
        for p in 0..<playerCount {
            var mine = 0
            for c in hands[p] { mine |= 1 << c.rank }
            var others = 0
            for q in 0..<playerCount where q != p { for c in hands[q] { others |= 1 << c.rank } }
            unsharedMask[p] = mine & ~others
            sharedMask[p] = mine & others
        }

        var ranks = [HandRank](repeating: evaluate5([Card](repeating: remaining[0], count: 5)),
                               count: playerCount)
        var sevenCards = [Card](repeating: remaining[0], count: 7)
        var boardBuf = [Card](repeating: remaining[0], count: 5)
        var winners = [Int]()
        winners.reserveCapacity(playerCount)

        // Tally one runout: `fill` is the cards completing the board.
        func tally(_ fill: [Card]) {
            var bi = 0
            for c in board { boardBuf[bi] = c; bi += 1 }
            for c in fill { boardBuf[bi] = c; bi += 1 }

            var bestScore = Int.min, bestCat = 0
            var secondScore = Int.min, secondCat = 0
            for p in 0..<playerCount {
                sevenCards[0] = hands[p][0]
                sevenCards[1] = hands[p][1]
                var idx = 2
                for c in board { sevenCards[idx] = c; idx += 1 }
                for c in fill { sevenCards[idx] = c; idx += 1 }
                let r = evaluate(sevenCards)
                ranks[p] = r
                if r.score > bestScore {
                    secondScore = bestScore; secondCat = bestCat
                    bestScore = r.score; bestCat = r.category.rawValue
                } else if r.score > secondScore {
                    secondScore = r.score; secondCat = r.category.rawValue
                }
            }

            winners.removeAll(keepingCapacity: true)
            for p in 0..<playerCount where ranks[p].score == bestScore { winners.append(p) }
            let winnerCount = winners.count

            totalRunouts += 1
            for a in winners { for b in winners { coWin[a][b] += 1 } }

            // --- relative ("how I improve") classification ---
            let bd = evaluate(boardBuf)
            var boardRankMask = 0
            for c in boardBuf { boardRankMask |= 1 << c.rank }
            for p in 0..<playerCount {
                let outcome = ranks[p].score == bestScore ? (winnerCount == 1 ? 0 : 1) : 2
                let src = ranks[p].score == bd.score ? 2
                    : (ranks[p].category.rawValue > bd.category.rawValue ? 0 : 1)
                relProb[p][src][outcome] += 1

                var key: String
                if src == 0 {
                    let c = ranks[p].category.rawValue
                    let mech: Int
                    if c == HandCategory.straight.rawValue || c == HandCategory.flush.rawValue
                        || c == HandCategory.straightFlush.rawValue {
                        mech = 2
                    } else if unsharedMask[p] & boardRankMask != 0 {
                        mech = 0
                    } else if sharedMask[p] & boardRankMask != 0 {
                        mech = 1
                    } else {
                        mech = 2
                    }
                    relEdge[p][mech][outcome] += 1
                    key = "edge-\(mech)-\(outcome)"
                } else if src == 1 {
                    if outcome == 1 {
                        let tex = boardTexture(boardBuf, bd)
                        relChop[p][tex] += 1
                        key = "kicker-tie-\(tex)"
                    } else {
                        key = "kicker-\(outcome)"
                    }
                } else {
                    key = "board-\(outcome)"
                }
                if (relExamples[p][key]?.count ?? 0) < 3 {
                    relExamples[p][key, default: []].append(boardBuf)
                }
            }

            if winnerCount == 1 {
                for p in 0..<playerCount {
                    let cat = ranks[p].category.rawValue
                    if ranks[p].score == bestScore {
                        winCat[p][cat] += 1
                        equityPoints[p] += 1
                        winSrc[p][cat][secondCat] += 1   // what the winner beat
                    } else {
                        loseCat[p][cat] += 1
                        loseSrc[p][cat][bestCat] += 1     // what beat this player
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
                        loseSrc[p][cat][bestCat] += 1
                    }
                }
            }
        }

        let exactCount = combinationCount(remaining.count, missing)
        if exactCount <= maxRunouts {
            var stop = false
            var sinceCheck = 0
            forEachCombination(remaining, choose: missing) { combo in
                if stop { return }
                sinceCheck += 1
                if sinceCheck >= 8192 { sinceCheck = 0; if shouldCancel() { stop = true; return } }
                tally(combo)
            }
        } else {
            // Monte-Carlo: sample `maxRunouts` distinct-card runouts.
            // Deterministic RNG seeded from the known cards, so identical inputs
            // always yield identical estimates (no flicker between recomputes).
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for hand in hands { for card in hand { seed = seed &* 1099511628211 &+ UInt64(card.index + 1) } }
            for card in board { seed = seed &* 1099511628211 &+ UInt64(card.index + 1) }
            var rng = SplitMix64(seed: seed)
            var deck = remaining
            let n = deck.count
            var fill = [Card](repeating: deck[0], count: missing)
            for k in 0..<maxRunouts {
                if k & 8191 == 0 && shouldCancel() { break }
                for i in 0..<missing {
                    let j = Int.random(in: i..<n, using: &rng)
                    deck.swapAt(i, j)
                    fill[i] = deck[i]
                }
                tally(fill)
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

            var winVs = [HandCategory: [HandCategory: Double]]()
            var loseVs = [HandCategory: [HandCategory: Double]]()
            for own in HandCategory.allCases {
                var wins = [HandCategory: Double]()
                var losses = [HandCategory: Double]()
                for opp in HandCategory.allCases {
                    let w = winSrc[p][own.rawValue][opp.rawValue]
                    if w > 0 { wins[opp] = w / total }
                    let l = loseSrc[p][own.rawValue][opp.rawValue]
                    if l > 0 { losses[opp] = l / total }
                }
                if !wins.isEmpty { winVs[own] = wins }
                if !losses.isEmpty { loseVs[own] = losses }
            }

            players.append(PlayerEquity(hand: hands[p],
                                        equity: equityPoints[p] / total,
                                        winProb: winSum / total,
                                        tieProb: tieSum / total,
                                        breakdown: breakdown,
                                        winVs: winVs,
                                        loseVs: loseVs))
        }

        var relative = [RelativeAnalysis]()
        relative.reserveCapacity(playerCount)
        for p in 0..<playerCount {
            relative.append(RelativeAnalysis(
                hand: hands[p],
                prob: relProb[p].map { row in row.map { $0 / total } },
                edgeMechanism: relEdge[p].map { row in row.map { $0 / total } },
                kickerChopTexture: relChop[p].map { $0 / total },
                examples: relExamples[p]
            ))
        }

        let coWinMatrix = coWin.map { row in row.map { $0 / total } }
        return EquityResult(players: players, totalRunouts: totalRunouts,
                            coWinMatrix: coWinMatrix, relative: relative)
    }
}

/// Small, fast, seedable PRNG (SplitMix64) for reproducible Monte-Carlo runs.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
