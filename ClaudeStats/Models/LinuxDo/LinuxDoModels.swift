import Foundation

enum LinuxDoTopPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        case .all: "All Time"
        }
    }
}

enum LinuxDoFeed: Hashable, Codable, Sendable, Identifiable {
    case latest
    case hot
    case top(LinuxDoTopPeriod)
    case category(id: Int, name: String, slug: String)
    case search(String)

    var id: String { key }

    var key: String {
        switch self {
        case .latest: "latest"
        case .hot: "hot"
        case .top(let period): "top:\(period.rawValue)"
        case .category(let id, _, _): "category:\(id)"
        case .search(let query): "search:\(query.lowercased())"
        }
    }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .hot: "Hot"
        case .top(let period): "Top \(period.displayName)"
        case .category(_, let name, _): name
        case .search(let query): "Search: \(query)"
        }
    }

    var cacheTTL: TimeInterval {
        switch self {
        case .latest, .hot: 5 * 60
        case .top: 30 * 60
        case .category: 10 * 60
        case .search: 15 * 60
        }
    }

    var storedValue: String {
        switch self {
        case .latest: "latest"
        case .hot: "hot"
        case .top(let period): "top|\(period.rawValue)"
        case .category(let id, let name, let slug): "category|\(id)|\(name)|\(slug)"
        case .search(let query): "search|\(query)"
        }
    }

    static func stored(_ raw: String) -> LinuxDoFeed? {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first else { return nil }
        switch head {
        case "latest": return .latest
        case "hot": return .hot
        case "top":
            guard parts.count >= 2, let period = LinuxDoTopPeriod(rawValue: parts[1]) else { return nil }
            return .top(period)
        case "category":
            guard parts.count >= 4, let id = Int(parts[1]) else { return nil }
            return .category(id: id, name: parts[2], slug: parts[3])
        case "search":
            guard parts.count >= 2, !parts[1].isEmpty else { return nil }
            return .search(parts[1])
        default:
            return nil
        }
    }
}

struct LinuxDoCategory: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let slug: String
    let colorHex: String?
    let textColorHex: String?
    let topicCount: Int
}

struct LinuxDoUser: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarURL: URL?
}

struct LinuxDoTopicSummary: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let slug: String?
    let categoryID: Int?
    let tags: [String]
    let excerpt: String?
    let postsCount: Int
    let replyCount: Int
    let views: Int
    let likeCount: Int
    let createdAt: Date?
    let bumpedAt: Date?
    let lastPostedAt: Date?
    let imageURL: URL?

    var displayTitle: String {
        let candidate = (fancyTitle?.isEmpty == false ? fancyTitle : title) ?? title
        return candidate.htmlStrippedAndDecoded
    }

    var displayExcerpt: String {
        (excerpt ?? "").htmlStrippedAndDecoded
    }

    var topicURL: URL? {
        guard let slug else {
            return URL(string: "https://linux.do/t/topic/\(id)")
        }
        return URL(string: "https://linux.do/t/\(slug)/\(id)")
    }
}

struct LinuxDoTopicDetail: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let slug: String?
    let categoryID: Int?
    let tags: [String]
    let postsCount: Int
    let stream: [Int]
    var posts: [LinuxDoPost]
    let fetchedAt: Date

    var displayTitle: String {
        let candidate = (fancyTitle?.isEmpty == false ? fancyTitle : title) ?? title
        return candidate.htmlStrippedAndDecoded
    }

    var topicURL: URL? {
        guard let slug else {
            return URL(string: "https://linux.do/t/topic/\(id)")
        }
        return URL(string: "https://linux.do/t/\(slug)/\(id)")
    }
}

struct LinuxDoPost: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let topicID: Int?
    let postNumber: Int
    let username: String
    let name: String?
    let avatarURL: URL?
    let cookedHTML: String
    let createdAt: Date?
    let updatedAt: Date?
    let likeCount: Int
    let replyCount: Int

    var textPreview: String {
        cookedHTML.htmlStrippedAndDecoded
    }
}

