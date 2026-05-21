import Foundation
import Testing
@testable import ClaudeStats

@Suite("Token Town")
struct TokenTownTests {
    @Test("Same seed and snapshot generate the same town")
    func deterministicGeneration() {
        let snapshot = makeSnapshot(effectiveTokens: 180_000, cacheReadTokens: 40_000)
        let state = TownState(seed: 42)
        let params = TownParams.from(snapshot: snapshot, state: state)

        let first = TownMapGenerator.generate(params: params, snapshot: snapshot, state: state)
        let second = TownMapGenerator.generate(params: params, snapshot: snapshot, state: state)

        #expect(first == second)
        #expect(first.validation.ok)
    }

    @Test("Provider, period, and usage fingerprints influence town shape")
    func fingerprintsInfluenceGeneration() {
        let state = TownState(seed: 42)
        let firstSnapshot = makeSnapshot(provider: .claude, period: .last7Days, effectiveTokens: 100_000)
        let secondSnapshot = makeSnapshot(provider: .codex, period: .last30Days, effectiveTokens: 320_000)

        let first = TownMapGenerator.generate(params: .from(snapshot: firstSnapshot, state: state), snapshot: firstSnapshot, state: state)
        let second = TownMapGenerator.generate(params: .from(snapshot: secondSnapshot, state: state), snapshot: secondSnapshot, state: state)

        #expect(first.revisionID != second.revisionID)
    }

    @Test("Generated buildings do not block roads or water and entrances are reachable")
    func generatedTownConnectivity() {
        let snapshot = makeSnapshot(effectiveTokens: 420_000, cacheReadTokens: 240_000, projectCount: 5)
        let state = TownState(seed: 99)
        let map = TownMapGenerator.generate(params: .from(snapshot: snapshot, state: state), snapshot: snapshot, state: state)

        #expect(map.validation.ok)
        for building in map.buildings where building.kind != .plaza {
            #expect(map.grid[building.entrance].isWalkable)
            for point in building.footprint.points {
                #expect(map.grid.contains(point))
                #expect(map.grid[point] == .buildingFloor)
            }
        }
    }

    @Test("Economy excludes cache-read tokens and only grants new daily deltas")
    func economyExcludesCacheReadAndDeduplicates() {
        var state = TownState(seed: 1)
        let day = Date(timeIntervalSince1970: 1_768_200_000)
        let usage = TokenUsage(inputTokens: 50_000, outputTokens: 0, cacheReadTokens: 1_000_000)
        let effective = TownUsageSnapshotBuilder.effectiveTokens(usage)

        #expect(effective == 50_000)
        #expect(TownEconomy.reconcile(state: &state, provider: .claude, day: day, effectiveTokens: effective) == 100)
        #expect(TownEconomy.reconcile(state: &state, provider: .claude, day: day, effectiveTokens: effective) == 0)
        #expect(TownEconomy.reconcile(state: &state, provider: .claude, day: day, effectiveTokens: 100_000) == 7)
        #expect(TownEconomy.coins(forEffectiveTokens: 20_000_000) == TownEconomy.dailyCoinCap)
        #expect(state.balance == 107)
    }

    @Test("Town state round-trips and invalid JSON falls back")
    func stateStoreRoundTripAndInvalidFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenTownTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TownStateStore(directory: directory)

        var state = TownState(seed: 123)
        state.balance = 44
        state.placedItems = [
            TownPlacedItem(
                id: "lamp-1",
                kind: .lamp,
                footprint: TownRect(origin: TownPoint(x: 2, y: 3), size: TownSize(width: 1, height: 1)),
                purchasedAt: Date(timeIntervalSince1970: 1_768_200_000)
            ),
        ]
        await store.writeState(state)
        #expect(await store.readState() == state)

