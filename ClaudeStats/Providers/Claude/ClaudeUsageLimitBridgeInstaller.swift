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
        INCOMING="${CACHE}.$$.incoming"
        TMP="${CACHE}.$$"
        INPUT=$(/bin/cat)

        /bin/mkdir -p "$DIR"
        if /usr/bin/printf "%s" "$INPUT" | /usr/bin/plutil -extract rate_limits json -o "$INCOMING" - 2>/dev/null; then
          if [ -s "$INCOMING" ] && ! /usr/bin/grep -qx 'null' "$INCOMING"; then
            if command -v python3 >/dev/null 2>&1; then
              python3 -c '
        import json
        import sys

        cache_path, incoming_path, output_path = sys.argv[1:4]
        ordered_ids = ["five_hour", "seven_day", "weekly_claude_design", "sonnet_only"]

        def load_json(path):
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    value = json.load(handle)
                    return value if isinstance(value, dict) else {}
            except Exception:
                return {}

        def rate_limits(payload):
            nested = payload.get("rate_limits")
            if isinstance(nested, dict):
                return nested
            return {
                key: value
                for key, value in payload.items()
                if isinstance(value, dict)
            }

        existing = rate_limits(load_json(cache_path))
        incoming = rate_limits(load_json(incoming_path))
        merged = {}
        for key in ordered_ids:
            if key in existing:
                merged[key] = existing[key]
            if key in incoming:
                merged[key] = incoming[key]

        if not merged:
            sys.exit(1)

        payload = {
            "source": "claude_statusline",
            "rate_limits": merged,
        }
        with open(output_path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\\n")
        ' "$CACHE" "$INCOMING" "$TMP"
            else
              /bin/cp "$INCOMING" "$TMP"
            fi
            /bin/mv "$TMP" "$CACHE"
          else
            /bin/rm -f "$TMP" "$INCOMING"
          fi
        else
          /bin/rm -f "$TMP" "$INCOMING"
        fi
        /bin/rm -f "$INCOMING"

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
