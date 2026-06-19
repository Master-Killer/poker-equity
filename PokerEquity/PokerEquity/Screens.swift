import SwiftUI
import PokerEngine

struct ContentView: View {
    @StateObject private var vm = GameViewModel()
    @Environment(\.horizontalSizeClass) private var hSize

    /// iPad / Mac (Catalyst) get the roomier layout.
    private var isWide: Bool { hSize == .regular }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            CardPickerView(vm: vm)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { vm.recompute() }
    }

    private var header: some View {
        HStack {
            Text("Équité Poker")
                .font(.system(.headline, design: .monospaced))
            Spacer()
            if vm.isCalculating { ProgressView().controlSize(.small) }
            Button { vm.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 16) {
            if isWide {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    playerRows
                }
            } else {
                playerRows
            }

            if vm.playerCards.count < 9 {
                Button { vm.addPlayer() } label: {
                    Label("Main", systemImage: "plus").font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 8) {
                Text("TABLEAU")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                BoardRowView(vm: vm)
                    .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let outs = vm.outs {
                OutsView(outs: outs, vm: vm)
            }
        }
    }

    @ViewBuilder private var playerRows: some View {
        ForEach(vm.playerCards.indices, id: \.self) { i in
            PlayerRowView(vm: vm, index: i, defaultExpanded: isWide)
        }
    }
}

// MARK: - Player row

struct PlayerRowView: View {
    @ObservedObject var vm: GameViewModel
    let index: Int
    @State private var expanded: Bool

    init(vm: GameViewModel, index: Int, defaultExpanded: Bool) {
        _vm = ObservedObject(wrappedValue: vm)
        self.index = index
        _expanded = State(initialValue: defaultExpanded)
    }

    private var equity: PlayerEquity? { vm.equity?.players[safe: index] }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { i in
                    let slot = Slot.hole(player: index, index: i)
                    CardSlotView(card: vm.card(at: slot), isFocused: vm.focusedSlot == slot)
                        .frame(width: 48)
                        .onTapGesture { vm.focus(slot) }
                }
                Spacer()
                headline
                if vm.playerCards.count > 2 {
                    Button { vm.removePlayer(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if let equity {
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Masquer le détail" : "Détail de la victoire")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if expanded {
                    DecompositionView(equity: equity)
                    splitPartners
                }
            }
        }
        .padding(12)
        .background(Theme.panel.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var headline: some View {
        if let equity {
            VStack(alignment: .trailing, spacing: 0) {
                Text(percentString(equity.winProb))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                if equity.tieProb > 0.00005 {
                    Text("Partage \(percentString(equity.tieProb))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("—")
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// Pairwise split breakdown: who this player chops with (3+ player pots).
    @ViewBuilder private var splitPartners: some View {
        let partners = partnerList
        if !partners.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Partagé avec")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(partners, id: \.index) { partner in
                    HStack {
                        handLabel(partner.cards).font(.caption)
                        Spacer()
                        Text(percentString(partner.prob))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private struct Partner { let index: Int; let cards: [Card]; let prob: Double }

    private var partnerList: [Partner] {
        guard vm.playerCards.count > 2,
              let matrix = vm.equity?.coWinMatrix,
              matrix.indices.contains(index) else { return [] }
        var result: [Partner] = []
        for j in matrix[index].indices where j != index {
            let prob = matrix[index][j]
            guard prob > 0.00005 else { continue }
            let cards = vm.playerCards[safe: j]?.compactMap { $0 } ?? []
            result.append(Partner(index: j, cards: cards, prob: prob))
        }
        return result.sorted { $0.prob > $1.prob }
    }
}

// MARK: - Win / lose / tie decomposition

struct DecompositionView: View {
    let equity: PlayerEquity

    private var rows: [(HandCategory, CategoryBreakdown)] {
        HandCategory.allCases.reversed().compactMap { cat in
            equity.breakdown[cat].map { (cat, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Main").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gagne").frame(width: 64, alignment: .trailing)
                Text("Perd").frame(width: 64, alignment: .trailing)
                Text("Partage").frame(width: 64, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(rows, id: \.0) { cat, b in
                HStack {
                    Text(cat.frenchName).frame(maxWidth: .infinity, alignment: .leading)
                    cell(b.winProb, color: b.winProb > 0 ? Theme.win : .secondary)
                    cell(b.loseProb, color: .secondary)
                    cell(b.tieProb, color: .secondary)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.top, 4)
    }

    private func cell(_ value: Double, color: Color) -> some View {
        Text(value < 0.00005 ? "·" : percentString(value))
            .frame(width: 64, alignment: .trailing)
            .foregroundStyle(color)
    }
}

// MARK: - Board

struct BoardRowView: View {
    @ObservedObject var vm: GameViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                let slot = Slot.board(i)
                CardSlotView(card: vm.card(at: slot), isFocused: vm.focusedSlot == slot)
                    .onTapGesture { vm.focus(slot) }
            }
        }
    }
}

// MARK: - Outs (TV style)

struct OutsView: View {
    let outs: OutsResult
    @ObservedObject var vm: GameViewModel

    private var trailing: [PlayerOuts] {
        outs.players.filter { $0.isTrailing && (!$0.directOuts.isEmpty || !$0.runnerRunner.isEmpty) }
    }

    var body: some View {
        if !trailing.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("CARTES QUI AMÉLIORENT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(trailing, id: \.playerIndex) { po in
                    VStack(alignment: .leading, spacing: 6) {
                        (handLabel(handCards(po.playerIndex))
                         + Text(" — \(po.directOuts.count) cartes pour passer devant"))
                            .font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 4)], spacing: 4) {
                            ForEach(po.directOuts.indices, id: \.self) { idx in
                                CardFace(card: po.directOuts[idx].card, rankSize: 12, suitSize: 10)
                                    .frame(width: 30, height: 40)
                            }
                        }

                        ForEach(po.runnerRunner.indices, id: \.self) { idx in
                            let rr = po.runnerRunner[idx]
                            Text("Tirage en deux cartes — \(rr.category.frenchName) · \(percentString(rr.probability))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func handCards(_ index: Int) -> [Card] {
        vm.playerCards[safe: index]?.compactMap { $0 } ?? []
    }
}
