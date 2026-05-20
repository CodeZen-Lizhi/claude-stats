import AppKit
import Foundation
import Observation

struct LinuxDoListState: Sendable {
    var topics: [LinuxDoTopicSummary] = []
    var nextPage: Int? = 0
    var isLoading = false
    var isRefreshing = false
    var isStale = false
    var lastFetchedAt: Date?
    var error: String?

    var canLoadMore: Bool { nextPage != nil && !isLoading && !isRefreshing }
}

struct LinuxDoTopicDetailState: Sendable {
    var detail: LinuxDoTopicDetail?
    var loadedPostIDs: Set<Int> = []
    var remainingPostIDs: [Int] = []
    var isLoading = false
    var isLoadingMore = false
    var isStale = false
    var error: String?
}

@MainActor
@Observable
final class LinuxDoStore {
    private(set) var categories: [LinuxDoCategory] = []
    private(set) var listStates: [String: LinuxDoListState] = [:]
    private(set) var topicStates: [Int: LinuxDoTopicDetailState] = [:]
    private(set) var currentUser: LinuxDoCurrentUser?
    private(set) var notifications: [LinuxDoNotification] = []
    private(set) var notificationAuthorization: LinuxDoNotificationAuthorizationStatus = .notDetermined
    private(set) var isLoadingCategories = false
    private(set) var isSigningIn = false
    private(set) var isRefreshingNotifications = false
    private(set) var lastError: String?
    private(set) var rateLimitedUntil: Date?

    var selectedFeed: LinuxDoFeed {
        didSet {
            preferences.linuxDoSelectedFeed = selectedFeed.storedValue
        }
    }
    var topPeriod: LinuxDoTopPeriod = .weekly
    var searchText = ""
    var submittedSearch = ""
    var selectedTopicID: Int?

    var isAuthenticated: Bool {
        credentials.readAPIKey() != nil
    }

    var selectedTopicState: LinuxDoTopicDetailState? {
        selectedTopicID.flatMap { topicStates[$0] }
    }

    var currentListState: LinuxDoListState {
        listStates[selectedFeed.key] ?? LinuxDoListState()
    }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let client: any LinuxDoClienting
    @ObservationIgnored private let cache: any LinuxDoCaching
    @ObservationIgnored private let credentials: any LinuxDoCredentialStoring
    @ObservationIgnored private let authService: LinuxDoAuthService
    @ObservationIgnored private let notificationService: any LinuxDoNotificationServicing
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var notificationTask: Task<Void, Never>?

    init(
        preferences: Preferences,
        credentials: any LinuxDoCredentialStoring = LinuxDoKeychainStore.shared,
        cache: any LinuxDoCaching = LinuxDoCache(),
        notificationService: any LinuxDoNotificationServicing = LinuxDoNotificationService(),
        client: (any LinuxDoClienting)? = nil,
        authService: LinuxDoAuthService? = nil
    ) {
        self.preferences = preferences
        self.credentials = credentials
        self.cache = cache
        self.notificationService = notificationService
        self.client = client ?? LinuxDoClient(credentials: credentials)
        self.authService = authService ?? LinuxDoAuthService(credentials: credentials)
        self.selectedFeed = LinuxDoFeed.stored(preferences.linuxDoSelectedFeed) ?? .latest
    }

    deinit {
        searchTask?.cancel()
        notificationTask?.cancel()
    }

    func start() {
        Task {
            notificationAuthorization = await notificationService.authorizationStatus()
            if preferences.linuxDoNotificationsEnabled {
                startNotificationPolling()
            }
        }
    }

    func loadInitialIfNeeded() async {
        await loadCategoriesIfNeeded()
        await loadCurrentFeedIfNeeded()
        if isAuthenticated {
            await loadCurrentUserIfNeeded()
        }
    }

    func selectFeed(_ feed: LinuxDoFeed) {
        selectedFeed = feed
        if case .search(let query) = feed {
            submittedSearch = query
            searchText = query
        }
        Task {
            await loadCurrentFeedIfNeeded()
        }
    }

