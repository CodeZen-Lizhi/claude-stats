import Foundation
import Testing
@testable import ClaudeStats

@MainActor
@Suite("OpenAIStatusViewModel")
struct OpenAIStatusViewModelTests {
    @Test("Fresh cache satisfies refreshIfNeeded without network")
    func freshCacheHit() async {
        let old = Self.snapshot(groupStatuses: [.operational, .operational], fetchedAt: Date())
        let uptime = Self.uptimeSnapshot(groupIDs: [OpenAIStatusGroupCatalog.chatGPTID])
        let fixture = makeFixture(cacheSnapshot: old, cacheStale: false, uptimeCacheSnapshot: uptime)

        await fixture.viewModel.refreshIfNeeded()

        #expect(fixture.viewModel.snapshot == old)
        #expect(await fixture.client.fetchCount() == 0)
        #expect(await fixture.uptimeClient.fetchCount() == 0)
        #expect(fixture.viewModel.isStale == false)
    }

    @Test("Stale cache refreshes and writes fresh snapshot")
    func staleCacheRefreshes() async {
        let old = Self.snapshot(groupStatuses: [.operational, .operational], fetchedAt: Date(timeIntervalSince1970: 1))
        let fresh = Self.snapshot(groupStatuses: [.degradedPerformance, .operational], fetchedAt: Date(timeIntervalSince1970: 2))
        let fixture = makeFixture(cacheSnapshot: old, cacheStale: true, clientResult: .success(fresh))

        await fixture.viewModel.refreshIfNeeded()

        #expect(fixture.viewModel.snapshot == fresh)
        #expect(fixture.viewModel.isStale == false)
        #expect(fixture.cache.writeCount == 1)
        #expect(await fixture.client.fetchCount() == 1)
    }

    @Test("Network failure keeps stale cache visible")
    func networkFailureUsesStaleCache() async {
        let old = Self.snapshot(groupStatuses: [.operational, .operational], fetchedAt: Date(timeIntervalSince1970: 1))
        let fixture = makeFixture(
            cacheSnapshot: old,
            cacheStale: true,
            clientResult: .failure(OpenAIStatusClient.ClientError.network("offline"))
        )

        await fixture.viewModel.refresh(force: true)

        #expect(fixture.viewModel.snapshot == old)
        #expect(fixture.viewModel.isStale == true)
        #expect(fixture.viewModel.lastError == "OpenAI Status is unreachable.")
    }

    @Test("Uptime failure does not block summary refresh")
    func uptimeFailureDoesNotBlockSummaryRefresh() async {
        let fresh = Self.snapshot(groupStatuses: [.operational, .operational])
        let fixture = makeFixture(
            clientResult: .success(fresh),
            uptimeClientResult: .failure(OpenAIStatusClient.ClientError.network("offline"))
        )

        await fixture.viewModel.refresh(force: true)

        #expect(fixture.viewModel.snapshot == fresh)
        #expect(fixture.viewModel.uptimeSnapshot == nil)
        #expect(fixture.viewModel.uptimeLastError == "OpenAI Status is unreachable.")
    }

    @Test("Operational refresh clears previous abnormal notification fingerprint")
    func operationalClearsFingerprint() async {
        let fresh = Self.snapshot(groupStatuses: [.operational, .operational])
        let fixture = makeFixture(clientResult: .success(fresh))
        fixture.preferences.openAIStatusLastNotificationFingerprint = "old"

        await fixture.viewModel.refresh(force: true)

        #expect(fixture.preferences.openAIStatusLastNotificationFingerprint == "")
    }

    @Test("Only visible abnormal groups notify")
    func onlyVisibleAbnormalGroupsNotify() async {
        let fresh = Self.snapshot(groupStatuses: [.operational, .fullOutage])
        let fixture = makeFixture(clientResult: .success(fresh), notificationStatus: .authorized)
        fixture.preferences.openAIStatusNotificationsEnabled = true
        fixture.preferences.openAIStatusVisibleGroupIDs = [OpenAIStatusGroupCatalog.chatGPTID]

        await fixture.viewModel.refresh(force: true)

        #expect(await fixture.notifications.sentCount() == 0)
    }

    @Test("Duplicate abnormal notification is suppressed until recovery")
    func duplicateNotificationsAreSuppressedUntilRecovery() async {
        let abnormal = Self.snapshot(groupStatuses: [.fullOutage, .operational])
        let normal = Self.snapshot(groupStatuses: [.operational, .operational])
        let fixture = makeFixture(clientResult: .success(abnormal), notificationStatus: .authorized)
        fixture.preferences.openAIStatusNotificationsEnabled = true
        fixture.preferences.openAIStatusVisibleGroupIDs = [OpenAIStatusGroupCatalog.chatGPTID]

        await fixture.viewModel.refresh(force: true)
        await fixture.viewModel.refresh(force: true)
        #expect(await fixture.notifications.sentCount() == 1)

        await fixture.client.setResult(Result.success(normal))
        await fixture.viewModel.refresh(force: true)
        #expect(fixture.preferences.openAIStatusLastNotificationFingerprint == "")

        await fixture.client.setResult(Result.success(abnormal))
        await fixture.viewModel.refresh(force: true)
        #expect(await fixture.notifications.sentCount() == 2)
    }

