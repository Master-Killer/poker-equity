// Génère l'icône de l'app (pique sombre + liseré or sur bandes obliques
// vert/bleu/rouge — le code couleur gagne/partage/perd de l'app).
//
// Rendu en pur CoreGraphics, 100 % hors-ligne (aucune dépendance externe,
// pas de convertisseur SVG à installer). Produit un PNG 1024×1024 sans
// transparence ni coins arrondis : iOS applique lui-même le masque.
//
// Régénérer l'asset depuis la racine du dépôt :
//   swift PokerEquity/Tools/make_icon.swift \
//     PokerEquity/PokerEquity/Assets.xcassets/AppIcon.appiconset/icon_1024.png
//
// Réglages utiles : `slant` (inclinaison des bandes), `s` (taille du pique),
// la largeur du liseré (`setLineWidth`), et la palette ci-dessous (alignée
// sur Theme dans App.swift).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let N = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no ctx")
}

// Travailler en coordonnées « écran » (origine en haut à gauche, y vers le bas).
ctx.translateBy(x: 0, y: CGFloat(N))
ctx.scaleBy(x: 1, y: -1)

func col(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, 1])!
}
let dark  = col(18, 19, 22)
let green = col(77, 189, 115)
let blue  = col(115, 125, 204)
let red   = col(190, 99, 96)   // rouge adouci (moins saturé que la version d'origine)
let gold  = col(219, 176, 51)

let W = CGFloat(N)

// --- Fond : bandes obliques pleine page (vert / bleu / rouge) ---
func poly(_ pts: [(CGFloat, CGFloat)], _ c: CGColor) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
    ctx.closePath()
    ctx.setFillColor(c)
    ctx.fillPath()
}
let slant: CGFloat = W * 0.21        // décalage du bas vers la gauche
// Le slant transfère de la surface du vert vers le rouge (aire ∝ largeur en bas
// de bande) : à t1 = W/3, t2 = 2W/3, on obtient vert 22,8 % / bleu 33,3 % / rouge
// 43,8 % — d'où le déséquilibre. On recale pour vert 33 % / bleu 37 % / rouge 30 %
// (rouge un peu réduit + adouci car plus « bruyant » à l'œil à surface égale).
let t1: CGFloat = W * 0.33 + slant / 2
let t2: CGFloat = t1 + W * 0.37
poly([(0,0),(t1,0),(t1-slant,W),(0,W)], green)
poly([(t1,0),(t2,0),(t2-slant,W),(t1-slant,W)], blue)
poly([(t2,0),(W,0),(W,W),(t2-slant,W)], red)

// --- Pique centré ---
let s: CGFloat = 8.5
let xoff: CGFloat = (W - 100 * s) / 2     // centrage horizontal
func m(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
    CGPoint(x: xoff + lx * s, y: W/2 + (ly - 50) * s)
}
let spade = CGMutablePath()
spade.move(to: m(50, 10))
spade.addCurve(to: m(20, 60), control1: m(50, 10), control2: m(20, 38))
spade.addCurve(to: m(46, 70), control1: m(20, 74), control2: m(34, 78))
spade.addCurve(to: m(38, 90), control1: m(46, 70), control2: m(46, 80))
spade.addLine(to: m(62, 90))
spade.addCurve(to: m(54, 70), control1: m(54, 80), control2: m(54, 70))
spade.addCurve(to: m(80, 60), control1: m(66, 78), control2: m(80, 74))
spade.addCurve(to: m(50, 10), control1: m(80, 38), control2: m(50, 10))
spade.closeSubpath()

ctx.addPath(spade)
ctx.setFillColor(dark)
ctx.fillPath()

ctx.addPath(spade)
ctx.setStrokeColor(gold)
ctx.setLineWidth(7.5)                 // liseré or « fin »
ctx.setLineJoin(.round)
ctx.strokePath()

guard let img = ctx.makeImage() else { fatalError("no image") }
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"
let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("écrit: \(outURL.path)")
