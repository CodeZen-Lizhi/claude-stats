import Darwin
import Foundation
import Testing
@testable import ClaudeStats

struct OpsParserTests {
    @Test("ps parser identifies developer processes and protected owners")
    func psParserIdentifiesDeveloperProcessesAndProtection() {
        let output = """
          123     1 alice   12.5  1.2  01:02 /opt/homebrew/bin/node node server.js
          456     1 root     0.0  0.1  02:03 /usr/sbin/networkd /usr/sbin/networkd
          789   123 alice    3.0  0.4  00:12 /usr/bin/python3 python3 -m http.server
        """

        let processes = OpsParsers.parseProcessList(output, currentPID: 999, currentUser: "alice")

        #expect(processes.first?.pid == 123)
        #expect(processes.first?.isDeveloperProcess == true)
        #expect(processes.contains { $0.pid == 456 && $0.protection.reason == "Root-owned process." })
        #expect(processes.contains { $0.pid == 789 && $0.protection.reason == nil })
    }

    @Test("lsof field parser maps ports to process metadata")
    func lsofFieldParserMapsPortsToProcessMetadata() {
        let process = OpsProcessItem(
            pid: 123,
            ppid: 1,
            user: "alice",
            cpuPercent: 0,
            memoryPercent: 0,
            elapsed: "00:01",
            executablePath: "/opt/homebrew/bin/node",
            commandLine: "node server.js",
            protection: .allowed
        )
        let output = """
        p123
        cnode
        Lalice
        PTCP
        n*:3000
        """

        let ports = OpsParsers.parseLsofFieldOutput(output, processLookup: [123: process])

        #expect(ports.count == 1)
        #expect(ports.first?.port == 3000)
        #expect(ports.first?.processName == "node")
        #expect(ports.first?.commandLine == "node server.js")
        #expect(ports.first?.localhostURL == "http://localhost:3000")
    }

    @Test("brew parsers handle text and json fallbacks")
    func brewParsersHandleTextAndJSONFallbacks() {
        let packages = OpsParsers.parseBrewListVersions(
            """
            node 24.1.0
            openssl@3 3.6.0
            """,
            kind: .formula
        )
        let outdated = OpsParsers.parseBrewOutdated("node 24.1.0 < 24.2.0\n")
        let jsonOutdated = OpsParsers.parseBrewOutdated(#"{"formulae":[{"name":"git","current_version":"2.60.0"}],"casks":[]}"#)
        let services = OpsParsers.parseBrewServices(#"[{"name":"postgresql@16","status":"started","user":"alice","file":"/tmp/p.plist"}]"#)

        #expect(packages.map(\.name) == ["node", "openssl@3"])
        #expect(outdated["node"] == "24.2.0")
        #expect(jsonOutdated["git"] == "2.60.0")
        #expect(services.first?.name == "postgresql@16")
        #expect(services.first?.status == "started")
    }

    @Test("diagnostic parsers summarize proxy dns and TLS expiry")
    func diagnosticParsersSummarizeProxyDNSAndTLSExpiry() throws {
        let proxy = OpsParsers.proxySummary(from: "HTTPEnable : 1\nHTTPProxy : 127.0.0.1\n")
        let dns = OpsParsers.dnsSummary(from: "nameserver[0] : 1.1.1.1\nnameserver[1] : 8.8.8.8\n")
        let cert = OpsParsers.firstPEMCertificate(from: "x\n-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----\ny")
        let expiry = try #require(OpsParsers.parseOpenSSLNotAfter("notAfter=Jun 10 12:00:00 2026 GMT"))

        #expect(proxy.contains("HTTPEnable"))
        #expect(dns.contains("1.1.1.1"))
        #expect(cert?.contains("BEGIN CERTIFICATE") == true)
        #expect(Calendar(identifier: .gregorian).component(.year, from: expiry) == 2026)
    }
}

@MainActor
struct OpsStoreTests {
    @Test("terminate requires confirmation before service call")
    func terminateRequiresConfirmationBeforeServiceCall() async throws {
        let service = FakeOpsService()
        let store = OpsStore(service: service)
        let process = OpsProcessItem(
            pid: 222,
            ppid: 1,
            user: "alice",
            cpuPercent: 0,
            memoryPercent: 0,
            elapsed: "00:01",
            executablePath: "/bin/node",
            commandLine: "node server.js",
            protection: .allowed
        )

        store.requestTerminate(process)

        #expect(store.pendingConfirmation != nil)
        #expect(await service.terminatedSignals.isEmpty)

        store.confirmPendingAction()
        try await waitFor { await service.terminatedSignals == [SIGTERM] }
    }

    @Test("protected processes cannot create terminate confirmation")
    func protectedProcessesCannotCreateTerminateConfirmation() {
        let store = OpsStore(service: FakeOpsService())
        let process = OpsProcessItem(
            pid: 1,
            ppid: 0,
            user: "root",
            cpuPercent: 0,
            memoryPercent: 0,
            elapsed: "1-00:00",
            executablePath: "/sbin/launchd",
            commandLine: "/sbin/launchd",
            protection: .protected(reason: "System launch process.")
        )

        store.requestTerminate(process)

        #expect(store.pendingConfirmation == nil)
        #expect(store.lastError?.contains("System launch process.") == true)
    }

    @Test("cleanup confirmation runs selected allowlisted cleanup")
    func cleanupConfirmationRunsSelectedAllowlistedCleanup() async throws {
        let service = FakeOpsService()
        let store = OpsStore(service: service)
        store.cleanupItems = [
            OpsCleanupItem(kind: .npmCache, path: "/tmp/.npm", sizeBytes: 10, isAvailable: true, detail: "ok"),
        ]
        store.toggleCleanupSelection(store.cleanupItems[0])

        store.requestCleanupSelected()
        #expect(store.pendingConfirmation != nil)

        store.confirmPendingAction()
        try await waitFor { await service.cleanedKinds == [.npmCache] }
    }
}

struct OpsServiceCleanupTests {
    @Test("cleanup only removes known cache path for selected kind")
    func cleanupOnlyRemovesKnownCachePath() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }

        let npm = dir.appendingPathComponent(".npm", isDirectory: true)
        try FileManager.default.createDirectory(at: npm, withIntermediateDirectories: true)
        try TempDir.write("cache", to: npm.appendingPathComponent("entry.txt"))

        let service = OpsService(runner: FailingOpsRunner(), environment: ["PATH": ""], homeDirectory: dir)
        let result = try await service.cleanup(kinds: [.npmCache])

        #expect(result.removedKinds == [.npmCache])
        #expect(!FileManager.default.fileExists(atPath: npm.path))
    }
}

