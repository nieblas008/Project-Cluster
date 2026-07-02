#!/usr/bin/env swift
// Generates the mansion map (Tiled JSON — editable later in Tiled's GUI):
//   Project Cluster/Resources/mansion.json
// Run from the repo root:  swift scripts/generate-mansion.swift
//
// Layout: hedge ring → grass + gravel loop (the future kart track, PLAN §11)
// → the mansion: north wing with four offices (16 desk zones), great hall
// with the spawn, library west, lounge east, doorways everywhere people walk.
import Foundation

let W = 44
let H = 30

// Local tile ids (see scripts/generate-assets.swift).
let GRASS = 0
let GRASSD = 1
let PATH = 2
let WOOD = 3
let WOODD = 4
let CARPET = 5
let WATER = 6
let WALLS = 7  // stone (interior)
let WALLW = 8  // wood (exterior)
let WINDOW = 9
let HEDGE = 10
let DOOR = 11
let COLLIDING = [WATER, WALLS, WALLW, WINDOW, HEDGE]

var floorL = [Int](repeating: GRASS, count: W * H)
var wallsL = [Int](repeating: -1, count: W * H)  // -1 = empty (gid 0)

func idx(_ x: Int, _ y: Int) -> Int { y * W + x }
func fillFloor(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ t: Int) {
    for y in y0...y1 { for x in x0...x1 { floorL[idx(x, y)] = t } }
}
func wallRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ t: Int) {
    for x in x0...x1 {
        wallsL[idx(x, y0)] = t
        wallsL[idx(x, y1)] = t
    }
    for y in y0...y1 {
        wallsL[idx(x0, y)] = t
        wallsL[idx(x1, y)] = t
    }
}

// Grass decor sprinkle (deterministic).
var seed: UInt64 = 99
func rand(_ n: Int) -> Int {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Int((seed >> 33) % UInt64(n))
}
for i in 0..<(W * H) where rand(7) == 0 { floorL[i] = GRASSD }

// Hedge ring.
wallRect(0, 0, W - 1, H - 1, HEDGE)

// Gravel loop — the kart track corridor (2 tiles wide).
fillFloor(2, 2, W - 3, 3, PATH)
fillFloor(2, H - 4, W - 3, H - 3, PATH)
fillFloor(2, 2, 3, H - 3, PATH)
fillFloor(W - 4, 2, W - 3, H - 3, PATH)

// Pond, east lawn.
fillFloor(37, 24, 39, 25, WATER)
for y in 24...25 { for x in 37...39 { wallsL[idx(x, y)] = WATER } }

// The mansion shell: x 8…35, y 7…22. Wood floors inside.
fillFloor(8, 7, 35, 22, WOOD)
for y in 7...22 { for x in 8...35 where (x + y) % 5 == 0 { floorL[idx(x, y)] = WOODD } }
wallRect(8, 7, 35, 22, WALLW)
// Windows on the long exterior walls.
for x in stride(from: 11, through: 32, by: 4) {
    wallsL[idx(x, 7)] = WINDOW
    if x != 21 && x != 22 { wallsL[idx(x, 22)] = WINDOW }
}

// North wing: corridor y 8…9, offices y 10…13 below it.
// Interior wall under the corridor with four doorways.
for x in 9...34 { wallsL[idx(x, 10)] = WALLS }
// Office dividers.
for y in 10...13 {
    wallsL[idx(15, y)] = WALLS
    wallsL[idx(21, y)] = WALLS
    wallsL[idx(28, y)] = WALLS
}
// South wall of offices, with doorways into the hall area.
for x in 9...34 { wallsL[idx(x, 14)] = WALLS }
for doorX in [11, 18, 24, 31] {
    wallsL[idx(doorX, 10)] = -1
    floorL[idx(doorX, 10)] = DOOR
}
for doorX in [12, 18, 24, 31] {
    wallsL[idx(doorX, 14)] = -1
    floorL[idx(doorX, 14)] = DOOR
}

