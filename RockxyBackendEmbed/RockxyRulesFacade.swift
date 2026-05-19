import Foundation

public extension RockxyProxyBackend {
    func rules() async -> [RockxyProxyRuleSnapshot] {
        let native = await ruleEngine.allRules.map(Self.snapshot(from:))
        let inline = await inlineScriptRules()
        return (native + inline).sorted { lhs, rhs in
            if lhs.priority == rhs.priority { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return lhs.priority < rhs.priority
        }
    }

    func saveRule(_ snapshot: RockxyProxyRuleSnapshot) async throws {
        if snapshot.action.kind == .script {
            try await removeNativeRule(id: snapshot.id)
            try await saveInlineScriptRule(snapshot)
            return
        }

        try await removeInlineScriptRule(id: snapshot.id)
        var rules = await ruleEngine.allRules
        let native = try Self.nativeRule(from: snapshot)
        if let index = rules.firstIndex(where: { $0.id == snapshot.id }) {
            rules[index] = native
        } else {
            rules.append(native)
        }
        try await replaceNativeRules(rules)
    }

    func deleteRule(id: UUID) async throws {
        try await removeNativeRule(id: id)
        try await removeInlineScriptRule(id: id)
    }

    func setRuleEnabled(id: UUID, enabled: Bool) async throws {
        var rules = await ruleEngine.allRules
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled = enabled
            try await replaceNativeRules(rules)
            return
        }

        let pluginID = Self.inlinePluginID(for: id)
        if enabled {
            await pluginManager.scriptManager.loadAllPlugins()
            _ = try await pluginManager.scriptManager.enablePluginIfAllowed(id: pluginID, maxEnabled: Int.max)
        } else {
            await pluginManager.scriptManager.disablePlugin(id: pluginID)
        }
        try await updateInlineRuleMetadata(id: id) { $0.isEnabled = enabled }
    }

    func moveRule(id: UUID, before destinationID: UUID?) async throws {
        var snapshots = await rules()
        guard let source = snapshots.firstIndex(where: { $0.id == id }) else { return }
        let item = snapshots.remove(at: source)
        if let destinationID, let destination = snapshots.firstIndex(where: { $0.id == destinationID }) {
            snapshots.insert(item, at: destination)
        } else {
            snapshots.append(item)
        }
        for index in snapshots.indices {
            snapshots[index].priority = index
        }
        for snapshot in snapshots {
            try await saveRule(snapshot)
        }
    }

    func testRule(_ snapshot: RockxyProxyRuleSnapshot, url: URL, method: String, headers: [RockxyCapturedHeader]) async -> RockxyRuleMatchSnapshot {
        let condition = Self.matchCondition(from: snapshot)
        let httpHeaders = headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let matches = condition.matches(method: method, url: url, headers: httpHeaders)
        return RockxyRuleMatchSnapshot(
            matches: matches,
            message: matches ? "Rule matches \(method.uppercased()) \(url.absoluteString)" : "Rule does not match this request."
        )
    }

