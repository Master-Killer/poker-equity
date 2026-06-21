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
        precondition(remaining.count >= missing, "not enough cards left to complete the board")

        var winCat = Array(repeating: [Double](repeating: 0, count: categoryCount), count: playerCount)
        var tieCat = Array(repeating: [Double](repeating: 0, count: categoryCount), count: playerCount)
        var loseCat = Array(repeating: [Double](repeating: 0, count: categoryCount), count: playerCount)
        var equityPoints = [Double](repeating: 0, count: playerCount)
        var coWin = Array(repeating: [Double](repeating: 0, count: playerCount), count: playerCount)
        // [player][ownCategory][opponentCategory]
        var winSrc = Array(repeating: Array(repeating: [Double](repeating: 0, count: categoryCount), count: categoryCount), count: playerCount)
        var loseSrc = Array(repeating: Array(repeating: [Double](repeating: 0, count: categoryCount), count: categoryCount), count: playerCount)
        var totalRunouts = 0

        // Relative ("how I improve, vs the opponent") accumulators + rank bitmasks.
        // Each runout is classified by the showdown verdict against the best opponent.
        let mechCount = EdgeMechanism.allCases.count
        var relWinCombo = Array(repeating: [Double](repeating: 0, count: mechCount), count: playerCount)
        var relWinKicker = [Double](repeating: 0, count: playerCount)
        var relChop = Array(repeating: [Double](repeating: 0, count: 4), count: playerCount)
        var relLoseCombo = [Double](repeating: 0, count: playerCount)
        var relLoseKicker = [Double](repeating: 0, count: playerCount)
        // Per (player, leaf key): runouts bucketed by scenario signature, so the
        // few examples kept are varied (typical + contrasting) instead of the
        // near-identical adjacent boards that lexicographic enumeration yields.
        var relBuckets = Array(repeating: [String: [Int: ExampleBucket]](), count: playerCount)
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

        // Placeholder cards just size the reused buffers; every slot is
        // overwritten before use, so a fixed deck card avoids indexing an
        // empty `remaining` when the board is already complete.
        let placeholder = Card.fullDeck[0]
        var ranks = [HandRank](repeating: evaluate5([Card](repeating: placeholder, count: 5)),
                               count: playerCount)
        var sevenCards = [Card](repeating: placeholder, count: 7)
        var boardBuf = [Card](repeating: placeholder, count: 5)
        var winners = [Int]()
        winners.reserveCapacity(playerCount)

        // Tally one runout: `fill` is the cards completing the board.
        func tally(_ fill: [Card]) {
            var bi = 0
            for c in board { boardBuf[bi] = c; bi += 1 }
            for c in fill { boardBuf[bi] = c; bi += 1 }

            var bestScore = Int.min, bestCat = 0, bestIdx = 0
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
                    bestScore = r.score; bestCat = r.category.rawValue; bestIdx = p
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
                // Classify by the showdown against the best opponent: the runner-up
                // when p is the sole leader, otherwise the table best.
                let myScore = ranks[p].score
                let myCatEnum = ranks[p].category
                let myCat = myCatEnum.rawValue
                let pSoleBest = myScore == bestScore && winnerCount == 1
                let oppScore = pSoleBest ? secondScore : bestScore
                let oppCat = pSoleBest ? secondCat : bestCat
                let verdict = showdownVerdict(myScore: myScore, myCategory: myCatEnum,
                                              oppScore: oppScore, oppCategory: HandCategory(rawValue: oppCat)!)

                var key: String
                var mech = -1
                var winnerHand = hands[p]   // whose combination to highlight on the board
                switch verdict {
                case .higherCategory, .betterCombination:
                    // I win by my combination — classify how my hole built it over the board.
                    if myCat == HandCategory.straight.rawValue || myCat == HandCategory.flush.rawValue
                        || myCat == HandCategory.straightFlush.rawValue {
                        mech = EdgeMechanism.draw.rawValue
                    } else if unsharedMask[p] & boardRankMask != 0 {
                        mech = EdgeMechanism.unsharedCard.rawValue
                    } else if sharedMask[p] & boardRankMask != 0 {
                        mech = EdgeMechanism.sharedRank.rawValue
                    } else {
                        mech = EdgeMechanism.pocketPair.rawValue
                    }
                    relWinCombo[p][mech] += 1
                    key = RelativeAnalysis.winComboKey(EdgeMechanism(rawValue: mech)!)
                case .kickerWin:
                    relWinKicker[p] += 1
                    key = RelativeAnalysis.winKickerKey
                case .chop:
                    let tex = boardTexture(boardBuf, bd)
                    relChop[p][tex] += 1
                    key = RelativeAnalysis.chopKey(ChopTexture(rawValue: tex)!)
                case .worseCombination, .lowerCategory:
                    relLoseCombo[p] += 1
                    key = RelativeAnalysis.loseComboKey
                    winnerHand = hands[bestIdx]   // highlight the opponent's winning combination
                case .kickerLose:
                    relLoseKicker[p] += 1
                    key = RelativeAnalysis.loseKickerKey
                }

                // Bucket this runout by its scenario signature so the kept examples
                // stay varied (typical + contrasting), not near-identical boards.
                var decisiveRank = 0
                if mech == EdgeMechanism.unsharedCard.rawValue {
                    decisiveRank = highestSetRank(unsharedMask[p] & boardRankMask)
                } else if mech == EdgeMechanism.sharedRank.rawValue {
                    decisiveRank = highestSetRank(sharedMask[p] & boardRankMask)
                }
                let sig = (myCat << 16) | (oppCat << 8) | decisiveRank
                if relBuckets[p][key]?[sig] != nil {
                    relBuckets[p][key]![sig]!.count += 1
                } else {
                    // First runout of this signature: representative + decisive cards.
                    let dec = decisiveBoardIndices(hand: winnerHand, board: boardBuf)
                    relBuckets[p][key, default: [:]][sig] =
                        ExampleBucket(sig: sig, count: 1, board: boardBuf,
                                      decisive: dec, myCat: myCat, oppCat: oppCat)
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
            var examples = [String: [RelExample]]()
            for (key, buckets) in relBuckets[p] {
                examples[key] = selectVariedExamples(Array(buckets.values), limit: relExampleLimit, total: total)
            }
            relative.append(RelativeAnalysis(
                hand: hands[p],
                winCombination: relWinCombo[p].map { $0 / total },
                winKicker: relWinKicker[p] / total,
                chop: relChop[p].map { $0 / total },
                loseCombination: relLoseCombo[p] / total,
                loseKicker: relLoseKicker[p] / total,
                examples: examples
            ))
        }

        let coWinMatrix = coWin.map { row in row.map { $0 / total } }
        return EquityResult(players: players, totalRunouts: totalRunouts,
                            coWinMatrix: coWinMatrix, relative: relative)
    }
}

