import Foundation
import Testing
@testable import ClaudeStats

@Suite("LinuxDo")
@MainActor
struct LinuxDoTests {
    @Test("Feed storage round-trips stable routes")
    func feedStorageRoundTrips() {
        let feeds: [LinuxDoFeed] = [
            .latest,
            .hot,
            .top(.monthly),
            .category(id: 7, name: "General", slug: "general"),
            .search("swift native"),
        ]

        for feed in feeds {
            #expect(LinuxDoFeed.stored(feed.storedValue) == feed)
        }
    }

    @Test("Cooked HTML is reduced to native safe blocks")
    func cookedHTMLBlocks() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p>Hello &amp; welcome</p>
        <blockquote>Keep it native</blockquote>
        <pre><code>print(&quot;hi&quot;)</code></pre>
        <ul><li>One</li><li>Two</li></ul>
        <img src="/uploads/test.png">
        """)

        #expect(blocks.contains(.paragraph("Hello & welcome")))
        #expect(blocks.contains(.quote("Keep it native")))
        #expect(blocks.contains(.code("print(\"hi\")")))
        #expect(blocks.contains(.list(["One", "Two"])))
        #expect(blocks.contains(.image(try #require(URL(string: "https://linux.do/uploads/test.png")))))
    }

    @Test("Discourse topic list fixture decodes to app models")
    func topicListFixtureDecode() throws {
        let json = """
        {
          "topic_list": {
            "more_topics_url": "/latest.json?page=1",
            "topics": [
              {
                "id": 42,
                "title": "Hello &amp; Linux",
                "fancy_title": null,
                "slug": "hello-linux",
                "category_id": 1,
                "tags": [{"id": 1, "name": "mac", "slug": "mac-tag"}],
                "excerpt": "<p>Native &amp; fast</p>",
                "posts_count": 3,
                "reply_count": 2,
                "views": 10,
                "like_count": 4,
                "image_url": "/uploads/default/original/1X/image.png"
              }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(TopicListResponse.self, from: Data(json.utf8))
        let list = LinuxDoResponseMapper.topicList(from: response, page: 0, now: Date(timeIntervalSince1970: 100))
        let topic = try #require(list.topics.first)

        #expect(list.nextPage == 1)
        #expect(topic.displayTitle == "Hello & Linux")
        #expect(topic.tags == ["mac"])
        #expect(topic.displayExcerpt == "Native & fast")
        #expect(topic.imageURL?.absoluteString == "https://linux.do/uploads/default/original/1X/image.png")
    }

    @Test("Topic tags decode from string object and empty shapes")
    func tagShapesDecode() throws {
        let json = """
        {
          "topic_list": {
            "topics": [
              { "id": 1, "title": "String tags", "slug": "one", "tags": ["swift"] },
              { "id": 2, "title": "Object tags", "slug": "two", "tags": [{"id": 2, "name": "macOS", "slug": "macos"}] },
              { "id": 3, "title": "Empty tags", "slug": "three", "tags": [] }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(TopicListResponse.self, from: Data(json.utf8))
        let topics = LinuxDoResponseMapper.topicList(from: response, page: 0, now: Date()).topics

        #expect(topics.map(\.tags) == [["swift"], ["macOS"], []])
    }

    @Test("Linux.do guest topic list shape decodes")
    func linuxDoGuestShapeDecode() throws {
        let json = """
        {
          "users": [],
          "topic_list": {
            "more_topics_url": "/hot.json?page=1",
            "topics": [
              {
                "fancy_title": "Hot &amp; Native",
                "id": 2213371,
                "title": "Hot Native",
                "slug": "topic",
                "posts_count": 47,
                "reply_count": 24,
                "image_url": "https://cdn3.ldstatic.com/original/example.png",
                "created_at": "2026-05-20T09:09:14.607Z",
                "last_posted_at": "2026-05-20T14:33:33.809Z",
                "bumped_at": "2026-05-20T14:33:33.809Z",
                "tags": [{"id": 1461, "name": "纯水", "slug": "1461-tag"}],
                "views": 1297,
                "like_count": 70,
                "category_id": 42
              }
            ]
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeLinuxDoDate)
        let response = try decoder.decode(TopicListResponse.self, from: Data(json.utf8))
        let list = LinuxDoResponseMapper.topicList(from: response, page: 0, now: Date())
        let topic = try #require(list.topics.first)

        #expect(list.nextPage == 1)
        #expect(topic.displayTitle == "Hot & Native")
        #expect(topic.tags == ["纯水"])
    }

    @Test("User API key auth URL and callback payload are strict")
    func authURLAndPayload() throws {
        let url = try LinuxDoAuthService.authURL(
            baseURL: try #require(URL(string: "https://linux.do")),
            clientID: "client-1",
            nonce: "nonce-1",
            publicKeyPEM: "-----BEGIN PUBLIC KEY-----\nabc\n-----END PUBLIC KEY-----"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.path == "/user-api-key/new")
        #expect(query["client_id"] == "client-1")
        #expect(query["nonce"] == "nonce-1")
        #expect(query["scopes"] == "read,notifications,session_info")
        #expect(query["auth_redirect"] == "claude-stats://linuxdo-auth")
        #expect(query["padding"] == "oaep")

        let callback = try #require(URL(string: "claude-stats://linuxdo-auth?payload=abc123"))
        #expect(try LinuxDoAuthService.payload(from: callback) == "abc123")

        let missingPayload = try #require(URL(string: "claude-stats://linuxdo-auth"))
        #expect(throws: LinuxDoAuthService.AuthError.missingPayload) {
            try LinuxDoAuthService.payload(from: missingPayload)
        }
    }

    @Test("Cache distinguishes fresh and stale list entries")
    func cacheFreshAndStale() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LinuxDoCache(rootURL: root)
        let list = LinuxDoTopicList(
            topics: [Self.topic(id: 1, title: "Cached")],
            page: 0,
            nextPage: 1,
            fetchedAt: Date(timeIntervalSince1970: 10)
        )

        try cache.writeTopicList(list, feed: .latest)

        let fresh = try #require(cache.readTopicList(feed: .latest, ttl: 100, now: Date()))
        #expect(fresh.list.topics.first?.title == "Cached")
        #expect(fresh.isStale == false)

        let stale = try #require(cache.readTopicList(feed: .latest, ttl: 5, now: Date().addingTimeInterval(10)))
        #expect(stale.isStale == true)
    }

    @Test("In-memory credential store covers save read and logout")
    func credentialStoreRoundTrip() {
        let store = InMemoryLinuxDoCredentialStore(clientID: "client-a")

        #expect(store.readAPIKey() == nil)
        #expect(store.readClientID() == "client-a")

        store.saveAPIKey("api-key")
        store.saveClientID("client-b")
        store.saveWebSession(Self.webSession(username: "tester"))

        #expect(store.readAPIKey() == "api-key")
        #expect(store.readClientID() == "client-b")
        #expect(store.readWebSession()?.username == "tester")
        #expect(store.readAuthCredential() == .userAPIKey(key: "api-key", clientID: "client-b"))

        store.deleteAPIKey()
        #expect(store.readAPIKey() == nil)
        #expect(store.readAuthCredential() == .webSession(Self.webSession(username: "tester")))

        store.deleteWebSession()
        #expect(store.readAuthCredential() == nil)
    }

    @Test("Store uses fresh cache without touching network")
    func storeUsesFreshCache() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LinuxDoCache(rootURL: root)
        let cached = LinuxDoTopicList(
            topics: [Self.topic(id: 2, title: "From Cache")],
            page: 0,
            nextPage: nil,
            fetchedAt: Date()
        )
        try cache.writeTopicList(cached, feed: .latest)

        let client = FakeLinuxDoClient(topicList: LinuxDoTopicList(
            topics: [Self.topic(id: 3, title: "From Network")],
            page: 0,
            nextPage: nil,
            fetchedAt: Date()
        ))
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: cache,
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadCurrentFeedIfNeeded()

        #expect(store.currentListState.topics.first?.title == "From Cache")
        #expect(client.fetchTopicListCalls == 0)
    }

