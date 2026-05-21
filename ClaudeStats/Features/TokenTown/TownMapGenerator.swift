import Foundation

enum TownMapGenerator {
    static func generate(params: TownParams, snapshot: TownUsageSnapshot, state: TownState) -> TownMap {
        for attempt in 0..<max(1, params.maxAttempts) {
            let attemptParams = TownParams(
                seed: params.seed &+ UInt64(attempt) &* 0x9E37_79B9_7F4A_7C15,
                size: params.size,
                patchCount: params.patchCount,
                roadWidth: params.roadWidth,
                density: params.density,
                irregularity: params.irregularity,
                wallChance: params.wallChance,
                maxAttempts: params.maxAttempts
            )
            let map = WatabouTownMapBuilder.build(params: attemptParams, snapshot: snapshot, state: state)
            if map.validation.ok { return map }
        }
        return fallback(params: params, snapshot: snapshot, state: state)
    }

    private static func build(
        params: TownParams,
        snapshot: TownUsageSnapshot,
        state: TownState,
        rng: inout TownRandom
    ) -> TownMap {
        var grid = TownTileGrid(width: params.size.width, height: params.size.height, fill: .meadow)
        sprinkleGroves(in: &grid, density: snapshot.isEmpty ? 0.05 : 0.025 + params.irregularity * 0.035, rng: &rng)

        let wallEnabled = rng.bool(probability: params.wallChance)
        let gates = makeGates(size: params.size, rng: &rng)
        if wallEnabled { drawCurtainWall(in: &grid, gates: gates) }

        let plaza = TownRect(
            origin: TownPoint(x: params.size.width / 2 - 4, y: params.size.height / 2 - 3),
            size: TownSize(width: 9, height: 7)
        )
        grid.fill(plaza, with: .plaza)

        var roads: [TownRoadEdge] = []
        let roadTargets = gates + makeSecondaryTargets(size: params.size, count: min(9, max(4, params.patchCount / 4)), rng: &rng)
        for target in roadTargets {
            guard let path = shortestPath(from: target, to: plaza.center, in: grid, prefer: plaza.center) else { continue }
            carveRoad(path, in: &grid, width: params.roadWidth, kind: .road)
            roads.append(TownRoadEdge(id: roads.count, from: target, to: plaza.center, points: path, isPrimary: gates.contains(target)))
        }
        grid.fill(plaza, with: .plaza)

        carveCacheWater(in: &grid, snapshot: snapshot, rng: &rng)

        let patches = makePatches(params: params, plaza: plaza, snapshot: snapshot, rng: &rng)
        var buildings = makeBuildings(
            grid: &grid,
            params: params,
            snapshot: snapshot,
            plaza: plaza,
            rng: &rng
        )
        buildings.insert(
            TownBuilding(
                id: "plaza",
                kind: .plaza,
                district: .plaza,
                footprint: plaza,
                entrance: plaza.center,
                tokenWeight: snapshot.effectiveTokens,
                sourceLabel: nil
            ),
            at: 0
        )

        var report = validate(grid: grid, plaza: plaza, gates: gates, buildings: buildings)
        if !report.ok {
            repairEntrances(in: &grid, plaza: plaza, buildings: buildings, report: &report)
            report = validate(grid: grid, plaza: plaza, gates: gates, buildings: buildings, repairedRoads: report.repairedRoads)
        }

        return TownMap(
            params: params,
            snapshot: snapshot,
            grid: grid,
            patches: patches,
            roads: roads,
            buildings: buildings,
            plaza: plaza,
            gates: gates,
            spawnPoint: gates.first ?? plaza.center,
            weather: weather(for: snapshot, state: state),
            secrets: secrets(for: snapshot, state: state),
            validation: report
        )
    }

