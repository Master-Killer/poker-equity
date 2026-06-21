import XCTest
@testable import PokerEngine

/// THROWAWAY: dumps the relative analysis for AA vs Q9 (préflop) as JSON for the
/// HTML maquette (`docs/maquette-relative.html`). Mirrors the showdown model and
/// `RelativeSentence`. Delete once the maquette is no longer used for review.
final class MaquetteDump: XCTestCase {

    private let neg = 0.00005

    func testDumpAAvsQ9() throws {
        let hands = [Card.parse("As Ah"), Card.parse("Qs 9s")]
        let result = EquityCalculator.compute(hands: hands, board: [])

        var players = [PlayerJSON]()
        for p in hands.indices {
            let a = result.relative[p]
            players.append(PlayerJSON(
                hand: hands[p].map(card),
                win: a.winTotal, tie: a.tieTotal, lose: a.loseTotal,
                groups: groups(a, myHand: hands[p], oppHand: hands[1 - p])))
        }

        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        let data = try enc.encode(Payload(players: players))
        let path = "/Users/francoisdevemy/PycharmProjects/poker-equity/.claude/worktrees/elegant-shaw-34b197/docs/maquette-data.json"
        try data.write(to: URL(fileURLWithPath: path))
        print("WROTE \(data.count) bytes to \(path)")
    }

    // MARK: - Build

    private func groups(_ a: RelativeAnalysis, myHand: [Card], oppHand: [Card]) -> [GroupJSON] {
        // Je gagne — combination mechanisms (sorted) then the kicker win.
        var winLeaves = EdgeMechanism.allCases
            .filter { a.winCombination[$0.rawValue] > neg }
            .sorted { a.winCombination[$0.rawValue] > a.winCombination[$1.rawValue] }
            .map { leaf(label: shortLabel($0), value: a.winCombination[$0.rawValue],
                        key: RelativeAnalysis.winComboKey($0), color: "win",
                        mech: $0, a: a, myHand: myHand, oppHand: oppHand) }
        if a.winKicker > neg {
            winLeaves.append(leaf(label: "mon kicker l'emporte", value: a.winKicker,
                                  key: RelativeAnalysis.winKickerKey, color: "win",
                                  mech: nil, a: a, myHand: myHand, oppHand: oppHand))
        }

        // Partage — chop textures (sorted).
        let chopLeaves = ChopTexture.allCases
            .filter { a.chop[$0.rawValue] > neg }
            .sorted { a.chop[$0.rawValue] > a.chop[$1.rawValue] }
            .map { leaf(label: $0.label, value: a.chop[$0.rawValue],
                        key: RelativeAnalysis.chopKey($0), color: "tie",
                        mech: nil, a: a, myHand: myHand, oppHand: oppHand) }

        // Je perds — better opponent combination, then opponent kicker.
        var loseLeaves = [LeafJSON]()
        if a.loseCombination > neg {
            loseLeaves.append(leaf(label: "l'adversaire a une meilleure combinaison",
                                   value: a.loseCombination, key: RelativeAnalysis.loseComboKey,
                                   color: "lose", mech: nil, a: a, myHand: myHand, oppHand: oppHand))
        }
        if a.loseKicker > neg {
            loseLeaves.append(leaf(label: "le kicker de l'adversaire l'emporte",
                                   value: a.loseKicker, key: RelativeAnalysis.loseKickerKey,
                                   color: "lose", mech: nil, a: a, myHand: myHand, oppHand: oppHand))
        }

        return [
            GroupJSON(title: "Je gagne", total: a.winTotal, color: "win",
                      subtitle: "ma combinaison — ou mon kicker — l'emporte", leaves: winLeaves),
            GroupJSON(title: "Partage", total: a.tieTotal, color: "tie",
                      subtitle: "mains identiques, le tableau se partage", leaves: chopLeaves),
            GroupJSON(title: "Je perds", total: a.loseTotal, color: "lose",
                      subtitle: "l'adversaire a la meilleure main", leaves: loseLeaves),
        ]
    }

    private func leaf(label: String, value: Double, key: String, color: String,
                      mech: EdgeMechanism?, a: RelativeAnalysis,
                      myHand: [Card], oppHand: [Card]) -> LeafJSON {
        let exs = (a.examples[key] ?? []).map { ex -> ExampleJSON in
            ExampleJSON(
                board: ex.board.map(card),
                decisive: ex.decisive,
                share: ex.share, count: ex.count,
                sentence: sentence(mechanism: mech, ex: ex, myHand: myHand, oppHand: oppHand),
                me: SideJSON(five: bestFive(myHand + ex.board).map(card), cat: ex.myCategory.fr),
                opp: SideJSON(five: bestFive(oppHand + ex.board).map(card), cat: ex.oppCategory.fr))
        }
        return LeafJSON(label: label, value: value, color: color, examples: exs)
    }

