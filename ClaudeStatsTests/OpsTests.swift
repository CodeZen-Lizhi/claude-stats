import Foundation
import Testing
@testable import ClaudeStats

struct OpsParserTests {
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

    @Test("first meaningful line skips blanks")
    func firstMeaningfulLineSkipsBlanks() {
        #expect(OpsParsers.firstMeaningfulLine("\n\n  git version 2.50.0\n") == "git version 2.50.0")
    }
}

struct OpsCommandRunnerTests {
    @Test("runner drains large stdout without timing out")
    func runnerDrainsLargeStdoutWithoutTimingOut() async {
        let runner = DefaultOpsCommandRunner()
        let input = Data(repeating: UInt8(ascii: "x"), count: 200_000)

        let result = await runner.run(OpsCommandInvocation(
            executablePath: "/bin/cat",
            timeout: 3,
            standardInput: input,
            maxOutputBytes: 300_000
        ))

        #expect(result.isSuccess)
        #expect(result.stdout.count == 200_000)
        #expect(!result.stdoutTruncated)
    }

    @Test("runner drains large stderr without blocking")
    func runnerDrainsLargeStderrWithoutBlocking() async {
        let runner = DefaultOpsCommandRunner()

        let result = await runner.run(OpsCommandInvocation(
            executablePath: "/usr/bin/perl",
            arguments: ["-e", "print STDERR 'x' x 200000"],
            timeout: 3,
            maxOutputBytes: 300_000
        ))

        #expect(result.isSuccess)
        #expect(result.stderr.count == 200_000)
    }

    @Test("runner truncates output at configured cap")
    func runnerTruncatesOutputAtConfiguredCap() async {
        let runner = DefaultOpsCommandRunner()
        let input = Data(repeating: UInt8(ascii: "x"), count: 200_000)

        let result = await runner.run(OpsCommandInvocation(
            executablePath: "/bin/cat",
            timeout: 3,
            standardInput: input,
            maxOutputBytes: 1_024
        ))

        #expect(result.isSuccess)
        #expect(result.stdoutTruncated)
        #expect(result.stdout.contains("[output truncated]"))
    }

    @Test("runner timeout returns bounded result")
    func runnerTimeoutReturnsBoundedResult() async {
        let runner = DefaultOpsCommandRunner()

        let result = await runner.run(OpsCommandInvocation(
            executablePath: "/bin/sleep",
            arguments: ["5"],
            timeout: 0.2
        ))

        #expect(result.timedOut)
        #expect(!result.isSuccess)
    }

    @Test("runner cancellation stops external process")
    func runnerCancellationStopsExternalProcess() async throws {
        let runner = DefaultOpsCommandRunner()
        let task = Task {
            await runner.run(OpsCommandInvocation(
                executablePath: "/bin/sleep",
                arguments: ["10"],
                timeout: 30
            ))
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.value

        #expect(!result.isSuccess)
    }

    @Test("runner strips secret environment variables")
    func runnerStripsSecretEnvironmentVariables() async {
        let runner = DefaultOpsCommandRunner()
        let result = await runner.run(OpsCommandInvocation(
            executablePath: "/usr/bin/env",
            environment: [
                "PATH": "/usr/bin:/bin",
                "OPENAI_API_KEY": "sk-test",
                "ANTHROPIC_API_KEY": "anthropic-test",
                "GH_TOKEN": "gh-test",
                "DYLD_INSERT_LIBRARIES": "/tmp/hook.dylib",
            ],
            timeout: 3
        ))

        #expect(result.isSuccess)
        #expect(!result.stdout.contains("OPENAI_API_KEY"))
        #expect(!result.stdout.contains("ANTHROPIC_API_KEY"))
        #expect(!result.stdout.contains("GH_TOKEN"))
        #expect(!result.stdout.contains("DYLD_INSERT_LIBRARIES"))
    }
}

struct OpsServiceBrewTests {
    @Test("brew environment fronts Homebrew paths for GUI launches")
    func brewEnvironmentFrontsHomebrewPathsForGUILaunches() {
        let environment = OpsService.readOnlyBrewEnvironment(
            base: ["PATH": "/usr/bin:/opt/homebrew/bin:/bin"],
            brewPath: "/opt/homebrew/bin/brew"
        )
        let pathParts = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        #expect(Array(pathParts.prefix(2)) == ["/opt/homebrew/bin", "/opt/homebrew/sbin"])
        #expect(pathParts.filter { $0 == "/opt/homebrew/bin" }.count == 1)
        #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(environment["HOMEBREW_NO_ANALYTICS"] == "1")
    }

