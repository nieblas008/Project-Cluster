import Foundation

/// A placeable decoration. Static content (ADR 0005) — ids are stable across
/// versions; appending is safe, renumbering is not. `spriteIndex` maps into
/// items.png (8 columns).
public struct CatalogItem: Equatable, Sendable, Identifiable {
    public enum Category: String, Sendable, CaseIterable {
        case plants, tech, comfort, fun, trophies
    }

    public let id: UInt16
    public let name: String
    public let category: Category
    public let spriteIndex: Int
    /// Footprint in tiles (most items are 1×1).
    public let widthTiles: Double
    public let heightTiles: Double

    public init(
        id: UInt16, name: String, category: Category, spriteIndex: Int,
        widthTiles: Double = 1, heightTiles: Double = 1
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.spriteIndex = spriteIndex
        self.widthTiles = widthTiles
        self.heightTiles = heightTiles
    }
}

public enum ItemCatalog {
    public static let all: [CatalogItem] = [
        CatalogItem(id: 1, name: "Small Plant", category: .plants, spriteIndex: 0),
        CatalogItem(id: 2, name: "Tall Plant", category: .plants, spriteIndex: 1),
        CatalogItem(id: 3, name: "Cactus", category: .plants, spriteIndex: 2),
        CatalogItem(id: 4, name: "Hanging Vine", category: .plants, spriteIndex: 3),
        CatalogItem(id: 5, name: "Monitor", category: .tech, spriteIndex: 8),
        CatalogItem(id: 6, name: "Dual Monitors", category: .tech, spriteIndex: 9),
        CatalogItem(id: 7, name: "Laptop", category: .tech, spriteIndex: 10),
        CatalogItem(id: 8, name: "Keyboard", category: .tech, spriteIndex: 11),
        CatalogItem(id: 9, name: "Headphones", category: .tech, spriteIndex: 12),
        CatalogItem(id: 10, name: "Desk Lamp", category: .comfort, spriteIndex: 16),
        CatalogItem(id: 11, name: "Coffee Mug", category: .comfort, spriteIndex: 17),
        CatalogItem(id: 12, name: "Books", category: .comfort, spriteIndex: 18),
        CatalogItem(id: 13, name: "Picture Frame", category: .comfort, spriteIndex: 19),
        CatalogItem(id: 14, name: "Wall Clock", category: .comfort, spriteIndex: 20),
        CatalogItem(id: 15, name: "Lava Lamp", category: .fun, spriteIndex: 24),
        CatalogItem(id: 16, name: "Desk Cat", category: .fun, spriteIndex: 25),
        CatalogItem(id: 17, name: "Rubber Duck", category: .fun, spriteIndex: 26),
        CatalogItem(id: 18, name: "Speaker", category: .fun, spriteIndex: 27),
        CatalogItem(id: 19, name: "Kart Trophy", category: .trophies, spriteIndex: 32),
        CatalogItem(id: 20, name: "Star Trophy", category: .trophies, spriteIndex: 33),
    ]

    public static func item(id: UInt16) -> CatalogItem? {
        all.first { $0.id == id }
    }

    public static var spriteColumns: Int { 8 }
}

/// Who owns which desk. An unclaimed desk has `ownerID == ""`.
public struct DeskClaim: Equatable, Sendable {
    public var zone: String
    public var ownerID: String

    public init(zone: String, ownerID: String) {
        self.zone = zone
        self.ownerID = ownerID
    }
}

/// One decoration placed in a desk, at absolute map tile coordinates.
public struct PlacedItem: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var zone: String
    public var catalogID: UInt16
    public var x: Float
    public var y: Float
    /// Quarter turns clockwise (0–3).
    public var rotation: UInt8

    public init(id: UInt32, zone: String, catalogID: UInt16, x: Float, y: Float, rotation: UInt8) {
        self.id = id
        self.zone = zone
        self.catalogID = catalogID
        self.x = x
        self.y = y
        self.rotation = rotation
    }

    public var position: Vec2 { Vec2(x: Double(x), y: Double(y)) }
}

/// The whole desk world: claims + placements. Broadcast in full on any change
/// (ADR 0005) — at team scale this is a few hundred bytes.
public struct DeskState: Equatable, Sendable {
    public var claims: [DeskClaim]
    public var items: [PlacedItem]

    public init(claims: [DeskClaim] = [], items: [PlacedItem] = []) {
        self.claims = claims
        self.items = items
    }

    public func owner(of zone: String) -> String? {
        claims.first { $0.zone == zone }.map(\.ownerID).flatMap { $0.isEmpty ? nil : $0 }
    }

