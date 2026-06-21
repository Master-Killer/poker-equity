import Foundation

/// Outcome of a runout for a player, relative to the best opponent.
public enum RelOutcome: Int, Sendable, CaseIterable {
    case win = 0   // strictly best at the table (sole winner)
    case tie       // tied for best (chop)
    case lose      // someone else is better
}

/// When I WIN by combination, which hole card(s) built that combination over the
/// board.
public enum EdgeMechanism: Int, Sendable, CaseIterable {
    case unsharedCard = 0   // an UNSHARED hole rank paired on the board (e.g. my 2)
    case sharedRank         // a rank both players hold paired (e.g. the common 10)
    case draw               // my hole makes the better straight/flush (completed, or higher than the board's)
    case pocketPair         // my two hole cards are a pair, above the board (no hole rank on board)

    public var label: String {
        switch self {
        case .unsharedCard: return "via ma carte non partagée"
        case .sharedRank: return "via un rang partagé"
        case .draw: return "via une quinte/couleur"
        case .pocketPair: return "via une paire servie"
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

/// One illustrative runout for a leaf cell: a real board, which board card(s)
/// are decisive, what each side ends up with, and how representative it is.
public struct RelExample: Sendable {
    /// The complete five-card board for this runout.
    public let board: [Card]
    /// Indices into `board` of the card(s) that make the player's hand
    /// (the paired hole rank, or the cards completing a straight/flush).
    /// Empty when the board plays or only a kicker decides.
    public let decisive: [Int]
    /// The five-card category the player ends up with.
    public let myCategory: HandCategory
    /// The five-card category of the *best opponent* on this board.
    public let oppCategory: HandCategory
    /// Number of runouts (board combinations) matching this example's scenario.
    public let count: Int
    /// `count` as a fraction of *all* runouts (absolute probability, not relative
    /// to the cell) — the UI shows this in %, or `count` combos when it rounds to 0.
    public let share: Double
}

/// "How I improve, relative to the opponent" — a decomposition of every runout by
/// the **showdown** between me and the best opponent (not by what I add to the bare
/// board). This keeps "le kicker tranche" to genuine kicker duels: same combination
/// on both sides, a side card decides. All values are fractions of all runouts.
public struct RelativeAnalysis: Sendable {
    public let hand: [Card]
    /// I win because my combination beats the opponent's, split by how my hole
    /// built that combination over the board (`EdgeMechanism`).
    public let winCombination: [Double]   // indexed by EdgeMechanism.rawValue
    /// I win a genuine kicker duel (same combination as the opponent, my side card wins).
    public let winKicker: Double
    /// Chop — identical hands — split by board texture (`ChopTexture`).
    public let chop: [Double]             // indexed by ChopTexture.rawValue
    /// I lose because the opponent has a better combination.
    public let loseCombination: Double
    /// I lose a genuine kicker duel.
    public let loseKicker: Double
    /// A few *varied* example runouts per leaf, keyed by the helpers below; every
    /// non-empty leaf has at least one, so every number is explainable.
    public let examples: [String: [RelExample]]

    public var winTotal: Double { winCombination.reduce(0, +) + winKicker }
    public var tieTotal: Double { chop.reduce(0, +) }
    public var loseTotal: Double { loseCombination + loseKicker }

    // Stable leaf keys.
    public static func winComboKey(_ m: EdgeMechanism) -> String { "wincombo-\(m.rawValue)" }
    public static let winKickerKey = "winkicker"
    public static func chopKey(_ t: ChopTexture) -> String { "chop-\(t.rawValue)" }
    public static let loseComboKey = "losecombo"
    public static let loseKickerKey = "losekicker"
}

// The relative decomposition is produced in the same single enumeration pass as
// the equity: read it from `EquityCalculator.compute(...).relative`.

/// Why one five-card hand beats (or ties) another, honouring the strict kicker
/// definition: a *kicker* decides ONLY between two identical combinations. A made
/// hand (full / straight / flush) never has a kicker — a higher one is a
/// `betterCombination`, never a `kickerWin`.
public enum ShowdownVerdict: Sendable, Equatable {
    case higherCategory     // my category outranks the opponent's
    case lowerCategory      // the opponent's category outranks mine
    case betterCombination  // same category, my combination is stronger (no kicker involved)
    case worseCombination   // same category, the opponent's combination is stronger
    case kickerWin          // identical combination, my side card wins
    case kickerLose         // identical combination, the opponent's side card wins
    case chop               // identical hands
}

/// Classify the showdown between two evaluated five-card hands.
public func showdownVerdict(_ myFive: [Card], _ oppFive: [Card]) -> ShowdownVerdict {
    let mine = evaluate(myFive), opp = evaluate(oppFive)
    return showdownVerdict(myScore: mine.score, myCategory: mine.category,
                           oppScore: opp.score, oppCategory: opp.category)
}

/// Same classification from already-evaluated packed scores (hot-loop friendly).
@inline(__always)
func showdownVerdict(myScore: Int, myCategory: HandCategory,
                     oppScore: Int, oppCategory: HandCategory) -> ShowdownVerdict {
    if myScore == oppScore { return .chop }
    if myCategory != oppCategory {
        return myCategory > oppCategory ? .higherCategory : .lowerCategory
    }
    let myCombi = combinationScore(myScore, myCategory)
    let oppCombi = combinationScore(oppScore, oppCategory)
    if myCombi == oppCombi { return myScore > oppScore ? .kickerWin : .kickerLose }
    return myCombi > oppCombi ? .betterCombination : .worseCombination
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
