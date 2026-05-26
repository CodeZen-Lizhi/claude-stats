@testable import AtollEmbed
import Foundation
import Testing

@Suite("AtollRuntimeResourceLocator")
struct AtollRuntimeResourceLocatorTests {
    @Test("Finds MediaRemote framework in Contents/Frameworks")
    func findsFrameworksDirectoryAdapter() throws {
        let fixture = try RuntimeResourceFixture(frameworkLocation: .frameworks)
        defer { fixture.remove() }

        let adapter = fixture.locator.mediaRemoteAdapter()

        #expect(adapter?.scriptURL == fixture.scriptURL)
        #expect(adapter?.frameworkURL == fixture.frameworkURL)
        #expect(adapter?.frameworkPath == fixture.frameworkURL.path)
    }

    @Test("Falls back to MediaRemote framework in Resources")
    func fallsBackToResourcesFrameworkAdapter() throws {
        let fixture = try RuntimeResourceFixture(frameworkLocation: .resources)
        defer { fixture.remove() }

        let adapter = fixture.locator.mediaRemoteAdapter()

        #expect(adapter?.frameworkURL == fixture.frameworkURL)
    }

    @Test("NowPlayingTestClient must be executable")
    func requiresExecutableNowPlayingTestClient() throws {
        let executableFixture = try RuntimeResourceFixture(helperMode: .executable)
        defer { executableFixture.remove() }

        #expect(executableFixture.locator.nowPlayingTestClientPath() == executableFixture.helperURL.path)

        let nonExecutableFixture = try RuntimeResourceFixture(helperMode: .nonExecutable)
        defer { nonExecutableFixture.remove() }

        #expect(nonExecutableFixture.locator.nowPlayingTestClientPath() == nil)
    }

    @Test("Missing script or framework returns nil")
    func missingRequiredAdapterResourcesReturnNil() throws {
        let missingScriptFixture = try RuntimeResourceFixture(includeScript: false)
        defer { missingScriptFixture.remove() }

        #expect(missingScriptFixture.locator.mediaRemoteAdapter() == nil)

        let missingFrameworkFixture = try RuntimeResourceFixture(frameworkLocation: nil)
        defer { missingFrameworkFixture.remove() }

        #expect(missingFrameworkFixture.locator.mediaRemoteAdapter() == nil)
    }
}

private struct RuntimeResourceFixture {
    enum FrameworkLocation {
        case frameworks
        case resources
    }

    enum HelperMode {
        case executable
        case nonExecutable
        case missing
    }

    let rootURL: URL
    let appURL: URL
    let resourceURL: URL
    let frameworksURL: URL
    let helperURL: URL
    let frameworkURL: URL
    let scriptURL: URL
    let locator: AtollRuntimeResourceLocator

    init(
        frameworkLocation: FrameworkLocation? = .frameworks,
        helperMode: HelperMode = .executable,
        includeScript: Bool = true
    ) throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("AtollRuntimeResourceLocatorTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Codex Statistics.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourceURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        let helpersURL = contentsURL.appendingPathComponent("Helpers", isDirectory: true)

        try fileManager.createDirectory(at: resourceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: frameworksURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: helpersURL, withIntermediateDirectories: true)

        let scriptURL = resourceURL.appendingPathComponent("mediaremote-adapter.pl")
        if includeScript {
            try Data("#!/usr/bin/perl\n".utf8).write(to: scriptURL)
        }

        let frameworkParentURL: URL
        switch frameworkLocation {
        case .frameworks:
            frameworkParentURL = frameworksURL
        case .resources:
            frameworkParentURL = resourceURL
        case nil:
            frameworkParentURL = frameworksURL
        }

        let frameworkURL = frameworkParentURL.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        if frameworkLocation != nil {
            try fileManager.createDirectory(at: frameworkURL, withIntermediateDirectories: true)
        }

        let helperURL = helpersURL.appendingPathComponent("NowPlayingTestClient")
        switch helperMode {
        case .executable:
            try Data().write(to: helperURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        case .nonExecutable:
            try Data().write(to: helperURL)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: helperURL.path)
        case .missing:
            break
        }

        self.rootURL = rootURL
        self.appURL = appURL
        self.resourceURL = resourceURL
        self.frameworksURL = frameworksURL
        self.helperURL = helperURL
        self.frameworkURL = frameworkURL
        self.scriptURL = scriptURL
        self.locator = AtollRuntimeResourceLocator(
            layout: AtollRuntimeBundleLayout(
                bundleURL: appURL,
                resourceURL: resourceURL,
                privateFrameworksURL: frameworksURL
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
