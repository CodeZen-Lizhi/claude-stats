import AppKit
import SpriteKit

@MainActor
final class TokenTownScene: SKScene {
    private let tileSize: CGFloat = 12
    private let cameraNode = SKCameraNode()
    private var renderedRevision = ""
    var onSelect: ((TownEntitySelection?) -> Void)?
    var pausedAnimation = false {
        didSet { updateResidentAnimation() }
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = TokenTownPalette.background
        camera = cameraNode
        addChild(cameraNode)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func configure(map: TownMap, state: TownState) {
        let revision = [
            map.revisionID,
            state.placedItems.map { "\($0.id):\($0.kind.rawValue):\($0.footprint.origin.x):\($0.footprint.origin.y)" }.joined(separator: ","),
            "\(state.camera.scale)",
            state.residentMemory.lastActivity.rawValue,
        ].joined(separator: "#")
        guard revision != renderedRevision else {
            applyCamera(map: map, state: state)
            return
        }
        renderedRevision = revision
        removeAllChildren()
        addChild(cameraNode)
        size = CGSize(width: CGFloat(map.grid.width) * tileSize, height: CGFloat(map.grid.height) * tileSize)
        backgroundColor = TokenTownPalette.sky(for: map.weather)
        renderTiles(map.grid)
        renderBuildings(map.buildings)
        renderPlacedItems(state.placedItems)
        renderResident(map: map, state: state)
        renderVisitors(map: map, state: state)
        applyCamera(map: map, state: state)
    }

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let hit = nodes(at: location).first { $0.name != nil }
        if let name = hit?.name {
            if name == "resident:user" {
                onSelect?(.resident("user"))
                return
            }
            if name.hasPrefix("building:") {
                onSelect?(.building(String(name.dropFirst("building:".count))))
                return
            }
            if name.hasPrefix("item:") {
                onSelect?(.item(String(name.dropFirst("item:".count))))
                return
            }
        }
        let point = TownPoint(x: Int(location.x / tileSize), y: Int(location.y / tileSize))
        onSelect?(.tile(point))
    }

