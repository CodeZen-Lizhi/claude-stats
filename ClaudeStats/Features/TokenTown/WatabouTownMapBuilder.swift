import Foundation

enum WatabouTownMapBuilder {
    static func build(params: TownParams, snapshot: TownUsageSnapshot, state: TownState) -> TownMap {
        var builder = Builder(params: params, snapshot: snapshot, state: state)
        return builder.build()
    }
}

private struct Builder {
    private let params: TownParams
    private let snapshot: TownUsageSnapshot
    private let state: TownState
    private var rng: TownRandom

    init(params: TownParams, snapshot: TownUsageSnapshot, state: TownState) {
        self.params = params
        self.snapshot = snapshot
        self.state = state
        self.rng = TownRandom(seed: params.seed)
    }

    mutating func build() -> TownMap {
        var grid = TownTileGrid(width: params.size.width, height: params.size.height, fill: .meadow)
        sprinkleGroves(in: &grid)

        let plaza = TownRect(
            origin: TownPoint(x: params.size.width / 2 - 4, y: params.size.height / 2 - 3),
            size: TownSize(width: 9, height: 7)
        )

        var patches = makePatches(plaza: plaza)
        let innerCells = Set(patches.filter(\.withinCity).flatMap(\.cells))
        let boundary = cityBoundary(in: innerCells, grid: grid)
        let gates = makeGates(from: boundary, center: plaza.center)
        if rng.bool(probability: params.wallChance) {
            drawWall(boundary: boundary, gates: gates, in: &grid)
        }

        grid.fill(plaza, with: .plaza)

        var roads: [TownRoadEdge] = []
        for gate in gates {
            if let path = shortestPath(from: gate, to: plaza.center, in: grid) {
                carveRoad(path, in: &grid, width: params.roadWidth, kind: .road)
                roads.append(TownRoadEdge(id: roads.count, from: gate, to: plaza.center, points: path, isPrimary: true))
            }
        }
        grid.fill(plaza, with: .plaza)

        let patchRoadTargets = patches
            .filter { $0.withinCity && $0.id != 0 }
            .sorted { lhs, rhs in
                let ld = lhs.center.manhattanDistance(to: plaza.center)
                let rd = rhs.center.manhattanDistance(to: plaza.center)
                return ld == rd ? lhs.id < rhs.id : ld < rd
            }
            .prefix(max(6, min(params.patchCount, params.patchCount / 2 + snapshot.projects.count + snapshot.models.count)))

        for patch in patchRoadTargets {
            let target = nearestRoad(to: patch.center, in: grid) ?? plaza.center
            if let path = shortestPath(from: patch.center, to: target, in: grid) {
                carveRoad(path, in: &grid, width: max(0, params.roadWidth - 1), kind: .road)
                roads.append(TownRoadEdge(id: roads.count, from: patch.center, to: target, points: path, isPrimary: false))
            }
        }
        grid.fill(plaza, with: .plaza)

        carveCacheWater(in: &grid)

        let buildings = makeBuildings(grid: &grid, patches: patches, plaza: plaza)
        patches = patches.map { patch in
            patch.id == 0 ? patch.withCells(plaza.points) : patch
        }

        let allBuildings = [
            TownBuilding(
                id: "plaza",
                kind: .plaza,
                district: .plaza,
                footprint: plaza,
                entrance: plaza.center,
                tokenWeight: snapshot.effectiveTokens,
                sourceLabel: nil
            ),
        ] + buildings

        var report = validate(grid: grid, plaza: plaza, gates: gates, buildings: allBuildings)
        if !report.ok {
            repairEntrances(in: &grid, plaza: plaza, buildings: allBuildings, report: &report)
            report = validate(grid: grid, plaza: plaza, gates: gates, buildings: allBuildings, repairedRoads: report.repairedRoads)
        }

        return TownMap(
            params: params,
            snapshot: snapshot,
            grid: grid,
            patches: patches.map(\.townPatch),
            roads: roads,
            buildings: allBuildings,
            plaza: plaza,
            gates: gates,
            spawnPoint: gates.first ?? plaza.center,
            weather: weather(),
            secrets: secrets(),
            validation: report
        )
    }