struct LinuxDoTopicList: Codable, Sendable {
    var topics: [LinuxDoTopicSummary]
    var page: Int
    var nextPage: Int?
    var fetchedAt: Date
}

struct LinuxDoNotification: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let notificationType: Int
    let read: Bool
    let createdAt: Date?
    let topicID: Int?
    let postNumber: Int?
    let slug: String?
    let title: String?
    let excerpt: String?

    var displayTitle: String {
        (title?.isEmpty == false ? title : "Linux.do notification") ?? "Linux.do notification"
    }

    var displayBody: String {
        (excerpt ?? "").htmlStrippedAndDecoded
    }

    var topicURL: URL? {
        guard let topicID else { return nil }
        let slug = slug?.isEmpty == false ? slug! : "topic"
        if let postNumber, postNumber > 1 {
            return URL(string: "https://linux.do/t/\(slug)/\(topicID)/\(postNumber)")
        }
        return URL(string: "https://linux.do/t/\(slug)/\(topicID)")
    }
}

struct LinuxDoCurrentUser: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarURL: URL?
}

struct LinuxDoStoredCookie: Codable, Hashable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = true,
        isHTTPOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    init(cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresAt: cookie.expiresDate,
            isSecure: cookie.isSecure,
            isHTTPOnly: cookie.isHTTPOnly
        )
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var isLinuxDoCookie: Bool {
        let normalized = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return normalized == "linux.do" || normalized.hasSuffix(".linux.do")
    }
}

struct LinuxDoWebSession: Codable, Hashable, Sendable {
    var cookies: [LinuxDoStoredCookie]
    var csrfToken: String?
    var username: String?
    var savedAt: Date

    init(cookies: [LinuxDoStoredCookie], csrfToken: String? = nil, username: String? = nil, savedAt: Date = .now) {
        self.cookies = cookies
        self.csrfToken = csrfToken
        self.username = username
        self.savedAt = savedAt
    }

    var isAuthenticated: Bool {
        containsCookie(named: "_t")
    }

    func containsCookie(named name: String) -> Bool {
        cookies.contains { $0.name == name && !$0.isExpired && $0.isLinuxDoCookie && !$0.value.isEmpty }
    }

    func cookieHeader(now: Date = .now) -> String? {
        let liveCookies = cookies
            .filter { cookie in
                cookie.isLinuxDoCookie && !cookie.value.isEmpty && (cookie.expiresAt.map { $0 > now } ?? true)
            }
            .sorted { lhs, rhs in
                Self.cookieSortRank(lhs.name) < Self.cookieSortRank(rhs.name)
            }
        guard !liveCookies.isEmpty else { return nil }
        return liveCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func with(csrfToken: String?, username: String?) -> LinuxDoWebSession {
        LinuxDoWebSession(
            cookies: cookies,
            csrfToken: csrfToken ?? self.csrfToken,
            username: username ?? self.username,
            savedAt: .now
        )
    }

    private static func cookieSortRank(_ name: String) -> Int {
        switch name {
        case "_t": 0
        case "_forum_session": 1
        case "cf_clearance": 2
        default: 10
        }
    }
}

enum LinuxDoAuthCredential: Equatable, Sendable {
    case userAPIKey(key: String, clientID: String)
    case webSession(LinuxDoWebSession)
}

enum LinuxDoContentBlock: Hashable, Sendable, Identifiable {
    case paragraph(String)
    case quote(String)
    case code(String)
    case list([String])
    case image(URL)
    case link(title: String, url: URL)

    var id: String {
        switch self {
        case .paragraph(let text): "p:\(text.hashValue)"
        case .quote(let text): "q:\(text.hashValue)"
        case .code(let text): "c:\(text.hashValue)"
        case .list(let items): "l:\(items.hashValue)"
        case .image(let url): "i:\(url.absoluteString)"
        case .link(let title, let url): "a:\(title.hashValue):\(url.absoluteString)"
        }
    }
}

extension String {
    var htmlStrippedAndDecoded: String {
        let withoutTags = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
