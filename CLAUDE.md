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
│   ├── RelativeAnalyzer.swift     # types de la vue relative (ShowdownVerdict, EdgeMechanism/ChopTexture, RelExample) ; le calcul vit dans EquityCalculator
│   └── OutsAnalyzer.swift         # outs directs + runner-runner (post-flop)
├── Tests/PokerEngineTests/        # 61 tests (swift test)
└── PokerEquity/                   # app Xcode (SwiftUI)
    ├── PokerEquity.xcodeproj
    └── PokerEquity/               # groupe synchronisé : App, GameViewModel, Screens, CardViews, RelativeView, RelativeSentence
```

- **Moteur (PokerEngine)** : pur, testable en CLI. `EquityCalculator.compute(hands:board:maxRunouts:)` produit `EquityResult` (par joueur : `equity`, `winProb`/`tieProb`, `breakdown` par catégorie Gagne/Perd/Partage, `winVs`/`loseVs` attribution, plus `coWinMatrix` et `relative`).
- **App (SwiftUI)** : `GameViewModel` (état mains/tableau, focus, calcul async hors-main-thread), `Screens` (lignes joueurs, board, outs, layout adaptatif iPhone/iPad), `RelativeView` (vue « comment j'améliore » : décomposition du duel en *je gagne / partage / perds*, lignes triées par probabilité, carte décisive surlignée, part absolue/combos, phrase à droite), `RelativeSentence` (phrases de synthèse, rendu du `showdownVerdict`), `CardViews` (cartes + picker 52 cartes escamotable). Le projet Xcode référence le package local en `..`.

## Conventions

- UI **100 % français**, **virgules** décimales, **code couleur unifié** : gagne = vert (`Theme.win`), partage = bleu (`Theme.tie`), perd = rouge (`Theme.lose`) — utilisé sur les triplets ET la frise de composition.
- **Calcul exact par défaut** (l'app appelle `compute` sans plafonner `maxRunouts`). Repli Monte-Carlo déterministe (graine dérivée des cartes) dispo en passant `maxRunouts: 200_000` — à une ligne près dans `GameViewModel`.
- Deux joueurs par défaut ; picker : sélection en 1 tap, focus auto (mains d'abord, puis tableau).

## Modèle « relatif » (concept clé)

Chaque runout est classé par le **duel moi ↔ meilleur adversaire** (`showdownVerdict`, pas par rapport au tableau nu) → décomposition « pourquoi je gagne / partage / perds ». La frontière se mesure sur la **combinaison seule** (`combinationScore`, score privé de ses bits de kicker) — un kicker n'existe que quand les deux mains ont la *même* combinaison et qu'une carte annexe départage ; un full/quinte/couleur n'a jamais de kicker. Cela garde « le kicker tranche » aux **vrais duels de kicker**, symétriquement pour les deux mains.
- **Je gagne** : *ma combinaison l'emporte* (catégorie supérieure ou meilleure combinaison de même catégorie), sous-étiquetée par 4 mécanismes (`EdgeMechanism` : *carte non partagée*, *rang partagé*, *paire servie*, *quinte/couleur*) ; ou *mon kicker l'emporte* (même combinaison que l'adversaire).
- **Partage** : mains identiques, sous-étiqueté par texture du tableau (`ChopTexture`).
- **Je perds** : *l'adversaire a une meilleure combinaison* ; ou *le kicker de l'adversaire l'emporte*.

`RelativeAnalysis` expose `winCombination[mécanisme]`, `winKicker`, `chop[texture]`, `loseCombination`, `loseKicker` (fractions de tous les runouts ; `winTotal+tieTotal+loseTotal == 1`). Chaque feuille garde quelques **exemples variés** (`RelExample` : bucketés par signature `(maCat, catAdv, rang décisif)` puis « variété max » — cas typique + contrastés, même passe). Chaque exemple porte : les **cartes décisives** (`decisive` = la combinaison entière du **vainqueur** sur le tableau — la mienne si je gagne, celle de l'adversaire si je perds — surlignée par `CardFace(highlight:)`), sa **part absolue** (`share`) + nombre de combos (`count`), et une **phrase de synthèse** : `RelativeSentence` (app) rend en français neutre le verdict de `showdownVerdict` — lequel respecte la définition stricte du kicker. Tout chiffre s'explique d'un clic. Générique : l'Omaha ne changera que l'évaluateur.

## Vérification

- **Moteur** : `cd ~/IdeaProjects/poker-equity && swift test` (61 tests : évaluateur, équités de référence, exhaustivité des décompositions, cohérence inter-analyses, validité/variété des exemples relatifs).
- **App (build)** : `cd PokerEquity && xcodebuild -scheme PokerEquity -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO`.
- **App (visuel)** : booter un simulateur (`xcrun simctl boot`), `xcodebuild` pour ce device, `xcrun simctl install/launch`, puis `xcrun simctl io <device> screenshot`. Pour vérifier une donne précise, seed temporaire dans `GameViewModel` (à retirer ensuite).
- ⚠️ Si Xcode compile contre une version périmée du module `PokerEngine` après modif du moteur : `xcodebuild clean` puis rebuild.

## État actuel & suite

- **Fait** : moteur exact + évaluateur rapide ; équité, décompositions Gagne/Perd/Partage, attribution, matrice de co-partage, outs, vue relative « comment j'améliore » avec exemples variés (carte décisive surlignée, part absolue, phrase de synthèse) et reclassement combinaison/kicker ; UI iPhone/iPad française avec bascule `Par catégorie | Comment j'améliore` ; 61 tests verts.
- **Pistes** : **Omaha** (toute la mécanique est générique, seul l'évaluateur change) ; activer le repli Monte-Carlo si le préflop multi-joueurs exact gêne sur device ; affiner les formulations des phrases sur écran iPhone réel.
