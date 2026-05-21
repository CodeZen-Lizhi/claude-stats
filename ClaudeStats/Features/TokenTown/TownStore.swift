import Foundation
import Observation

@MainActor
@Observable
final class TownStore {
    var period: StatsPeriod = .last7Days
    var selectedEntity: TownEntitySelection?
    var shopPresented = false
    var isPaused = false

    private(set) var state: TownState = .empty
    private(set) var map: TownMap?
    private(set) var isLoading = false
    private(set) var lastMintedCoins = 0
    private(set) var lastError: String?

    @ObservationIgnored private let pricing: ModelPricing
    @ObservationIgnored private let stateStore: any TownStateStoring
    @ObservationIgnored private var hasLoadedState = false

    init(pricing: ModelPricing, stateStore: any TownStateStoring = TownStateStore()) {
        self.pricing = pricing
        self.stateStore = stateStore
    }

    var shopItems: [TownShopItem] { TownShopItem.catalog }

    var balanceText: String {
        "\(state.balance)"
    }

    var selectedBuilding: TownBuilding? {
        guard case .building(let id) = selectedEntity else { return nil }
        return map?.buildings.first { $0.id == id }
    }

    var selectedPlacedItem: TownPlacedItem? {
        guard case .item(let id) = selectedEntity else { return nil }
        return state.placedItems.first { $0.id == id }
    }

    func loadIfNeeded(from sessionStore: SessionStore, provider: ProviderKind, now: Date = .now) async {
        if !hasLoadedState {
            state = await stateStore.readState()
            hasLoadedState = true
        }
        await refresh(from: sessionStore, provider: provider, now: now)
    }

    func refresh(from sessionStore: SessionStore, provider: ProviderKind, now: Date = .now) async {
        if !hasLoadedState {
            state = await stateStore.readState()
            hasLoadedState = true
        }
        let snapshot = TownUsageSnapshotBuilder.make(
            provider: provider,
            period: period,
            sessions: sessionStore.sessions,
            pricing: pricing,
            now: now
        )
        var nextState = state
        let minted = TownEconomy.reconcile(
            state: &nextState,
            provider: provider,
            day: now,
            effectiveTokens: snapshot.todayEffectiveTokens
        )
        if minted > 0 {
            nextState.residentMemory = residentMemory(
                snapshot: snapshot,
                activity: .celebrate,
                targetID: nil,
                extra: "Minted \(minted) town coins from today's new tokens."
            )
        } else {
            nextState.residentMemory = residentMemory(snapshot: snapshot, activity: chooseActivity(snapshot: snapshot, state: nextState), targetID: nil)
        }

        let params = TownParams.from(snapshot: snapshot, state: nextState)
        isLoading = true
        lastError = nil
        let generated = await Task.detached(priority: .userInitiated) {
            TownMapGenerator.generate(params: params, snapshot: snapshot, state: nextState)
        }.value
        state = nextState
        map = generated
        lastMintedCoins = minted
        isLoading = false
        selectedEntity = selectedEntityStillExists(selectedEntity, in: generated, state: nextState) ? selectedEntity : nil
        await stateStore.writeState(nextState)
    }

    func buy(_ item: TownShopItem) {
        guard state.balance >= item.cost else {
            lastError = "Not enough coins for \(item.kind.displayName)."
            return
        }
        guard let map else {
            lastError = "The town is still generating."
            return
        }
        guard let footprint = suggestedPlacement(for: item, map: map, state: state) else {
            lastError = "No open lot near a road yet."
            return
        }

        let placed = TownPlacedItem(
            id: "item-\(UUID().uuidString)",
            kind: item.kind,
            footprint: footprint,
            purchasedAt: .now
        )
        state.balance -= item.cost
        state.spent += item.cost
        state.placedItems.append(placed)
        state.residentMemory = residentMemory(
            snapshot: map.snapshot,
            activity: item.affordances.contains(.work) ? .work : .inspect,
            targetID: placed.id,
            extra: "\(item.kind.displayName) is now part of the town."
        )
        selectedEntity = .item(placed.id)
        lastError = nil
        persistState()
    }

    func resetLayout() {
        state.placedItems.removeAll()
        state.discoveredSecrets.removeAll()
        state.residentMemory = TownResidentMemory(
            lastActivity: .wander,
            thought: "The town square has room to breathe again.",
            visitedEntityID: nil
        )
        selectedEntity = nil
        persistState()
    }

    func setCameraScale(_ scale: Double) {
        state.camera.scale = min(2.4, max(0.65, scale))
        persistState()
    }

    func select(_ selection: TownEntitySelection?) {
        selectedEntity = selection
    }

    func discover(_ secret: String) {
        guard !secret.isEmpty else { return }
        state.discoveredSecrets.insert(secret)
        persistState()
    }