    @Test("Notification sync skips history and delivers each new unread id once")
    func notificationsHighWaterMark() async {
        let preferences = Self.makePreferences()
        let credentials = InMemoryLinuxDoCredentialStore(apiKey: "api-key")
        let client = FakeLinuxDoClient(notifications: [Self.notification(id: 10)])
        let notificationService = FakeLinuxDoNotificationService()
        let store = LinuxDoStore(
            preferences: preferences,
            credentials: credentials,
            notificationService: notificationService,
            client: client
        )

        await store.refreshNotifications(announce: true)
        #expect(notificationService.sentIDs == [])
        #expect(preferences.linuxDoLastSeenNotificationID == 10)

        client.notifications = [Self.notification(id: 11), Self.notification(id: 10)]
        await store.refreshNotifications(announce: true)
        await store.refreshNotifications(announce: true)

        #expect(notificationService.sentIDs == [11])
        #expect(preferences.linuxDoLastSeenNotificationID == 11)
        #expect(preferences.linuxDoNotificationDeliveredIDs == [11])
    }

    @Test("Store treats web session as authenticated and clears it on sign out")
    func storeWebSessionAuthAndLogout() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(username: "tester"))
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: credentials,
            notificationService: FakeLinuxDoNotificationService(),
            client: FakeLinuxDoClient()
        )

        #expect(store.isAuthenticated)
        #expect(store.authenticationDescription == "Browser session")

        await store.signOut()

        #expect(credentials.readWebSession() == nil)
        #expect(!store.isAuthenticated)
    }

    @Test("Client sends API key credentials")
    func clientSendsAPIKeyCredentials() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(apiKey: "api-key", clientID: "client-id")
        let client = Self.makeClient(credentials: credentials) { request in
            #expect(request.value(forHTTPHeaderField: "User-Api-Key") == "api-key")
            #expect(request.value(forHTTPHeaderField: "User-Api-Client-Id") == "client-id")
            return Self.response(body: Self.currentUserJSON)
        }

        _ = try await client.fetchCurrentUser()
    }

    @Test("Client sends web session cookies")
    func clientSendsWebSessionCookies() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession(csrfToken: "csrf-token"))
        let client = Self.makeClient(credentials: credentials) { request in
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("_t=session-token") == true)
            #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "csrf-token")
            #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
            #expect(request.value(forHTTPHeaderField: "Discourse-Logged-In") == "true")
            return Self.response(body: Self.currentUserJSON)
        }

        _ = try await client.fetchCurrentUser()
    }

    @Test("Client retries public feed as guest after stale web session unauthorized")
    func clientRetriesPublicFeedAsGuest() async throws {
        let credentials = InMemoryLinuxDoCredentialStore(webSession: Self.webSession())
        let calls = LinuxDoCallCounter()
        let client = Self.makeClient(credentials: credentials) { request in
            let call = calls.increment()
            if call == 1 {
                #expect(request.value(forHTTPHeaderField: "Cookie") != nil)
                return Self.response(status: 401, body: "{}")
            }
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            return Self.response(body: Self.topicListJSON)
        }

        let list = try await client.fetchTopicList(feed: LinuxDoFeed.latest, page: 0, now: Date())

        #expect(calls.value == 2)
        #expect(credentials.readWebSession() == nil)
        #expect(list.topics.first?.title == "Guest Topic")
    }

    private static func makePreferences() -> Preferences {
        let suiteName = "ClaudeStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return Preferences(defaults: defaults)
    }

    private static func topic(id: Int, title: String) -> LinuxDoTopicSummary {
        LinuxDoTopicSummary(
            id: id,
            title: title,
            fancyTitle: nil,
            slug: "topic-\(id)",
            categoryID: nil,
            tags: [],
            excerpt: nil,
            postsCount: 1,
            replyCount: 0,
            views: 0,
            likeCount: 0,
            createdAt: nil,
            bumpedAt: nil,
            lastPostedAt: nil,
            imageURL: nil
        )
    }

    nonisolated fileprivate static func detail(id: Int = 1) -> LinuxDoTopicDetail {
        LinuxDoTopicDetail(
            id: id,
            title: "Detail",
            fancyTitle: nil,
            slug: "detail",
            categoryID: nil,
            tags: [],
            postsCount: 1,
            stream: [100],
            posts: [
                LinuxDoPost(
                    id: 100,
                    topicID: id,
                    postNumber: 1,
                    username: "user",
                    name: nil,
                    avatarURL: nil,
                    cookedHTML: "<p>Hello</p>",
                    createdAt: nil,
                    updatedAt: nil,
                    likeCount: 0,
                    replyCount: 0
                ),
            ],
            fetchedAt: Date()
        )
    }

    private static func notification(id: Int) -> LinuxDoNotification {
        LinuxDoNotification(
            id: id,
            notificationType: 1,
            read: false,
            createdAt: nil,
            topicID: 1,
            postNumber: 1,
            slug: "topic",
            title: "Notification \(id)",
            excerpt: "Body"
        )
    }

    nonisolated private static func webSession(csrfToken: String? = nil, username: String? = nil) -> LinuxDoWebSession {
        LinuxDoWebSession(
            cookies: [
                LinuxDoStoredCookie(name: "_t", value: "session-token", domain: ".linux.do"),
                LinuxDoStoredCookie(name: "_forum_session", value: "forum-session", domain: "linux.do"),
                LinuxDoStoredCookie(name: "cf_clearance", value: "clearance", domain: ".linux.do"),
            ],
            csrfToken: csrfToken,
            username: username,
            savedAt: Date(timeIntervalSince1970: 100)
        )
    }

    nonisolated private static let currentUserJSON = """
    {
      "current_user": {
        "id": 1,
        "username": "tester",
        "name": "Tester",
        "avatar_template": "/user_avatar/linux.do/tester/{size}/1.png"
      }
    }
    """

    nonisolated private static let topicListJSON = """
    {
      "topic_list": {
        "topics": [
          { "id": 1, "title": "Guest Topic", "slug": "guest-topic", "tags": [] }
        ]
      }
    }
    """

    nonisolated private static func response(status: Int = 200, body: String, headers: [String: String] = [:]) -> MockLinuxDoResponse {
        MockLinuxDoResponse(status: status, headers: headers, data: Data(body.utf8))
    }

    nonisolated private static func makeClient(
        credentials: InMemoryLinuxDoCredentialStore,
        handler: @escaping @Sendable (URLRequest) throws -> MockLinuxDoResponse
    ) -> LinuxDoClient {
        MockLinuxDoURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockLinuxDoURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return LinuxDoClient(baseURL: URL(string: "https://linux.do")!, session: session, credentials: credentials)
    }

    nonisolated private static func decodeLinuxDoDate(from decoder: Decoder) throws -> Date {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
    }
}

