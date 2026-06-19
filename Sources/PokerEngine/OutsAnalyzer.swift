import Foundation

/// A single card that, if it lands on the next street, gives a trailing player
/// the lead — grouped for display by the hand it completes.
public struct DirectOut: Sendable {
    public let card: Card
    public let resultingCategory: HandCategory
}

/// A runner-runner draw: wins that need *both* remaining cards (no single card
/// gives the lead), grouped by the final category reached.
public struct RunnerRunner: Sendable {
    public let category: HandCategory
    public let combos: Int       // number of two-card runouts
    public let probability: Double // fraction of all runouts
}

public struct PlayerOuts: Sendable {
    public let playerIndex: Int
    public let isTrailing: Bool
    /// Cards that take the lead on the next card.
    public let directOuts: [DirectOut]
    /// Backdoor draws (only populated on the flop, two cards to come).
    public let runnerRunner: [RunnerRunner]
}

public struct OutsResult: Sendable {
    /// Index of the current sole leader, or -1 if the lead is currently tied.
    public let currentLeader: Int
    public let players: [PlayerOuts]
}

public enum OutsAnalyzer {

    /// Analyse who is behind on the current board and which cards rescue them.
    ///
    /// Defined for a post-flop board (3 or 4 community cards). Direct outs are
    /// next-card cards that hand a trailing player the lead; runner-runner draws
    /// (flop only) are wins requiring both remaining cards.
    public static func analyze(hands: [[Card]], board: [Card]) -> OutsResult {
        precondition(board.count == 3 || board.count == 4, "outs are defined on the flop or turn")
        let playerCount = hands.count

        let known = Set(hands.flatMap { $0 } + board)
        let remaining = Card.fullDeck.filter { !known.contains($0) }

        // Current standing on the existing board.
        let currentRanks = hands.map { evaluate($0 + board) }
        let currentBest = currentRanks.map { $0.score }.max()!
        let currentWinners = (0..<playerCount).filter { currentRanks[$0].score == currentBest }
        let currentLeader = currentWinners.count == 1 ? currentWinners[0] : -1

        var perPlayer = [PlayerOuts]()
        perPlayer.reserveCapacity(playerCount)

        for p in 0..<playerCount {
            let trailing = !(currentLeader == p)

            // Direct outs: a single next card that makes p the sole leader.
            var directOuts = [DirectOut]()
            var giveLead = [Bool](repeating: false, count: 52) // by card index
            for c in remaining {
                let nextBoard = board + [c]
                var best = Int.min
                var bestPlayer = -1
                var tie = false
                for q in 0..<playerCount {
                    let s = evaluate(hands[q] + nextBoard).score
                    if s > best { best = s; bestPlayer = q; tie = false }
                    else if s == best { tie = true }
                }
                if !tie && bestPlayer == p {
                    let cat = evaluate(hands[p] + nextBoard).category
                    directOuts.append(DirectOut(card: c, resultingCategory: cat))
                    giveLead[c.index] = true
                }
            }

            // Runner-runner: only meaningful with two cards to come.
            var runnerRunner = [RunnerRunner]()
            if board.count == 3 && trailing {
                var rrCounts = [Int](repeating: 0, count: HandCategory.allCases.count)
                var totalPairs = 0
                forEachCombination(remaining, choose: 2) { pair in
                    totalPairs += 1
                    let finalBoard = board + pair
                    var best = Int.min
                    var winnerCount = 0
                    var pScore = 0
                    var pCategory = HandCategory.highCard
                    var ranksScore = [Int](repeating: 0, count: playerCount)
                    for q in 0..<playerCount {
                        let r = evaluate(hands[q] + finalBoard)
                        ranksScore[q] = r.score
                        if q == p { pScore = r.score; pCategory = r.category }
                        if r.score > best { best = r.score }
                    }
                    for q in 0..<playerCount where ranksScore[q] == best { winnerCount += 1 }
                    let pWinsAlone = (pScore == best && winnerCount == 1)
                    guard pWinsAlone else { return }
                    // Runner-runner only if neither single card already gives the lead.
                    if giveLead[pair[0].index] || giveLead[pair[1].index] { return }
                    rrCounts[pCategory.rawValue] += 1
                }
                let denom = Double(max(totalPairs, 1))
                for cat in HandCategory.allCases where rrCounts[cat.rawValue] > 0 {
                    runnerRunner.append(RunnerRunner(category: cat,
                                                     combos: rrCounts[cat.rawValue],
                                                     probability: Double(rrCounts[cat.rawValue]) / denom))
                }
            }

            perPlayer.append(PlayerOuts(playerIndex: p,
                                        isTrailing: trailing,
                                        directOuts: directOuts,
                                        runnerRunner: runnerRunner))
        }

        return OutsResult(currentLeader: currentLeader, players: perPlayer)
    }
}
