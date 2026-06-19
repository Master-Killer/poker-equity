import Foundation

/// The four suits, ordered as displayed in the picker grid (♠ ♥ ♣ ♦).
public enum Suit: Int, CaseIterable, Sendable {
    case spades = 0
    case hearts = 1
    case clubs = 2
    case diamonds = 3

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .clubs: return "♣"
        case .diamonds: return "♦"
        }
    }

    public var letter: Character {
        switch self {
        case .spades: return "s"
        case .hearts: return "h"
        case .clubs: return "c"
        case .diamonds: return "d"
        }
    }

    public var isRed: Bool { self == .hearts || self == .diamonds }
}

/// A playing card. `rank` is 2...14 where 11=J, 12=Q, 13=K, 14=A.
public struct Card: Hashable, Sendable, CustomStringConvertible {
    public let rank: Int
    public let suit: Suit

    public init(rank: Int, suit: Suit) {
        precondition((2...14).contains(rank), "rank \(rank) out of range 2...14")
        self.rank = rank
        self.suit = suit
    }

    /// Stable 0...51 index, useful for bitsets and deck math.
    public var index: Int { (rank - 2) * 4 + suit.rawValue }

    public var rankLetter: String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        case 10: return "T"
        default: return String(rank)
        }
    }

    public var description: String { "\(rankLetter)\(suit.letter)" }

    /// The complete 52-card deck.
    public static let fullDeck: [Card] = {
        var deck = [Card]()
        deck.reserveCapacity(52)
        for rank in 2...14 {
            for suit in Suit.allCases {
                deck.append(Card(rank: rank, suit: suit))
            }
        }
        return deck
    }()
}

extension Card {
    /// Parse a two-character notation such as "Ks", "Th", "2c", "Ad".
    public init?(_ text: String) {
        guard text.count == 2 else { return nil }
        let chars = Array(text)

        let parsedRank: Int
        switch chars[0] {
        case "A", "a": parsedRank = 14
        case "K", "k": parsedRank = 13
        case "Q", "q": parsedRank = 12
        case "J", "j": parsedRank = 11
        case "T", "t": parsedRank = 10
        default:
            guard let digit = chars[0].wholeNumberValue, (2...9).contains(digit) else { return nil }
            parsedRank = digit
        }

        let parsedSuit: Suit
        switch chars[1] {
        case "s", "S": parsedSuit = .spades
        case "h", "H": parsedSuit = .hearts
        case "c", "C": parsedSuit = .clubs
        case "d", "D": parsedSuit = .diamonds
        default: return nil
        }

        self.init(rank: parsedRank, suit: parsedSuit)
    }

    /// Parse a whitespace-separated list of cards, e.g. "Ks Qs" or "Js 6s 2c".
    public static func parse(_ text: String) -> [Card] {
        text.split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Card(String($0)) }
    }
}
