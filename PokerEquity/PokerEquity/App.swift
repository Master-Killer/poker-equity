import SwiftUI
import PokerEngine

@main
struct PokerEquityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Theme

enum Theme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panel = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let cardFace = Color(white: 0.93)
    static let focus = Color(red: 0.86, green: 0.69, blue: 0.20)   // gold focus border
    static let accent = Color(red: 0.45, green: 0.58, blue: 0.96)  // equity blue
    static let win = Color(red: 0.32, green: 0.78, blue: 0.47)
}

extension Suit {
    var displayColor: Color {
        isRed ? Color(red: 0.84, green: 0.20, blue: 0.20) : .black
    }
}

extension HandCategory {
    /// French poker hand names for display.
    var frenchName: String {
        switch self {
        case .highCard: return "Carte haute"
        case .onePair: return "Une paire"
        case .twoPair: return "Deux paires"
        case .trips: return "Brelan"
        case .straight: return "Quinte"
        case .flush: return "Couleur"
        case .fullHouse: return "Full"
        case .quads: return "Carré"
        case .straightFlush: return "Quinte flush"
        }
    }
}

extension Suit {
    /// Suit colour legible on a dark background (black suits shown light grey).
    var onDarkColor: Color {
        isRed ? Color(red: 0.92, green: 0.36, blue: 0.36) : Color(white: 0.92)
    }
}

extension Card {
    /// "A♠", "T♥" — rank + suit symbol (no English letters).
    var symbolText: String { "\(rankLetter)\(suit.symbol)" }
}

/// A hand rendered as coloured rank+symbol tokens, e.g. A♠ A♥ (for dark panels).
func handLabel(_ cards: [Card]) -> Text {
    var text = Text("")
    for (i, card) in cards.enumerated() {
        if i > 0 { text = text + Text(" ") }
        text = text + Text(card.symbolText).foregroundColor(card.suit.onDarkColor)
    }
    return text
}

// MARK: - Selection slot

/// A position the focus can sit on. Hands are traversed before the board.
enum Slot: Hashable {
    case hole(player: Int, index: Int)
    case board(Int)
}

// MARK: - Small helpers

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

func percentString(_ x: Double) -> String {
    // French decimal separator (comma).
    String(format: "%.2f", x * 100).replacingOccurrences(of: ".", with: ",") + "%"
}