    @Test("brew doctor warnings remain doctor output")
    func brewDoctorWarningsRemainDoctorOutput() {
        let warning = """
        Please note that these warnings are just used to help the Homebrew maintainers.

        Warning: /usr/bin occurs before /opt/homebrew/bin in your PATH.
        """
        let presentation = OpsService.brewDoctorPresentation(for: OpsCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: warning,
            launchError: nil,
            timedOut: false
        ))

        #expect(presentation.output.contains("Warning: /usr/bin occurs before /opt/homebrew/bin"))
        #expect(presentation.error == nil)
    }

    @Test("brew typed actions reject unsafe tokens")
    func brewTypedActionsRejectUnsafeTokens() {
        #expect(!OpsService.brewActionIsAllowed(.install("--HEAD")))
        #expect(!OpsService.brewActionIsAllowed(.install("/tmp/foo.rb")))
        #expect(!OpsService.brewActionIsAllowed(.install("https://example.com/formula.rb")))
        #expect(!OpsService.brewActionIsAllowed(.service(.start, "../plist")))
        #expect(OpsService.brewActionIsAllowed(.install("openssl@3")))
        #expect(OpsService.brewActionIsAllowed(.service(.restart, "postgresql@16")))
    }

    @Test("environment loader reports tool versions")
    func environmentLoaderReportsToolVersions() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let executable = temp.appendingPathComponent("git")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let service = OpsService(
            runner: RecordingOpsRunner(results: [
                executable.path: OpsCommandResult(
                    exitCode: 0,
                    stdout: "git version 2.50.0\n",
                    stderr: "",
                    launchError: nil,
                    timedOut: false
                ),
            ]),
            environment: ["PATH": temp.path]
        )

        let tools = await service.loadEnvironment()
        let git = tools.first { $0.command == "git" }

        #expect(git?.resolvedPath == executable.path)
        #expect(git?.version == "git version 2.50.0")
        #expect(git?.status == .available)
    }

    private func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stats-ops-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

@MainActor
struct OpsStoreTests {
    @Test("brew install requires confirmation before service call")
    func brewInstallRequiresConfirmationBeforeServiceCall() async throws {
        let service = FakeOpsService()
        let store = OpsStore(service: service)

        store.requestBrewInstall("git")

        #expect(store.pendingConfirmation != nil)
        #expect(await service.actions.isEmpty)

        store.confirmPendingAction()
        try await waitFor { await service.actions == [.install("git")] }
        #expect(store.lastActionOutput == "ok")
    }

    @Test("brew selection repairs to visible package")
    func brewSelectionRepairsToVisiblePackage() {
        let store = OpsStore(service: FakeOpsService())
        store.brewSnapshot = OpsBrewSnapshot(
            brewPath: "/opt/homebrew/bin/brew",
            packages: [
                OpsBrewPackage(name: "git", installedVersion: "2.50.0", kind: .formula),
                OpsBrewPackage(name: "node", installedVersion: "24.1.0", kind: .formula),
            ],
            services: [],
            doctorOutput: ""
        )
        store.selectedBrewPackageID = "formula:missing"
        store.brewQuery = "node"

        #expect(store.selectedBrewPackage?.name == "node")
    }
}

private actor FakeOpsService: OpsServicing {
    var actions: [OpsBrewAction] = []

    func loadBrew() async -> OpsBrewSnapshot { .missing }
    func loadEnvironment() async -> [OpsEnvironmentTool] { [] }

    func runBrew(action: OpsBrewAction) async throws -> OpsCommandResult {
        actions.append(action)
        return OpsCommandResult(exitCode: 0, stdout: "ok", stderr: "", launchError: nil, timedOut: false)
    }
}

private struct RecordingOpsRunner: OpsCommandRunning {
    var results: [String: OpsCommandResult]

    func run(_ invocation: OpsCommandInvocation) async -> OpsCommandResult {
        results[invocation.executablePath]
            ?? OpsCommandResult(exitCode: 1, stdout: "", stderr: "missing", launchError: nil, timedOut: false)
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