    private func renderTiles(_ grid: TownTileGrid) {
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let point = TownPoint(x: x, y: y)
                let node = SKSpriteNode(color: TokenTownPalette.color(for: grid[point]), size: CGSize(width: tileSize, height: tileSize))
                node.anchorPoint = .zero
                node.position = position(for: point)
                node.zPosition = 0
                addChild(node)

                if grid[point] == .road || grid[point] == .plaza {
                    let pebble = SKSpriteNode(color: TokenTownPalette.roadDetail, size: CGSize(width: 2, height: 2))
                    pebble.anchorPoint = .zero
                    pebble.position = CGPoint(x: node.position.x + CGFloat((x * 5 + y * 3) % 8), y: node.position.y + CGFloat((x * 2 + y * 7) % 8))
                    pebble.zPosition = 0.5
                    addChild(pebble)
                }
            }
        }
    }

    private func renderBuildings(_ buildings: [TownBuilding]) {
        for building in buildings where building.kind != .plaza {
            let node = SKSpriteNode(color: TokenTownPalette.building(for: building.kind), size: size(for: building.footprint))
            node.anchorPoint = .zero
            node.position = position(for: building.footprint.origin)
            node.zPosition = 10
            node.name = "building:\(building.id)"
            addChild(node)

            let roof = SKSpriteNode(color: TokenTownPalette.roof(for: building.kind), size: CGSize(width: size(for: building.footprint).width, height: tileSize * 0.55))
            roof.anchorPoint = .zero
            roof.position = CGPoint(x: node.position.x, y: node.position.y + size(for: building.footprint).height - tileSize * 0.55)
            roof.zPosition = 11
            roof.name = node.name
            addChild(roof)

            let door = SKSpriteNode(color: TokenTownPalette.door, size: CGSize(width: 5, height: 7))
            door.anchorPoint = .zero
            door.position = CGPoint(x: node.position.x + size(for: building.footprint).width / 2 - 2.5, y: node.position.y)
            door.zPosition = 12
            door.name = node.name
            addChild(door)
        }
    }

    private func renderPlacedItems(_ items: [TownPlacedItem]) {
        for item in items {
            let node = SKSpriteNode(color: TokenTownPalette.item(for: item.kind), size: size(for: item.footprint))
            node.anchorPoint = .zero
            node.position = position(for: item.footprint.origin)
            node.zPosition = 20
            node.name = "item:\(item.id)"
            addChild(node)

            if item.kind == .lamp {
                let glow = SKShapeNode(circleOfRadius: tileSize * 1.2)
                glow.fillColor = TokenTownPalette.lampGlow
                glow.strokeColor = .clear
                glow.position = CGPoint(x: node.position.x + tileSize / 2, y: node.position.y + tileSize / 2)
                glow.zPosition = 19
                glow.name = node.name
                addChild(glow)
            }
        }
    }

    private func renderResident(map: TownMap, state: TownState) {
        let resident = makeResidentNode(color: TokenTownPalette.resident, name: "resident:user")
        resident.position = position(for: map.spawnPoint).offsetBy(dx: tileSize / 2, dy: tileSize * 0.75)
        resident.zPosition = 40
        addChild(resident)
        updateResidentAnimation()
    }

    private func renderVisitors(map: TownMap, state: TownState) {
        let visitorCount = min(4, max(1, state.placedItems.count / 3 + map.snapshot.projects.count / 3))
        let roadPoints = map.roads.flatMap(\.points)
        guard !roadPoints.isEmpty else { return }
        for index in 0..<visitorCount {
            let point = roadPoints[(index * 17) % roadPoints.count]
            let visitor = makeResidentNode(color: TokenTownPalette.visitor(index: index), name: nil)
            visitor.position = position(for: point).offsetBy(dx: tileSize / 2, dy: tileSize * 0.7)
            visitor.zPosition = 35
            addChild(visitor)
            if !pausedAnimation {
                let bob = SKAction.sequence([
                    .moveBy(x: 0, y: 2, duration: 0.55 + Double(index) * 0.08),
                    .moveBy(x: 0, y: -2, duration: 0.55 + Double(index) * 0.08),
                ])
                visitor.run(.repeatForever(bob), withKey: "bob")
            }
        }
    }

    private func makeResidentNode(color: SKColor, name: String?) -> SKNode {
        let container = SKNode()
        container.name = name
        let body = SKSpriteNode(color: color, size: CGSize(width: 7, height: 9))
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        body.position = .zero
        body.name = name
        container.addChild(body)
        let face = SKSpriteNode(color: TokenTownPalette.face, size: CGSize(width: 5, height: 3))
        face.anchorPoint = CGPoint(x: 0.5, y: 0)
        face.position = CGPoint(x: 0, y: 5)
        face.name = name
        container.addChild(face)
        return container
    }

    private func updateResidentAnimation() {
        guard let resident = childNode(withName: "resident:user") else { return }
        resident.removeAction(forKey: "idle")
        guard !pausedAnimation else { return }
        let idle = SKAction.sequence([
            .moveBy(x: 0, y: 2, duration: 0.45),
            .moveBy(x: 0, y: -2, duration: 0.45),
            .wait(forDuration: 0.8),
        ])
        resident.run(.repeatForever(idle), withKey: "idle")
    }

    private func applyCamera(map: TownMap, state: TownState) {
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cameraNode.setScale(CGFloat(1 / max(0.65, min(2.4, state.camera.scale))))
    }

    private func position(for point: TownPoint) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * tileSize, y: CGFloat(point.y) * tileSize)
    }

    private func size(for rect: TownRect) -> CGSize {
        CGSize(width: CGFloat(rect.size.width) * tileSize, height: CGFloat(rect.size.height) * tileSize)
    }
}

private enum TokenTownPalette {
    static let background = SKColor(calibratedRed: 0.06, green: 0.07, blue: 0.08, alpha: 1)
    static let roadDetail = SKColor(calibratedRed: 0.55, green: 0.46, blue: 0.33, alpha: 0.55)
    static let door = SKColor(calibratedRed: 0.23, green: 0.15, blue: 0.10, alpha: 1)
    static let face = SKColor(calibratedRed: 0.95, green: 0.78, blue: 0.56, alpha: 1)
    static let resident = SKColor(calibratedRed: 0.28, green: 0.42, blue: 0.80, alpha: 1)
    static let lampGlow = SKColor(calibratedRed: 1.0, green: 0.75, blue: 0.28, alpha: 0.18)

    static func sky(for weather: TownWeather) -> SKColor {
        switch weather {
        case .clear: SKColor(calibratedRed: 0.08, green: 0.10, blue: 0.11, alpha: 1)
        case .drizzle: SKColor(calibratedRed: 0.08, green: 0.12, blue: 0.16, alpha: 1)
        case .rainClock: SKColor(calibratedRed: 0.05, green: 0.08, blue: 0.13, alpha: 1)
        case .lanternFog: SKColor(calibratedRed: 0.12, green: 0.10, blue: 0.08, alpha: 1)
        }
    }