// Library (west) and lounge (east) split from the great hall.
for y in 15...21 {
    wallsL[idx(15, y)] = WALLS
    wallsL[idx(28, y)] = WALLS
}
wallsL[idx(15, 18)] = -1
floorL[idx(15, 18)] = DOOR
wallsL[idx(28, 18)] = -1
floorL[idx(28, 18)] = DOOR

// Great hall carpet + front door to the lawn.
fillFloor(18, 16, 25, 20, CARPET)
wallsL[idx(21, 22)] = -1
wallsL[idx(22, 22)] = -1
floorL[idx(21, 22)] = DOOR
floorL[idx(22, 22)] = DOOR
fillFloor(21, 23, 22, 25, PATH)  // stub from the door to the loop

// MARK: Objects

struct Obj {
    let name: String
    let type: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
}
var objects: [Obj] = [
    Obj(name: "spawn", type: "spawn", x: 22, y: 18, w: 0, h: 0),
    Obj(name: "kart-track", type: "kart-track", x: 2, y: 2, w: W - 4, h: H - 4),
    // Kart pads, lined up on the south straight of the gravel loop (ADR 0006).
    Obj(name: "kart-01", type: "kart", x: 17, y: 26, w: 1, h: 1),
    Obj(name: "kart-02", type: "kart", x: 19, y: 26, w: 1, h: 1),
    Obj(name: "kart-03", type: "kart", x: 24, y: 26, w: 1, h: 1),
    Obj(name: "kart-04", type: "kart", x: 26, y: 26, w: 1, h: 1),
    // Checkpoints, in lap order: cp-0 is start/finish on the south straight,
    // then east, north, west — each spans the full loop width.
    Obj(name: "cp-0", type: "checkpoint", x: 21, y: 25, w: 2, h: 4),
    Obj(name: "cp-1", type: "checkpoint", x: 39, y: 13, w: 4, h: 2),
    Obj(name: "cp-2", type: "checkpoint", x: 21, y: 1, w: 2, h: 4),
    Obj(name: "cp-3", type: "checkpoint", x: 1, y: 13, w: 4, h: 2),
]
// 16 desks: 4 per office (offices: x 9–14, 16–20, 22–27, 29–34 / y 10–13).
let officeRanges = [(9, 14), (16, 20), (22, 27), (29, 34)]
var deskNumber = 1
for (officeIndex, office) in officeRanges.enumerated() {
    let positions = [
        (office.0 + 1, 11), (office.1 - 1, 11),
        (office.0 + 1, 13), (office.1 - 1, 13),
    ]
    for (x, y) in positions {
        objects.append(
            Obj(name: String(format: "desk-%02d", deskNumber), type: "desk", x: x, y: y, w: 1, h: 1))
        deskNumber += 1
    }
    _ = officeIndex
}

// MARK: Emit Tiled JSON

let tilesetTiles = COLLIDING.map { id in
    ["id": id, "properties": [["name": "collides", "type": "bool", "value": true]]] as [String: Any]
}
let json: [String: Any] = [
    "type": "map", "version": "1.10", "orientation": "orthogonal",
    "renderorder": "right-down", "infinite": false,
    "width": W, "height": H, "tilewidth": 32, "tileheight": 32,
    "layers": [
        [
            "name": "floor", "type": "tilelayer", "width": W, "height": H,
            "data": floorL.map { $0 + 1 },
        ],
        [
            "name": "walls", "type": "tilelayer", "width": W, "height": H,
            "data": wallsL.map { $0 + 1 },
        ],
        [
            "name": "objects", "type": "objectgroup",
            "objects": objects.map { o in
                [
                    "name": o.name, "type": o.type,
                    "x": o.x * 32, "y": o.y * 32,
                    "width": o.w * 32, "height": o.h * 32,
                ] as [String: Any]
            },
        ],
    ],
    "tilesets": [
        [
            "firstgid": 1, "name": "cluster-tiles", "image": "tiles.png",
            "imagewidth": 256, "imageheight": 64,
            "tilewidth": 32, "tileheight": 32, "tilecount": 16, "columns": 8,
            "tiles": tilesetTiles,
        ]
    ],
]

let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: "Project Cluster/Resources/mansion.json"))
print("wrote Project Cluster/Resources/mansion.json (\(W)×\(H), \(objects.count) objects)")
