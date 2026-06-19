import SwiftUI
import PokerEngine

/// A filled card face (rank above suit), as in the picker and the slots.
struct CardFace: View {
    let card: Card
    var rankSize: CGFloat = 18
    var suitSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            Text(card.rankLetter)
                .font(.system(size: rankSize, weight: .bold, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: suitSize))
        }
        .foregroundStyle(card.suit.displayColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardFace)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A board or hole-card slot: shows a card or an empty placeholder, with a gold
/// border when it holds the focus.
struct CardSlotView: View {
    let card: Card?
    let isFocused: Bool

    var body: some View {
        ZStack {
            if let card {
                CardFace(card: card)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Theme.panel)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFocused ? Theme.focus : Color.white.opacity(0.15),
                              lineWidth: isFocused ? 2.5 : 1)
        )
        .aspectRatio(0.7, contentMode: .fit)
    }
}

/// One cell in the 52-card picker grid.
struct PickerCell: View {
    let card: Card
    let used: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(card.rankLetter)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(card.suit.symbol)
                    .font(.system(size: 11))
            }
            .foregroundStyle(used ? Theme.focus : card.suit.displayColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(used ? Theme.panel : Theme.cardFace)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(used ? Theme.focus : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The full 52-card picker pinned at the bottom: four suit rows × thirteen ranks.
/// Collapsible via the handle so it can free up vertical space.
struct CardPickerView: View {
    @ObservedObject var vm: GameViewModel
    private let ranks = [14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2]

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { vm.isPickerVisible.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.isPickerVisible ? "chevron.compact.down" : "chevron.compact.up")
                    Text(vm.isPickerVisible ? "Masquer les cartes" : "Choisir les cartes")
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }

            if vm.isPickerVisible {
                VStack(spacing: 3) {
                    ForEach(Suit.allCases, id: \.self) { suit in
                        HStack(spacing: 3) {
                            ForEach(ranks, id: \.self) { rank in
                                let card = Card(rank: rank, suit: suit)
                                PickerCell(card: card, used: vm.usedCards.contains(card)) {
                                    vm.tapPickerCard(card)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.background.shadow(.drop(color: .black.opacity(0.5), radius: 6, y: -2)))
    }
}