    private static func fallback(params: TownParams, snapshot: TownUsageSnapshot, state: TownState) -> TownMap {
        var grid = TownTileGrid(width: params.size.width, height: params.size.height, fill: .meadow)
        let gates = [
            TownPoint(x: params.size.width / 2, y: 1),
            TownPoint(x: params.size.width / 2, y: params.size.height - 2),
        ]
        drawCurtainWall(in: &grid, gates: gates)
        let plaza = TownRect(
            origin: TownPoint(x: params.size.width / 2 - 3, y: params.size.height / 2 - 2),
            size: TownSize(width: 7, height: 5)
        )
        grid.fill(plaza, with: .plaza)
        for gate in gates {
            if let path = shortestPath(from: gate, to: plaza.center, in: grid, prefer: plaza.center) {
                carveRoad(path, in: &grid, width: 1, kind: .road)
            }
        }
        grid.fill(plaza, with: .plaza)
        let buildings = [
            TownBuilding(id: "plaza", kind: .plaza, district: .plaza, footprint: plaza, entrance: plaza.center, tokenWeight: 0, sourceLabel: nil),
        ]
        return TownMap(
            params: params,
            snapshot: snapshot,
            grid: grid,
            patches: [],
            roads: [],
            buildings: buildings,
            plaza: plaza,
            gates: gates,
            spawnPoint: gates[0],
            weather: weather(for: snapshot, state: state),
            secrets: secrets(for: snapshot, state: state),
            validation: validate(grid: grid, plaza: plaza, gates: gates, buildings: buildings)
        )
    }

    private static func sprinkleGroves(in grid: inout TownTileGrid, density: Double, rng: inout TownRandom) {
        for y in 2..<(grid.height - 2) {
            for x in 2..<(grid.width - 2) where rng.bool(probability: density) {
                grid[TownPoint(x: x, y: y)] = .grove
            }
        }
    }

    private static func makeGates(size: TownSize, rng: inout TownRandom) -> [TownPoint] {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let jitterX = max(2, size.width / 10)
        let jitterY = max(2, size.height / 10)
        return [
            TownPoint(x: centerX + rng.int(in: -jitterX...jitterX), y: 1),
            TownPoint(x: centerX + rng.int(in: -jitterX...jitterX), y: size.height - 2),
            TownPoint(x: 1, y: centerY + rng.int(in: -jitterY...jitterY)),
            TownPoint(x: size.width - 2, y: centerY + rng.int(in: -jitterY...jitterY)),
        ]
    }

    private static func drawCurtainWall(in grid: inout TownTileGrid, gates: [TownPoint]) {
        let gateSet = Set(gates.flatMap { [$0, $0.offset(dx: 1, dy: 0), $0.offset(dx: -1, dy: 0), $0.offset(dx: 0, dy: 1), $0.offset(dx: 0, dy: -1)] })
        for x in 0..<grid.width {
            for y in [0, 1, grid.height - 2, grid.height - 1] {
                let point = TownPoint(x: x, y: y)
                grid[point] = gateSet.contains(point) ? .gate : .wall
            }
        }
        for y in 0..<grid.height {
            for x in [0, 1, grid.width - 2, grid.width - 1] {
                let point = TownPoint(x: x, y: y)
                grid[point] = gateSet.contains(point) ? .gate : .wall
            }
        }
    }

    private static func makeSecondaryTargets(size: TownSize, count: Int, rng: inout TownRandom) -> [TownPoint] {
        (0..<count).map { _ in
            TownPoint(
                x: rng.int(in: 7...(size.width - 8)),
                y: rng.int(in: 6...(size.height - 7))
            )
        }
    }

    private static func makePatches(
        params: TownParams,
        plaza: TownRect,
        snapshot: TownUsageSnapshot,
        rng: inout TownRandom
    ) -> [TownPatch] {
        let districts = districtSequence(snapshot: snapshot)
        var centers: [TownPoint] = [plaza.center]
        while centers.count < params.patchCount {
            let point = TownPoint(
                x: rng.int(in: 4...(params.size.width - 5)),
                y: rng.int(in: 4...(params.size.height - 5))
            )
            guard !plaza.expanded(by: 2).contains(point),
                  centers.allSatisfy({ $0.manhattanDistance(to: point) > 5 }) else { continue }
            centers.append(point)
        }

        var cells: [[TownPoint]] = Array(repeating: [], count: centers.count)
        for y in 2..<(params.size.height - 2) {
            for x in 2..<(params.size.width - 2) {
                let point = TownPoint(x: x, y: y)
                let nearest = centers.indices.min { a, b in
                    centers[a].manhattanDistance(to: point) < centers[b].manhattanDistance(to: point)
                } ?? 0
                cells[nearest].append(point)
            }
        }

        return centers.indices.map { index in
            TownPatch(
                id: index,
                center: centers[index],
                district: index == 0 ? .plaza : districts[(index - 1) % districts.count],
                cells: cells[index]
            )
        }
    }