    static func color(for tile: TownTileKind) -> SKColor {
        switch tile {
        case .meadow: SKColor(calibratedRed: 0.24, green: 0.38, blue: 0.24, alpha: 1)
        case .grove: SKColor(calibratedRed: 0.14, green: 0.28, blue: 0.18, alpha: 1)
        case .road: SKColor(calibratedRed: 0.46, green: 0.38, blue: 0.27, alpha: 1)
        case .plaza: SKColor(calibratedRed: 0.58, green: 0.52, blue: 0.40, alpha: 1)
        case .wall: SKColor(calibratedRed: 0.28, green: 0.28, blue: 0.31, alpha: 1)
        case .gate: SKColor(calibratedRed: 0.55, green: 0.40, blue: 0.25, alpha: 1)
        case .water: SKColor(calibratedRed: 0.14, green: 0.38, blue: 0.53, alpha: 1)
        case .buildingFloor: SKColor(calibratedRed: 0.43, green: 0.32, blue: 0.26, alpha: 1)
        case .garden: SKColor(calibratedRed: 0.28, green: 0.45, blue: 0.22, alpha: 1)
        }
    }

    static func building(for kind: TownBuildingKind) -> SKColor {
        switch kind {
        case .archiveHut: SKColor(calibratedRed: 0.58, green: 0.48, blue: 0.34, alpha: 1)
        case .workshop: SKColor(calibratedRed: 0.48, green: 0.42, blue: 0.50, alpha: 1)
        case .marketStall: SKColor(calibratedRed: 0.58, green: 0.34, blue: 0.32, alpha: 1)
        case .cacheWell: SKColor(calibratedRed: 0.26, green: 0.45, blue: 0.55, alpha: 1)
        case .cottage: SKColor(calibratedRed: 0.54, green: 0.43, blue: 0.32, alpha: 1)
        case .gardenHouse: SKColor(calibratedRed: 0.38, green: 0.49, blue: 0.32, alpha: 1)
        case .plaza: SKColor(calibratedRed: 0.58, green: 0.52, blue: 0.40, alpha: 1)
        }
    }

    static func roof(for kind: TownBuildingKind) -> SKColor {
        switch kind {
        case .workshop: SKColor(calibratedRed: 0.30, green: 0.28, blue: 0.38, alpha: 1)
        case .marketStall: SKColor(calibratedRed: 0.74, green: 0.24, blue: 0.20, alpha: 1)
        case .cacheWell: SKColor(calibratedRed: 0.12, green: 0.27, blue: 0.42, alpha: 1)
        default: SKColor(calibratedRed: 0.36, green: 0.18, blue: 0.12, alpha: 1)
        }
    }

    static func item(for kind: TownItemKind) -> SKColor {
        switch kind {
        case .lamp: SKColor(calibratedRed: 0.95, green: 0.65, blue: 0.22, alpha: 1)
        case .tree: SKColor(calibratedRed: 0.10, green: 0.35, blue: 0.18, alpha: 1)
        case .signpost: SKColor(calibratedRed: 0.62, green: 0.44, blue: 0.24, alpha: 1)
        case .bench: SKColor(calibratedRed: 0.48, green: 0.27, blue: 0.18, alpha: 1)
        case .cacheWell: SKColor(calibratedRed: 0.10, green: 0.43, blue: 0.58, alpha: 1)
        case .archiveHut: building(for: .archiveHut)
        case .workshop: building(for: .workshop)
        case .marketStall: building(for: .marketStall)
        case .bridge: SKColor(calibratedRed: 0.52, green: 0.38, blue: 0.24, alpha: 1)
        case .garden: SKColor(calibratedRed: 0.36, green: 0.55, blue: 0.25, alpha: 1)
        }
    }

    static func visitor(index: Int) -> SKColor {
        [
            SKColor(calibratedRed: 0.70, green: 0.33, blue: 0.28, alpha: 1),
            SKColor(calibratedRed: 0.25, green: 0.56, blue: 0.48, alpha: 1),
            SKColor(calibratedRed: 0.70, green: 0.58, blue: 0.25, alpha: 1),
            SKColor(calibratedRed: 0.42, green: 0.35, blue: 0.68, alpha: 1),
        ][index % 4]
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}
