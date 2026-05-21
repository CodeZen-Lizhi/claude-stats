import Foundation

struct TownPoint: Codable, Hashable, Sendable, Comparable {
    var x: Int
    var y: Int

    static func < (lhs: TownPoint, rhs: TownPoint) -> Bool {
        lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
    }

    func offset(dx: Int, dy: Int) -> TownPoint {
        TownPoint(x: x + dx, y: y + dy)
    }

    func manhattanDistance(to other: TownPoint) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }

    var cardinalNeighbors: [TownPoint] {
        [
            offset(dx: 1, dy: 0),
            offset(dx: -1, dy: 0),
            offset(dx: 0, dy: 1),
            offset(dx: 0, dy: -1),
        ]
    }
}

struct TownSize: Codable, Hashable, Sendable {
    var width: Int
    var height: Int
}

struct TownRect: Codable, Hashable, Sendable {
    var origin: TownPoint
    var size: TownSize

    var minX: Int { origin.x }
    var minY: Int { origin.y }
    var maxX: Int { origin.x + size.width - 1 }
    var maxY: Int { origin.y + size.height - 1 }
    var center: TownPoint {
        TownPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    func contains(_ point: TownPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    var points: [TownPoint] {
        guard size.width > 0, size.height > 0 else { return [] }
        return (minY...maxY).flatMap { y in
            (minX...maxX).map { x in TownPoint(x: x, y: y) }
        }
    }

    func expanded(by amount: Int) -> TownRect {
        TownRect(
            origin: TownPoint(x: origin.x - amount, y: origin.y - amount),
            size: TownSize(width: size.width + amount * 2, height: size.height + amount * 2)
        )
    }
}

enum TownTileKind: String, Codable, Hashable, Sendable {
    case meadow
    case grove
    case road
    case plaza
    case wall
    case gate
    case water
    case buildingFloor
    case garden

    var isWalkable: Bool {
        switch self {
        case .meadow, .grove, .road, .plaza, .gate, .garden:
            return true
        case .wall, .water, .buildingFloor:
            return false
        }
    }

    var isBuildableGround: Bool {
        switch self {
        case .meadow, .grove, .garden:
            return true
        case .road, .plaza, .wall, .gate, .water, .buildingFloor:
            return false
        }
    }
}

struct TownTileGrid: Codable, Hashable, Sendable {
    let width: Int
    let height: Int
    var tiles: [TownTileKind]

    init(width: Int, height: Int, fill: TownTileKind = .meadow) {
        self.width = width
        self.height = height
        self.tiles = Array(repeating: fill, count: width * height)
    }

    var size: TownSize { TownSize(width: width, height: height) }

    func contains(_ point: TownPoint) -> Bool {
        point.x >= 0 && point.x < width && point.y >= 0 && point.y < height
    }

    func index(for point: TownPoint) -> Int {
        point.y * width + point.x
    }

    subscript(_ point: TownPoint) -> TownTileKind {
        get {
            guard contains(point) else { return .wall }
            return tiles[index(for: point)]
        }
        set {
            guard contains(point) else { return }
            tiles[index(for: point)] = newValue
        }
    }

    mutating func fill(_ rect: TownRect, with kind: TownTileKind) {
        for point in rect.points where contains(point) {
            self[point] = kind
        }
    }
}

enum TownDistrictKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case plaza
    case archive
    case workshop
    case market
    case garden
    case cache
    case homes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plaza: "Plaza"
        case .archive: "Archive Ward"
        case .workshop: "Workshop Ward"
        case .market: "Market Ward"
        case .garden: "Garden Ward"
        case .cache: "Cache Ward"
        case .homes: "Homes"
        }
    }
}

enum TownBuildingKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case plaza
    case archiveHut
    case workshop
    case marketStall
    case cacheWell
    case cottage
    case gardenHouse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plaza: "Central Plaza"
        case .archiveHut: "Archive Hut"
        case .workshop: "Workshop"
        case .marketStall: "Market Stall"
        case .cacheWell: "Cache Well"
        case .cottage: "Quiet Cottage"
        case .gardenHouse: "Garden House"
        }
    }
}