    private static func districtSequence(snapshot: TownUsageSnapshot) -> [TownDistrictKind] {
        var districts: [TownDistrictKind] = [.homes, .workshop, .archive, .market, .garden]
        if snapshot.cacheReadTokens > 0 || snapshot.cacheCreationTokens > 0 { districts.append(.cache) }
        if snapshot.outputTokens > snapshot.effectiveTokens / 3 { districts.append(.workshop) }
        return districts
    }

    private static func makeBuildings(
        grid: inout TownTileGrid,
        params: TownParams,
        snapshot: TownUsageSnapshot,
        plaza: TownRect,
        rng: inout TownRandom
    ) -> [TownBuilding] {
        var buildings: [TownBuilding] = []
        var requests: [(TownBuildingKind, TownDistrictKind, TownSize, Int, String?)] = []

        for project in snapshot.projects.prefix(6) {
            let kind: TownBuildingKind = project.effectiveTokens > 120_000 ? .workshop : .archiveHut
            requests.append((kind, kind == .workshop ? .workshop : .archive, TownSize(width: 3, height: 2), project.effectiveTokens, project.name))
        }
        for model in snapshot.models.prefix(4) {
            requests.append((.marketStall, .market, TownSize(width: 3, height: 2), model.effectiveTokens, shortModelName(model.model)))
        }
        if snapshot.cacheReadTokens + snapshot.cacheCreationTokens > 0 {
            requests.append((.cacheWell, .cache, TownSize(width: 2, height: 2), snapshot.cacheReadTokens + snapshot.cacheCreationTokens, nil))
        }
        let cottageCount = snapshot.isEmpty ? 5 : min(10, max(4, snapshot.sessionCount / 3))
        for index in 0..<cottageCount {
            requests.append((index.isMultiple(of: 3) ? .gardenHouse : .cottage, .homes, TownSize(width: 2, height: 2), 0, nil))
        }

        let roadPoints = allRoadPoints(in: grid).shuffledStable(rng: &rng)
        for request in requests {
            guard let placement = findBuildingPlacement(size: request.2, roadPoints: roadPoints, grid: grid, plaza: plaza, rng: &rng) else {
                continue
            }
            grid.fill(placement.footprint, with: .buildingFloor)
            buildings.append(TownBuilding(
                id: "building-\(buildings.count)-\(request.0.rawValue)",
                kind: request.0,
                district: request.1,
                footprint: placement.footprint,
                entrance: placement.entrance,
                tokenWeight: request.3,
                sourceLabel: request.4
            ))
        }
        return buildings
    }

    private static func findBuildingPlacement(
        size: TownSize,
        roadPoints: [TownPoint],
        grid: TownTileGrid,
        plaza: TownRect,
        rng: inout TownRandom
    ) -> (footprint: TownRect, entrance: TownPoint)? {
        let directions = [
            TownPoint(x: 1, y: 0),
            TownPoint(x: -1, y: 0),
            TownPoint(x: 0, y: 1),
            TownPoint(x: 0, y: -1),
        ].shuffledStable(rng: &rng)

        for road in roadPoints.prefix(320) {
            for dir in directions {
                let origin: TownPoint
                if dir.x > 0 {
                    origin = TownPoint(x: road.x + 1, y: road.y - size.height / 2)
                } else if dir.x < 0 {
                    origin = TownPoint(x: road.x - size.width, y: road.y - size.height / 2)
                } else if dir.y > 0 {
                    origin = TownPoint(x: road.x - size.width / 2, y: road.y + 1)
                } else {
                    origin = TownPoint(x: road.x - size.width / 2, y: road.y - size.height)
                }
                let rect = TownRect(origin: origin, size: size)
                guard rect.points.allSatisfy({ grid.contains($0) && grid[$0].isBuildableGround }),
                      !rect.expanded(by: 1).points.contains(where: plaza.contains) else { continue }
                return (rect, road)
            }
        }
        return nil
    }

