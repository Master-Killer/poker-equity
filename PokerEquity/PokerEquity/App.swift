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
    String(format: "%.2f%%", x * 100)
}
