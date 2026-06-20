import SwiftUI
import PokerEngine

/// "Comment j'améliore ma main" — relative decomposition with a shared win/tie/lose
/// colour code, a composition bar, and every number tappable to reveal an example board.
struct RelativeView: View {
    let analysis: RelativeAnalysis
    let playerIndex: Int
    @ObservedObject var vm: GameViewModel
    @State private var open: Set<String> = []

    private var winTotal: Double { RelSource.allCases.reduce(0) { $0 + analysis.prob[$1.rawValue][0] } }
    private var tieTotal: Double { RelSource.allCases.reduce(0) { $0 + analysis.prob[$1.rawValue][1] } }
    private var loseTotal: Double { RelSource.allCases.reduce(0) { $0 + analysis.prob[$1.rawValue][2] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            compositionBar
            group(.ownEdge, "Amélioration propre", "les cartes privatives font une vraie main au-dessus du tableau")
            group(.kicker, "Le kicker tranche", "même main que le tableau, seul le kicker bouge")
            group(.playsBoard, "Le tableau joue", "les cartes privatives n'ajoutent rien")
        }
        .padding(.top, 6)
    }

    // MARK: - Composition bar

    private var compositionBar: some View {
        let total = max(winTotal + tieTotal + loseTotal, 1e-9)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.win).frame(width: geo.size.width * winTotal / total)
                    Rectangle().fill(Theme.tie).frame(width: geo.size.width * tieTotal / total)
                    Rectangle().fill(Theme.lose).frame(width: geo.size.width * loseTotal / total)
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 14) {
                legend(Theme.win, "gagne", winTotal)
                legend(Theme.tie, "partage", tieTotal)
                legend(Theme.lose, "perd", loseTotal)
            }
            .font(.caption2)
        }
    }

    private func legend(_ c: Color, _ label: String, _ v: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            Text("\(label) \(percentString(v))").foregroundStyle(.secondary)
        }
    }

    // MARK: - Group

    @ViewBuilder private func group(_ source: RelSource, _ title: String, _ subtitle: String) -> some View {
        let w = analysis.prob[source.rawValue][0]
        let t = analysis.prob[source.rawValue][1]
        let l = analysis.prob[source.rawValue][2]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                triplet(w, t, l, clickable: false, source: source)
            }
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            rows(for: source)
        }
    }

    // MARK: - Rows

    @ViewBuilder private func rows(for source: RelSource) -> some View {
        switch source {
        case .ownEdge:
            ForEach(EdgeMechanism.allCases, id: \.self) { m in
                let v = analysis.edgeMechanism[m.rawValue]
                if v[0] + v[1] + v[2] > negligibleProbability {
                    row(.ownEdge, shortLabel(m),
                        [(v[0], Theme.win, .win, m, nil),
                         (v[1], Theme.tie, .tie, m, nil),
                         (v[2], Theme.lose, .lose, m, nil)])
                }
            }
        case .kicker:
            row(.kicker, "le kicker décide",
                [(analysis.prob[1][0], Theme.win, .win, nil, nil),
                 (analysis.prob[1][2], Theme.lose, .lose, nil, nil)])
            ForEach(ChopTexture.allCases, id: \.self) { tex in
                let v = analysis.kickerChopTexture[tex.rawValue]
                if v > negligibleProbability {
                    row(.kicker, "partage · \(tex.label)", [(v, Theme.tie, .tie, nil, tex)])
                }
            }
        case .playsBoard:
            row(.playsBoard, "issue",
                [(analysis.prob[2][0], Theme.win, .win, nil, nil),
                 (analysis.prob[2][1], Theme.tie, .tie, nil, nil),
                 (analysis.prob[2][2], Theme.lose, .lose, nil, nil)])
        }
    }

    private typealias Entry = (value: Double, color: Color, outcome: RelOutcome, mech: EdgeMechanism?, tex: ChopTexture?)

    @ViewBuilder private func row(_ source: RelSource, _ label: String, _ entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                ForEach(entries.indices, id: \.self) { i in
                    value(entries[i], source: source)
                }
            }
            ForEach(entries.indices, id: \.self) { i in
                let k = keyFor(entries[i], source: source)
                if open.contains(k) { examples(k) }
            }
        }
    }

    private func keyFor(_ e: Entry, source: RelSource) -> String {
        RelativeAnalysis.leafKey(source: source, outcome: e.outcome, mechanism: e.mech, texture: e.tex)
    }

    private func value(_ e: Entry, source: RelSource) -> some View {
        let k = keyFor(e, source: source)
        let hasEx = (analysis.examples[k]?.isEmpty == false) && e.value >= negligibleProbability
        return Text(e.value < negligibleProbability ? "·" : percentString(e.value))
            .font(.caption.monospacedDigit())
            .foregroundStyle(e.value < negligibleProbability ? Color.secondary : e.color)
            .overlay(alignment: .bottom) {
                if hasEx { Rectangle().fill(e.color.opacity(0.55)).frame(height: 1) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if hasEx { toggle(k) } }
    }

    private func toggle(_ k: String) {
        if open.contains(k) { open.remove(k) } else { open.insert(k) }
    }

    // MARK: - Examples

    @ViewBuilder private func examples(_ k: String) -> some View {
        let boards = analysis.examples[k] ?? []
        VStack(alignment: .leading, spacing: 7) {
            ForEach(boards.prefix(3).indices, id: \.self) { i in
                exampleRow(boards[i])
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 2)
    }

    @ViewBuilder private func exampleRow(_ board: [Card]) -> some View {
        let myHand = vm.playerCards[safe: playerIndex]?.compactMap { $0 } ?? []
        let oppIdx = opponentIndex(board: board)
        let oppHand = oppIdx.flatMap { vm.playerCards[safe: $0]?.compactMap { $0 } } ?? []
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(board.indices, id: \.self) { i in
                    CardFace(card: board[i], rankSize: 11, suitSize: 9).frame(width: 22, height: 30)
                }
            }
            if myHand.count == 2 { handLine("moi", bestFive(myHand + board)) }
            if oppHand.count == 2 { handLine("adv", bestFive(oppHand + board)) }
        }
    }

    private func handLine(_ who: String, _ five: [Card]) -> some View {
        HStack(spacing: 6) {
            Text(who).font(.caption2).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
            handLabel(five).font(.caption2)
            Text(evaluate(five).category.frenchName).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func opponentIndex(board: [Card]) -> Int? {
        var best = -1
        var bestScore = Int.min
        for q in vm.playerCards.indices where q != playerIndex {
            let h = vm.playerCards[q].compactMap { $0 }
            guard h.count == 2 else { continue }
            let s = evaluate(h + board).score
            if s > bestScore { bestScore = s; best = q }
        }
        return best >= 0 ? best : nil
    }

    private func triplet(_ w: Double, _ t: Double, _ l: Double, clickable: Bool, source: RelSource) -> some View {
        HStack(spacing: 4) {
            Text(w < negligibleProbability ? "·" : percentString(w)).foregroundStyle(Theme.win)
            Text("·").foregroundStyle(.secondary)
            Text(t < negligibleProbability ? "·" : percentString(t)).foregroundStyle(Theme.tie)
            Text("·").foregroundStyle(.secondary)
            Text(l < negligibleProbability ? "·" : percentString(l)).foregroundStyle(Theme.lose)
        }
        .font(.caption.monospacedDigit())
    }

    private func shortLabel(_ m: EdgeMechanism) -> String {
        switch m {
        case .unsharedCard: return "carte non partagée"
        case .sharedRank: return "rang partagé"
        case .draw: return "tirage (couleur/quinte)"
        }
    }
}
