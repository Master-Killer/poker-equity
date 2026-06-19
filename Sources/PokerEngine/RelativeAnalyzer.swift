import Foundation

/// Outcome of a runout for a player, relative to the best opponent.
public enum RelOutcome: Int, Sendable, CaseIterable {
    case win = 0   // strictly best at the table (sole winner)
    case tie       // tied for best (chop)
    case lose      // someone else is better
}

/// Where a player's result comes from, measured against the *bare board*.
public enum RelSource: Int, Sendable, CaseIterable {
    /// Hole cards build a strictly higher category than the bare board (a real new hand).
    case ownEdge = 0
    /// Same category as the bare board; hole cards only shift in-category rank/kicker.
    case kicker
    /// Hole cards add nothing to the best five — the board plays.
    case playsBoard

    public var label: String {
        switch self {
        case .ownEdge: return "Mon edge propre"
        case .kicker: return "Le kicker tranche"
        case .playsBoard: return "Le tableau joue"
        }
    }
}

/// For an `ownEdge`, which hole card(s) created the new hand.
public enum EdgeMechanism: Int, Sendable, CaseIterable {
    case unsharedCard = 0   // an UNSHARED hole rank paired on the board (e.g. my 2)
    case sharedRank         // a rank both players hold paired (e.g. the common 10)
    case draw               // a straight/flush from my hole, no paired hole rank

    public var label: String {
        switch self {
        case .unsharedCard: return "via ma carte non partagée"
        case .sharedRank: return "via un rang partagé"
        case .draw: return "via un tirage (couleur/quinte)"
        }
    }
}

/// Board texture behind a `kicker`-chop, to separate "board pairs low (changes nothing)"
/// from "board pairs high (kickers fall out → split)".
public enum ChopTexture: Int, Sendable, CaseIterable {
    case boardPairHigh = 0  // board pairs a rank >= 10
    case boardPairLow       // board pairs a rank < 10
    case boardRun           // straight / flush / better on the board itself
    case other

    public var label: String {
        switch self {
        case .boardPairHigh: return "le tableau s'appaire ≥ 10"
        case .boardPairLow: return "le tableau s'appaire < 10"
        case .boardRun: return "quinte/couleur au tableau"
        case .other: return "autre"
        }
    }
}

public struct RelativeAnalysis: Sendable {
    public let hand: [Card]
    /// `prob[source.rawValue][outcome.rawValue]` — fractions of all runouts, summing to 1.
    public let prob: [[Double]]
    /// `edgeMechanism[mechanism.rawValue][outcome.rawValue]` — splits the `ownEdge` row.
    public let edgeMechanism: [[Double]]
    /// `kickerChopTexture[texture.rawValue]` — splits the `kicker`+`tie` cell.
    public let kickerChopTexture: [Double]
    /// Up to a few example boards per *leaf cell*, keyed by `leafKey(...)`.
    /// Every non-empty cell has at least one, so every number is explainable.
    public let examples: [String: [[Card]]]

    public func p(_ s: RelSource, _ o: RelOutcome) -> Double { prob[s.rawValue][o.rawValue] }

    /// Stable key for a leaf cell of the decomposition.
    public static func leafKey(source: RelSource, outcome: RelOutcome,
                               mechanism: EdgeMechanism? = nil, texture: ChopTexture? = nil) -> String {
        switch source {
        case .ownEdge: return "edge-\(mechanism?.rawValue ?? -1)-\(outcome.rawValue)"
        case .kicker: return outcome == .tie ? "kicker-tie-\(texture?.rawValue ?? -1)" : "kicker-\(outcome.rawValue)"
        case .playsBoard: return "board-\(outcome.rawValue)"
        }
    }
}

/// Decomposes runouts by HOW a hand improves *relative to the opponent*, setting aside
/// contributions shared by the board. Heads-up oriented; for 3+ players the result is
/// measured against the best opponent ("the field").
public enum RelativeAnalyzer {