    private mutating func makePatches(plaza: TownRect) -> [WatabouPatch] {
        let totalCount = max(params.patchCount + 8, Int(Double(params.patchCount) * 1.45))
        let centers = spiralCenters(count: totalCount)
        let districts = districtSequence()

        var cellsByPatch: [[TownPoint]] = Array(repeating: [], count: centers.count)
        for y in 2..<(params.size.height - 2) {
            for x in 2..<(params.size.width - 2) {
                let point = TownPoint(x: x, y: y)
                let nearest = centers.indices.min { lhs, rhs in
                    weightedDistance(point, centers[lhs]) < weightedDistance(point, centers[rhs])
                } ?? 0
                cellsByPatch[nearest].append(point)
            }
        }

        return centers.indices.map { index in
            WatabouPatch(
                id: index,
                center: centroid(of: cellsByPatch[index], fallback: centers[index]),
                district: index == 0 ? .plaza : districts[(index - 1) % districts.count],
                cells: cellsByPatch[index],
                withinCity: index < params.patchCount,
                withinWalls: index < params.patchCount && params.wallChance > 0.5
            )
        }
    }

    private mutating func spiralCenters(count: Int) -> [TownPoint] {
        let center = TownPoint(x: params.size.width / 2, y: params.size.height / 2)
        var values: [TownPoint] = [center]
        let startAngle = rng.double(in: 0...(Double.pi * 2))
        let maxRadiusX = Double(params.size.width - 8) / 2
        let maxRadiusY = Double(params.size.height - 8) / 2
        let goldenAngle = Double.pi * (3 - sqrt(5))

        for index in 1..<(count * 3) {
            let progress = sqrt(Double(index) / Double(max(1, count * 3 - 1)))
            let angle = startAngle + Double(index) * goldenAngle + rng.double(in: -0.12...0.12)
            let x = center.x + Int((cos(angle) * maxRadiusX * progress).rounded())
            let y = center.y + Int((sin(angle) * maxRadiusY * progress).rounded())
            let point = TownPoint(
                x: min(params.size.width - 4, max(3, x)),
                y: min(params.size.height - 4, max(3, y))
            )
            if !values.contains(point) {
                values.append(point)
            }
            if values.count >= count { break }
        }

        return values.sorted { lhs, rhs in
            let ld = weightedDistance(lhs, center)
            let rd = weightedDistance(rhs, center)
            return ld == rd ? lhs < rhs : ld < rd
        }
    }

