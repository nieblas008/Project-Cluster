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
