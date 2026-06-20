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

/// The evaluated strength of a poker hand.
///
/// `score` packs the category and up to five tiebreaker ranks into a single
/// integer so that a plain `<` comparison is a correct hand comparison.
public struct HandRank: Comparable, Sendable {
    public let score: Int
    public let category: HandCategory

    public static func < (lhs: HandRank, rhs: HandRank) -> Bool { lhs.score < rhs.score }
    public static func == (lhs: HandRank, rhs: HandRank) -> Bool { lhs.score == rhs.score }
}

// MARK: - Bit-twiddling helpers (allocation-free)

@inline(__always)
private func packScore(_ category: HandCategory,
                       _ k1: Int = 0, _ k2: Int = 0, _ k3: Int = 0,
                       _ k4: Int = 0, _ k5: Int = 0) -> Int {
    // category in bits 20+, then five 4-bit kicker ranks (rank ≤ 14 < 16).
    (category.rawValue << 20) | (k1 << 16) | (k2 << 12) | (k3 << 8) | (k4 << 4) | k5
}

/// Build a score from the `take` highest ranks present in a 15-bit rank mask.
@inline(__always)
private func scoreFromMask(_ category: HandCategory, _ mask: Int, take: Int) -> Int {
    var score = category.rawValue << 20
    var shift = 16
    var taken = 0
    var rank = 14
    while rank >= 2 && taken < take {
        if mask & (1 << rank) != 0 {
            score |= (rank << shift)
            shift -= 4
            taken += 1
        }
        rank -= 1
    }
    return score
}

/// Highest straight in a 15-bit rank mask, or 0. Handles the A-2-3-4-5 wheel.
@inline(__always)
private func straightHigh(_ mask: Int) -> Int {
    var m = mask
    if m & (1 << 14) != 0 { m |= (1 << 1) } // ace plays low for the wheel
    var high = 14
    while high >= 5 {
        let window = (1 << high) | (1 << (high - 1)) | (1 << (high - 2)) | (1 << (high - 3)) | (1 << (high - 4))
        if m & window == window { return high }
        high -= 1
    }
    return 0
}

/// Highest rank present in `mask` at or below `from`, skipping excluded ranks.
@inline(__always)
private func highestRank(_ mask: Int, from: Int, exclude1: Int = 0, exclude2: Int = 0) -> Int {
    var rank = from
    while rank >= 2 {
        if rank != exclude1 && rank != exclude2 && (mask & (1 << rank)) != 0 { return rank }
        rank -= 1
    }
    return 0
}

// MARK: - Evaluator