// MARK: - Relative example selection

/// How many example runouts to keep per leaf cell.
private let relExampleLimit = 3

/// One scenario bucket gathered during the pass: a representative board plus how
/// often this signature occurs, used to pick varied examples afterwards.
private struct ExampleBucket {
    let sig: Int
    var count: Int
    let board: [Card]
    let decisive: [Int]
    let myCat: Int
    let oppCat: Int
}

/// Highest rank (2...14) set in a 15-bit rank mask, or 0 if none.
@inline(__always)
func highestSetRank(_ mask: Int) -> Int {
    var r = 14
    while r >= 2 { if mask & (1 << r) != 0 { return r }; r -= 1 }
    return 0
}

/// A packed score stripped of its *kicker* nibbles, keeping only the category and
/// the ranks that form the combination itself (the paired part; all five ranks for
/// a flush; the run-high for a straight). Two hands with the same `combinationScore`
/// hold the exact same combination and differ — if at all — only by a kicker.
@inline(__always)
func combinationScore(_ score: Int, _ category: HandCategory) -> Int {
    // Score layout: category<<20 | k1<<16 | k2<<12 | k3<<8 | k4<<4 | k5.
    let lowMask: Int
    switch category {
    case .highCard:               lowMask = 0x00000          // all five are kickers
    case .onePair, .trips, .quads,
         .straight, .straightFlush: lowMask = 0xF0000        // first nibble only
    case .twoPair, .fullHouse:    lowMask = 0xFF000          // first two nibbles
    case .flush:                  lowMask = 0xFFFFF          // a flush has no kicker
    }
    return (score & ~0xFFFFF) | (score & lowMask)
}

/// The board cards that compose the given hand's combination — both pairs of a two
/// pair, the trips and pair of a full house, all five of a straight/flush, etc.
/// (kickers excluded). Highlighting these shows the whole made hand. `hand` is the
/// winner's hole cards, so a loss highlights the opponent's winning combination.
private func decisiveBoardIndices(hand: [Card], board: [Card]) -> [Int] {
    let combo = Set(combinationCards(bestFive(hand + board)))
    return board.indices.filter { combo.contains(board[$0]) }
}

/// The cards forming the combination itself — the paired ranks (two cards per
/// pair, three for trips, four for quads), or all five for a straight/flush/full
/// house. Pure kickers are excluded; a bare high card has no combination.
func combinationCards(_ five: [Card]) -> [Card] {
    switch evaluate(five).category {
    case .highCard: return []
    case .straight, .flush, .fullHouse, .straightFlush: return five
    case .onePair, .twoPair, .trips, .quads:
        var counts = [Int: Int]()
        for c in five { counts[c.rank, default: 0] += 1 }
        return five.filter { (counts[$0.rank] ?? 0) >= 2 }
    }
}

/// "Variété max": the most frequent scenario first, then greedily the buckets
/// that contrast most with those already chosen (different opponent category
/// outweighs a different own category, which outweighs a different decisive
/// rank), ties broken by frequency. Each example carries its share of the cell.
private func selectVariedExamples(_ buckets: [ExampleBucket], limit: Int, total: Double) -> [RelExample] {
    guard !buckets.isEmpty else { return [] }
    var pool = buckets.sorted { $0.count > $1.count }
    var chosen = [pool.removeFirst()]
    while chosen.count < limit && !pool.isEmpty {
        var bestIdx = 0
        var bestKey = (-1, -1)
        for (i, b) in pool.enumerated() {
            let minDist = chosen.map { bucketDistance($0, b) }.min() ?? 0
            let candidate = (minDist, b.count)
            if candidate > bestKey { bestKey = candidate; bestIdx = i }
        }
        chosen.append(pool.remove(at: bestIdx))
    }
    return chosen.map { b in
        RelExample(board: b.board, decisive: b.decisive,
                   myCategory: HandCategory(rawValue: b.myCat)!,
                   oppCategory: HandCategory(rawValue: b.oppCat)!,
                   count: b.count,
                   share: Double(b.count) / total)   // absolute: fraction of all runouts
    }
}

/// Contrast between two scenario buckets (higher = more different).
private func bucketDistance(_ a: ExampleBucket, _ b: ExampleBucket) -> Int {
    (a.oppCat != b.oppCat ? 4 : 0)
        + (a.myCat != b.myCat ? 2 : 0)
        + ((a.sig & 0xFF) != (b.sig & 0xFF) ? 1 : 0)
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