    private func weightedDistance(_ lhs: TownPoint, _ rhs: TownPoint) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dy = Double(lhs.y - rhs.y)
        return dx * dx * 1.15 + dy * dy
    }

    private func centroid(of cells: [TownPoint], fallback: TownPoint) -> TownPoint {
        guard !cells.isEmpty else { return fallback }
        let x = cells.reduce(0) { $0 + $1.x } / cells.count
        let y = cells.reduce(0) { $0 + $1.y } / cells.count
        return TownPoint(x: x, y: y)
    }

    private func cityBoundary(in innerCells: Set<TownPoint>, grid: TownTileGrid) -> [TownPoint] {
        innerCells
            .filter { point in
                point.cardinalNeighbors.contains { !innerCells.contains($0) || !grid.contains($0) }
            }
            .sorted()
    }

    private mutating func makeGates(from boundary: [TownPoint], center: TownPoint) -> [TownPoint] {
        guard !boundary.isEmpty else {
            return [
                TownPoint(x: params.size.width / 2, y: 2),
                TownPoint(x: params.size.width / 2, y: params.size.height - 3),
            ]
        }

        let south = boundary.min { lhs, rhs in lhs.y == rhs.y ? abs(lhs.x - center.x) < abs(rhs.x - center.x) : lhs.y < rhs.y }
        let north = boundary.max { lhs, rhs in lhs.y == rhs.y ? abs(lhs.x - center.x) > abs(rhs.x - center.x) : lhs.y < rhs.y }
        let west = boundary.min { lhs, rhs in lhs.x == rhs.x ? abs(lhs.y - center.y) < abs(rhs.y - center.y) : lhs.x < rhs.x }
        let east = boundary.max { lhs, rhs in lhs.x == rhs.x ? abs(lhs.y - center.y) > abs(rhs.y - center.y) : lhs.x < rhs.x }
        var gates = [south, north, west, east].compactMap(\.self)

        gates = gates.reduce(into: []) { result, gate in
            guard result.allSatisfy({ $0.manhattanDistance(to: gate) > 5 }) else { return }
            result.append(gate)
        }

        if gates.count < 2 {
            gates.append(contentsOf: boundary.shuffledStable(rng: &rng).prefix(2))
        }
        return Array(Set(gates)).sorted()
    }

    private func drawWall(boundary: [TownPoint], gates: [TownPoint], in grid: inout TownTileGrid) {
        let gateSet = Set(gates.flatMap { [$0, $0.offset(dx: 1, dy: 0), $0.offset(dx: -1, dy: 0), $0.offset(dx: 0, dy: 1), $0.offset(dx: 0, dy: -1)] })
        for point in boundary {
            grid[point] = gateSet.contains(point) ? .gate : .wall
        }
    }

    private mutating func sprinkleGroves(in grid: inout TownTileGrid) {
        let density = snapshot.isEmpty ? 0.055 : 0.02 + params.irregularity * 0.03
        for y in 2..<(grid.height - 2) {
            for x in 2..<(grid.width - 2) where rng.bool(probability: density) {
                grid[TownPoint(x: x, y: y)] = .grove
            }
        }
    }

    private mutating func carveCacheWater(in grid: inout TownTileGrid) {
        guard snapshot.cacheIntensity > 0.12 else { return }
        let canalCount = snapshot.cacheIntensity > 0.45 ? 2 : 1
        for index in 0..<canalCount {
            let baseX = index == 0 ? max(5, grid.width / 5) : min(grid.width - 6, grid.width * 4 / 5)
            var x = baseX + rng.int(in: -2...2)
            for y in 3..<(grid.height - 3) {
                if y.isMultiple(of: 6) {
                    x = min(grid.width - 5, max(4, x + rng.int(in: -1...1)))
                }
                let point = TownPoint(x: x, y: y)
                if grid[point] == .meadow || grid[point] == .grove {
                    grid[point] = .water
                }
            }
        }
    }

    private mutating func makeBuildings(
        grid: inout TownTileGrid,
        patches: [WatabouPatch],
        plaza: TownRect
    ) -> [TownBuilding] {
        var buildings: [TownBuilding] = []
        var requests = buildingRequests()
        let innerPatches = patches.filter { $0.withinCity && $0.id != 0 }.shuffledStable(rng: &rng)

        while !requests.isEmpty {
            let request = requests.removeFirst()
            let candidatePatches = innerPatches
                .filter { $0.district == request.district || request.district == .homes }
                .ifEmpty(innerPatches)
            guard let placement = findLot(
                request: request,
                patches: candidatePatches,
                grid: grid,
                plaza: plaza
            ) else {
                continue
            }

            grid.fill(placement.footprint, with: .buildingFloor)
            buildings.append(TownBuilding(
                id: "watabou-\(buildings.count)-\(request.kind.rawValue)",
                kind: request.kind,
                district: request.district,
                footprint: placement.footprint,
                entrance: placement.entrance,
                tokenWeight: request.tokenWeight,
                sourceLabel: request.sourceLabel
            ))
        }

        return buildings
    }

    private func buildingRequests() -> [BuildingRequest] {
        var requests: [BuildingRequest] = []
        for project in snapshot.projects.prefix(7) {
            let kind: TownBuildingKind = project.effectiveTokens > 120_000 ? .workshop : .archiveHut
            requests.append(BuildingRequest(
                kind: kind,
                district: kind == .workshop ? .workshop : .archive,
                size: TownSize(width: 3, height: 2),
                tokenWeight: project.effectiveTokens,
                sourceLabel: project.name
            ))
        }
        for model in snapshot.models.prefix(5) {
            requests.append(BuildingRequest(
                kind: .marketStall,
                district: .market,
                size: TownSize(width: 3, height: 2),
                tokenWeight: model.effectiveTokens,
                sourceLabel: shortModelName(model.model)
            ))
        }
        if snapshot.cacheReadTokens + snapshot.cacheCreationTokens > 0 {
            requests.append(BuildingRequest(
                kind: .cacheWell,
                district: .cache,
                size: TownSize(width: 2, height: 2),
                tokenWeight: snapshot.cacheReadTokens + snapshot.cacheCreationTokens,
                sourceLabel: nil
            ))
        }
        let cottageCount = snapshot.isEmpty ? 6 : min(12, max(5, snapshot.sessionCount / 3))
        for index in 0..<cottageCount {
            requests.append(BuildingRequest(
                kind: index.isMultiple(of: 3) ? .gardenHouse : .cottage,
                district: index.isMultiple(of: 3) ? .garden : .homes,
                size: TownSize(width: 2, height: 2),
                tokenWeight: 0,
                sourceLabel: nil
            ))
        }
        return requests
    }

    private mutating func findLot(
        request: BuildingRequest,
        patches: [WatabouPatch],
        grid: TownTileGrid,
        plaza: TownRect
    ) -> (footprint: TownRect, entrance: TownPoint)? {
        let roadPoints = allRoadPoints(in: grid).shuffledStable(rng: &rng)
        for patch in patches {
            let patchCells = Set(patch.cells)
            for road in roadPoints.prefix(420) where road.cardinalNeighbors.contains(where: patchCells.contains) {
                for rect in candidateRects(around: road, size: request.size).shuffledStable(rng: &rng) {
                    guard rect.points.allSatisfy({ patchCells.contains($0) && grid.contains($0) && grid[$0].isBuildableGround }),
                          !rect.expanded(by: 1).points.contains(where: plaza.contains) else { continue }
                    return (rect, road)
                }
            }
        }
        return nil
    }

    private func candidateRects(around point: TownPoint, size: TownSize) -> [TownRect] {
        [
            TownRect(origin: TownPoint(x: point.x + 1, y: point.y - size.height / 2), size: size),
            TownRect(origin: TownPoint(x: point.x - size.width, y: point.y - size.height / 2), size: size),
            TownRect(origin: TownPoint(x: point.x - size.width / 2, y: point.y + 1), size: size),
            TownRect(origin: TownPoint(x: point.x - size.width / 2, y: point.y - size.height), size: size),
        ]
    }

    private func nearestRoad(to point: TownPoint, in grid: TownTileGrid) -> TownPoint? {
        allRoadPoints(in: grid).min { lhs, rhs in
            let ld = lhs.manhattanDistance(to: point)
            let rd = rhs.manhattanDistance(to: point)
            return ld == rd ? lhs < rhs : ld < rd
        }
    }

    private func allRoadPoints(in grid: TownTileGrid) -> [TownPoint] {
        var points: [TownPoint] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let point = TownPoint(x: x, y: y)
                if grid[point] == .road || grid[point] == .plaza || grid[point] == .gate {
                    points.append(point)
                }
            }
        }
        return points
    }

    private func shortestPath(from start: TownPoint, to goal: TownPoint, in grid: TownTileGrid) -> [TownPoint]? {
        guard grid.contains(start), grid.contains(goal) else { return nil }
        var open: [TownPoint] = [start]
        var cameFrom: [TownPoint: TownPoint] = [:]
        var gScore: [TownPoint: Int] = [start: 0]

        while !open.isEmpty {
            open.sort { lhs, rhs in
                let lf = (gScore[lhs] ?? .max / 2) + lhs.manhattanDistance(to: goal)
                let rf = (gScore[rhs] ?? .max / 2) + rhs.manhattanDistance(to: goal)
                return lf == rf ? lhs < rhs : lf < rf
            }
            let current = open.removeFirst()
            if current == goal {
                return reconstructPath(cameFrom: cameFrom, current: current)
            }
            for neighbor in current.cardinalNeighbors where grid.contains(neighbor) {
                guard grid[neighbor] != .wall && grid[neighbor] != .water && grid[neighbor] != .buildingFloor else { continue }
                let cost = grid[neighbor] == .road || grid[neighbor] == .plaza || grid[neighbor] == .gate ? 1 : 5
                let tentative = (gScore[current] ?? 0) + cost
                guard tentative < (gScore[neighbor] ?? .max) else { continue }
                cameFrom[neighbor] = current
                gScore[neighbor] = tentative
                if !open.contains(neighbor) {
                    open.append(neighbor)
                }
            }
        }
        return nil
    }

    private func reconstructPath(cameFrom: [TownPoint: TownPoint], current: TownPoint) -> [TownPoint] {
        var path = [current]
        var cursor = current
        while let next = cameFrom[cursor] {
            path.append(next)
            cursor = next
        }
        return path.reversed()
    }

    private func carveRoad(_ path: [TownPoint], in grid: inout TownTileGrid, width: Int, kind: TownTileKind) {
        for point in path {
            for dy in -width...width {
                for dx in -width...width where abs(dx) + abs(dy) <= width {
                    let p = point.offset(dx: dx, dy: dy)
                    guard grid.contains(p), grid[p] != .wall else { continue }
                    grid[p] = grid[p] == .gate ? .gate : kind
                }
            }
        }
    }

    private func validate(
        grid: TownTileGrid,
        plaza: TownRect,
        gates: [TownPoint],
        buildings: [TownBuilding],
        repairedRoads: Int = 0
    ) -> TownValidationReport {
        let reachable = reachableWalkable(from: plaza.center, in: grid)
        let gateReachable = gates.allSatisfy { reachable.contains($0) }
        let blocked = buildings
            .filter { $0.kind != .plaza }
            .filter { !reachable.contains($0.entrance) || !hasWalkableNeighbor($0.entrance, in: grid) }
            .map(\.id)
        return TownValidationReport(
            graphReachable: gateReachable,
            tileReachable: reachable.contains(plaza.center),
            blockedEntrances: blocked,
            repairedRoads: repairedRoads
        )
    }

    private func reachableWalkable(from start: TownPoint, in grid: TownTileGrid) -> Set<TownPoint> {
        guard grid.contains(start), grid[start].isWalkable else { return [] }
        var visited: Set<TownPoint> = [start]
        var queue: [TownPoint] = [start]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for neighbor in current.cardinalNeighbors where grid.contains(neighbor) && grid[neighbor].isWalkable && !visited.contains(neighbor) {
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return visited
    }

    private func hasWalkableNeighbor(_ point: TownPoint, in grid: TownTileGrid) -> Bool {
        point.cardinalNeighbors.contains { grid.contains($0) && grid[$0].isWalkable }
    }

    private func repairEntrances(
        in grid: inout TownTileGrid,
        plaza: TownRect,
        buildings: [TownBuilding],
        report: inout TownValidationReport
    ) {
        for building in buildings where building.kind != .plaza {
            guard let path = shortestPath(from: building.entrance, to: plaza.center, in: grid) else { continue }
            carveRoad(path, in: &grid, width: 1, kind: .road)
            report.repairedRoads += path.count
        }
    }

    private func districtSequence() -> [TownDistrictKind] {
        var districts: [TownDistrictKind] = [.homes, .workshop, .archive, .market, .garden, .homes]
        if snapshot.cacheReadTokens > 0 || snapshot.cacheCreationTokens > 0 {
            districts.append(.cache)
        }
        if snapshot.outputTokens > snapshot.effectiveTokens / 3 {
            districts.append(.workshop)
        }
        return districts
    }

    private func weather() -> TownWeather {
        if snapshot.cacheIntensity > 0.58 { return .rainClock }
        if snapshot.todayEffectiveTokens > 75_000 { return .drizzle }
        if state.placedItems.contains(where: { $0.kind == .lamp }) { return .lanternFog }
        return .clear
    }

    private func secrets() -> [String] {
        var values: [String] = []
        if snapshot.cacheReadTokens > 150_000 { values.append("cache-well") }
        if snapshot.projects.count >= 3 { values.append("crossroads-market") }
        if snapshot.todayEffectiveTokens > 80_000 { values.append("clocktower-rain") }
        if state.placedItems.count >= 6 { values.append("lantern-alley") }
        return values
    }

    private func shortModelName(_ model: String) -> String {
        let chunks = model
            .split(separator: "-")
            .filter { !$0.allSatisfy(\.isNumber) }
        return chunks.suffix(2).joined(separator: "-").prefix(28).description
    }
}

private struct WatabouPatch: Hashable, Sendable {
    let id: Int
    let center: TownPoint
    let district: TownDistrictKind
    let cells: [TownPoint]
    let withinCity: Bool
    let withinWalls: Bool

    var townPatch: TownPatch {
        TownPatch(id: id, center: center, district: district, cells: cells)
    }

    func withCells(_ extraCells: [TownPoint]) -> WatabouPatch {
        WatabouPatch(
            id: id,
            center: center,
            district: district,
            cells: Array(Set(cells).union(extraCells)).sorted(),
            withinCity: withinCity,
            withinWalls: withinWalls
        )
    }
}

private struct BuildingRequest: Hashable, Sendable {
    let kind: TownBuildingKind
    let district: TownDistrictKind
    let size: TownSize
    let tokenWeight: Int
    let sourceLabel: String?
}

private extension Array {
    func shuffledStable(rng: inout TownRandom) -> [Element] {
        var values = self
        guard values.count > 1 else { return values }
        for index in values.indices.dropLast() {
            let swapIndex = rng.int(in: index...(values.count - 1))
            values.swapAt(index, swapIndex)
        }
        return values
    }

    func ifEmpty(_ fallback: [Element]) -> [Element] {
        isEmpty ? fallback : self
    }
}