    func exportRulesData() async throws -> Data {
        let snapshots = await rules()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshots)
    }

    func importRulesData(_ data: Data) async throws {
        let snapshots = try JSONDecoder().decode([RockxyProxyRuleSnapshot].self, from: data)
        for snapshot in snapshots {
            try await saveRule(snapshot)
        }
    }

    func plugins() async -> [RockxyPluginSnapshot] {
        await pluginManager.scriptManager.loadAllPlugins()
        return await pluginManager.scriptManager.plugins.map(Self.snapshot(from:))
    }

    func breakpoints() async -> [RockxyBreakpointItemSnapshot] {
        await BreakpointManager.shared.pausedItems.map(Self.snapshot(from:))
    }

    func resolveBreakpoint(id: UUID, decision: RockxyBreakpointDecisionSnapshot) async {
        await BreakpointManager.shared.resolve(id: id, decision: decision.internalDecision)
    }

    func resolveAllBreakpoints(decision: RockxyBreakpointDecisionSnapshot) async {
        await BreakpointManager.shared.resolveAll(decision: decision.internalDecision)
    }

    func updateBreakpoint(_ snapshot: RockxyBreakpointItemSnapshot) async {
        await BreakpointManager.shared.updateDraft(id: snapshot.id) { draft in
            draft.method = snapshot.method
            draft.url = snapshot.url
            draft.headers = snapshot.headers.map { EditableHeader(name: $0.name, value: $0.value) }
            draft.body = snapshot.body
            draft.statusCode = snapshot.statusCode ?? draft.statusCode
        }
    }

    func installPlugin(at path: String) async throws {
        try await pluginManager.scriptManager.installPlugin(from: URL(fileURLWithPath: path))
        await pluginManager.scriptManager.loadAllPlugins()
    }

    func setPluginEnabled(id: String, enabled: Bool) async throws {
        if enabled {
            _ = try await pluginManager.scriptManager.enablePluginIfAllowed(id: id, maxEnabled: Int.max)
        } else {
            await pluginManager.scriptManager.disablePlugin(id: id)
        }
    }

    func reloadPlugin(id: String) async throws {
        try await pluginManager.scriptManager.reloadPlugin(id: id)
    }

    func deletePlugin(id: String) async throws {
        try await pluginManager.scriptManager.uninstallPlugin(id: id)
    }

    func replay(_ request: RockxyReplayRequest) async throws -> RockxyReplayResult {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for header in request.headers {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if let body = request.body {
            urlRequest.httpBody = body
        }
        if let contentType = request.contentType, urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = Self.proxyDictionary(from: currentUpstreamProxy)

        let started = Date()
        let (data, response) = try await URLSession(configuration: configuration).data(for: urlRequest)
        let http = response as? HTTPURLResponse
        let headers = (http?.allHeaderFields ?? [:]).compactMap { key, value -> RockxyCapturedHeader? in
            guard let name = key as? String else { return nil }
            return RockxyCapturedHeader(name: name, value: "\(value)")
        }
        let captured = RockxyCapturedTransaction(
            id: UUID(),
            sequenceNumber: sequenceCounter.next(),
            timestamp: started,
            measuredDuration: Date().timeIntervalSince(started),
            request: RockxyCapturedRequest(
                method: request.method,
                url: request.url,
                httpVersion: "HTTP/1.1",
                headers: request.headers,
                body: request.body,
                contentType: request.contentType
            ),
            response: RockxyCapturedResponse(
                statusCode: http?.statusCode ?? 0,
                statusMessage: HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                headers: headers,
                body: data,
                bodyTruncated: false,
                contentType: http?.value(forHTTPHeaderField: "Content-Type")
            ),
            state: .completed,
            isTLSFailure: false,
            isWebSocket: false,
            sourcePort: nil,
            clientApp: "Replay",
            matchedRuleName: nil,
            upstreamProxySummary: currentUpstreamProxy.isEnabled ? currentUpstreamProxy.proxies.first?.displayName : "Direct",
            upstreamProxyKind: currentUpstreamProxy.isEnabled ? currentUpstreamProxy.proxies.first?.kind.displayName : "Direct"
        )
        return RockxyReplayResult(transaction: captured)
    }
}

private extension RockxyProxyBackend {
    func replaceNativeRules(_ rules: [ProxyRule]) async throws {
        try ruleStore.saveRules(rules)
        await ruleEngine.replaceAll(rules)
    }

    func removeNativeRule(id: UUID) async throws {
        let rules = await ruleEngine.allRules.filter { $0.id != id }
        try await replaceNativeRules(rules)
    }

    func inlineScriptRules() async -> [RockxyProxyRuleSnapshot] {
        await pluginManager.scriptManager.loadAllPlugins()
        let plugins = await pluginManager.scriptManager.plugins
        return plugins.compactMap { plugin in
            guard plugin.id.hasPrefix(Self.inlinePluginPrefix) else { return nil }
            let metadata = plugin.bundlePath.appendingPathComponent(Self.inlineRuleMetadataFile)
            guard let data = try? Data(contentsOf: metadata),
                  var snapshot = try? JSONDecoder().decode(RockxyProxyRuleSnapshot.self, from: data)
            else { return nil }
            snapshot.isEnabled = plugin.isEnabled
            snapshot.lastError = plugin.lastError
            return snapshot
        }
    }

