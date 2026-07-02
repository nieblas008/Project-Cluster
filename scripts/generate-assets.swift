#!/usr/bin/env swift
// Generates the placeholder art (original, license-free — see assets/LICENSES.md):
//   Project Cluster/Resources/tiles.png    — 8×2 sheet of 32 px tiles
//   Project Cluster/Resources/avatars.png  — 5 presets × 4 facings, 32 px
// Run from the repo root:  swift scripts/generate-assets.swift
import AppKit

let tile = 32

struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    func darker(_ f: CGFloat) -> NSColor {
        NSColor(srgbRed: r * f, green: g * f, blue: b * f, alpha: 1)
    }
}

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func savePNG(_ context: CGContext, to path: String) {
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// MARK: Tiles — flat colors, 1px darker frame, light texture dots

// Local ids: 0 grass · 1 grass-decor · 2 path · 3 wood · 4 wood-dark ·
// 5 carpet · 6 water · 7 wall-stone · 8 wall-wood · 9 window · 10 hedge ·
// 11 doorway. (7,8,9,10 collide — the map generator sets the property.)
let palette: [Int: RGB] = [
    0: RGB(r: 0.45, g: 0.62, b: 0.36),
    1: RGB(r: 0.42, g: 0.60, b: 0.34),
    2: RGB(r: 0.72, g: 0.66, b: 0.54),
    3: RGB(r: 0.62, g: 0.47, b: 0.33),
    4: RGB(r: 0.55, g: 0.41, b: 0.28),
    5: RGB(r: 0.55, g: 0.35, b: 0.38),
    6: RGB(r: 0.33, g: 0.51, b: 0.66),
    7: RGB(r: 0.48, g: 0.47, b: 0.50),
    8: RGB(r: 0.40, g: 0.30, b: 0.24),
    9: RGB(r: 0.58, g: 0.66, b: 0.74),
    10: RGB(r: 0.30, g: 0.45, b: 0.28),
    11: RGB(r: 0.50, g: 0.38, b: 0.27),
]

let columns = 8
let rows = 2
let tilesCtx = makeContext(width: columns * tile, height: rows * tile)
var seed: UInt64 = 0x5EED
func nextRandom() -> CGFloat {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return CGFloat((seed >> 33) % 1000) / 1000
}

for (id, rgb) in palette {
    let cx = (id % columns) * tile
    // CGContext origin is bottom-left; row 0 of the sheet is the TOP row.
    let cy = (rows - 1 - id / columns) * tile
    let rect = CGRect(x: cx, y: cy, width: tile, height: tile)

    tilesCtx.setFillColor(rgb.color.cgColor)
    tilesCtx.fill(rect)
    // Frame
    tilesCtx.setStrokeColor(rgb.darker(0.82).cgColor)
    tilesCtx.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1)
    // Texture dots / accents
    tilesCtx.setFillColor(rgb.darker(0.9).cgColor)
    for _ in 0..<14 {
        let px = rect.minX + nextRandom() * CGFloat(tile - 2)
        let py = rect.minY + nextRandom() * CGFloat(tile - 2)
        tilesCtx.fill(CGRect(x: px, y: py, width: 1.5, height: 1.5))
    }
    switch id {
    case 1:  // flowers on decor grass
        tilesCtx.setFillColor(NSColor(srgbRed: 0.95, green: 0.85, blue: 0.4, alpha: 1).cgColor)
        for _ in 0..<3 {
            let px = rect.minX + 4 + nextRandom() * CGFloat(tile - 10)
            let py = rect.minY + 4 + nextRandom() * CGFloat(tile - 10)
            tilesCtx.fill(CGRect(x: px, y: py, width: 3, height: 3))
        }
    case 3, 4, 11:  // wood planks
        tilesCtx.setStrokeColor(rgb.darker(0.78).cgColor)
        for i in 1..<4 {
            let y = rect.minY + CGFloat(i * 8)
            tilesCtx.strokeLineSegments(between: [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)])
        }
    case 7, 8:  // brick courses
        tilesCtx.setStrokeColor(rgb.darker(0.7).cgColor)
        for i in 0..<2 {
            let y = rect.minY + CGFloat(10 + i * 12)
            tilesCtx.strokeLineSegments(between: [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)])
        }
        tilesCtx.strokeLineSegments(between: [
            CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY + 10),
        ])
    case 9:  // window pane
        tilesCtx.setFillColor(NSColor(srgbRed: 0.78, green: 0.88, blue: 0.95, alpha: 1).cgColor)
        tilesCtx.fill(rect.insetBy(dx: 7, dy: 9))
        tilesCtx.setStrokeColor(rgb.darker(0.6).cgColor)
        tilesCtx.stroke(rect.insetBy(dx: 7, dy: 9), width: 1.5)
    case 6:  // water ripples
        tilesCtx.setStrokeColor(NSColor(srgbRed: 0.5, green: 0.68, blue: 0.8, alpha: 1).cgColor)
        for i in 0..<2 {
            let y = rect.minY + CGFloat(9 + i * 13)
            tilesCtx.strokeLineSegments(between: [
                CGPoint(x: rect.minX + 5, y: y), CGPoint(x: rect.minX + 15, y: y),
            ])
        }
    default:
        break
    }
}
savePNG(tilesCtx, to: "Project Cluster/Resources/tiles.png")