/// Evaluate the best 5-card poker hand from 5, 6, or 7 cards.
///
/// Allocation-free: works entirely from four per-suit 13-bit rank masks, so it
/// is fast enough to enumerate millions of runouts even in a debug build.
public func evaluate(_ cards: [Card]) -> HandRank {
    precondition(cards.count >= 5 && cards.count <= 7, "evaluate expects 5...7 cards")

    var suitMask0 = 0, suitMask1 = 0, suitMask2 = 0, suitMask3 = 0
    var suitCount0 = 0, suitCount1 = 0, suitCount2 = 0, suitCount3 = 0
    for card in cards {
        let bit = 1 << card.rank
        switch card.suit.rawValue {
        case 0: suitMask0 |= bit; suitCount0 += 1
        case 1: suitMask1 |= bit; suitCount1 += 1
        case 2: suitMask2 |= bit; suitCount2 += 1
        default: suitMask3 |= bit; suitCount3 += 1
        }
    }
    let rankMask = suitMask0 | suitMask1 | suitMask2 | suitMask3

    // Flush suit (five or more of one suit), if any.
    var flushMask = 0
    if suitCount0 >= 5 { flushMask = suitMask0 }
    else if suitCount1 >= 5 { flushMask = suitMask1 }
    else if suitCount2 >= 5 { flushMask = suitMask2 }
    else if suitCount3 >= 5 { flushMask = suitMask3 }

    if flushMask != 0 {
        let sfHigh = straightHigh(flushMask)
        if sfHigh != 0 {
            return HandRank(score: packScore(.straightFlush, sfHigh),
                            category: .straightFlush)
        }
    }

    // Rank multiplicities, high to low. count(rank) = number of suits holding it.
    var quad = 0, trip = 0, trip2 = 0, pair1 = 0, pair2 = 0
    var rank = 14
    while rank >= 2 {
        let bit = 1 << rank
        let count = ((suitMask0 & bit) != 0 ? 1 : 0)
                  + ((suitMask1 & bit) != 0 ? 1 : 0)
                  + ((suitMask2 & bit) != 0 ? 1 : 0)
                  + ((suitMask3 & bit) != 0 ? 1 : 0)
        switch count {
        case 4: if quad == 0 { quad = rank }
        case 3: if trip == 0 { trip = rank } else if trip2 == 0 { trip2 = rank }
        case 2: if pair1 == 0 { pair1 = rank } else if pair2 == 0 { pair2 = rank }
        default: break
        }
        rank -= 1
    }

    if quad != 0 {
        return HandRank(score: packScore(.quads, quad, highestRank(rankMask, from: 14, exclude1: quad)),
                        category: .quads)
    }
    if trip != 0 && (pair1 != 0 || trip2 != 0) {
        let pairRank = max(pair1, trip2) // a second trip can fill the pair slot
        return HandRank(score: packScore(.fullHouse, trip, pairRank),
                        category: .fullHouse)
    }
    if flushMask != 0 {
        return HandRank(score: scoreFromMask(.flush, flushMask, take: 5),
                        category: .flush)
    }
    let sHigh = straightHigh(rankMask)
    if sHigh != 0 {
        return HandRank(score: packScore(.straight, sHigh), category: .straight)
    }
    if trip != 0 {
        let k1 = highestRank(rankMask, from: 14, exclude1: trip)
        let k2 = highestRank(rankMask, from: k1 - 1, exclude1: trip)
        return HandRank(score: packScore(.trips, trip, k1, k2), category: .trips)
    }
    if pair1 != 0 && pair2 != 0 {
        let kicker = highestRank(rankMask, from: 14, exclude1: pair1, exclude2: pair2)
        return HandRank(score: packScore(.twoPair, pair1, pair2, kicker), category: .twoPair)
    }
    if pair1 != 0 {
        let k1 = highestRank(rankMask, from: 14, exclude1: pair1)
        let k2 = highestRank(rankMask, from: k1 - 1, exclude1: pair1)
        let k3 = highestRank(rankMask, from: k2 - 1, exclude1: pair1)
        return HandRank(score: packScore(.onePair, pair1, k1, k2, k3), category: .onePair)
    }
    return HandRank(score: scoreFromMask(.highCard, rankMask, take: 5),
                    category: .highCard)
}

/// Convenience for callers (and tests) that pass exactly five cards.
public func evaluate5(_ cards: [Card]) -> HandRank {
    precondition(cards.count == 5, "evaluate5 expects 5 cards")
    return evaluate(cards)
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

/// All index combinations choosing `k` of `n` (small n; used for display only).
func combinationIndices(n: Int, k: Int) -> [[Int]] {
    var result = [[Int]]()
    guard k >= 0, k <= n else { return result }
    if k == 0 { return [[]] }
    var idx = Array(0..<k)
    while true {
        result.append(idx)
        var i = k - 1
        while i >= 0 && idx[i] == n - k + i { i -= 1 }
        if i < 0 { break }
        idx[i] += 1
        for j in (i + 1)..<k { idx[j] = idx[j - 1] + 1 }
    }
    return result
}

/// The actual 5 cards forming the best hand from 5...7 cards (for illustration).
public func bestFive(_ cards: [Card]) -> [Card] {
    precondition(cards.count >= 5 && cards.count <= 7)
    if cards.count == 5 { return cards }
    var bestScore = Int.min
    var bestCards = Array(cards.prefix(5))
    for combo in combinationIndices(n: cards.count, k: 5) {
        var five = [Card]()
        five.reserveCapacity(5)
        for i in combo { five.append(cards[i]) }
        let s = evaluate5(five).score
        if s > bestScore { bestScore = s; bestCards = five }
    }
    return bestCards
}

/// Showdown standing from each player's packed score: the best score, how many
/// players share it, and the sole leader's index (-1 when the lead is tied).
func standing(_ scores: [Int]) -> (best: Int, winnerCount: Int, soleLeader: Int) {
    var best = Int.min
    for s in scores where s > best { best = s }
    var winnerCount = 0
    var soleLeader = -1
    for (i, s) in scores.enumerated() where s == best { winnerCount += 1; soleLeader = i }
    return (best, winnerCount, winnerCount == 1 ? soleLeader : -1)
}

/// Number of combinations C(n, k). Safe for the small n, k used here.
func combinationCount(_ n: Int, _ k: Int) -> Int {
    guard k >= 0, k <= n else { return 0 }
    if k == 0 { return 1 }
    var result = 1
    for i in 0..<k {
        result = result * (n - i) / (i + 1)
    }
    return result
}
