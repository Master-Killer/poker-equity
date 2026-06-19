import Foundation

/// Poker hand categories, ordered from weakest to strongest.
public enum HandCategory: Int, Comparable, CaseIterable, Sendable {
    case highCard = 0
    case onePair
    case twoPair
    case trips
    case straight
    case flush
    case fullHouse
    case quads
    case straightFlush

    public static func < (lhs: HandCategory, rhs: HandCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .highCard: return "High Card"
        case .onePair: return "One Pair"
        case .twoPair: return "Two Pair"
        case .trips: return "Trips"
        case .straight: return "Straight"
        case .flush: return "Flush"
        case .fullHouse: return "Full House"
        case .quads: return "Quads"
        case .straightFlush: return "Straight Flush"
        }
    }
}

/// The evaluated strength of a 5-card hand.
///
/// `score` packs the category and up to five tiebreaker ranks into a single
/// integer so that a plain `<` comparison is a correct hand comparison.
public struct HandRank: Comparable, Sendable {
    public let score: Int
    public let category: HandCategory
    /// True only for the ace-high straight flush, so the UI can label it "Royal Flush".
    public let isRoyalFlush: Bool

    public static func < (lhs: HandRank, rhs: HandRank) -> Bool { lhs.score < rhs.score }
    public static func == (lhs: HandRank, rhs: HandRank) -> Bool { lhs.score == rhs.score }
}

@inline(__always)
private func packScore(_ category: HandCategory, _ kickers: [Int]) -> Int {
    // category in bits 20+, then up to five 4-bit kicker ranks (rank ≤ 14 < 16).
    var score = category.rawValue << 20
    var shift = 16
    for kicker in kickers {
        score |= (kicker << shift)
        shift -= 4
    }
    return score
}

/// Evaluate exactly five cards.
public func evaluate5(_ cards: [Card]) -> HandRank {
    precondition(cards.count == 5, "evaluate5 expects 5 cards")

    var rankCounts = [Int](repeating: 0, count: 15) // indexed by rank 2...14
    var suitCounts = [Int](repeating: 0, count: 4)
    for card in cards {
        rankCounts[card.rank] += 1
        suitCounts[card.suit.rawValue] += 1
    }
    let isFlush = suitCounts.contains(5)

    // Distinct ranks, high to low.
    var ranksDesc = [Int]()
    ranksDesc.reserveCapacity(5)
    for rank in stride(from: 14, through: 2, by: -1) where rankCounts[rank] > 0 {
        ranksDesc.append(rank)
    }

    // Straight detection (only possible with five distinct ranks).
    var straightHigh = 0
    if ranksDesc.count == 5 {
        if ranksDesc[0] - ranksDesc[4] == 4 {
            straightHigh = ranksDesc[0]
        } else if ranksDesc == [14, 5, 4, 3, 2] { // wheel: A-2-3-4-5
            straightHigh = 5
        }
    }
    let isStraight = straightHigh != 0

    // Group ranks by multiplicity.
    var quadRank = 0
    var tripRank = 0
    var pairRanks = [Int]() // high to low
    for rank in stride(from: 14, through: 2, by: -1) {
        switch rankCounts[rank] {
        case 4: quadRank = rank
        case 3: tripRank = rank
        case 2: pairRanks.append(rank)
        default: break
        }
    }

    if isStraight && isFlush {
        return HandRank(score: packScore(.straightFlush, [straightHigh]),
                        category: .straightFlush,
                        isRoyalFlush: straightHigh == 14)
    }
    if quadRank != 0 {
        let kicker = ranksDesc.first { $0 != quadRank } ?? 0
        return HandRank(score: packScore(.quads, [quadRank, kicker]), category: .quads, isRoyalFlush: false)
    }
    if tripRank != 0 && !pairRanks.isEmpty {
        return HandRank(score: packScore(.fullHouse, [tripRank, pairRanks[0]]), category: .fullHouse, isRoyalFlush: false)
    }
    if isFlush {
        return HandRank(score: packScore(.flush, ranksDesc), category: .flush, isRoyalFlush: false)
    }
    if isStraight {
        return HandRank(score: packScore(.straight, [straightHigh]), category: .straight, isRoyalFlush: false)
    }
    if tripRank != 0 {
        let kickers = ranksDesc.filter { $0 != tripRank } // exactly two
        return HandRank(score: packScore(.trips, [tripRank] + kickers), category: .trips, isRoyalFlush: false)
    }
    if pairRanks.count >= 2 {
        let kicker = ranksDesc.first { $0 != pairRanks[0] && $0 != pairRanks[1] } ?? 0
        return HandRank(score: packScore(.twoPair, [pairRanks[0], pairRanks[1], kicker]), category: .twoPair, isRoyalFlush: false)
    }
    if pairRanks.count == 1 {
        let kickers = ranksDesc.filter { $0 != pairRanks[0] } // exactly three
        return HandRank(score: packScore(.onePair, [pairRanks[0]] + kickers), category: .onePair, isRoyalFlush: false)
    }
    return HandRank(score: packScore(.highCard, ranksDesc), category: .highCard, isRoyalFlush: false)
}

/// Precomputed index combinations choosing 5 from n, for n = 6 and n = 7.
private let combos6 = combinationIndices(n: 6, k: 5)
private let combos7 = combinationIndices(n: 7, k: 5)

/// Evaluate the best 5-card hand from 5, 6, or 7 cards.
public func evaluate(_ cards: [Card]) -> HandRank {
    switch cards.count {
    case 5:
        return evaluate5(cards)
    case 6, 7:
        let combos = cards.count == 6 ? combos6 : combos7
        var buffer = [Card](repeating: cards[0], count: 5)
        for i in 0..<5 { buffer[i] = cards[combos[0][i]] }
        var best = evaluate5(buffer)
        for combo in combos {
            for i in 0..<5 { buffer[i] = cards[combo[i]] }
            let rank = evaluate5(buffer)
            if rank.score > best.score { best = rank }
        }
        return best
    default:
        preconditionFailure("evaluate expects 5...7 cards, got \(cards.count)")
    }
}

/// All index combinations choosing `k` out of `n` (small n only).
func combinationIndices(n: Int, k: Int) -> [[Int]] {
    var result = [[Int]]()
    guard k <= n, k >= 0 else { return result }
    if k == 0 { return [[]] }
    var indices = Array(0..<k)
    while true {
        result.append(indices)
        var i = k - 1
        while i >= 0 && indices[i] == n - k + i { i -= 1 }
        if i < 0 { break }
        indices[i] += 1
        for j in (i + 1)..<k { indices[j] = indices[j - 1] + 1 }
    }
    return result
}

/// Enumerate combinations of `k` items from `items`, invoking `body` for each
/// without materialising the full list (suitable for millions of runouts).
func forEachCombination<T>(_ items: [T], choose k: Int, _ body: ([T]) -> Void) {
    let n = items.count
    if k == 0 { body([]); return }
    guard k <= n else { return }
    var indices = Array(0..<k)
    var combo = [T](repeating: items[0], count: k)
    while true {
        for i in 0..<k { combo[i] = items[indices[i]] }
        body(combo)
        var i = k - 1
        while i >= 0 && indices[i] == n - k + i { i -= 1 }
        if i < 0 { break }
        indices[i] += 1
        for j in (i + 1)..<k { indices[j] = indices[j - 1] + 1 }
    }
}