struct TownPatch: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let center: TownPoint
    var district: TownDistrictKind
    var cells: [TownPoint]
}

struct TownRoadEdge: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let from: TownPoint
    let to: TownPoint
    let points: [TownPoint]
    let isPrimary: Bool
}

struct TownBuilding: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: TownBuildingKind
    let district: TownDistrictKind
    let footprint: TownRect
    let entrance: TownPoint
    let tokenWeight: Int
    let sourceLabel: String?

    var displayName: String {
        sourceLabel.map { "\(kind.displayName): \($0)" } ?? kind.displayName
    }
}

enum TownAffordance: String, Codable, CaseIterable, Hashable, Sendable {
    case rest
    case work
    case browse
    case repair
    case celebrate
    case cache
    case garden
    case wander
}

enum TownItemKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case lamp
    case tree
    case signpost
    case bench
    case cacheWell
    case archiveHut
    case workshop
    case marketStall
    case bridge
    case garden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lamp: "Lamp"
        case .tree: "Tree"
        case .signpost: "Signpost"
        case .bench: "Bench"
        case .cacheWell: "Cache Well"
        case .archiveHut: "Archive Hut"
        case .workshop: "Workshop"
        case .marketStall: "Market Stall"
        case .bridge: "Bridge"
        case .garden: "Garden"
        }
    }

    var systemSymbol: String {
        switch self {
        case .lamp: "lightbulb"
        case .tree: "tree"
        case .signpost: "signpost.right"
        case .bench: "rectangle.and.hand.point.up.left"
        case .cacheWell: "drop"
        case .archiveHut: "archivebox"
        case .workshop: "hammer"
        case .marketStall: "storefront"
        case .bridge: "road.lanes"
        case .garden: "leaf"
        }
    }
}

struct TownShopItem: Codable, Hashable, Sendable, Identifiable {
    let kind: TownItemKind
    let cost: Int
    let footprint: TownSize
    let tags: [String]
    let affordances: [TownAffordance]

    var id: TownItemKind { kind }

    static let catalog: [TownShopItem] = [
        TownShopItem(kind: .lamp, cost: 8, footprint: TownSize(width: 1, height: 1), tags: ["light"], affordances: [.wander, .celebrate]),
        TownShopItem(kind: .tree, cost: 10, footprint: TownSize(width: 1, height: 1), tags: ["shade"], affordances: [.rest, .garden]),
        TownShopItem(kind: .signpost, cost: 12, footprint: TownSize(width: 1, height: 1), tags: ["wayfinding"], affordances: [.browse, .wander]),
        TownShopItem(kind: .bench, cost: 16, footprint: TownSize(width: 2, height: 1), tags: ["rest"], affordances: [.rest]),
        TownShopItem(kind: .cacheWell, cost: 24, footprint: TownSize(width: 2, height: 2), tags: ["cache"], affordances: [.cache, .browse]),
        TownShopItem(kind: .archiveHut, cost: 32, footprint: TownSize(width: 3, height: 2), tags: ["archive"], affordances: [.work, .browse]),
        TownShopItem(kind: .workshop, cost: 42, footprint: TownSize(width: 3, height: 2), tags: ["work"], affordances: [.work, .repair]),
        TownShopItem(kind: .marketStall, cost: 36, footprint: TownSize(width: 3, height: 2), tags: ["market"], affordances: [.browse, .celebrate]),
        TownShopItem(kind: .bridge, cost: 28, footprint: TownSize(width: 3, height: 1), tags: ["path"], affordances: [.wander, .repair]),
        TownShopItem(kind: .garden, cost: 20, footprint: TownSize(width: 2, height: 2), tags: ["garden"], affordances: [.garden, .rest]),
    ]