private actor FakeOpsService: OpsServicing {
    var terminatedSignals: [Int32] = []
    var cleanedKinds: Set<OpsCleanupKind> = []

    func loadPorts() async throws -> [OpsPortItem] { [] }
    func loadProcesses() async throws -> [OpsProcessItem] { [] }
    func loadBrew() async -> OpsBrewSnapshot { .missing }
    func loadEnvironment() async -> [OpsEnvironmentTool] { [] }
    func loadCleanupItems() async -> [OpsCleanupItem] { [] }
    func loadDiagnostics() async -> OpsDiagnosticsSnapshot {
        OpsDiagnosticsSnapshot(proxySummary: "", dnsSummary: "", hostsEntries: [])
    }
    func runURLDiagnostics(_ rawURL: String) async -> OpsURLDiagnosticResult {
        OpsURLDiagnosticResult(url: rawURL, headerText: "", tlsExpiration: nil, errorMessage: nil)
    }
    func terminate(pid: Int32, signal: Int32) async throws -> OpsTerminationOutcome {
        terminatedSignals.append(signal)
        return OpsTerminationOutcome(pid: pid, signal: signal, isStillRunning: false)
    }
    func runBrew(arguments: [String]) async throws -> OpsCommandResult {
        OpsCommandResult(exitCode: 0, stdout: "ok", stderr: "", launchError: nil, timedOut: false)
    }
    func cleanup(kinds: Set<OpsCleanupKind>) async throws -> OpsCleanupResult {
        cleanedKinds = kinds
        return OpsCleanupResult(removedKinds: kinds, skippedKinds: [:], commandOutput: nil)
    }
}

private struct FailingOpsRunner: OpsCommandRunning {
    func run(_ invocation: OpsCommandInvocation) async -> OpsCommandResult {
        OpsCommandResult(exitCode: 1, stdout: "", stderr: "missing", launchError: nil, timedOut: false)
    }
}

@MainActor
private func waitFor(_ predicate: @escaping @MainActor () async -> Bool) async throws {
    for _ in 0 ..< 100 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await predicate())
}