private final class FakeLinuxDoClient: LinuxDoClienting, @unchecked Sendable {
    var topicList: LinuxDoTopicList
    var notifications: [LinuxDoNotification]
    var fetchTopicListCalls = 0

    init(
        topicList: LinuxDoTopicList = LinuxDoTopicList(topics: [], page: 0, nextPage: nil, fetchedAt: Date()),
        notifications: [LinuxDoNotification] = []
    ) {
        self.topicList = topicList
        self.notifications = notifications
    }

    func fetchTopicList(feed: LinuxDoFeed, page: Int, now: Date) async throws -> LinuxDoTopicList {
        fetchTopicListCalls += 1
        return topicList
    }

    func fetchCategories() async throws -> [LinuxDoCategory] {
        []
    }

    func fetchTopic(id: Int, slug: String?, now: Date) async throws -> LinuxDoTopicDetail {
        LinuxDoTests.detail(id: id)
    }

    func fetchPosts(topicID: Int, postIDs: [Int]) async throws -> [LinuxDoPost] {
        []
    }

    func fetchCurrentUser() async throws -> LinuxDoCurrentUser {
        LinuxDoCurrentUser(id: 1, username: "tester", name: nil, avatarURL: nil)
    }

    func fetchCSRFToken() async throws -> String {
        "csrf-token"
    }

    func fetchNotifications(limit: Int) async throws -> [LinuxDoNotification] {
        notifications
    }

    func revokeUserAPIKey() async {}
}

private struct MockLinuxDoResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let data: Data
}

private final class LinuxDoCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class MockLinuxDoURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> MockLinuxDoResponse)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let mock = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: mock.status,
                httpVersion: nil,
                headerFields: mock.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class FakeLinuxDoNotificationService: LinuxDoNotificationServicing, @unchecked Sendable {
    var sentIDs: [Int] = []
    var status: LinuxDoNotificationAuthorizationStatus = .authorized

    func authorizationStatus() async -> LinuxDoNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> LinuxDoNotificationAuthorizationStatus {
        status
    }

    func send(notification: LinuxDoNotification) async throws {
        sentIDs.append(notification.id)
    }
}
