import ClusterProtocol
import SpriteKit

@MainActor
protocol WorldSceneDelegate: AnyObject {
    /// ~20 Hz while in the world: the local avatar's predicted state, for the
    /// session to publish (host) or send as input (joiner).
    func worldScene(
        _ scene: WorldScene, didUpdateLocal position: Vec2, facing: Facing,
        isMoving: Bool, input: MoveInput)
}

/// The mansion, rendered: tiles from the shared map, the local avatar driven
/// by prediction (PLAN §7), remotes driven by interpolators sampling 120 ms
/// in the past, camera glued to you.
final class WorldScene: SKScene {
    private let map: WorldMap
    private let localWireID: UInt64
    private let localDisplayName: String
    private let localPreset: String
    weak var worldDelegate: WorldSceneDelegate?

    private static let presetOrder = ["default", "sky", "mint", "coral", "violet"]
    private static let tilePoints: CGFloat = 32

    private var tilesTexture: SKTexture?
    private var avatarsTexture: SKTexture?

    private var localNode: AvatarNode?
    private var localPosition: Vec2?
    private var localFacing: Facing = .down
    private var currentInput = MoveInput.idle
    private var lastUpdateTime: TimeInterval = 0
    private var emitAccumulator: TimeInterval = 0

    private var interpolators: [UInt64: RemotePlayerInterpolator] = [:]
    private var remoteNodes: [UInt64: AvatarNode] = [:]
    private var rosterMeta: [UInt64: (name: String, preset: String)] = [:]
    private let cameraNode = SKCameraNode()

    init(map: WorldMap, localWireID: UInt64, localDisplayName: String, localPreset: String) {
        self.map = map
        self.localWireID = localWireID
        self.localDisplayName = localDisplayName
        self.localPreset = localPreset
        super.init(size: CGSize(width: 900, height: 620))
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(srgbRed: 0.10, green: 0.12, blue: 0.10, alpha: 1)
        loadTextures()
        buildTileNodes()
        camera = cameraNode
        addChild(cameraNode)
        cameraNode.setScale(0.8)
        if let spawn = map.spawnPoints.first {
            cameraNode.position = Self.point(forTile: spawn)
        }
    }

    // MARK: Inbound state

    func setInput(_ input: MoveInput) {
        currentInput = input
    }

    func setSpeaking(_ ids: Set<UInt64>) {
        localNode?.setSpeaking(ids.contains(localWireID))
        for (id, node) in remoteNodes {
            node.setSpeaking(ids.contains(id))
        }
    }

    func applyRoster(_ roster: [RosterEntry]) {
        rosterMeta = Dictionary(
            uniqueKeysWithValues: roster.map {
                (PlayerWireID.prefix(fromHexID: $0.playerID), ($0.displayName, $0.avatarPreset))
            })
        for (id, node) in remoteNodes where rosterMeta[id] == nil {
            node.removeFromParent()
            remoteNodes.removeValue(forKey: id)
            interpolators.removeValue(forKey: id)
        }
    }

    func applySnapshot(_ snapshot: WorldSnapshot) {
        let now = CACurrentMediaTime()
        for player in snapshot.players {
            if player.id == localWireID {
                if localPosition == nil {
                    // First sight of ourselves = the host's spawn for us.
                    localPosition = player.position
                } else if let current = localPosition,
                    current.distance(to: player.position) > 1.5
                {
                    // The authority disagrees hard (validation clamp) — snap.
                    localPosition = player.position
                }
            } else {
                interpolators[player.id, default: RemotePlayerInterpolator()]
                    .record(player, at: now)
            }
        }
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 0.1)
        lastUpdateTime = currentTime
        guard dt > 0 else { return }

        if var position = localPosition {
            position = MovementSim.step(
                position: position, input: currentInput, dt: dt, collision: map.collision)
            localPosition = position
            localFacing = Facing.from(input: currentInput, previous: localFacing)

            let node = localNode ?? makeAvatarNode(name: localDisplayName, preset: localPreset)
            if localNode == nil {
                localNode = node
                addChild(node)
            }
            node.apply(
                point: Self.point(forTile: position), facing: localFacing,
                moving: currentInput.isMoving,
                texture: avatarTexture(preset: localPreset, facing: localFacing))

            let target = Self.point(forTile: position)
            cameraNode.position = CGPoint(
                x: cameraNode.position.x + (target.x - cameraNode.position.x) * 0.18,
                y: cameraNode.position.y + (target.y - cameraNode.position.y) * 0.18)

            emitAccumulator += dt
            if emitAccumulator >= 0.05 {
                emitAccumulator = 0
                worldDelegate?.worldScene(
                    self, didUpdateLocal: position, facing: localFacing,
                    isMoving: currentInput.isMoving, input: currentInput)
            }
        }