    private static func carveCacheWater(in grid: inout TownTileGrid, snapshot: TownUsageSnapshot, rng: inout TownRandom) {
        guard snapshot.cacheIntensity > 0.12 else { return }
        let canalCount = snapshot.cacheIntensity > 0.45 ? 2 : 1
        for index in 0..<canalCount {
            let x = index == 0 ? max(4, grid.width / 5) : min(grid.width - 5, grid.width * 4 / 5)
            let wiggle = rng.int(in: -2...2)
            for y in 3..<(grid.height - 3) {
                let point = TownPoint(x: min(max(3, x + ((y + wiggle).isMultiple(of: 7) ? 1 : 0)), grid.width - 4), y: y)
                if grid[point] == .meadow || grid[point] == .grove {
                    grid[point] = .water
                }
            }
        }
    }

    private static func allRoadPoints(in grid: TownTileGrid) -> [TownPoint] {
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

    private static func shortestPath(
        from start: TownPoint,
        to goal: TownPoint,
        in grid: TownTileGrid,
        prefer: TownPoint
    ) -> [TownPoint]? {
        guard grid.contains(start), grid.contains(goal) else { return nil }
        var open: [TownPoint] = [start]
        var cameFrom: [TownPoint: TownPoint] = [:]
        var gScore: [TownPoint: Int] = [start: 0]

        while !open.isEmpty {
            open.sort { lhs, rhs in
                let lf = (gScore[lhs] ?? .max / 2) + lhs.manhattanDistance(to: goal)
                let rf = (gScore[rhs] ?? .max / 2) + rhs.manhattanDistance(to: goal)
                return lf == rf ? lhs.manhattanDistance(to: prefer) < rhs.manhattanDistance(to: prefer) : lf < rf
            }
            let current = open.removeFirst()
            if current == goal {
                return reconstructPath(cameFrom: cameFrom, current: current)
            }
            for neighbor in current.cardinalNeighbors where grid.contains(neighbor) {
                guard grid[neighbor] != .wall && grid[neighbor] != .water && grid[neighbor] != .buildingFloor else { continue }
                let cost = grid[neighbor] == .road || grid[neighbor] == .plaza || grid[neighbor] == .gate ? 1 : 4
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

    private static func reconstructPath(cameFrom: [TownPoint: TownPoint], current: TownPoint) -> [TownPoint] {
        var path = [current]
        var cursor = current
        while let next = cameFrom[cursor] {
            path.append(next)
            cursor = next
        }
        return path.reversed()
    }

    private static func carveRoad(_ path: [TownPoint], in grid: inout TownTileGrid, width: Int, kind: TownTileKind) {
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

    private static func validate(
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

    private static func reachableWalkable(from start: TownPoint, in grid: TownTileGrid) -> Set<TownPoint> {
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

    private static func hasWalkableNeighbor(_ point: TownPoint, in grid: TownTileGrid) -> Bool {
        point.cardinalNeighbors.contains { grid.contains($0) && grid[$0].isWalkable }
    }

    private static func repairEntrances(
        in grid: inout TownTileGrid,
        plaza: TownRect,
        buildings: [TownBuilding],
        report: inout TownValidationReport
    ) {
        for building in buildings where building.kind != .plaza {
            guard let path = shortestPath(from: building.entrance, to: plaza.center, in: grid, prefer: plaza.center) else { continue }
            carveRoad(path, in: &grid, width: 1, kind: .road)
            report.repairedRoads += path.count
        }
    }

    private static func weather(for snapshot: TownUsageSnapshot, state: TownState) -> TownWeather {
        if snapshot.cacheIntensity > 0.58 { return .rainClock }
        if snapshot.todayEffectiveTokens > 75_000 { return .drizzle }
        if state.placedItems.contains(where: { $0.kind == .lamp }) { return .lanternFog }
        return .clear
    }

    private static func secrets(for snapshot: TownUsageSnapshot, state: TownState) -> [String] {
        var values: [String] = []
        if snapshot.cacheReadTokens > 150_000 { values.append("cache-well") }
        if snapshot.projects.count >= 3 { values.append("crossroads-market") }
        if snapshot.todayEffectiveTokens > 80_000 { values.append("clocktower-rain") }
        if state.placedItems.count >= 6 { values.append("lantern-alley") }
        return values
    }

    private static func shortModelName(_ model: String) -> String {
        let chunks = model
            .split(separator: "-")
            .filter { !$0.allSatisfy(\.isNumber) }
        return chunks.suffix(2).joined(separator: "-").prefix(28).description
    }
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
}
