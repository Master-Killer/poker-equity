import SwiftUI
import PokerEngine

/// "Comment j'améliore ma main" — the showdown against the best opponent, decomposed
/// into why I win / chop / lose, with a shared colour code, a composition bar, and
/// every number tappable to reveal varied example boards.
struct RelativeView: View {
    let analysis: RelativeAnalysis
    let playerIndex: Int
    @ObservedObject var vm: GameViewModel
    @State private var open: Set<String> = []

    /// One tappable reason line: a label, its probability, the examples key, the
    /// outcome colour, and (for a win-by-combination) the mechanism that built it.
    private struct Leaf: Identifiable {
        let label: String
        let value: Double
        let key: String
        let color: Color
        let mechanism: EdgeMechanism?
        var id: String { key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            compositionBar
            group("Je gagne", analysis.winTotal, Theme.win,
                  "ma combinaison — ou mon kicker — l'emporte", winLeaves)
            group("Partage", analysis.tieTotal, Theme.tie,
                  "mains identiques, le tableau se partage", chopLeaves)
            group("Je perds", analysis.loseTotal, Theme.lose,
                  "l'adversaire a la meilleure main", loseLeaves)
        }
        .padding(.top, 6)
    }

    // MARK: - Leaves

    private var winLeaves: [Leaf] {
        var leaves = EdgeMechanism.allCases
            .filter { analysis.winCombination[$0.rawValue] > negligibleProbability }
            .sorted { analysis.winCombination[$0.rawValue] > analysis.winCombination[$1.rawValue] }
            .map { Leaf(label: shortLabel($0), value: analysis.winCombination[$0.rawValue],
                        key: RelativeAnalysis.winComboKey($0), color: Theme.win, mechanism: $0) }
        if analysis.winKicker > negligibleProbability {
            leaves.append(Leaf(label: "mon kicker l'emporte", value: analysis.winKicker,
                               key: RelativeAnalysis.winKickerKey, color: Theme.win, mechanism: nil))
        }
        return leaves
    }

    private var chopLeaves: [Leaf] {
        ChopTexture.allCases
            .filter { analysis.chop[$0.rawValue] > negligibleProbability }
            .sorted { analysis.chop[$0.rawValue] > analysis.chop[$1.rawValue] }
            .map { Leaf(label: $0.label, value: analysis.chop[$0.rawValue],
                        key: RelativeAnalysis.chopKey($0), color: Theme.tie, mechanism: nil) }
    }

    private var loseLeaves: [Leaf] {
        var leaves: [Leaf] = []
        if analysis.loseCombination > negligibleProbability {
            leaves.append(Leaf(label: "l'adversaire a une meilleure combinaison",
                               value: analysis.loseCombination,
                               key: RelativeAnalysis.loseComboKey, color: Theme.lose, mechanism: nil))
        }
        if analysis.loseKicker > negligibleProbability {
            leaves.append(Leaf(label: "le kicker de l'adversaire l'emporte",
                               value: analysis.loseKicker,
                               key: RelativeAnalysis.loseKickerKey, color: Theme.lose, mechanism: nil))
        }
        return leaves
    }

    // MARK: - Composition bar

    private var compositionBar: some View {
        let win = analysis.winTotal, tie = analysis.tieTotal, lose = analysis.loseTotal
        let total = max(win + tie + lose, 1e-9)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.win).frame(width: geo.size.width * win / total)
                    Rectangle().fill(Theme.tie).frame(width: geo.size.width * tie / total)
                    Rectangle().fill(Theme.lose).frame(width: geo.size.width * lose / total)
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 14) {
                legend(Theme.win, "gagne", win)
                legend(Theme.tie, "partage", tie)
                legend(Theme.lose, "perd", lose)
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

    // MARK: - Group / rows

    @ViewBuilder private func group(_ title: String, _ total: Double, _ color: Color,
                                    _ subtitle: String, _ leaves: [Leaf]) -> some View {
        if total > negligibleProbability {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(percentString(total))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(color)
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                ForEach(leaves) { row($0) }
            }
        }
    }

    @ViewBuilder private func row(_ leaf: Leaf) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(leaf.label).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                value(leaf)
            }
            if open.contains(leaf.key) { examples(leaf) }
        }
    }

    private func value(_ leaf: Leaf) -> some View {
        let hasEx = (analysis.examples[leaf.key]?.isEmpty == false) && leaf.value >= negligibleProbability
        return Text(leaf.value < negligibleProbability ? "·" : percentString(leaf.value))
            .font(.caption.monospacedDigit())
            .foregroundStyle(leaf.value < negligibleProbability ? Color.secondary : leaf.color)
            .overlay(alignment: .bottom) {
                if hasEx { Rectangle().fill(leaf.color.opacity(0.55)).frame(height: 1) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if hasEx { toggle(leaf.key) } }
    }

    private func toggle(_ k: String) {
        if open.contains(k) { open.remove(k) } else { open.insert(k) }
    }

    // MARK: - Examples

    @ViewBuilder private func examples(_ leaf: Leaf) -> some View {
        let exs = analysis.examples[leaf.key] ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(exs.prefix(3).indices, id: \.self) { i in
                exampleRow(exs[i], color: leaf.color, mech: leaf.mechanism)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.exampleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 2)
    }

    @ViewBuilder private func exampleRow(_ ex: RelExample, color: Color, mech: EdgeMechanism?) -> some View {
        let myHand = vm.playerCards[safe: playerIndex]?.compactMap { $0 } ?? []
        let oppIdx = opponentIndex(board: ex.board)
        let oppHand = oppIdx.flatMap { vm.playerCards[safe: $0]?.compactMap { $0 } } ?? []
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(ex.board.indices, id: \.self) { i in
                        CardFace(card: ex.board[i], rankSize: 11, suitSize: 9,
                                 highlight: ex.decisive.contains(i) ? color : nil)
                            .frame(width: 22, height: 30)
                    }
                }
                if myHand.count == 2 { handLine("moi", bestFive(myHand + ex.board)) }
                if oppHand.count == 2 { handLine("adv", bestFive(oppHand + ex.board)) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(shareText(ex))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                Text(RelativeSentence.text(mechanism: mech, example: ex, myHand: myHand, oppHand: oppHand))
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Absolute share of all runouts (2 decimals), or the raw combo count when it
    /// would round to zero — never a misleading "0,00 %".
    private func shareText(_ ex: RelExample) -> String {
        ex.share < negligibleProbability ? "\(ex.count) combo\(ex.count > 1 ? "s" : "")"
                                         : percentString(ex.share)
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

    private func shortLabel(_ m: EdgeMechanism) -> String {
        switch m {
        case .unsharedCard: return "carte non partagée"
        case .sharedRank: return "rang partagé"
        case .draw: return "quinte/couleur"
        case .pocketPair: return "paire servie"
        }
    }
}