        let stateURL = directory.appendingPathComponent("state.json", isDirectory: false)
        try Data("not-json".utf8).write(to: stateURL)
        #expect(await store.readState() == .empty)
    }

    @Test("Usage snapshot keeps project metadata local and compact")
    func snapshotUsesProjectDisplayNameOnly() {
        let now = Date(timeIntervalSince1970: 1_768_200_000)
        let session = makeSession(
            id: "s1",
            cwd: "/Users/private/customer/secret-project",
            lastActivity: now,
            usage: TokenUsage(inputTokens: 1_000, outputTokens: 500, cacheReadTokens: 9_000)
        )
        let snapshot = TownUsageSnapshotBuilder.make(
            provider: .claude,
            period: .today,
            sessions: [session],
            pricing: TestPricing.table,
            now: now
        )

        #expect(snapshot.projects.first?.name == "secret-project")
        #expect(!snapshot.fingerprint.contains("/Users/private"))
        #expect(snapshot.effectiveTokens == 1_500)
        #expect(snapshot.cacheReadTokens == 9_000)
    }

    @Test("Watabou fork submodule is configured on the integration branch")
    func watabouSubmoduleConfiguration() throws {
        let root = repoRoot()
        let gitmodules = try String(contentsOf: root.appendingPathComponent(".gitmodules"), encoding: .utf8)
        #expect(gitmodules.contains(#"[submodule "ThirdParty/TownGeneratorOS"]"#))
        #expect(gitmodules.contains("url = https://github.com/1pitaph/TownGeneratorOS.git"))
        #expect(gitmodules.contains("branch = integration/claude-stats"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("ThirdParty/TownGeneratorOS/LICENSE").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("ThirdParty/TownGeneratorOS/Source/com/watabou/towngenerator/building/Model.hx").path))
    }

    @Test("Camera state migrates old JSON and clamps pan and zoom")
    func cameraStateMigrationAndMath() throws {
        let legacy = try JSONDecoder().decode(TownCameraState.self, from: Data(#"{"scale":1.4}"#.utf8))
        #expect(legacy.centerX == nil)
        #expect(legacy.centerY == nil)
        #expect(legacy.scale == 1.4)

        let viewport = TownCameraViewport(viewWidth: 100, viewHeight: 50, worldWidth: 400, worldHeight: 220)
        let centered = TownCameraMath.normalized(TownCameraState(scale: 0.2), viewport: viewport)
        #expect(centered.scale == TownCameraMath.minScale)
        #expect(abs((centered.centerX ?? 0) - 200) < 0.01)
        #expect(abs((centered.centerY ?? 0) - 110) < 0.01)

        let zoomed = TownCameraMath.zoomed(centered, factor: 2, anchorX: 260, anchorY: 110, viewport: viewport)
        #expect(zoomed.scale == 2)
        #expect((zoomed.centerX ?? 0) > (centered.centerX ?? 0))

        let panned = TownCameraMath.panned(zoomed, deltaViewX: 20, deltaViewY: -10, viewport: viewport)
        #expect((panned.centerX ?? 0) < (zoomed.centerX ?? 0))
        #expect((panned.centerY ?? 0) > (zoomed.centerY ?? 0))

        let clamped = TownCameraMath.panned(panned, deltaViewX: 10_000, deltaViewY: 10_000, viewport: viewport)
        let visible = TownCameraMath.visibleWorldSize(for: clamped.scale, viewport: viewport)
        #expect((clamped.centerX ?? 0) >= visible.width / 2)
        #expect((clamped.centerY ?? 0) >= visible.height / 2)
    }

    private func makeSnapshot(
        provider: ProviderKind = .claude,
        period: StatsPeriod = .last7Days,
        effectiveTokens: Int,
        cacheReadTokens: Int = 0,
        projectCount: Int = 2
    ) -> TownUsageSnapshot {
        TownUsageSnapshot(
            provider: provider,
            period: period,
            sessionCount: max(1, projectCount * 2),
            messageCount: max(1, projectCount * 12),
            effectiveTokens: effectiveTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: effectiveTokens / 8,
            outputTokens: effectiveTokens / 4,
            todayEffectiveTokens: min(effectiveTokens, 75_000),
            todayCacheReadTokens: min(cacheReadTokens, 25_000),
            projects: (0..<projectCount).map {
                TownProjectUsage(name: "project-\($0)", effectiveTokens: effectiveTokens / max(1, projectCount), sessionCount: 2)
            },
            models: [
                TownModelUsage(model: "claude-sonnet", effectiveTokens: effectiveTokens / 2),
                TownModelUsage(model: "claude-opus", effectiveTokens: effectiveTokens / 3),
            ],
            timelineBuckets: [effectiveTokens / 3, effectiveTokens / 4, effectiveTokens / 5]
        )
    }

    private func makeSession(id: String, cwd: String, lastActivity: Date, usage: TokenUsage) -> Session {
        let stats = SessionStats(
            title: "Private title should not be used in town thoughts",
            messageCount: 1,
            firstActivity: lastActivity,
            lastActivity: lastActivity,
            models: [
                ModelUsage(model: "claude-sonnet", messageCount: 1, usage: usage, pricing: TestPricing.table),
            ],
            timeline: [
                ModelBucket(model: "claude-sonnet", start: lastActivity, usage: usage),
            ]
        )
        return Session(
            id: id,
            externalID: id,
            provider: .claude,
            projectDirectoryName: "-Users-private-customer-secret-project",
            filePath: "/tmp/\(id).jsonl",
            cwd: cwd,
            lastModified: lastActivity,
            fileSize: 1,
            stats: stats
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