    static func item(for kind: TownItemKind) -> TownShopItem? {
        catalog.first { $0.kind == kind }
    }
}

struct TownPlacedItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: TownItemKind
    let footprint: TownRect
    let purchasedAt: Date

    var center: TownPoint { footprint.center }
}

enum TownResidentActivity: String, Codable, CaseIterable, Hashable, Sendable {
    case work
    case rest
    case wander
    case inspect
    case shop
    case repair
    case celebrate

    var displayName: String {
        switch self {
        case .work: "Working"
        case .rest: "Resting"
        case .wander: "Wandering"
        case .inspect: "Inspecting"
        case .shop: "Shopping"
        case .repair: "Repairing"
        case .celebrate: "Celebrating"
        }
    }
}

struct TownResidentMemory: Codable, Hashable, Sendable {
    var lastActivity: TownResidentActivity
    var thought: String
    var visitedEntityID: String?
}

enum TownWeather: String, Codable, Hashable, Sendable {
    case clear
    case drizzle
    case rainClock
    case lanternFog

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .drizzle: "Drizzle"
        case .rainClock: "Rain Clock"
        case .lanternFog: "Lantern Fog"
        }
    }
}

struct TownProjectUsage: Codable, Hashable, Sendable {
    let name: String
    let effectiveTokens: Int
    let sessionCount: Int
}

struct TownModelUsage: Codable, Hashable, Sendable {
    let model: String
    let effectiveTokens: Int
}

struct TownUsageSnapshot: Codable, Hashable, Sendable {
    let provider: ProviderKind
    let period: StatsPeriod
    let sessionCount: Int
    let messageCount: Int
    let effectiveTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let outputTokens: Int
    let todayEffectiveTokens: Int
    let todayCacheReadTokens: Int
    let projects: [TownProjectUsage]
    let models: [TownModelUsage]
    let timelineBuckets: [Int]

    var isEmpty: Bool { sessionCount == 0 || effectiveTokens == 0 }
    var cacheIntensity: Double {
        guard effectiveTokens + cacheReadTokens > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(effectiveTokens + cacheReadTokens)
    }

    var fingerprint: String {
        [
            provider.rawValue,
            period.rawValue,
            "\(sessionCount)",
            "\(messageCount)",
            "\(effectiveTokens)",
            "\(cacheReadTokens)",
            "\(cacheCreationTokens)",
            "\(outputTokens)",
            "\(todayEffectiveTokens)",
            projects.map { "\($0.name):\($0.effectiveTokens):\($0.sessionCount)" }.joined(separator: ","),
            models.map { "\($0.model):\($0.effectiveTokens)" }.joined(separator: ","),
            timelineBuckets.map(String.init).joined(separator: ","),
        ].joined(separator: "|")
    }

    static let empty = TownUsageSnapshot(
        provider: .claude,
        period: .allTime,
        sessionCount: 0,
        messageCount: 0,
        effectiveTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        outputTokens: 0,
        todayEffectiveTokens: 0,
        todayCacheReadTokens: 0,
        projects: [],
        models: [],
        timelineBuckets: []
    )
}

struct TownParams: Codable, Hashable, Sendable {
    var seed: UInt64
    var size: TownSize
    var patchCount: Int
    var roadWidth: Int
    var density: Double
    var irregularity: Double
    var wallChance: Double
    var maxAttempts: Int