        let renderTime = currentTime - RemotePlayerInterpolator.renderDelay
        for (id, interpolator) in interpolators {
            guard let sample = interpolator.sample(at: renderTime) else { continue }
            let meta = rosterMeta[id]
            let node =
                remoteNodes[id]
                ?? {
                    let created = makeAvatarNode(
                        name: meta?.name ?? "…", preset: meta?.preset ?? "default")
                    remoteNodes[id] = created
                    addChild(created)
                    return created
                }()
            node.apply(
                point: Self.point(forTile: sample.position), facing: sample.facing,
                moving: sample.isMoving,
                texture: avatarTexture(preset: meta?.preset ?? "default", facing: sample.facing))
        }
    }

    // MARK: Construction

    private func loadTextures() {
        func texture(_ name: String) -> SKTexture? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                let image = NSImage(contentsOf: url)
            else { return nil }
            let result = SKTexture(image: image)
            result.filteringMode = .nearest
            return result
        }
        tilesTexture = texture("tiles")
        avatarsTexture = texture("avatars")
    }

    private func buildTileNodes() {
        guard tilesTexture != nil else { return }
        let container = SKNode()
        for y in 0..<map.heightTiles {
            for x in 0..<map.widthTiles {
                let index = y * map.widthTiles + x
                addTile(gid: map.floor[index], x: x, y: y, z: 0, into: container)
                addTile(gid: map.walls[index], x: x, y: y, z: 1, into: container)
            }
        }
        addChild(container)
    }

    private func addTile(gid: UInt32, x: Int, y: Int, z: CGFloat, into container: SKNode) {
        guard gid > 0 else { return }
        let sprite = SKSpriteNode(texture: tileTexture(localID: Int(gid) - 1))
        sprite.size = CGSize(width: Self.tilePoints, height: Self.tilePoints)
        sprite.position = CGPoint(
            x: (CGFloat(x) + 0.5) * Self.tilePoints,
            y: -(CGFloat(y) + 0.5) * Self.tilePoints)
        sprite.zPosition = z
        container.addChild(sprite)
    }

    /// Sheet is 8×2, row 0 on top; SKTexture rects use bottom-left unit coords.
    private func tileTexture(localID: Int) -> SKTexture? {
        guard let tilesTexture else { return nil }
        let column = localID % 8
        let row = localID / 8
        let rect = CGRect(
            x: CGFloat(column) / 8, y: 1 - CGFloat(row + 1) * 0.5,
            width: 1.0 / 8, height: 0.5)
        return SKTexture(rect: rect, in: tilesTexture)
    }

    /// Avatar sheet: 4 facing columns (down/up/left/right) × 5 preset rows.
    private func avatarTexture(preset: String, facing: Facing) -> SKTexture? {
        guard let avatarsTexture else { return nil }
        let row = Self.presetOrder.firstIndex(of: preset) ?? 0
        let column: Int
        switch facing {
        case .down: column = 0
        case .up: column = 1
        case .left: column = 2
        case .right: column = 3
        }
        let rect = CGRect(
            x: CGFloat(column) / 4, y: 1 - CGFloat(row + 1) / 5,
            width: 1.0 / 4, height: 1.0 / 5)
        return SKTexture(rect: rect, in: avatarsTexture)
    }

    private func makeAvatarNode(name: String, preset: String) -> AvatarNode {
        AvatarNode(displayName: name)
    }

    static func point(forTile position: Vec2) -> CGPoint {
        CGPoint(x: position.x * tilePoints, y: -position.y * tilePoints)
    }
}

/// Body sprite + nameplate. Texture is swapped per facing by the scene.
final class AvatarNode: SKNode {
    private let body: SKSpriteNode
    private let nameplate: SKLabelNode
    private let speakingRing: SKShapeNode

    init(displayName: String) {
        body = SKSpriteNode(color: .systemTeal, size: CGSize(width: 32, height: 32))
        nameplate = SKLabelNode(text: displayName)
        speakingRing = SKShapeNode(circleOfRadius: 19)
        super.init()

        speakingRing.strokeColor = NSColor(srgbRed: 0.35, green: 0.95, blue: 0.55, alpha: 0.95)
        speakingRing.lineWidth = 2.5
        speakingRing.fillColor = .clear
        speakingRing.zPosition = 4
        speakingRing.isHidden = true
        addChild(speakingRing)

        nameplate.fontName = "Menlo-Bold"
        nameplate.fontSize = 11
        nameplate.fontColor = .white
        nameplate.position = CGPoint(x: 0, y: 22)
        nameplate.zPosition = 11

        let plateBackground = SKShapeNode(
            rectOf: CGSize(width: max(nameplate.frame.width + 10, 30), height: 16),
            cornerRadius: 8)
        plateBackground.fillColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
        plateBackground.strokeColor = .clear
        plateBackground.position = CGPoint(x: 0, y: 27)
        plateBackground.zPosition = 10

        body.zPosition = 5
        addChild(body)
        addChild(plateBackground)
        addChild(nameplate)
        zPosition = 5
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func setSpeaking(_ speaking: Bool) {
        speakingRing.isHidden = !speaking
    }

    func apply(point: CGPoint, facing: Facing, moving: Bool, texture: SKTexture?) {
        position = point
        if let texture {
            body.texture = texture
            body.color = .clear
        }
        // Subtle walk bob.
        body.yScale = moving ? 1.0 + 0.04 * sin(CACurrentMediaTime() * 14) : 1.0
    }
}
