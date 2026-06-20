import SwiftUI
import UIKit
import PokerEngine

@main
struct PokerEquityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Pas de schéma forcé : on suit le mode clair/sombre du système.
        }
    }
}

// MARK: - Theme

extension Color {
    /// Couleur qui s'adapte au mode clair/sombre du système.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Theme {
    static let background = Color.adaptive(light: Color(white: 0.93),
                                           dark: Color(red: 0.07, green: 0.07, blue: 0.08))
    /// Surface des « cartes » de joueurs / blocs (fond plein).
    static let surface = Color.adaptive(light: .white,
                                        dark: Color(red: 0.13, green: 0.14, blue: 0.16))
    /// Emplacements vides + case utilisée du picker.
    static let panel = Color.adaptive(light: Color(white: 0.88),
                                      dark: Color(red: 0.16, green: 0.17, blue: 0.20))
    /// Face de carte (toujours blanc cassé, dans les deux modes).
    static let cardFace = Color(white: 0.96)
    /// Filet de contour de la face de carte (la carte étant blanche, un filet
    /// sombre la détache du fond — indispensable en mode clair).
    static let cardBorder = Color.black.opacity(0.18)
    static let focus = Color(red: 0.86, green: 0.69, blue: 0.20)   // gold focus border
    static let accent = Color.adaptive(light: Color(red: 0.23, green: 0.40, blue: 0.86),
                                       dark: Color(red: 0.45, green: 0.58, blue: 0.96))  // equity blue
    // Shared win / tie / lose colour code (triplets + composition bar).
    static let win = Color.adaptive(light: Color(red: 0.18, green: 0.60, blue: 0.34),
                                    dark: Color(red: 0.30, green: 0.74, blue: 0.45))
    static let tie = Color.adaptive(light: Color(red: 0.33, green: 0.38, blue: 0.74),
                                    dark: Color(red: 0.45, green: 0.49, blue: 0.80))
    static let lose = Color.adaptive(light: Color(red: 0.74, green: 0.24, blue: 0.24),
                                     dark: Color(red: 0.82, green: 0.34, blue: 0.34))
    /// Filets / séparateurs discrets (sombre sur clair, clair sur sombre).
    static let hairline = Color.adaptive(light: Color.black.opacity(0.12),
                                         dark: Color.white.opacity(0.12))
    /// Fond des encarts d'exemples.
    static let exampleBackground = Color.adaptive(light: Color.black.opacity(0.05),
                                                  dark: Color.black.opacity(0.28))
    /// Piste et segment sélectionné de la bascule de mode.
    static let segmentTrack = Color.adaptive(light: Color.black.opacity(0.05),
                                             dark: Color.black.opacity(0.30))
    static let segmentSelected = Color.adaptive(light: .white,
                                                dark: Color(white: 0.27))
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
    /// Couleur de l'enseigne sur une surface (panel/exemple), lisible dans les
    /// deux modes : les enseignes noires suivent le contraste du système.
    var onDarkColor: Color {
        isRed
            ? Color.adaptive(light: Color(red: 0.80, green: 0.18, blue: 0.18),
                             dark: Color(red: 0.92, green: 0.36, blue: 0.36))
            : Color.adaptive(light: Color(white: 0.13), dark: Color(white: 0.92))
    }
}

extension Card {
    /// Rang pour l'affichage : « 10 » plutôt que « T » (le moteur garde « T »).
    var rankLabel: String { rank == 10 ? "10" : rankLetter }

    /// "A♠", "10♥" — rang + symbole d'enseigne (sans lettres anglaises).
    var symbolText: String { "\(rankLabel)\(suit.symbol)" }
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

/// Below this probability a value is shown as a dot ("·") rather than a number.
let negligibleProbability = 0.00005

func percentString(_ x: Double) -> String {
    // French decimal separator (comma).
    String(format: "%.2f", x * 100).replacingOccurrences(of: ".", with: ",") + "%"
}
