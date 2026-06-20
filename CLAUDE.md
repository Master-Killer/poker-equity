# CLAUDE.md — Poker Equity

Guide pour travailler sur ce projet. À lire en début de session, à tenir à jour.

## Comment travailler avec François (préférences)

- **Langue : français.** Toujours répondre, expliquer et commenter en français.
- **Jamais de commit sans autorisation explicite.** Ne pas lancer `git commit`/`git push` de soi-même, même quand tout est terminé et vérifié. Faire le travail, le vérifier, puis **proposer** un commit (avec message) et attendre l'accord. François gère ses commits lui-même, souvent au fil de l'eau. (Init de repo / `.gitignore` : OK. Le commit : non.)
- **Textes d'interface en français neutre, sans tutoiement.** « perd », « les cartes », « la paire de 2 l'emporte » — pas « tu perds », « vos cartes ». La 1ʳᵉ personne du cadrage choisi (« comment j'améliore ma main ») est acceptable.
- **Valider sur visuel avant de coder les gros morceaux.** Pour une nouvelle UI : maquette (page HTML interactive autonome, style de l'app) + chiffres réels calculés par le moteur, puis SwiftUI, puis vérif par capture du simulateur. François décide mieux sur maquette que sur description.
- **Exactitude > performance, et comprendre le « pourquoi ».** Il préfère le calcul exact (« tant pis pour les perfs »), veut de la précision (2 décimales), et veut **comprendre les mécanismes et cas limites** (« je veux comprendre !! »). Étayer par des données réelles / exemples concrets, jamais par des affirmations de tête.
- **Goût UI : dense/riche à hiérarchie claire** (pas minimaliste), code couleur, drill-down. Décimales avec **virgule** (français).

## Le projet

App iOS/iPadOS (SwiftUI) + moteur Swift pur, à `~/IdeaProjects/poker-equity`. Calculateur d'équité Texas Hold'em pensé comme un **outil de compréhension** : pas seulement « ma cote », mais **comment ma main s'améliore *relativement* à l'adversaire**, en mettant de côté ce que le tableau apporte à parts égales. 100 % hors-ligne, aucune dépendance externe.

Doc visuelle d'avancement : [`docs/index.html`](docs/index.html) (page autonome interactive).

## Architecture

```
poker-equity/
├── Package.swift                  # package SPM « PokerEngine »
├── Sources/PokerEngine/
│   ├── Card.swift                 # carte/couleur, deck, parsing "Ks", bestFive()
│   ├── HandEvaluator.swift        # évaluateur 5–7 cartes SANS allocation (masques de bits) ; evaluate(), evaluate5(), bestFive()
│   ├── EquityCalculator.swift     # UNE passe d'énumération → équité + breakdown + attribution + coWinMatrix + relative
│   ├── RelativeAnalyzer.swift     # types de la vue relative + façade analyze() (le calcul vit dans EquityCalculator)
│   └── OutsAnalyzer.swift         # outs directs + runner-runner (post-flop)
├── Tests/PokerEngineTests/        # 21 tests (swift test)
└── PokerEquity/                   # app Xcode (SwiftUI)
    ├── PokerEquity.xcodeproj
    └── PokerEquity/               # groupe synchronisé : App, GameViewModel, Screens, CardViews, RelativeView
```

- **Moteur (PokerEngine)** : pur, testable en CLI. `EquityCalculator.compute(hands:board:maxRunouts:)` produit `EquityResult` (par joueur : `equity`, `winProb`/`tieProb`, `breakdown` par catégorie Gagne/Perd/Partage, `winVs`/`loseVs` attribution, plus `coWinMatrix` et `relative`).
- **App (SwiftUI)** : `GameViewModel` (état mains/tableau, focus, calcul async hors-main-thread), `Screens` (lignes joueurs, board, outs, layout adaptatif iPhone/iPad), `RelativeView` (vue « comment j'améliore » + exemples), `CardViews` (cartes + picker 52 cartes escamotable). Le projet Xcode référence le package local en `..`.

## Conventions

- UI **100 % français**, **virgules** décimales, **code couleur unifié** : gagne = vert (`Theme.win`), partage = bleu (`Theme.tie`), perd = rouge (`Theme.lose`) — utilisé sur les triplets ET la frise de composition.
- **Calcul exact par défaut** (l'app appelle `compute` sans plafonner `maxRunouts`). Repli Monte-Carlo déterministe (graine dérivée des cartes) dispo en passant `maxRunouts: 200_000` — à une ligne près dans `GameViewModel`.
- Deux joueurs par défaut ; picker : sélection en 1 tap, focus auto (mains d'abord, puis tableau).

## Modèle « relatif » (concept clé)

Chaque runout est comparé au **tableau nu** (`evaluate(board)`) → 3 sources, croisées avec gagne/partage/perd (9 feuilles, partition exhaustive vérifiée par test) :
- **Amélioration propre** : `catégorie(moi+board) > catégorie(board)` — mes cartes font une vraie main. Sous-étiquetée par mécanisme : *via une carte non partagée* (ma carte distinctive), *via un rang partagé*, *via un tirage* (quinte/couleur).
- **Le kicker tranche** : score > board mais même catégorie — seul le kicker bouge.
- **Le tableau joue** : score(moi+board) == score(board) — mes cartes n'ajoutent rien.

Chaque case garde quelques **tableaux-exemples réels** (réservoir, même passe), affichés avec la main de 5 cartes (`bestFive`) jouée par chaque joueur → tout chiffre s'explique d'un clic. Générique : l'Omaha ne changera que l'évaluateur.

## Vérification

- **Moteur** : `cd ~/IdeaProjects/poker-equity && swift test` (21 tests : évaluateur, équités de référence, exhaustivité des décompositions, cohérence inter-analyses).
- **App (build)** : `cd PokerEquity && xcodebuild -scheme PokerEquity -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO`.
- **App (visuel)** : booter un simulateur (`xcrun simctl boot`), `xcodebuild` pour ce device, `xcrun simctl install/launch`, puis `xcrun simctl io <device> screenshot`. Pour vérifier une donne précise, seed temporaire dans `GameViewModel` (à retirer ensuite).
- ⚠️ Si Xcode compile contre une version périmée du module `PokerEngine` après modif du moteur : `xcodebuild clean` puis rebuild.

## État actuel & suite

- **Fait** : moteur exact + évaluateur rapide ; équité, décompositions Gagne/Perd/Partage, attribution, matrice de co-partage, outs, vue relative « comment j'améliore » + exemples cliquables ; UI iPhone/iPad française avec bascule `Par catégorie | Comment j'améliore` ; 21 tests verts.
- **Pistes** : attribution au niveau kicker (« paire de 10 + meilleur kicker ») ; ligne de résumé en langage naturel ; **Omaha** (toute la mécanique est générique, seul l'évaluateur change) ; activer le repli Monte-Carlo si le préflop multi-joueurs exact gêne sur device.