// MARK: Avatars — preset rows × facing columns (down, up, left, right)

let presets: [(String, RGB)] = [
    ("default", RGB(r: 0.26, g: 0.62, b: 0.58)),
    ("sky", RGB(r: 0.33, g: 0.55, b: 0.83)),
    ("mint", RGB(r: 0.38, g: 0.72, b: 0.52)),
    ("coral", RGB(r: 0.88, g: 0.52, b: 0.35)),
    ("violet", RGB(r: 0.58, g: 0.44, b: 0.78)),
]

let avatarsCtx = makeContext(width: 4 * tile, height: presets.count * tile)
for (row, preset) in presets.enumerated() {
    for facing in 0..<4 {  // 0 down, 1 up, 2 left, 3 right
        let originX = facing * tile
        let originY = (presets.count - 1 - row) * tile
        let body = CGRect(x: originX + 6, y: originY + 4, width: 20, height: 24)

        // Shadow
        avatarsCtx.setFillColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18).cgColor)
        avatarsCtx.fillEllipse(in: CGRect(x: originX + 7, y: originY + 1, width: 18, height: 6))
        // Body
        let bodyPath = CGPath(roundedRect: body, cornerWidth: 8, cornerHeight: 8, transform: nil)
        avatarsCtx.addPath(bodyPath)
        avatarsCtx.setFillColor(preset.1.color.cgColor)
        avatarsCtx.fillPath()
        avatarsCtx.addPath(bodyPath)
        avatarsCtx.setStrokeColor(preset.1.darker(0.65).cgColor)
        avatarsCtx.setLineWidth(1.5)
        avatarsCtx.strokePath()

        // Eyes per facing (none when facing up — that's the back).
        avatarsCtx.setFillColor(NSColor.white.cgColor)
        let eyeY = body.maxY - 9
        func eye(_ x: CGFloat) {
            avatarsCtx.fillEllipse(in: CGRect(x: x, y: eyeY, width: 5, height: 5))
            avatarsCtx.setFillColor(NSColor(srgbRed: 0.1, green: 0.1, blue: 0.15, alpha: 1).cgColor)
            avatarsCtx.fillEllipse(in: CGRect(x: x + 1.5, y: eyeY + 1, width: 2.5, height: 2.5))
            avatarsCtx.setFillColor(NSColor.white.cgColor)
        }
        switch facing {
        case 0:
            eye(body.minX + 4)
            eye(body.maxX - 9)
        case 2:
            eye(body.minX + 2)
        case 3:
            eye(body.maxX - 7)
        default:
            break
        }
    }
}
savePNG(avatarsCtx, to: "Project Cluster/Resources/avatars.png")

// MARK: Desk items — 8 columns × 5 category rows (ADR 0005 sprite indices)

let itemsCtx = makeContext(width: 8 * tile, height: 5 * tile)

func itemRect(_ spriteIndex: Int) -> CGRect {
    let col = spriteIndex % 8
    let row = spriteIndex / 8
    return CGRect(x: col * tile, y: (5 - 1 - row) * tile, width: tile, height: tile)
}

func fillCircle(_ r: CGRect, _ c: NSColor) {
    itemsCtx.setFillColor(c.cgColor)
    itemsCtx.fillEllipse(in: r)
}
func fillRect(_ r: CGRect, _ c: NSColor) {
    itemsCtx.setFillColor(c.cgColor)
    itemsCtx.fill(r)
}

let pot = NSColor(srgbRed: 0.72, green: 0.45, blue: 0.3, alpha: 1)
let leaf = NSColor(srgbRed: 0.32, green: 0.65, blue: 0.38, alpha: 1)
let dark = NSColor(srgbRed: 0.18, green: 0.19, blue: 0.22, alpha: 1)
let metal = NSColor(srgbRed: 0.62, green: 0.65, blue: 0.7, alpha: 1)
let gold = NSColor(srgbRed: 0.92, green: 0.76, blue: 0.28, alpha: 1)