    public static func analyze(hands: [[Card]], board: [Card]) -> [RelativeAnalysis] {
        let n = hands.count
        precondition(n >= 2)
        let known = Set(hands.flatMap { $0 } + board)
        let remaining = Card.fullDeck.filter { !known.contains($0) }
        let missing = 5 - board.count
        precondition(missing >= 0)

        // Rank bitmasks: unshared = my ranks minus every opponent's ranks.
        var unsharedMask = [Int](repeating: 0, count: n)
        var sharedMask = [Int](repeating: 0, count: n)
        for p in 0..<n {
            var mine = 0
            for c in hands[p] { mine |= 1 << c.rank }
            var others = 0
            for q in 0..<n where q != p { for c in hands[q] { others |= 1 << c.rank } }
            unsharedMask[p] = mine & ~others
            sharedMask[p] = mine & others
        }

        var prob = Array(repeating: Array(repeating: [Double](repeating: 0, count: 3), count: 3), count: n)
        var edge = Array(repeating: Array(repeating: [Double](repeating: 0, count: 3), count: 3), count: n)
        var chop = Array(repeating: [Double](repeating: 0, count: 4), count: n)
        var examples = Array(repeating: [String: [[Card]]](), count: n)
        let exampleCap = 3
        var total = 0.0

        let placeholder = remaining.first ?? hands[0][0]
        var seven = [Card](repeating: placeholder, count: 7)
        var scores = [Int](repeating: 0, count: n)
        var cats = [Int](repeating: 0, count: n)

        func process(_ B: [Card]) {
            let bd = evaluate(B)
            var boardRankMask = 0
            for c in B { boardRankMask |= 1 << c.rank }

            for p in 0..<n {
                seven[0] = hands[p][0]; seven[1] = hands[p][1]
                for i in 0..<5 { seven[2 + i] = B[i] }
                let r = evaluate(seven)
                scores[p] = r.score; cats[p] = r.category.rawValue
            }
            total += 1

            for p in 0..<n {
                var bestOpp = Int.min
                for q in 0..<n where q != p && scores[q] > bestOpp { bestOpp = scores[q] }
                let outcome = scores[p] > bestOpp ? 0 : (scores[p] == bestOpp ? 1 : 2)
                let source = (scores[p] == bd.score) ? 2 : (cats[p] > bd.category.rawValue ? 0 : 1)

                prob[p][source][outcome] += 1

                var key: String
                if source == 0 {
                    // A straight/flush edge is a "draw"; otherwise it is a made hand
                    // from pairing a hole rank — then ask which one paired on the board.
                    let c = cats[p]
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
                    edge[p][mech][outcome] += 1
                    key = "edge-\(mech)-\(outcome)"
                } else if source == 1 {
                    if outcome == 1 {
                        let tex = texture(B, bd)
                        chop[p][tex] += 1
                        key = "kicker-tie-\(tex)"
                    } else {
                        key = "kicker-\(outcome)"
                    }
                } else {
                    key = "board-\(outcome)"
                }

                if (examples[p][key]?.count ?? 0) < exampleCap {
                    examples[p][key, default: []].append(B)
                }
            }
        }

        if missing == 0 { process(board) }
        else { forEachCombination(remaining, choose: missing) { process(board + $0) } }

        let t = max(total, 1)
        var results = [RelativeAnalysis]()
        for p in 0..<n {
            results.append(RelativeAnalysis(
                hand: hands[p],
                prob: prob[p].map { row in row.map { $0 / t } },
                edgeMechanism: edge[p].map { row in row.map { $0 / t } },
                kickerChopTexture: chop[p].map { $0 / t },
                examples: examples[p]
            ))
        }
        return results
    }

    /// Texture of the board behind a kicker-chop.
    private static func texture(_ B: [Card], _ bd: HandRank) -> Int {
        if bd.category >= .straight { return 2 } // board run (straight/flush/…)
        var counts = [Int](repeating: 0, count: 15)
        for c in B { counts[c.rank] += 1 }
        for r in stride(from: 14, through: 2, by: -1) where counts[r] >= 2 {
            return r >= 10 ? 0 : 1
        }
        return 3
    }
}
