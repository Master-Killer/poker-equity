import SwiftUI
import PokerEngine

struct ContentView: View {
    @StateObject private var vm = GameViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(vm.playerCards.indices, id: \.self) { i in
                        PlayerRowView(vm: vm, index: i)
                    }

                    if vm.playerCards.count < 9 {
                        Button { vm.addPlayer() } label: {
                            Label("Main", systemImage: "plus")
                                .font(.subheadline)
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
                    }

                    if let outs = vm.outs {
                        OutsView(outs: outs, vm: vm)
                    }
                }
                .padding()
            }
            CardPickerView(vm: vm)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { vm.recompute() }
    }

    private var header: some View {
        HStack {
            Text("Poker Equity")
                .font(.system(.headline, design: .monospaced))
            Spacer()
            if vm.isCalculating {
                ProgressView().controlSize(.small)
            }
            Button { vm.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Player row

struct PlayerRowView: View {
    @ObservedObject var vm: GameViewModel
    let index: Int
    @State private var expanded = false

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

                if let equity {
                    Text(percentString(equity.equity))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

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
                        Text(expanded ? "Masquer le détail" : "Détail des \(percentString(equity.equity))")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if expanded {
                    DecompositionView(equity: equity)
                }
            }
        }
        .padding(12)
        .background(Theme.panel.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Text("Catégorie").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gagne").frame(width: 56, alignment: .trailing)
                Text("Perd").frame(width: 56, alignment: .trailing)
                Text("Égalité").frame(width: 56, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(rows, id: \.0) { cat, b in
                HStack {
                    Text(cat.label).frame(maxWidth: .infinity, alignment: .leading)
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
        Text(value < 0.0005 ? "·" : percentString(value))
            .frame(width: 56, alignment: .trailing)
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
                Text("OUTS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(trailing, id: \.playerIndex) { po in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(handName(po.playerIndex)) — \(po.directOuts.count) outs directs")
                            .font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 4)], spacing: 4) {
                            ForEach(po.directOuts.indices, id: \.self) { idx in
                                CardFace(card: po.directOuts[idx].card, rankSize: 12, suitSize: 10)
                                    .frame(width: 30, height: 40)
                            }
                        }

                        ForEach(po.runnerRunner.indices, id: \.self) { idx in
                            let rr = po.runnerRunner[idx]
                            Text("Runner-runner \(rr.category.label) · \(percentString(rr.probability))")
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

    private func handName(_ index: Int) -> String {
        let cards = vm.playerCards[safe: index]?.compactMap { $0 } ?? []
        return cards.map { $0.description }.joined(separator: " ")
    }
}