    private func persistState() {
        let nextState = state
        Task { [stateStore] in
            await stateStore.writeState(nextState)
        }
    }

    private func selectedEntityStillExists(_ selection: TownEntitySelection?, in map: TownMap, state: TownState) -> Bool {
        guard let selection else { return false }
        switch selection {
        case .building(let id):
            return map.buildings.contains { $0.id == id }
        case .item(let id):
            return state.placedItems.contains { $0.id == id }
        case .resident:
            return true
        case .tile(let point):
            return map.grid.contains(point)
        }
    }

    private func suggestedPlacement(for item: TownShopItem, map: TownMap, state: TownState) -> TownRect? {
        let occupied = occupiedPoints(map: map, state: state)
        let roads = roadPoints(in: map.grid)
        for road in roads {
            let candidates = candidateRects(around: road, size: item.footprint)
            for rect in candidates where canPlace(item: item, rect: rect, map: map, occupied: occupied) {
                return rect
            }
        }
        return nil
    }

    private func roadPoints(in grid: TownTileGrid) -> [TownPoint] {
        var points: [TownPoint] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let point = TownPoint(x: x, y: y)
                if grid[point] == .road || grid[point] == .plaza || grid[point] == .gate {
                    points.append(point)
                }
            }
        }
        return points.sorted { lhs, rhs in
            let center = TownPoint(x: grid.width / 2, y: grid.height / 2)
            let ld = lhs.manhattanDistance(to: center)
            let rd = rhs.manhattanDistance(to: center)
            return ld == rd ? lhs < rhs : ld < rd
        }
    }

    private func candidateRects(around point: TownPoint, size: TownSize) -> [TownRect] {
        [
            TownRect(origin: TownPoint(x: point.x + 1, y: point.y - size.height / 2), size: size),
            TownRect(origin: TownPoint(x: point.x - size.width, y: point.y - size.height / 2), size: size),
            TownRect(origin: TownPoint(x: point.x - size.width / 2, y: point.y + 1), size: size),
            TownRect(origin: TownPoint(x: point.x - size.width / 2, y: point.y - size.height), size: size),
        ]
    }

    private func canPlace(item: TownShopItem, rect: TownRect, map: TownMap, occupied: Set<TownPoint>) -> Bool {
        guard rect.points.allSatisfy({ map.grid.contains($0) && !occupied.contains($0) }) else { return false }
        let allowsWater = item.kind == .bridge
        let cellsOK = rect.points.allSatisfy { point in
            let tile = map.grid[point]
            return allowsWater ? (tile == .water || tile.isBuildableGround) : tile.isBuildableGround
        }
        guard cellsOK else { return false }
        return rect.expanded(by: 1).points.contains { point in
            map.grid.contains(point) && map.grid[point].isWalkable
        }
    }

    private func occupiedPoints(map: TownMap, state: TownState) -> Set<TownPoint> {
        var occupied = Set<TownPoint>()
        for building in map.buildings where building.kind != .plaza {
            occupied.formUnion(building.footprint.points)
        }
        for item in state.placedItems {
            occupied.formUnion(item.footprint.points)
        }
        return occupied
    }

    private func chooseActivity(snapshot: TownUsageSnapshot, state: TownState) -> TownResidentActivity {
        if state.placedItems.contains(where: { $0.kind == .workshop }) && snapshot.todayEffectiveTokens > 20_000 { return .work }
        if state.placedItems.contains(where: { $0.kind == .bench }) { return .rest }
        if snapshot.cacheReadTokens > snapshot.effectiveTokens { return .inspect }
        if state.balance > 40 { return .shop }
        return .wander
    }

    private func residentMemory(
        snapshot: TownUsageSnapshot,
        activity: TownResidentActivity,
        targetID: String?,
        extra: String? = nil
    ) -> TownResidentMemory {
        let thought: String
        if let extra {
            thought = extra
        } else if snapshot.isEmpty {
            thought = "The streets are quiet. A future session can light the first windows."
        } else {
            switch activity {
            case .work:
                thought = "The workshops are humming on \(Format.tokens(snapshot.todayEffectiveTokens)) fresh tokens today."
            case .rest:
                thought = "A bench beside the road makes the whole town feel less hurried."
            case .wander:
                thought = "I am tracing the roads between \(snapshot.projects.count) project wards."
            case .inspect:
                thought = "The cache wells are reflecting old context without spending it twice."
            case .shop:
                thought = "There are enough coins for one small improvement."
            case .repair:
                thought = "A little path repair keeps every doorway connected."
            case .celebrate:
                thought = "The plaza has a tiny festival mood today."
            }
        }
        return TownResidentMemory(lastActivity: activity, thought: thought, visitedEntityID: targetID)
    }
}
