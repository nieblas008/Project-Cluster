import Foundation

/// The world as the simulation sees it: tile grids, collision, spawn points,
/// named zones. Loaded from a Tiled JSON map (authored by hand, by generator
/// script, or later in Tiled's GUI — same file either way).
public struct WorldMap: Sendable {
    public struct Zone: Equatable, Sendable {
        public var name: String
        public var type: String
        /// Tile coordinates.
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
    }

    public var widthTiles: Int
    public var heightTiles: Int
    public var tilePixels: Int
    /// Tile GIDs per layer, row-major, 0 = empty. Local tile id = gid - 1.
    public var floor: [UInt32]
    public var walls: [UInt32]
    public var collision: CollisionMap
    /// Tile coordinates of spawn markers (at least one required).
    public var spawnPoints: [Vec2]
    public var zones: [Zone]
    /// FNV-1a of the raw map file — joiners compare against the host's.
    public var contentHash: String
}

public struct CollisionMap: Sendable {
    public let width: Int
    public let height: Int
    private let solid: [Bool]

    public init(width: Int, height: Int, solid: [Bool]) {
        precondition(solid.count == width * height)
        self.width = width
        self.height = height
        self.solid = solid
    }

    /// Out of bounds is solid — the world has edges.
    public func isSolid(tileX: Int, tileY: Int) -> Bool {
        guard tileX >= 0, tileY >= 0, tileX < width, tileY < height else { return true }
        return solid[tileY * width + tileX]
    }
}

public enum WorldMapError: Error, Equatable {
    case missingLayer(String)
    case noSpawnPoints
    case malformed(String)
}

/// Decodes the subset of Tiled's JSON we author: orthogonal, one embedded
/// tileset, `floor` + `walls` tile layers, one `objects` object layer.
public enum TiledMapLoader {
    public static func load(data: Data) throws -> WorldMap {
        let tiled: TiledFile
        do {
            tiled = try JSONDecoder().decode(TiledFile.self, from: data)
        } catch {
            throw WorldMapError.malformed("\(error)")
        }

        guard let floorLayer = tiled.layers.first(where: { $0.name == "floor" })?.data else {
            throw WorldMapError.missingLayer("floor")
        }
        guard let wallsLayer = tiled.layers.first(where: { $0.name == "walls" })?.data else {
            throw WorldMapError.missingLayer("walls")
        }
        let objects = tiled.layers.first(where: { $0.type == "objectgroup" })?.objects ?? []

        // GIDs whose tile definition carries collides=true.
        var collidingGIDs = Set<UInt32>()
        for tileset in tiled.tilesets {
            for tile in tileset.tiles ?? [] {
                let collides = tile.properties?.contains {
                    $0.name == "collides" && $0.boolValue == true
                }
                if collides == true {
                    collidingGIDs.insert(tileset.firstgid + tile.id)
                }
            }
        }

        let solid = wallsLayer.map { collidingGIDs.contains($0) }
        let tileSize = Double(tiled.tilewidth)
        let spawns = objects.filter { $0.type == "spawn" || $0.name == "spawn" }
            .map { Vec2(x: $0.x / tileSize, y: $0.y / tileSize) }
        guard !spawns.isEmpty else { throw WorldMapError.noSpawnPoints }

        let zones = objects.filter { $0.type != "spawn" && $0.name != "spawn" }.map {
            WorldMap.Zone(
                name: $0.name, type: $0.type,
                x: $0.x / tileSize, y: $0.y / tileSize,
                width: ($0.width ?? 0) / tileSize, height: ($0.height ?? 0) / tileSize)
        }

        return WorldMap(
            widthTiles: tiled.width,
            heightTiles: tiled.height,
            tilePixels: tiled.tilewidth,
            floor: floorLayer,
            walls: wallsLayer,
            collision: CollisionMap(width: tiled.width, height: tiled.height, solid: solid),
            spawnPoints: spawns,
            zones: zones,
            contentHash: fnv1a(data)
        )
    }

    /// FNV-1a 64 — stable, dependency-free version stamp (not security).
    static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Tiled JSON schema subset

struct TiledFile: Decodable {
    var width: Int
    var height: Int
    var tilewidth: Int
    var layers: [TiledLayer]
    var tilesets: [TiledTileset]
}

struct TiledLayer: Decodable {
    var name: String
    var type: String
    var data: [UInt32]?
    var objects: [TiledObject]?
}

struct TiledObject: Decodable {
    var name: String
    var type: String
    var x: Double
    var y: Double
    var width: Double?
    var height: Double?
}

struct TiledTileset: Decodable {
    var firstgid: UInt32
    var tiles: [TiledTileDefinition]?
}

struct TiledTileDefinition: Decodable {
    var id: UInt32
    var properties: [TiledProperty]?
}

struct TiledProperty: Decodable {
    var name: String
    var boolValue: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.boolValue = try? container.decode(Bool.self, forKey: .value)
    }
}