    @Test("Denied notification permission leaves preference disabled")
    func deniedNotificationPermissionDisablesPreference() async {
        let fixture = makeFixture(notificationStatus: .denied)

        await fixture.viewModel.setNotificationsEnabled(true)

        #expect(fixture.preferences.openAIStatusNotificationsEnabled == false)
        #expect(fixture.viewModel.notificationPermissionDenied == true)
    }

    @Test("Visible uptime rows follow selected groups")
    func visibleUptimeRowsFollowSelectedGroups() async {
        let fresh = Self.snapshot(groupStatuses: [.operational, .operational])
        let uptime = Self.uptimeSnapshot(groupIDs: [
            OpenAIStatusGroupCatalog.chatGPTID,
            OpenAIStatusGroupCatalog.codexID,
        ])
        let fixture = makeFixture(clientResult: .success(fresh), uptimeClientResult: .success(uptime))
        fixture.preferences.openAIStatusVisibleGroupIDs = [OpenAIStatusGroupCatalog.chatGPTID]

        await fixture.viewModel.refresh(force: true)
        #expect(fixture.viewModel.visibleUptimeRows.map(\.group.id) == [OpenAIStatusGroupCatalog.chatGPTID])
        #expect(fixture.viewModel.visibleUptimeRows.first?.history?.groupID == OpenAIStatusGroupCatalog.chatGPTID)

        if let codex = fresh.groups.first(where: { $0.id == OpenAIStatusGroupCatalog.codexID }) {
            fixture.viewModel.setGroupVisibility(codex, isVisible: true)
        }
        #expect(fixture.viewModel.visibleUptimeRows.map(\.group.id) == [
            OpenAIStatusGroupCatalog.chatGPTID,
            OpenAIStatusGroupCatalog.codexID,
        ])
    }

    private func makeFixture(
        cacheSnapshot: OpenAIStatusSnapshot? = nil,
        cacheStale: Bool = false,
        clientResult: Result<OpenAIStatusSnapshot, OpenAIStatusClient.ClientError>? = nil,
        uptimeCacheSnapshot: OpenAIStatusUptimeSnapshot? = nil,
        uptimeCacheStale: Bool = false,
        uptimeClientResult: Result<OpenAIStatusUptimeSnapshot, OpenAIStatusClient.ClientError>? = nil,
        notificationStatus: StatusNotificationAuthorizationStatus = .notDetermined
    ) -> Fixture {
        let suiteName = "com.codexstats.tests.openai-status.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = Preferences(defaults: defaults)
        let client = FakeOpenAIStatusClient(result: clientResult ?? .success(Self.snapshot(groupStatuses: [.operational, .operational])))
        let cache = FakeOpenAIStatusCache(snapshot: cacheSnapshot, isStale: cacheStale)
        let uptimeClient = FakeOpenAIStatusUptimeClient(
            result: uptimeClientResult ?? .success(Self.uptimeSnapshot(groupIDs: [OpenAIStatusGroupCatalog.chatGPTID]))
        )
        let uptimeCache = FakeOpenAIStatusUptimeCache(snapshot: uptimeCacheSnapshot, isStale: uptimeCacheStale)
        let notifications = FakeOpenAIStatusNotifications(status: notificationStatus)
        let viewModel = OpenAIStatusViewModel(
            preferences: preferences,
            client: client,
            cache: cache,
            uptimeClient: uptimeClient,
            uptimeCache: uptimeCache,
            notifications: notifications
        )
        return Fixture(
            preferences: preferences,
            viewModel: viewModel,
            client: client,
            cache: cache,
            uptimeClient: uptimeClient,
            uptimeCache: uptimeCache,
            notifications: notifications
        )
    }

    private struct Fixture {
        let preferences: Preferences
        let viewModel: OpenAIStatusViewModel
        let client: FakeOpenAIStatusClient
        let cache: FakeOpenAIStatusCache
        let uptimeClient: FakeOpenAIStatusUptimeClient
        let uptimeCache: FakeOpenAIStatusUptimeCache
        let notifications: FakeOpenAIStatusNotifications
    }

    private static func snapshot(groupStatuses: [OpenAIStatusSeverity], fetchedAt: Date = Date()) -> OpenAIStatusSnapshot {
        let chatGPTStatus = groupStatuses.indices.contains(0) ? groupStatuses[0] : .operational
        let codexStatus = groupStatuses.indices.contains(1) ? groupStatuses[1] : .operational
        let components = [
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.chatGPTLoginID,
                name: "Login",
                status: chatGPTStatus,
                updatedAt: fetchedAt,
                position: 1
            ),
            OpenAIStatusComponent(
                id: OpenAIStatusGroupCatalog.codexWebID,
                name: "Codex Web",
                status: codexStatus,
                updatedAt: fetchedAt,
                position: 2
            ),
        ]
        let groups = OpenAIStatusGroupCatalog.groups(from: components)
        let rollup = groups.contains(where: { !$0.isOperational && OpenAIStatusGroupCatalog.defaultVisibleGroupIDs.contains($0.id) })
            ? OpenAIStatusRollup(severity: .fullOutage, description: "Major System Outage")
            : OpenAIStatusRollup(severity: .operational, description: "All Systems Operational")
        return OpenAIStatusSnapshot(
            pageName: "OpenAI",
            pageUpdatedAt: fetchedAt,
            rollup: rollup,
            groups: groups,
            components: components,
            incidents: [],
            scheduledMaintenances: [],
            fetchedAt: fetchedAt
        )
    }

    private static func uptimeSnapshot(groupIDs: [String], fetchedAt: Date = Date()) -> OpenAIStatusUptimeSnapshot {
        let histories = Dictionary(uniqueKeysWithValues: groupIDs.map { groupID in
            let name = groupID == OpenAIStatusGroupCatalog.codexID ? "Codex" : "ChatGPT"
            let history = OpenAIStatusUptimeHistory(
                groupID: groupID,
                groupName: name,
                startDate: Date(timeIntervalSince1970: 0),
                days: (0..<OpenAIStatusUptimeWindow.dayCount).map { index in
                    OpenAIStatusUptimeDay(
                        date: Date(timeIntervalSince1970: TimeInterval(index * OpenAIStatusUptimeWindow.secondsPerDay)),
                        degradedPerformanceSeconds: 0,
                        partialOutageSeconds: 0,
                        fullOutageSeconds: 0,
                        relatedEvents: []
                    )
                },
                sourceUptimePercent: nil
            )
            return (groupID, history)
        })
        return OpenAIStatusUptimeSnapshot(
            histories: histories,
            groupDefinitions: OpenAIStatusGroupCatalog.defaultGroupDefinitions,
            fetchedAt: fetchedAt
        )
    }
}

