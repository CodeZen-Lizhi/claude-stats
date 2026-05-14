import Foundation

/// On-disk JSON cache of the last successful GitHub contributions fetch, keyed
/// by `login`. Lets the dashboard render instantly on reopen and survive
/// offline / rate-limit windows. One file per login means switching accounts
/// doesn't poison another user's cache.
struct GitHubCalendarCache: Sendable {
    static let defaultTTL: TimeInterval = 6 * 60 * 60

    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleID = Bundle.main.bundleIdentifier ?? "com.claudestats.ClaudeStats"
        self.directory = caches.appendingPathComponent(bundleID).appendingPathComponent("github")
    }

    /// Returns `(snapshot, isStale)` where `isStale` is true when the snapshot
    /// is older than `ttl`. Returns `nil` when there is no readable cache
    /// (missing file, unreadable JSON, etc).
    func read(login: String, ttl: TimeInterval = defaultTTL, now: Date = .now) -> (snapshot: GitHubClient.CalendarSnapshot, isStale: Bool)? {
        let url = fileURL(login: login)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let snapshot = try decoder.decode(GitHubClient.CalendarSnapshot.self, from: data)
            let age = now.timeIntervalSince(snapshot.fetchedAt)
            return (snapshot, age > ttl)
        } catch {
            Log.app.error("GitHub cache decode failed for \(login, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Atomically write a snapshot. Creates the cache directory on first use.
    func write(_ snapshot: GitHubClient.CalendarSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(login: snapshot.login), options: .atomic)
    }

    /// Delete the cache for one login. Missing-file is treated as success.
    func delete(login: String) {
        let url = fileURL(login: login)
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // OK — nothing to delete.
        } catch {
            Log.app.error("GitHub cache delete failed for \(login, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wipe the entire cache directory — used as a defensive measure on
    /// unexpected decode failures.
    func clearAll() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch CocoaError.fileNoSuchFile {
            // OK.
        } catch {
            Log.app.error("GitHub cache clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(login: String) -> URL {
        // `login` is restricted by GitHub to `[A-Za-z0-9-]`, so it's safe as a
        // filename. Still sanitise to be defensive.
        let safe = login.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }
}
