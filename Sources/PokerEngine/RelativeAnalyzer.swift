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
    /// The relative decomposition is computed in the same single enumeration pass
    /// as the equity (see `EquityCalculator.compute`); this is a thin accessor.
    public static func analyze(hands: [[Card]], board: [Card], maxRunouts: Int = .max) -> [RelativeAnalysis] {
        EquityCalculator.compute(hands: hands, board: board, maxRunouts: maxRunouts).relative
    }
}

/// Texture of the board behind a kicker-chop (module-internal helper).
func boardTexture(_ board: [Card], _ bd: HandRank) -> Int {
    // Only an actual straight/flush on the board is a "run"; a paired board
    // (full house / quads) is classified by its paired rank below.
    if bd.category == .straight || bd.category == .flush || bd.category == .straightFlush {
        return 2
    }
    var counts = [Int](repeating: 0, count: 15)
    for c in board { counts[c.rank] += 1 }
    for r in stride(from: 14, through: 2, by: -1) where counts[r] >= 2 {
        return r >= 10 ? 0 : 1
    }
    return 3
}