    func selectTopPeriod(_ period: LinuxDoTopPeriod) {
        topPeriod = period
        selectFeed(.top(period))
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            lastError = "Type at least two characters to search LinuxDo."
            return
        }
        submittedSearch = query
        selectFeed(.search(query))
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.submitSearch()
        }
    }

    func refreshCurrentFeed() async {
        await loadTopicList(feed: selectedFeed, force: true)
    }

    func loadCurrentFeedIfNeeded() async {
        await loadTopicList(feed: selectedFeed, force: false)
    }

    func loadMoreCurrentFeed() async {
        var state = listStates[selectedFeed.key] ?? LinuxDoListState()
        guard let nextPage = state.nextPage, !state.isLoading, !state.isRefreshing else { return }
        state.isLoading = true
        state.error = nil
        listStates[selectedFeed.key] = state
        do {
            let list = try await client.fetchTopicList(feed: selectedFeed, page: nextPage, now: .now)
            state.topics.append(contentsOf: list.topics)
            state.nextPage = list.nextPage
            state.lastFetchedAt = list.fetchedAt
            state.isLoading = false
            try? cache.writeTopicList(LinuxDoTopicList(topics: state.topics, page: nextPage, nextPage: state.nextPage, fetchedAt: list.fetchedAt), feed: selectedFeed)
        } catch {
            state.isLoading = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        listStates[selectedFeed.key] = state
    }

    func selectTopic(_ topic: LinuxDoTopicSummary) {
        selectedTopicID = topic.id
        Task {
            await loadTopic(id: topic.id, slug: topic.slug, force: false)
        }
    }

    func loadTopic(id: Int, slug: String?, force: Bool) async {
        var state = topicStates[id] ?? LinuxDoTopicDetailState()
        if !force,
           let cached = cache.readTopic(id: id, ttl: 15 * 60, now: .now) {
            state.detail = cached.detail
            state.loadedPostIDs = Set(cached.detail.posts.map(\.id))
            state.remainingPostIDs = cached.detail.stream.filter { !state.loadedPostIDs.contains($0) }
            state.isStale = cached.isStale
            topicStates[id] = state
            if !cached.isStale { return }
        }

        state.isLoading = state.detail == nil
        state.error = nil
        topicStates[id] = state
        do {
            let detail = try await client.fetchTopic(id: id, slug: slug, now: .now)
            state.detail = detail
            state.loadedPostIDs = Set(detail.posts.map(\.id))
            state.remainingPostIDs = detail.stream.filter { !state.loadedPostIDs.contains($0) }
            state.isLoading = false
            state.isStale = false
            try? cache.writeTopic(detail)
        } catch {
            state.isLoading = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        topicStates[id] = state
    }

    func loadMorePosts(topicID: Int) async {
        var state = topicStates[topicID] ?? LinuxDoTopicDetailState()
        guard !state.remainingPostIDs.isEmpty, !state.isLoadingMore else { return }
        let batch = Array(state.remainingPostIDs.prefix(20))
        state.isLoadingMore = true
        state.error = nil
        topicStates[topicID] = state
        do {
            let posts = try await client.fetchPosts(topicID: topicID, postIDs: batch)
            state.detail?.posts.append(contentsOf: posts)
            state.detail?.posts.sort { $0.postNumber < $1.postNumber }
            state.loadedPostIDs.formUnion(posts.map(\.id))
            state.remainingPostIDs.removeAll { state.loadedPostIDs.contains($0) }
            state.isLoadingMore = false
            if let detail = state.detail {
                try? cache.writeTopic(detail)
            }
        } catch {
            state.isLoadingMore = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        topicStates[topicID] = state
    }

    func signIn(presentationAnchor: NSWindow?) async {
        guard let presentationAnchor else {
            lastError = "Open the main window before signing in to LinuxDo."
            return
        }
        isSigningIn = true
        lastError = nil
        do {
            _ = try await authService.login(presentationAnchor: presentationAnchor)
            await loadCurrentUserIfNeeded(force: true)
            await refreshNotifications(announce: false)
        } catch LinuxDoAuthService.AuthError.cancelled {
            lastError = nil
        } catch {
            lastError = userFacingMessage(error)
        }
        isSigningIn = false
    }

    func signOut() async {
        await client.revokeUserAPIKey()
        credentials.deleteAPIKey()
        preferences.linuxDoLastLoginUsername = ""
        preferences.linuxDoNotificationsEnabled = false
        preferences.linuxDoLastSeenNotificationID = 0
        preferences.linuxDoNotificationDeliveredIDs = []
        currentUser = nil
        notifications = []
        stopNotificationPolling()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard enabled else {
            preferences.linuxDoNotificationsEnabled = false
            stopNotificationPolling()
            return
        }
        guard isAuthenticated else {
            lastError = "Sign in to LinuxDo before enabling notifications."
            preferences.linuxDoNotificationsEnabled = false
            return
        }
        notificationAuthorization = await notificationService.requestAuthorization()
        preferences.linuxDoNotificationsEnabled = notificationAuthorization.canSendNotifications
        if notificationAuthorization.canSendNotifications {
            await refreshNotifications(announce: false)
            startNotificationPolling()
        }
    }

    func refreshNotifications(announce: Bool = true) async {
        guard isAuthenticated else { return }
        isRefreshingNotifications = true
        defer { isRefreshingNotifications = false }
        do {
            let fresh = try await client.fetchNotifications(limit: 30)
            notifications = fresh
            if fresh.isEmpty { return }
            let maxID = fresh.map(\.id).max() ?? 0
            let lastSeen = preferences.linuxDoLastSeenNotificationID
            if lastSeen == 0 || !announce {
                preferences.linuxDoLastSeenNotificationID = max(maxID, lastSeen)
                return
            }
            var delivered = Set(preferences.linuxDoNotificationDeliveredIDs)
            for notification in fresh where notification.id > lastSeen && !delivered.contains(notification.id) && !notification.read {
                try? await notificationService.send(notification: notification)
                delivered.insert(notification.id)
            }
            preferences.linuxDoLastSeenNotificationID = max(maxID, lastSeen)
            preferences.linuxDoNotificationDeliveredIDs = Array(delivered.sorted().suffix(80))
        } catch {
            handle(error)
        }
    }

    func clearCache() {
        do {
            try cache.clear()
            listStates.removeAll()
            topicStates.removeAll()
        } catch {
            lastError = "Could not clear LinuxDo cache."
        }
    }

    private func loadCategoriesIfNeeded() async {
        if !categories.isEmpty { return }
        if let cached = cache.readCategories(ttl: 24 * 60 * 60, now: .now) {
            categories = cached.categories
            if !cached.isStale { return }
        }
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            let fresh = try await client.fetchCategories()
            categories = fresh
            try? cache.writeCategories(fresh, now: .now)
        } catch {
            handle(error)
        }
    }

    private func loadTopicList(feed: LinuxDoFeed, force: Bool) async {
        if let limited = rateLimitedUntil, limited > Date() {
            var state = listStates[feed.key] ?? LinuxDoListState()
            state.error = "Linux.do asked us to slow down. Try again \(Format.relativeDate(limited))."
            listStates[feed.key] = state
            return
        }
        var state = listStates[feed.key] ?? LinuxDoListState()
        if !force,
           let cached = cache.readTopicList(feed: feed, ttl: feed.cacheTTL, now: .now) {
            state.topics = cached.list.topics
            state.nextPage = cached.list.nextPage
            state.lastFetchedAt = cached.list.fetchedAt
            state.isStale = cached.isStale
            state.error = nil
            listStates[feed.key] = state
            if !cached.isStale { return }
        }

        state.isRefreshing = !state.topics.isEmpty
        state.isLoading = state.topics.isEmpty
        state.error = nil
        listStates[feed.key] = state
        do {
            let list = try await client.fetchTopicList(feed: feed, page: 0, now: .now)
            state.topics = list.topics
            state.nextPage = list.nextPage
            state.lastFetchedAt = list.fetchedAt
            state.isStale = false
            state.isLoading = false
            state.isRefreshing = false
            try? cache.writeTopicList(list, feed: feed)
            if selectedTopicID == nil, let first = list.topics.first {
                selectTopic(first)
            }
        } catch {
            state.isLoading = false
            state.isRefreshing = false
            state.error = userFacingMessage(error)
            handle(error)
        }
        listStates[feed.key] = state
    }

    private func loadCurrentUserIfNeeded(force: Bool = false) async {
        guard isAuthenticated else { return }
        if currentUser != nil, !force { return }
        do {
            let user = try await client.fetchCurrentUser()
            currentUser = user
            preferences.linuxDoLastLoginUsername = user.username
        } catch {
            if preferences.linuxDoLastLoginUsername.isEmpty {
                lastError = userFacingMessage(error)
            }
        }
    }

    private func startNotificationPolling() {
        guard preferences.linuxDoNotificationsEnabled, notificationTask == nil else { return }
        notificationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNotifications(announce: true)
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private func stopNotificationPolling() {
        notificationTask?.cancel()
        notificationTask = nil
    }

    private func handle(_ error: Error) {
        if let clientError = error as? LinuxDoClient.ClientError {
            switch clientError {
            case .unauthorized:
                credentials.deleteAPIKey()
                currentUser = nil
                preferences.linuxDoNotificationsEnabled = false
                stopNotificationPolling()
            case .rateLimited(let retryAfter):
                rateLimitedUntil = retryAfter ?? Date().addingTimeInterval(120)
            default:
                break
            }
        }
        lastError = userFacingMessage(error)
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let clientError = error as? LinuxDoClient.ClientError {
            return clientError.description
        }
        if let authError = error as? LinuxDoAuthService.AuthError {
            return authError.description
        }
        return error.localizedDescription
    }
}
