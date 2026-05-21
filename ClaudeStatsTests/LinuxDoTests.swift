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

    @Test("Cooked HTML is reduced to ordered native blocks")
    func cookedHTMLBlocks() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p>Hello &amp; welcome</p>
        <blockquote>Keep it native</blockquote>
        <pre><code>if true {
            print(&quot;hi&quot;)
        }</code></pre>
        <ul><li>One</li><li>Two</li></ul>
        <img src="/uploads/test.png">
        """)

        #expect(blocks.count == 5)
        #expect(Self.plainText(blocks[0]) == "Hello & welcome")
        if case .quote(attribution: _, blocks: let quoteBlocks) = blocks[1].kind {
            #expect(Self.plainText(quoteBlocks.first) == "Keep it native")
        } else {
            Issue.record("Expected a quote block")
        }
        if case .codeBlock(_, let code) = blocks[2].kind {
            #expect(code.contains("print(\"hi\")"))
            #expect(code.contains("    "))
        } else {
            Issue.record("Expected a code block")
        }
        if case .list(false, let items) = blocks[3].kind {
            #expect(items.map { Self.plainText($0.blocks.first) } == ["One", "Two"])
        } else {
            Issue.record("Expected an unordered list")
        }
        if case .image(let url, _, _, _, _) = blocks[4].kind {
            #expect(url == URL(string: "https://linux.do/uploads/test.png")!)
        } else {
            Issue.record("Expected an image block")
        }
    }

    @Test("Paragraph-wrapped post images become native image blocks")
    func paragraphWrappedImagesBecomeBlocks() {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p>Before <img class="emoji" src="/emoji/apple/wave.png" alt=":wave:"> after</p>
        <p><img src="/uploads/direct.png" alt="Direct"></p>
        <p><a href="/uploads/original.png"><img src="/uploads/thumb.png" alt="Linked"></a></p>
        """)

        #expect(blocks.count == 3)
        #expect(Self.plainText(blocks[0]) == "Before :wave: after")
        if case .image(let url, let alt, _, _, let linkURL) = blocks[1].kind {
            #expect(url == URL(string: "https://linux.do/uploads/direct.png")!)
            #expect(alt == "Direct")
            #expect(linkURL == nil)
        } else {
            Issue.record("Expected a direct image block")
        }
        if case .image(let url, let alt, _, _, let linkURL) = blocks[2].kind {
            #expect(url == URL(string: "https://linux.do/uploads/thumb.png")!)
            #expect(alt == "Linked")
            #expect(linkURL == URL(string: "https://linux.do/uploads/original.png")!)
        } else {
            Issue.record("Expected a linked image block")
        }
    }

    @Test("Store caches parsed post blocks and invalidates when post content changes")
    func storeCachesParsedPostBlocks() {
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore()
        )
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let post = Self.post(
            id: 100,
            topicID: 1,
            postNumber: 1,
            cookedHTML: "<p>First</p>",
            updatedAt: updatedAt
        )

        let first = store.contentBlocks(for: post)
        let second = store.contentBlocks(for: post)

        #expect(first == second)
        #expect(Self.plainText(first.first) == "First")

        let changedHTML = Self.post(
            id: 100,
            topicID: 1,
            postNumber: 1,
            cookedHTML: "<p>Second</p>",
            updatedAt: updatedAt
        )
        let changedHTMLBlocks = store.contentBlocks(for: changedHTML)
        #expect(Self.plainText(changedHTMLBlocks.first) == "Second")

        let changedUpdatedAt = Self.post(
            id: 100,
            topicID: 1,
            postNumber: 1,
            cookedHTML: "<p>Third</p>",
            updatedAt: updatedAt.addingTimeInterval(1)
        )
        let changedUpdatedAtBlocks = store.contentBlocks(for: changedUpdatedAt)
        #expect(Self.plainText(changedUpdatedAtBlocks.first) == "Third")
    }

    @Test("Cooked HTML preserves rich Discourse shapes")
    func cookedHTMLRichDiscourseShapes() throws {
        let blocks = LinuxDoContentParser.blocks(from: """
        <p><a class="mention" href="/u/alice">@alice</a> see <a href="/t/dexo/42">Dexo</a> <span class="spoiler">hidden</span> <a class="hashtag-cooked" href="/tag/swift">#swift</a></p>
        <details><summary>More</summary><p>Inside</p></details>
        <table><thead><tr><th>Name</th><th>Link</th></tr></thead><tbody><tr><td>Dexo</td><td><a href="/t/dexo/42">Topic</a></td></tr></tbody></table>
        <aside class="onebox"><header><a href="https://github.com/Eilgnaw/dexo">Dexo</a></header><p>Native client</p></aside>
        """)

        #expect(blocks.count == 4)
        if case .paragraph(let nodes) = blocks[0].kind {
            #expect(nodes.contains(.mention(username: "alice", url: URL(string: "https://linux.do/u/alice")!)))
            #expect(nodes.contains(.hashtag(text: "#swift", url: URL(string: "https://linux.do/tag/swift")!)))
            #expect(Self.plainText(nodes).contains("hidden"))
            guard case .some(.link(let url, _)) = nodes.first(where: {
                if case .link = $0 { return true }
                return false
            }) else {
                Issue.record("Expected a link node")
                return
            }
            #expect(url == URL(string: "https://linux.do/t/dexo/42")!)
        } else {
            Issue.record("Expected a rich paragraph")
        }

        if case .details(let summary, let childBlocks) = blocks[1].kind {
            #expect(Self.plainText(summary) == "More")
            #expect(Self.plainText(childBlocks.first) == "Inside")
        } else {
            Issue.record("Expected details block")
        }

        if case .table(let headers, let rows) = blocks[2].kind {
            #expect(headers.count == 2)
            #expect(Self.plainText(headers[0].first) == "Name")
            #expect(Self.plainText(headers[1].first) == "Link")
            #expect(rows.first?.count == 2)
            #expect(Self.plainText(rows.first?[1].first) == "Topic")
        } else {
            Issue.record("Expected table block")
        }

        if case .onebox(let onebox) = blocks[3].kind {
            #expect(onebox.title == "Dexo")
            #expect(onebox.description == "Native client")
            #expect(onebox.url == URL(string: "https://github.com/Eilgnaw/dexo")!)
        } else {
            Issue.record("Expected onebox block")
        }
    }

    @Test("Post response optional Discourse metadata decodes without breaking older shapes")
    func postResponseMetadataDecode() throws {
        let rich = try JSONDecoder().decode(PostResponse.self, from: Data("""
        {
          "id": 10,
          "topic_id": 3,
          "post_number": 2,
          "reply_to_post_number": 1,
          "username": "alice",
          "cooked": "<p>Hello</p>",
          "reads": 12,
          "score": 3.5,
          "actions_summary": [
            { "id": 2, "count": 8, "acted": true, "ignored": "ok" }
          ]
        }
        """.utf8)).model

        #expect(rich.replyToPostNumber == 1)
        #expect(rich.reads == 12)
        #expect(rich.score == 3.5)
        #expect(rich.actionsSummary == [LinuxDoPostActionSummary(id: 2, count: 8, acted: true)])

        let old = try JSONDecoder().decode(PostResponse.self, from: Data("""
        { "id": 11, "post_number": 1, "username": "bob", "cooked": "<p>Old</p>" }
        """.utf8)).model

        #expect(old.replyToPostNumber == nil)
        #expect(old.reads == 0)
        #expect(old.score == nil)
        #expect(old.actionsSummary.isEmpty)
    }

    @Test("LinuxDo topic URLs map to native topic routes")
    func topicRouteParsesLinuxDoURLs() throws {
        let routed = try #require(LinuxDoTopicRoute(url: URL(string: "https://linux.do/t/dexo/42/7")!))
        #expect(routed.id == 42)
        #expect(routed.slug == "dexo")
        #expect(routed.postNumber == 7)

        let compact = try #require(LinuxDoTopicRoute(url: URL(string: "https://linux.do/t/42/3")!))
        #expect(compact.id == 42)
        #expect(compact.slug == nil)
        #expect(compact.postNumber == 3)

        #expect(LinuxDoTopicRoute(url: URL(string: "https://example.com/t/dexo/42")!) == nil)
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

    @Test("External browser auth prepares URL and requires a pending request")
    func externalBrowserAuthLifecycle() throws {
        let credentials = InMemoryLinuxDoCredentialStore(clientID: "client-browser")
        let service = LinuxDoAuthService(
            baseURL: try #require(URL(string: "https://linux.do")),
            credentials: credentials
        )

        let url = try service.beginExternalBrowserLogin()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.path == "/user-api-key/new")
        #expect(query["client_id"] == "client-browser")
        #expect(query["auth_redirect"] == "claude-stats://linuxdo-auth")
        #expect(service.hasPendingExternalBrowserLogin)
        #expect(LinuxDoAuthService.isCallbackURL(try #require(URL(string: "claude-stats://linuxdo-auth?payload=abc"))))
        #expect(LinuxDoAuthService.isCallbackURL(try #require(URL(string: "claude-stats:/linuxdo-auth?payload=abc"))))

        service.cancelExternalBrowserLogin()
        #expect(!service.hasPendingExternalBrowserLogin)
        #expect(throws: LinuxDoAuthService.AuthError.noPendingExternalLogin) {
            try service.completeExternalBrowserLogin(
                callbackURL: try #require(URL(string: "claude-stats://linuxdo-auth?payload=abc"))
            )
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

    @Test("Jump to post index loads a stream window and keeps post order stable")
    func jumpToPostIndexLoadsMissingPosts() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 9,
            postsCount: 5,
            stream: [100, 101, 102, 103, 104],
            posts: [
                Self.post(id: 100, topicID: 9, postNumber: 1),
                Self.post(id: 104, topicID: 9, postNumber: 5),
            ]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [
                101: Self.post(id: 101, topicID: 9, postNumber: 2),
                102: Self.post(id: 102, topicID: 9, postNumber: 3),
                103: Self.post(id: 103, topicID: 9, postNumber: 4),
            ]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 9, slug: "jump", force: true)

        let alreadyLoaded = await store.jumpToPostIndex(topicID: 9, index: 0)
        #expect(alreadyLoaded == 100)
        #expect(client.fetchPostsBatches.isEmpty)

        let target = await store.jumpToPostIndex(topicID: 9, index: 2)
        let state = try #require(store.topicStates[9])

        #expect(target == 102)
        #expect(state.scrollTargetPostID == 102)
        #expect(state.detail?.posts.map(\.id) == [100, 101, 102, 103, 104])
        #expect(client.fetchPostsBatches == [[101, 102, 103]])
    }

    @Test("Notification open loads the topic and targets the notification post number")
    func notificationOpenTargetsPostNumber() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 12,
            postsCount: 3,
            stream: [200, 201, 202],
            posts: [Self.post(id: 200, topicID: 12, postNumber: 1)]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [
                201: Self.post(id: 201, topicID: 12, postNumber: 2),
                202: Self.post(id: 202, topicID: 12, postNumber: 3),
            ]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        let target = await store.openNotificationAndWait(Self.notification(id: 40, topicID: 12, postNumber: 2, slug: "notice"))
        let state = try #require(store.topicStates[12])

        #expect(store.selectedTopicID == 12)
        #expect(target == 201)
        #expect(state.scrollTargetPostID == 201)
    }

    @Test("Jump to post index warns when LinuxDo omits the target post")
    func jumpToPostIndexWarnsWhenTargetIsMissing() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let detail = Self.detail(
            id: 14,
            postsCount: 3,
            stream: [300, 301, 302],
            posts: [Self.post(id: 300, topicID: 14, postNumber: 1)]
        )
        let client = FakeLinuxDoClient(
            topicDetail: detail,
            postsByID: [302: Self.post(id: 302, topicID: 14, postNumber: 3)]
        )
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: InMemoryLinuxDoCredentialStore(),
            cache: LinuxDoCache(rootURL: root),
            notificationService: FakeLinuxDoNotificationService(),
            client: client
        )

        await store.loadTopic(id: 14, slug: "missing", force: true)
        let target = await store.jumpToPostIndex(topicID: 14, index: 1)
        let state = try #require(store.topicStates[14])

        #expect(target == nil)
        #expect(state.scrollTargetPostID == nil)
        #expect(state.timelineWarning == "That floor could not be loaded from Linux.do.")
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

    @Test("Store caches auth summary for render-time access")
    func storeCachesAuthSummaryForRenderAccess() {
        let credentials = CountingLinuxDoCredentialStore(webSession: Self.webSession(username: "tester"))
        let store = LinuxDoStore(
            preferences: Self.makePreferences(),
            credentials: credentials,
            notificationService: FakeLinuxDoNotificationService(),
            client: FakeLinuxDoClient()
        )

        let readsAfterInit = credentials.readCount

        #expect(store.isAuthenticated)
        #expect(store.authenticationDescription == "Browser session")
        #expect(store.authenticationStatus.username == "tester")
        #expect(credentials.readCount == readsAfterInit)

        credentials.deleteWebSession()
        store.refreshAuthenticationState()

        #expect(!store.isAuthenticated)
        #expect(store.authenticationDescription == "Guest")
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

    nonisolated fileprivate static func detail(
        id: Int = 1,
        postsCount: Int = 1,
        stream: [Int] = [100],
        posts: [LinuxDoPost]? = nil
    ) -> LinuxDoTopicDetail {
        LinuxDoTopicDetail(
            id: id,
            title: "Detail",
            fancyTitle: nil,
            slug: "detail",
            categoryID: nil,
            tags: [],
            postsCount: postsCount,
            stream: stream,
            posts: posts ?? [Self.post(id: 100, topicID: id, postNumber: 1)],
            fetchedAt: Date()
        )
	}

    nonisolated private static func post(
        id: Int,
        topicID: Int,
        postNumber: Int,
        cookedHTML: String? = nil,
        updatedAt: Date? = nil
    ) -> LinuxDoPost {
        LinuxDoPost(
            id: id,
            topicID: topicID,
            postNumber: postNumber,
            replyToPostNumber: postNumber > 1 ? 1 : nil,
            username: "user\(postNumber)",
            name: nil,
            avatarURL: nil,
            cookedHTML: cookedHTML ?? "<p>Post \(postNumber)</p>",
            createdAt: nil,
            updatedAt: updatedAt,
            likeCount: 0,
            replyCount: 0,
            reads: 0,
            score: nil,
            actionsSummary: []
        )
    }

    private static func plainText(_ block: LinuxDoContentBlock?) -> String {
        guard let block else { return "" }
        switch block.kind {
        case .paragraph(let nodes):
            return plainText(nodes)
        case .heading(level: _, content: let nodes):
            return plainText(nodes)
        case .quote(attribution: _, blocks: let blocks):
            return blocks.map { plainText($0) }.joined(separator: " ")
        case .spoiler(let blocks):
            return blocks.map { plainText($0) }.joined(separator: " ")
        case .details(summary: _, blocks: let blocks):
            return blocks.map { plainText($0) }.joined(separator: " ")
        case .codeBlock(_, let code), .rawHTML(let code):
            return code
        case .list(_, let items):
            return items.map { $0.blocks.map { plainText($0) }.joined(separator: " ") }.joined(separator: " ")
        case .image, .onebox, .table, .divider:
            return ""
        }
    }

    private static func plainText(_ nodes: [LinuxDoInlineNode]) -> String {
        nodes.map { node in
            switch node {
            case .text(let text), .code(let text):
                return text
            case .strong(let children), .emphasis(let children), .strikethrough(let children), .spoiler(let children):
                return plainText(children)
            case .link(_, let children):
                return plainText(children)
            case .image(_, let alt, _, _, _):
                return alt ?? ""
            case .mention(let username, _):
                return "@\(username)"
            case .hashtag(let text, _):
                return text
            case .lineBreak:
                return "\n"
            }
        }.joined()
    }

    private static func notification(
        id: Int,
        topicID: Int? = 1,
        postNumber: Int? = 1,
        slug: String? = "topic"
    ) -> LinuxDoNotification {
        LinuxDoNotification(
            id: id,
            notificationType: 1,
            read: false,
            createdAt: nil,
            topicID: topicID,
            postNumber: postNumber,
            slug: slug,
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
    var topicDetail: LinuxDoTopicDetail?
    var postsByID: [Int: LinuxDoPost]
    var notifications: [LinuxDoNotification]
    var fetchTopicListCalls = 0
    var fetchPostsBatches: [[Int]] = []

    init(
        topicList: LinuxDoTopicList = LinuxDoTopicList(topics: [], page: 0, nextPage: nil, fetchedAt: Date()),
        topicDetail: LinuxDoTopicDetail? = nil,
        postsByID: [Int: LinuxDoPost] = [:],
        notifications: [LinuxDoNotification] = []
    ) {
        self.topicList = topicList
        self.topicDetail = topicDetail
        self.postsByID = postsByID
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
        topicDetail ?? LinuxDoTests.detail(id: id)
    }

    func fetchPosts(topicID: Int, postIDs: [Int]) async throws -> [LinuxDoPost] {
        fetchPostsBatches.append(postIDs)
        return postIDs.compactMap { postsByID[$0] }
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

private final class CountingLinuxDoCredentialStore: LinuxDoCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var apiKey: String?
    private var clientID: String
    private var webSession: LinuxDoWebSession?
    private var apiKeyReads = 0
    private var webSessionReads = 0

    init(apiKey: String? = nil, clientID: String = "test-client-id", webSession: LinuxDoWebSession? = nil) {
        self.apiKey = apiKey
        self.clientID = clientID
        self.webSession = webSession
    }

    var readCount: Int {
        lock.withLock { apiKeyReads + webSessionReads }
    }

    func readAPIKey() -> String? {
        lock.withLock {
            apiKeyReads += 1
            return apiKey
        }
    }

    func saveAPIKey(_ apiKey: String) {
        lock.withLock { self.apiKey = apiKey }
    }

    func deleteAPIKey() {
        lock.withLock { apiKey = nil }
    }

    func readWebSession() -> LinuxDoWebSession? {
        lock.withLock {
            webSessionReads += 1
            return webSession
        }
    }

    func saveWebSession(_ session: LinuxDoWebSession) {
        lock.withLock { webSession = session }
    }

    func deleteWebSession() {
        lock.withLock { webSession = nil }
    }

    func readClientID() -> String {
        lock.withLock { clientID }
    }

    func saveClientID(_ clientID: String) {
        lock.withLock { self.clientID = clientID }
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