for (index, draw) in [
    // plants
    (0, { (r: CGRect) in
        fillRect(CGRect(x: r.midX - 6, y: r.minY + 4, width: 12, height: 8), pot)
        fillCircle(CGRect(x: r.midX - 8, y: r.minY + 11, width: 16, height: 14), leaf)
    }),
    (1, { r in
        fillRect(CGRect(x: r.midX - 5, y: r.minY + 3, width: 10, height: 7), pot)
        fillCircle(CGRect(x: r.midX - 7, y: r.minY + 9, width: 14, height: 20), leaf)
    }),
    (2, { r in
        fillRect(CGRect(x: r.midX - 6, y: r.minY + 4, width: 12, height: 6), pot)
        fillRect(CGRect(x: r.midX - 3, y: r.minY + 9, width: 6, height: 16), leaf)
        fillRect(CGRect(x: r.midX - 9, y: r.minY + 14, width: 6, height: 4), leaf)
    }),
    (3, { r in
        fillCircle(CGRect(x: r.minX + 4, y: r.maxY - 12, width: 10, height: 8), leaf)
        fillCircle(CGRect(x: r.midX, y: r.maxY - 16, width: 12, height: 10), leaf)
        fillRect(CGRect(x: r.midX - 1, y: r.minY + 6, width: 2, height: 14), leaf)
    }),
    // tech
    (8, { r in
        fillRect(CGRect(x: r.minX + 5, y: r.minY + 10, width: 22, height: 14), dark)
        fillRect(CGRect(x: r.midX - 3, y: r.minY + 5, width: 6, height: 6), metal)
    }),
    (9, { r in
        fillRect(CGRect(x: r.minX + 2, y: r.minY + 10, width: 13, height: 12), dark)
        fillRect(CGRect(x: r.minX + 17, y: r.minY + 10, width: 13, height: 12), dark)
    }),
    (10, { r in
        fillRect(CGRect(x: r.minX + 6, y: r.minY + 6, width: 20, height: 4), metal)
        fillRect(CGRect(x: r.minX + 7, y: r.minY + 10, width: 18, height: 12), dark)
    }),
    (11, { r in
        fillRect(CGRect(x: r.minX + 4, y: r.midY - 5, width: 24, height: 10), metal)
    }),
    (12, { r in
        itemsCtx.setStrokeColor(dark.cgColor)
        itemsCtx.setLineWidth(3)
        itemsCtx.strokeEllipse(in: CGRect(x: r.midX - 8, y: r.midY - 4, width: 16, height: 14))
        fillCircle(CGRect(x: r.midX - 11, y: r.midY - 6, width: 7, height: 9), dark)
        fillCircle(CGRect(x: r.midX + 4, y: r.midY - 6, width: 7, height: 9), dark)
    }),
    // comfort
    (16, { r in
        fillRect(CGRect(x: r.midX - 1, y: r.minY + 5, width: 2, height: 12), metal)
        fillCircle(CGRect(x: r.midX - 7, y: r.minY + 15, width: 14, height: 10), gold)
    }),
    (17, { r in
        fillRect(CGRect(x: r.midX - 6, y: r.minY + 8, width: 12, height: 12), NSColor(srgbRed: 0.85, green: 0.4, blue: 0.35, alpha: 1))
        itemsCtx.setStrokeColor(dark.cgColor)
        itemsCtx.setLineWidth(2)
        itemsCtx.strokeEllipse(in: CGRect(x: r.midX + 5, y: r.minY + 11, width: 6, height: 6))
    }),
    (18, { r in
        fillRect(CGRect(x: r.minX + 6, y: r.minY + 6, width: 6, height: 18), NSColor(srgbRed: 0.55, green: 0.35, blue: 0.4, alpha: 1))
        fillRect(CGRect(x: r.minX + 13, y: r.minY + 6, width: 6, height: 16), NSColor(srgbRed: 0.35, green: 0.5, blue: 0.6, alpha: 1))
        fillRect(CGRect(x: r.minX + 20, y: r.minY + 6, width: 6, height: 17), gold)
    }),
    (19, { r in
        fillRect(CGRect(x: r.midX - 9, y: r.midY - 11, width: 18, height: 22), gold)
        fillRect(CGRect(x: r.midX - 6, y: r.midY - 8, width: 12, height: 16), NSColor(srgbRed: 0.75, green: 0.85, blue: 0.9, alpha: 1))
    }),
    (20, { r in
        fillCircle(CGRect(x: r.midX - 10, y: r.midY - 10, width: 20, height: 20), NSColor.white)
        itemsCtx.setStrokeColor(dark.cgColor)
        itemsCtx.setLineWidth(2)
        itemsCtx.strokeLineSegments(between: [CGPoint(x: r.midX, y: r.midY), CGPoint(x: r.midX, y: r.midY + 7)])
        itemsCtx.strokeLineSegments(between: [CGPoint(x: r.midX, y: r.midY), CGPoint(x: r.midX + 5, y: r.midY)])
    }),
    // fun
    (24, { r in
        fillRect(CGRect(x: r.midX - 5, y: r.minY + 4, width: 10, height: 4), metal)
        fillRect(CGRect(x: r.midX - 4, y: r.minY + 8, width: 8, height: 16), NSColor(srgbRed: 0.6, green: 0.3, blue: 0.7, alpha: 1))
        fillCircle(CGRect(x: r.midX - 3, y: r.minY + 10, width: 6, height: 6), NSColor(srgbRed: 0.95, green: 0.5, blue: 0.6, alpha: 1))
        fillCircle(CGRect(x: r.midX - 2, y: r.minY + 18, width: 4, height: 4), NSColor(srgbRed: 0.95, green: 0.5, blue: 0.6, alpha: 1))
    }),
    (25, { r in
        fillCircle(CGRect(x: r.midX - 8, y: r.minY + 4, width: 16, height: 12), NSColor(srgbRed: 0.45, green: 0.42, blue: 0.4, alpha: 1))
        fillCircle(CGRect(x: r.midX - 6, y: r.minY + 14, width: 12, height: 10), NSColor(srgbRed: 0.45, green: 0.42, blue: 0.4, alpha: 1))
        itemsCtx.setFillColor(NSColor(srgbRed: 0.45, green: 0.42, blue: 0.4, alpha: 1).cgColor)
        itemsCtx.fill(CGRect(x: r.midX - 7, y: r.minY + 21, width: 4, height: 5))
        itemsCtx.fill(CGRect(x: r.midX + 3, y: r.minY + 21, width: 4, height: 5))
    }),
    (26, { r in
        fillCircle(CGRect(x: r.midX - 9, y: r.minY + 5, width: 15, height: 12), gold)
        fillCircle(CGRect(x: r.midX + 1, y: r.minY + 12, width: 9, height: 9), gold)
        fillRect(CGRect(x: r.midX + 8, y: r.minY + 15, width: 5, height: 3), NSColor(srgbRed: 0.9, green: 0.5, blue: 0.2, alpha: 1))
    }),
    (27, { r in
        fillRect(CGRect(x: r.midX - 7, y: r.minY + 4, width: 14, height: 20), dark)
        fillCircle(CGRect(x: r.midX - 5, y: r.minY + 6, width: 10, height: 10), metal)
        fillCircle(CGRect(x: r.midX - 3, y: r.minY + 17, width: 6, height: 6), metal)
    }),
    // trophies
    (32, { r in
        fillRect(CGRect(x: r.midX - 8, y: r.minY + 3, width: 16, height: 4), gold)
        fillRect(CGRect(x: r.midX - 2, y: r.minY + 7, width: 4, height: 5), gold)
        fillCircle(CGRect(x: r.midX - 8, y: r.minY + 11, width: 16, height: 13), gold)
        fillRect(CGRect(x: r.midX - 5, y: r.minY + 14, width: 10, height: 5), dark)
    }),
    (33, { r in
        fillRect(CGRect(x: r.midX - 8, y: r.minY + 3, width: 16, height: 4), gold)
        fillRect(CGRect(x: r.midX - 2, y: r.minY + 7, width: 4, height: 6), gold)
        let starCenter = CGPoint(x: r.midX, y: r.minY + 19)
        let star = CGMutablePath()
        for i in 0..<10 {
            let radius: CGFloat = i % 2 == 0 ? 9 : 4
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: starCenter.x + radius * cos(angle), y: starCenter.y + radius * sin(angle))
            if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
        }
        star.closeSubpath()
        itemsCtx.addPath(star)
        itemsCtx.setFillColor(gold.cgColor)
        itemsCtx.fillPath()
    }),
] {
    draw(itemRect(index))
}
savePNG(itemsCtx, to: "Project Cluster/Resources/items.png")
