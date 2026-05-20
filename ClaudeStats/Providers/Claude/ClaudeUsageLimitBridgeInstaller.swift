import Foundation

protocol ClaudeUsageLimitBridgeInstalling: Sendable {
    var scriptURL: URL { get }
    var cacheURL: URL { get }
    var settingsURL: URL { get }

    func install() throws -> ClaudeUsageLimitBridgeConfiguration
    func settingsSnippet() -> String
}

struct ClaudeUsageLimitBridgeConfiguration: Sendable, Hashable {
    let scriptURL: URL
    let cacheURL: URL
    let settingsURL: URL
    let settingsSnippet: String
}

struct ClaudeUsageLimitBridgeInstaller: ClaudeUsageLimitBridgeInstalling {
    let paths: ClaudePaths

    init(paths: ClaudePaths = .default) {
        self.paths = paths
    }

    var scriptURL: URL { UsageLimitCachePaths.claudeBridgeScriptURL() }
    var cacheURL: URL { UsageLimitCachePaths.claudeCacheURL() }
    var settingsURL: URL { paths.configDirectory.appendingPathComponent("settings.json", isDirectory: false) }

    func install() throws -> ClaudeUsageLimitBridgeConfiguration {
        let directory = scriptURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try bridgeScript(cacheURL: cacheURL).write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return ClaudeUsageLimitBridgeConfiguration(
            scriptURL: scriptURL,
            cacheURL: cacheURL,
            settingsURL: settingsURL,
            settingsSnippet: settingsSnippet()
        )
    }

    func settingsSnippet() -> String {
        """
        {
          "statusLine": {
            "type": "command",
            "command": "\(jsonEscaped(scriptURL.path))"
          }
        }
        """
    }

    private func bridgeScript(cacheURL: URL) -> String {
        let cachePath = shellSingleQuoted(cacheURL.path)
        return """
        #!/bin/sh
        set -eu

        CACHE=\(cachePath)
        DIR=$(/usr/bin/dirname "$CACHE")
        TMP="${CACHE}.$$"
        INPUT=$(/bin/cat)

        /bin/mkdir -p "$DIR"
        if /usr/bin/printf "%s" "$INPUT" | /usr/bin/plutil -extract rate_limits json -o "$TMP" - 2>/dev/null; then
          if [ -s "$TMP" ] && ! /usr/bin/grep -qx 'null' "$TMP"; then
            /bin/mv "$TMP" "$CACHE"
          else
            /bin/rm -f "$TMP"
          fi
        else
          /bin/rm -f "$TMP"
        fi

        exit 0
        """
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