    func saveInlineScriptRule(_ snapshot: RockxyProxyRuleSnapshot) async throws {
        let pluginID = Self.inlinePluginID(for: snapshot.id)
        let pluginsDirectory = await pluginManager.scriptManager.pluginsDirectoryURL
        let bundleURL = pluginsDirectory.appendingPathComponent(pluginID, isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try snapshot.action.scriptSource.write(
            to: bundleURL.appendingPathComponent(Self.inlineScriptFile),
            atomically: true,
            encoding: .utf8
        )
        let manifest = PluginManifest(
            id: pluginID,
            name: snapshot.name,
            version: "1.0.0",
            author: PluginAuthor(name: "Claude Stats", url: nil),
            description: snapshot.summary,
            types: [.script],
            entryPoints: ["script": Self.inlineScriptFile],
            capabilities: ["script"],
            configuration: nil,
            minRockxyVersion: nil,
            homepage: nil,
            license: nil,
            scriptBehavior: ScriptBehavior(
                matchCondition: Self.matchCondition(from: snapshot),
                runOnRequest: snapshot.action.scriptRunOnRequest,
                runOnResponse: snapshot.action.scriptRunOnResponse,
                runAsMock: snapshot.action.scriptMode == .mock
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: bundleURL.appendingPathComponent("plugin.json"), options: .atomic)
        try encoder.encode(snapshot).write(to: bundleURL.appendingPathComponent(Self.inlineRuleMetadataFile), options: .atomic)

        await pluginManager.scriptManager.loadAllPlugins()
        if snapshot.isEnabled {
            _ = try await pluginManager.scriptManager.enablePluginIfAllowed(id: pluginID, maxEnabled: Int.max)
        } else {
            await pluginManager.scriptManager.disablePlugin(id: pluginID)
        }
    }

    func removeInlineScriptRule(id: UUID) async throws {
        let pluginsDirectory = await pluginManager.scriptManager.pluginsDirectoryURL
        let bundleURL = pluginsDirectory.appendingPathComponent(Self.inlinePluginID(for: id), isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }
        await pluginManager.scriptManager.loadAllPlugins()
    }

    func updateInlineRuleMetadata(id: UUID, transform: (inout RockxyProxyRuleSnapshot) -> Void) async throws {
        let pluginsDirectory = await pluginManager.scriptManager.pluginsDirectoryURL
        let metadata = pluginsDirectory
            .appendingPathComponent(Self.inlinePluginID(for: id), isDirectory: true)
            .appendingPathComponent(Self.inlineRuleMetadataFile)
        guard let data = try? Data(contentsOf: metadata) else { return }
        var snapshot = try JSONDecoder().decode(RockxyProxyRuleSnapshot.self, from: data)
        transform(&snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: metadata, options: .atomic)
    }
}

private extension RockxyProxyBackend {
    static let inlinePluginPrefix = "com.claudestats.inline-rule."
    static let inlineScriptFile = "script.js"
    static let inlineRuleMetadataFile = "claude-stats-rule.json"

    static func inlinePluginID(for id: UUID) -> String {
        inlinePluginPrefix + id.uuidString.lowercased()
    }

    static func snapshot(from rule: ProxyRule) -> RockxyProxyRuleSnapshot {
        RockxyProxyRuleSnapshot(
            id: rule.id,
            name: rule.name,
            isEnabled: rule.isEnabled,
            urlPattern: rule.matchCondition.urlPattern ?? ".*",
            method: rule.matchCondition.method.flatMap(RockxyRuleMatchMethod.init(rawValue:)) ?? .any,
            headerName: rule.matchCondition.headerName,
            headerValue: rule.matchCondition.headerValue,
            priority: rule.priority,
            action: snapshot(from: rule.action)
        )
    }

    static func snapshot(from action: RuleAction) -> RockxyRuleActionSnapshot {
        switch action {
        case let .block(statusCode):
            return RockxyRuleActionSnapshot(kind: .block, blockStatusCode: statusCode)
        case let .mapLocal(filePath, statusCode, isDirectory):
            return RockxyRuleActionSnapshot(
                kind: .mapLocal,
                mapLocalPath: filePath,
                mapLocalStatusCode: statusCode,
                mapLocalIsDirectory: isDirectory
            )
        case let .mapRemote(configuration):
            return RockxyRuleActionSnapshot(
                kind: .mapRemote,
                mapRemoteScheme: configuration.scheme,
                mapRemoteHost: configuration.host,
                mapRemotePort: configuration.port,
                mapRemotePath: configuration.path,
                mapRemoteQuery: configuration.query,
                mapRemotePreserveHostHeader: configuration.preserveHostHeader
            )
        case let .modifyHeader(operations):
            return RockxyRuleActionSnapshot(
                kind: .modifyHeaders,
                headerOperations: operations.map(snapshot(from:))
            )
        case let .throttle(delayMs):
            return RockxyRuleActionSnapshot(kind: .throttle, throttleDelayMs: delayMs)
        case let .networkCondition(preset, delayMs):
            return RockxyRuleActionSnapshot(
                kind: .networkCondition,
                networkConditionPreset: preset.rawValue,
                networkConditionDelayMs: delayMs
            )
        case let .breakpoint(phase):
            return RockxyRuleActionSnapshot(
                kind: .breakpoint,
                breakpointPhase: RockxyBreakpointPhaseSnapshot(rawValue: phase.rawValue) ?? .both
            )
        }
    }

    static func snapshot(from operation: HeaderOperation) -> RockxyRuleHeaderOperationSnapshot {
        RockxyRuleHeaderOperationSnapshot(
            kind: RockxyRuleHeaderOperationKind(rawValue: operation.type.rawValue) ?? .add,
            phase: RockxyRuleHeaderOperationPhase(rawValue: operation.phase.rawValue) ?? .request,
            name: operation.headerName,
            value: operation.headerValue ?? ""
        )
    }

    static func snapshot(from plugin: PluginInfo) -> RockxyPluginSnapshot {
        let configuration = plugin.manifest.configuration ?? [:]
        return RockxyPluginSnapshot(
            id: plugin.id,
            name: plugin.manifest.name,
            version: plugin.manifest.version,
            author: plugin.manifest.author.name,
            summary: plugin.manifest.description,
            bundlePath: plugin.bundlePath.path,
            isEnabled: plugin.isEnabled,
            status: snapshot(from: plugin.status),
            statusMessage: plugin.statusText,
            lastError: plugin.lastError,
            configurationFields: configuration.mapValues(\.type)
        )
    }

    static func snapshot(from item: PausedBreakpointItem) -> RockxyBreakpointItemSnapshot {
        RockxyBreakpointItemSnapshot(
            id: item.id,
            phase: snapshot(from: item.phase),
            method: item.editableDraft.method,
            url: item.editableDraft.url,
            headers: item.editableDraft.headers.map { RockxyCapturedHeader(name: $0.name, value: $0.value) },
            body: item.editableDraft.body,
            statusCode: item.editableDraft.statusCode,
            createdAt: item.createdAt
        )
    }

    static func snapshot(from phase: BreakpointPhase) -> RockxyBreakpointPhaseSnapshot {
        switch phase {
        case .request:
            .request
        case .response:
            .response
        }
    }

    static func snapshot(from status: PluginStatus) -> RockxyPluginStatusSnapshot {
        switch status {
        case .active: .active
        case .disabled: .disabled
        case .loading: .loading
        case .error: .error
        }
    }

    static func nativeRule(from snapshot: RockxyProxyRuleSnapshot) throws -> ProxyRule {
        ProxyRule(
            id: snapshot.id,
            name: snapshot.name,
            isEnabled: snapshot.isEnabled,
            matchCondition: matchCondition(from: snapshot),
            action: try nativeAction(from: snapshot.action),
            priority: snapshot.priority
        )
    }

    static func matchCondition(from snapshot: RockxyProxyRuleSnapshot) -> RuleMatchCondition {
        RuleMatchCondition(
            urlPattern: snapshot.urlPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : snapshot.urlPattern,
            method: snapshot.method == .any ? nil : snapshot.method.rawValue,
            headerName: snapshot.headerName?.nilIfBlank,
            headerValue: snapshot.headerValue?.nilIfBlank
        )
    }

    static func nativeAction(from action: RockxyRuleActionSnapshot) throws -> RuleAction {
        switch action.kind {
        case .block:
            return .block(statusCode: action.blockStatusCode)
        case .mapLocal:
            return .mapLocal(
                filePath: action.mapLocalPath,
                statusCode: action.mapLocalStatusCode,
                isDirectory: action.mapLocalIsDirectory
            )
        case .mapRemote:
            return .mapRemote(configuration: MapRemoteConfiguration(
                scheme: action.mapRemoteScheme?.nilIfBlank,
                host: action.mapRemoteHost?.nilIfBlank,
                port: action.mapRemotePort,
                path: action.mapRemotePath?.nilIfBlank,
                query: action.mapRemoteQuery?.nilIfBlank,
                preserveHostHeader: action.mapRemotePreserveHostHeader
            ))
        case .modifyHeaders:
            return .modifyHeader(operations: action.headerOperations.map(nativeOperation(from:)))
        case .throttle:
            return .throttle(delayMs: action.throttleDelayMs)
        case .networkCondition:
            return .networkCondition(
                preset: NetworkConditionPreset(rawValue: action.networkConditionPreset) ?? .custom,
                delayMs: action.networkConditionDelayMs
            )
        case .breakpoint:
            return .breakpoint(phase: BreakpointRulePhase(rawValue: action.breakpointPhase.rawValue) ?? .both)
        case .script:
            throw RockxyRuleFacadeError.scriptRulesUsePluginRuntime
        }
    }

    static func nativeOperation(from snapshot: RockxyRuleHeaderOperationSnapshot) -> HeaderOperation {
        HeaderOperation(
            type: HeaderOperationType(rawValue: snapshot.kind.rawValue) ?? .add,
            headerName: snapshot.name,
            headerValue: snapshot.value.nilIfBlank,
            phase: HeaderModifyPhase(rawValue: snapshot.phase.rawValue) ?? .request
        )
    }

    static func proxyDictionary(from configuration: RockxyUpstreamProxyConfiguration) -> [AnyHashable: Any]? {
        guard configuration.isEnabled, let proxy = configuration.proxies.first else { return nil }
        switch proxy.kind {
        case .http, .https:
            var dict: [AnyHashable: Any] = [
                "HTTPEnable": true,
                "HTTPProxy": proxy.host,
                "HTTPPort": Int(proxy.port),
                "HTTPSEnable": true,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": Int(proxy.port),
            ]
            if let username = proxy.username, let password = proxy.password {
                dict["HTTPUser"] = username
                dict["HTTPPassword"] = password
                dict["HTTPSUser"] = username
                dict["HTTPSPassword"] = password
            }
            return dict
        case .socks5:
            var dict: [AnyHashable: Any] = [
                "SOCKSEnable": true,
                "SOCKSProxy": proxy.host,
                "SOCKSPort": Int(proxy.port),
            ]
            if let username = proxy.username, let password = proxy.password {
                dict["SOCKSUser"] = username
                dict["SOCKSPassword"] = password
            }
            return dict
        case .pac:
            guard let url = proxy.pacURL else { return nil }
            return [
                "ProxyAutoConfigEnable": true,
                "ProxyAutoConfigURLString": url.absoluteString,
            ]
        }
    }
}

private extension RockxyBreakpointDecisionSnapshot {
    var internalDecision: BreakpointDecision {
        switch self {
        case .execute:
            .execute
        case .abort:
            .abort
        case .cancel:
            .cancel
        }
    }
}

private enum RockxyRuleFacadeError: LocalizedError {
    case scriptRulesUsePluginRuntime

    var errorDescription: String? {
        switch self {
        case .scriptRulesUsePluginRuntime:
            "Script rules are saved through the plugin runtime."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