private actor FakeOpenAIStatusClient: OpenAIStatusFetching {
    private var result: Result<OpenAIStatusSnapshot, OpenAIStatusClient.ClientError>
    private var count = 0

    init(result: Result<OpenAIStatusSnapshot, OpenAIStatusClient.ClientError>) {
        self.result = result
    }

    func setResult(_ result: Result<OpenAIStatusSnapshot, OpenAIStatusClient.ClientError>) {
        self.result = result
    }

    func fetchCount() -> Int { count }

    func fetchSummary(now: Date) async throws -> OpenAIStatusSnapshot {
        count += 1
        switch result {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}

private actor FakeOpenAIStatusUptimeClient: OpenAIStatusUptimeFetching {
    private var result: Result<OpenAIStatusUptimeSnapshot, OpenAIStatusClient.ClientError>
    private var count = 0

    init(result: Result<OpenAIStatusUptimeSnapshot, OpenAIStatusClient.ClientError>) {
        self.result = result
    }

    func fetchCount() -> Int { count }

    func fetchUptimeHistories(now: Date) async throws -> OpenAIStatusUptimeSnapshot {
        count += 1
        switch result {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}

private final class FakeOpenAIStatusCache: OpenAIStatusCaching, @unchecked Sendable {
    var snapshot: OpenAIStatusSnapshot?
    var isStale: Bool
    var writeCount = 0

    init(snapshot: OpenAIStatusSnapshot?, isStale: Bool) {
        self.snapshot = snapshot
        self.isStale = isStale
    }

    func read(ttl: TimeInterval, now: Date) -> (snapshot: OpenAIStatusSnapshot, isStale: Bool)? {
        guard let snapshot else { return nil }
        return (snapshot, isStale)
    }

    func write(_ snapshot: OpenAIStatusSnapshot) throws {
        self.snapshot = snapshot
        isStale = false
        writeCount += 1
    }
}

private final class FakeOpenAIStatusUptimeCache: OpenAIStatusUptimeCaching, @unchecked Sendable {
    var snapshot: OpenAIStatusUptimeSnapshot?
    var isStale: Bool
    var writeCount = 0

    init(snapshot: OpenAIStatusUptimeSnapshot?, isStale: Bool) {
        self.snapshot = snapshot
        self.isStale = isStale
    }

    func read(ttl: TimeInterval, now: Date) -> (snapshot: OpenAIStatusUptimeSnapshot, isStale: Bool)? {
        guard let snapshot else { return nil }
        return (snapshot, isStale)
    }

    func write(_ snapshot: OpenAIStatusUptimeSnapshot) throws {
        self.snapshot = snapshot
        isStale = false
        writeCount += 1
    }
}

private actor FakeOpenAIStatusNotifications: StatusNotificationServicing {
    private var status: StatusNotificationAuthorizationStatus
    private var sentAlerts: [(title: String, body: String, identifier: String)] = []

    init(status: StatusNotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> StatusNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> StatusNotificationAuthorizationStatus {
        status
    }

    func sendStatusAlert(title: String, body: String, identifier: String) async throws {
        sentAlerts.append((title, body, identifier))
    }

    func sentCount() -> Int { sentAlerts.count }
}