    // MARK: - Sentence (mirrors RelativeSentence, rendering showdownVerdict)

    private func sentence(mechanism: EdgeMechanism?, ex: RelExample, myHand: [Card], oppHand: [Card]) -> String {
        let board = ex.board
        let myFive = bestFive(myHand + board), oppFive = bestFive(oppHand + board)
        let clause = showdownClause(myFive, oppFive)
        guard let m = mechanism else { return clause }
        let myCat = ex.myCategory.fr
        let comboCards = ex.decisive.map { board[$0] }
        let myRanks = Set(myHand.map { $0.rank })
        let decText = comboCards.filter { myRanks.contains($0.rank) }.map { $0.disp }.joined(separator: " ")
        let head: String
        switch m {
        case .unsharedCard: head = "\(decText) apparie ma carte → \(myCat)"
        case .sharedRank:   head = "\(decText) apparie le rang commun → \(myCat)"
        case .draw:
            if evaluate(board).category.rawValue < ex.myCategory.rawValue {
                if let s = comboCards.first?.suit, ex.myCategory == .flush || ex.myCategory == .straightFlush {
                    head = "tirage \(s.symbol) complété → \(myCat)"
                } else { head = "tirage quinte complété → \(myCat)" }
            } else { return clause }
        case .pocketPair: head = "paire servie → \(myCat)"
        }
        return "\(head) ; \(clause)"
    }

    private func showdownClause(_ myFive: [Card], _ oppFive: [Card]) -> String {
        let myCat = evaluate(myFive).category, oppCat = evaluate(oppFive).category
        switch showdownVerdict(myFive, oppFive) {
        case .chop:              return "l'adversaire fait jeu égal → partage"
        case .higherCategory:    return "l'adversaire en reste à \(withArticle(oppCat))"
        case .lowerCategory:     return "l'adversaire a \(withArticle(oppCat))"
        case .betterCombination: return "j'ai \(meilleur(myCat))"
        case .worseCombination:  return "l'adversaire a \(meilleur(myCat))"
        case .kickerWin:         return "même \(myCat.fr), mon kicker l'emporte"
        case .kickerLose:        return "même \(myCat.fr), le kicker de l'adversaire l'emporte"
        }
    }

    private func withArticle(_ c: HandCategory) -> String {
        switch c {
        case .highCard: return "une carte haute"; case .onePair: return "une paire"
        case .twoPair: return "deux paires"; case .trips: return "un brelan"
        case .straight: return "une quinte"; case .flush: return "une couleur"
        case .fullHouse: return "un full"; case .quads: return "un carré"
        case .straightFlush: return "une quinte flush"
        }
    }
    private func meilleur(_ c: HandCategory) -> String {
        switch c {
        case .highCard: return "une meilleure carte haute"; case .onePair: return "une meilleure paire"
        case .twoPair: return "de meilleures deux paires"; case .trips: return "un meilleur brelan"
        case .straight: return "une meilleure quinte"; case .flush: return "une meilleure couleur"
        case .fullHouse: return "un meilleur full"; case .quads: return "un meilleur carré"
        case .straightFlush: return "une meilleure quinte flush"
        }
    }

    private func card(_ c: Card) -> CardJSON { CardJSON(r: c.disp10, s: c.suit.symbol, red: c.suit.isRed) }
    private func shortLabel(_ m: EdgeMechanism) -> String {
        switch m {
        case .unsharedCard: return "carte non partagée"; case .sharedRank: return "rang partagé"
        case .draw: return "quinte/couleur"; case .pocketPair: return "paire servie"
        }
    }
}

// MARK: - JSON model

private struct Payload: Encodable { let players: [PlayerJSON] }
private struct PlayerJSON: Encodable { let hand: [CardJSON]; let win, tie, lose: Double; let groups: [GroupJSON] }
private struct GroupJSON: Encodable { let title: String; let total: Double; let color, subtitle: String; let leaves: [LeafJSON] }
private struct LeafJSON: Encodable { let label: String; let value: Double; let color: String; let examples: [ExampleJSON] }
private struct ExampleJSON: Encodable {
    let board: [CardJSON]; let decisive: [Int]; let share: Double; let count: Int
    let sentence: String; let me: SideJSON; let opp: SideJSON
}
private struct SideJSON: Encodable { let five: [CardJSON]; let cat: String }
private struct CardJSON: Encodable { let r, s: String; let red: Bool }

private extension Card {
    var disp10: String { rank == 10 ? "10" : rankLetter }
    var disp: String { "\(disp10)\(suit.symbol)" }
}
private extension HandCategory {
    var fr: String {
        switch self {
        case .highCard: return "carte haute"; case .onePair: return "une paire"
        case .twoPair: return "deux paires"; case .trips: return "brelan"
        case .straight: return "quinte"; case .flush: return "couleur"
        case .fullHouse: return "full"; case .quads: return "carré"
        case .straightFlush: return "quinte flush"
        }
    }
}