    static func from(snapshot: TownUsageSnapshot, state: TownState) -> TownParams {
        let activity = max(snapshot.effectiveTokens, 1)
        let width = snapshot.isEmpty ? 58 : min(86, 58 + Int(log10(Double(activity) + 1) * 5))
        let height = snapshot.isEmpty ? 38 : min(58, 38 + Int(log10(Double(activity) + 1) * 3))
        let patchCount = snapshot.isEmpty ? 14 : min(34, max(18, snapshot.projects.count * 3 + snapshot.models.count * 2 + 12))
        return TownParams(
            seed: state.seed ^ TownHasher.hash(snapshot.fingerprint),
            size: TownSize(width: width, height: height),
            patchCount: patchCount,
            roadWidth: snapshot.effectiveTokens > 400_000 ? 2 : 1,
            density: min(0.85, 0.35 + Double(snapshot.sessionCount) / 80.0),
            irregularity: min(0.9, 0.25 + snapshot.cacheIntensity),
            wallChance: snapshot.effectiveTokens > 60_000 ? 0.85 : 0.35,
            maxAttempts: 5
        )
    }
}

struct TownValidationReport: Codable, Hashable, Sendable {
    var graphReachable: Bool
    var tileReachable: Bool
    var blockedEntrances: [String]
    var repairedRoads: Int

    var ok: Bool {
        graphReachable && tileReachable && blockedEntrances.isEmpty
    }

    static let empty = TownValidationReport(
        graphReachable: false,
        tileReachable: false,
        blockedEntrances: [],
        repairedRoads: 0
    )
}

struct TownMap: Codable, Hashable, Sendable {
    let params: TownParams
    let snapshot: TownUsageSnapshot
    let grid: TownTileGrid
    let patches: [TownPatch]
    let roads: [TownRoadEdge]
    let buildings: [TownBuilding]
    let plaza: TownRect
    let gates: [TownPoint]
    let spawnPoint: TownPoint
    let weather: TownWeather
    let secrets: [String]
    let validation: TownValidationReport

    var revisionID: String {
        [
            "\(params.seed)",
            snapshot.fingerprint,
            grid.tiles.map(\.rawValue).joined(separator: ","),
            buildings.map { "\($0.id):\($0.footprint.origin.x):\($0.footprint.origin.y)" }.joined(separator: ","),
            secrets.joined(separator: ","),
        ].joined(separator: "#")
    }
}

struct TownLedgerDayKey: Codable, Hashable, Sendable, Comparable {
    let provider: ProviderKind
    let day: String

    static func < (lhs: TownLedgerDayKey, rhs: TownLedgerDayKey) -> Bool {
        lhs.provider.rawValue == rhs.provider.rawValue
            ? lhs.day < rhs.day
            : lhs.provider.rawValue < rhs.provider.rawValue
    }

    static func make(provider: ProviderKind, date: Date, calendar: Calendar = .current) -> TownLedgerDayKey {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return TownLedgerDayKey(provider: provider, day: String(format: "%04d-%02d-%02d", year, month, day))
    }
}

struct TownLedgerEntry: Codable, Hashable, Sendable {
    var effectiveTokens: Int
    var coinsMinted: Int
}

struct TownEconomyLedger: Codable, Hashable, Sendable {
    var days: [TownLedgerDayKey: TownLedgerEntry] = [:]
}

struct TownCameraState: Codable, Hashable, Sendable {
    var centerX: Double?
    var centerY: Double?
    var scale: Double

    init(centerX: Double? = nil, centerY: Double? = nil, scale: Double = 1) {
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
    }
}

struct TownState: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var seed: UInt64 = 0xC0DE_570A_7A11
    var balance: Int = 0
    var spent: Int = 0
    var ledger: TownEconomyLedger = TownEconomyLedger()
    var placedItems: [TownPlacedItem] = []
    var discoveredSecrets: Set<String> = []
    var residentMemory: TownResidentMemory = TownResidentMemory(
        lastActivity: .wander,
        thought: "The town is waking up.",
        visitedEntityID: nil
    )
    var camera: TownCameraState = TownCameraState()

    static let empty = TownState()

    var purchasedCount: Int { placedItems.count }
}

enum TownEntitySelection: Codable, Hashable, Sendable {
    case building(String)
    case item(String)
    case resident(String)
    case tile(TownPoint)
}

enum TownHasher {
    static func hash(_ string: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
        return value
    }
}
