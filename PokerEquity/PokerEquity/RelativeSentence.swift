import PokerEngine

/// Builds the one-line synthesis shown to the right of each example board.
///
/// It states the showdown honestly per the project's strict kicker definition:
/// "kicker" is used ONLY when both sides hold the exact same combination and a
/// side card decides. A made hand (full / quinte / couleur) never has a kicker —
/// a higher one wins as "une meilleure couleur", etc. Neutral French, no tutoiement.
enum RelativeSentence {

    /// `mechanism` is non-nil only for a win-by-combination leaf — it adds a head
    /// describing how my hole built that combination. Every other leaf is just the
    /// showdown clause (kicker duel, opponent's better combination, chop).
    static func text(mechanism: EdgeMechanism?, example ex: RelExample,
                     myHand: [Card], oppHand: [Card]) -> String {
        let board = ex.board
        let myFive = myHand.count == 2 ? bestFive(myHand + board) : board
        let oppFive = oppHand.count == 2 ? bestFive(oppHand + board) : board
        let clause = showdownClause(myFive, oppFive)
        guard let m = mechanism else { return clause }

        let myCat = fr(ex.myCategory)
        // `decisive` is my whole combination on the board; the head names only the
        // card(s) my hole actually paired.
        let comboCards = ex.decisive.map { board[$0] }
        let myRanks = Set(myHand.map { $0.rank })
        let decText = comboCards.filter { myRanks.contains($0.rank) }
            .map { $0.symbolText }.joined(separator: " ")
        let head: String
        switch m {
        case .unsharedCard: head = "\(decText) apparie ma carte → \(myCat)"
        case .sharedRank:   head = "\(decText) apparie le rang commun → \(myCat)"
        case .draw:
            if evaluate(board).category.rawValue < ex.myCategory.rawValue {
                // I completed a straight/flush the board did not have.
                if let s = comboCards.first?.suit, ex.myCategory == .flush || ex.myCategory == .straightFlush {
                    head = "tirage \(s.symbol) complété → \(myCat)"
                } else {
                    head = "tirage quinte complété → \(myCat)"
                }
            } else {
                return clause   // board already had it; the clause says mine is higher
            }
        case .pocketPair: head = "paire servie → \(myCat)"
        }
        return "\(head) ; \(clause)"
    }

    // MARK: - Showdown

    private static func showdownClause(_ myFive: [Card], _ oppFive: [Card]) -> String {
        let myCat = evaluate(myFive).category
        let oppCat = evaluate(oppFive).category
        switch showdownVerdict(myFive, oppFive) {
        case .chop:              return "l'adversaire fait jeu égal → partage"
        case .higherCategory:    return "l'adversaire en reste à \(withArticle(oppCat))"
        case .lowerCategory:     return "l'adversaire a \(withArticle(oppCat))"
        case .betterCombination: return "j'ai \(meilleur(myCat))"
        case .worseCombination:  return "l'adversaire a \(meilleur(myCat))"
        case .kickerWin:         return "même \(fr(myCat)), mon kicker l'emporte"
        case .kickerLose:        return "même \(fr(myCat)), le kicker de l'adversaire l'emporte"
        }
    }

    // MARK: - French

    private static func fr(_ cat: HandCategory) -> String { cat.frenchName.lowercased() }

    /// "un full", "une couleur", "deux paires" — indefinite article + name.
    private static func withArticle(_ cat: HandCategory) -> String {
        switch cat {
        case .highCard: return "une carte haute"
        case .onePair: return "une paire"
        case .twoPair: return "deux paires"
        case .trips: return "un brelan"
        case .straight: return "une quinte"
        case .flush: return "une couleur"
        case .fullHouse: return "un full"
        case .quads: return "un carré"
        case .straightFlush: return "une quinte flush"
        }
    }

    /// "un meilleur full", "de meilleures deux paires", "une meilleure couleur" —
    /// with correct gender/number agreement.
    private static func meilleur(_ cat: HandCategory) -> String {
        switch cat {
        case .highCard: return "une meilleure carte haute"
        case .onePair: return "une meilleure paire"
        case .twoPair: return "de meilleures deux paires"
        case .trips: return "un meilleur brelan"
        case .straight: return "une meilleure quinte"
        case .flush: return "une meilleure couleur"
        case .fullHouse: return "un meilleur full"
        case .quads: return "un meilleur carré"
        case .straightFlush: return "une meilleure quinte flush"
        }
    }
}
