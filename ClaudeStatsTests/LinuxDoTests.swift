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
                "tags": ["mac"],
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
        #expect(topic.displayExcerpt == "Native & fast")
        #expect(topic.imageURL?.absoluteString == "https://linux.do/uploads/default/original/1X/image.png")
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

        #expect(store.readAPIKey() == "api-key")
        #expect(store.readClientID() == "client-b")

        store.deleteAPIKey()
        #expect(store.readAPIKey() == nil)
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

    func fetchNotifications(limit: Int) async throws -> [LinuxDoNotification] {
        notifications
    }

    func revokeUserAPIKey() async {}
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