    public func deskOwned(by playerID: String) -> String? {
        claims.first { $0.ownerID == playerID }?.zone
    }

    public func items(in zone: String) -> [PlacedItem] {
        items.filter { $0.zone == zone }
    }
}

/// Joiner → host desk edits. The host validates every one (ADR 0005).
public enum DeskCommand: Equatable, Sendable {
    case claim(zone: String)
    case release(zone: String)
    case place(zone: String, catalogID: UInt16, x: Float, y: Float, rotation: UInt8)
    case remove(itemID: UInt32)
    case move(itemID: UInt32, x: Float, y: Float, rotation: UInt8)

    private enum Kind: UInt8 {
        case claim = 1, release = 2, place = 3, remove = 4, move = 5
    }

    public func encoded() throws -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .claim(let zone):
            w.write(Kind.claim.rawValue)
            try w.write(zone)
        case .release(let zone):
            w.write(Kind.release.rawValue)
            try w.write(zone)
        case .place(let zone, let catalogID, let x, let y, let rotation):
            w.write(Kind.place.rawValue)
            try w.write(zone)
            w.write(catalogID)
            w.write(x)
            w.write(y)
            w.write(rotation)
        case .remove(let itemID):
            w.write(Kind.remove.rawValue)
            w.write(itemID)
        case .move(let itemID, let x, let y, let rotation):
            w.write(Kind.move.rawValue)
            w.write(itemID)
            w.write(x)
            w.write(y)
            w.write(rotation)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        guard let kind = Kind(rawValue: try r.readUInt8()) else { throw CodecError.invalidValue }
        switch kind {
        case .claim:
            self = .claim(zone: try r.readString())
        case .release:
            self = .release(zone: try r.readString())
        case .place:
            self = .place(
                zone: try r.readString(), catalogID: try r.readUInt16(),
                x: try r.readFloat(), y: try r.readFloat(), rotation: try r.readUInt8())
        case .remove:
            self = .remove(itemID: try r.readUInt32())
        case .move:
            self = .move(
                itemID: try r.readUInt32(), x: try r.readFloat(), y: try r.readFloat(),
                rotation: try r.readUInt8())
        }
    }
}

extension DeskState {
    /// Full-state codec (ADR 0005): rides `deskState` messages and stays tiny
    /// at team scale (16 desks × ≤8 items).
    public func encoded() throws -> [UInt8] {
        guard claims.count <= Int(UInt16.max), items.count <= Int(UInt16.max) else {
            throw CodecError.invalidValue
        }
        var w = ByteWriter()
        w.write(UInt16(claims.count))
        for claim in claims {
            try w.write(claim.zone)
            try w.write(claim.ownerID)
        }
        w.write(UInt16(items.count))
        for item in items {
            w.write(item.id)
            try w.write(item.zone)
            w.write(item.catalogID)
            w.write(item.x)
            w.write(item.y)
            w.write(item.rotation)
        }
        return w.bytes
    }

    public init(decoding bytes: [UInt8]) throws {
        var r = ByteReader(bytes)
        var claims: [DeskClaim] = []
        for _ in 0..<Int(try r.readUInt16()) {
            claims.append(DeskClaim(zone: try r.readString(), ownerID: try r.readString()))
        }
        var items: [PlacedItem] = []
        for _ in 0..<Int(try r.readUInt16()) {
            items.append(
                PlacedItem(
                    id: try r.readUInt32(), zone: try r.readString(),
                    catalogID: try r.readUInt16(), x: try r.readFloat(), y: try r.readFloat(),
                    rotation: try r.readUInt8()))
        }
        self.init(claims: claims, items: items)
    }
}

/// Pure desk geometry/policy — unit-tested (ADR 0005).
public enum DeskRules {
    /// A 1×1 desk zone has a 3×3 half-tile snap grid; eight items is already
    /// a very busy desk.
    public static let maxItemsPerDesk = 8

    /// An item center must sit inside the desk zone's tile rect. The grid snap
    /// keeps placements tidy and makes "remove" hit-testing trivial.
    public static func isInside(x: Double, y: Double, zone: WorldMap.Zone) -> Bool {
        x >= zone.x && x <= zone.x + zone.width && y >= zone.y && y <= zone.y + zone.height
    }

    /// Snap to half-tile centers within the zone.
    public static func snap(x: Double, y: Double) -> (x: Double, y: Double) {
        ((x * 2).rounded() / 2, (y * 2).rounded() / 2)
    }

    public static func deskZone(named name: String, in map: WorldMap) -> WorldMap.Zone? {
        map.zones.first { $0.type == "desk" && $0.name == name }
    }
}
