import AppKit
import Combine
import Foundation
import GhosttyKit

public struct EmbeddedTerminalTabItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let needsAttention: Bool
}

@MainActor
public final class EmbeddedTerminalStore: ObservableObject {
    @Published public private(set) var tabs: [EmbeddedTerminalTabItem] = []
    @Published public var selectedTabID: UUID?

    let ghostty: Ghostty.App
    private var controllers: [UUID: EmbeddedTerminalController] = [:]
    private var cancellables: [UUID: AnyCancellable] = [:]

    public init(configFileURL: URL? = nil) {
        GhosttyRuntime.initializeIfNeeded(resourcesURL: Self.resourcesDirectoryURL())

        let configURL = configFileURL ?? Self.defaultConfigFileURL()
        Self.ensureConfigFile(at: configURL)

        self.ghostty = Ghostty.App(configPath: configURL.path)
        self.ghostty.delegate = self
    }

    public func ensureDefaultTab() {
        if controllers.isEmpty {
            addTab()
        }
    }

    public func addTab() {
        let controller = EmbeddedTerminalController(ghostty)
        controller.onDisplayChange = { [weak self, weak controller] in
            guard let self, controller != nil else { return }
            self.refreshTabs()
        }

        controllers[controller.id] = controller
        cancellables[controller.id] = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refreshTabs() }
        }

        selectedTabID = controller.id
        refreshTabs()
    }

    public func selectTab(id: UUID) {
        selectedTabID = id
        refreshTabs()
    }

    @discardableResult
    public func closeTab(id: UUID, force: Bool) -> Bool {
        guard let controller = controllers[id] else { return true }
        if !force && controller.needsCloseConfirmation {
            return false
        }

        controller.closeAllSurfaces()
        controllers[id] = nil
        cancellables[id] = nil

        if selectedTabID == id {
            selectedTabID = controllers.keys.sorted { $0.uuidString < $1.uuidString }.first
        }

        if controllers.isEmpty {
            addTab()
        } else {
            refreshTabs()
        }

        return true
    }

    public func closeSelectedTab(force: Bool) -> Bool {
        guard let selectedTabID else { return true }
        return closeTab(id: selectedTabID, force: force)
    }

    public func closeAllTabs(force: Bool) {
        for id in Array(controllers.keys) {
            _ = closeTab(id: id, force: force)
        }
    }

    public func tabNeedsCloseConfirmation(id: UUID) -> Bool {
        controllers[id]?.needsCloseConfirmation ?? false
    }

    func controller(id: UUID?) -> EmbeddedTerminalController? {
        guard let id else { return nil }
        return controllers[id]
    }

    func ghosttySurface(id: UUID) -> Ghostty.SurfaceView? {
        for controller in controllers.values {
            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }
        return nil
    }

    private func refreshTabs() {
        tabs = controllers.values
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.tabItem }
        if selectedTabID == nil {
            selectedTabID = tabs.first?.id
        }
    }

    private static func defaultConfigFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.claudestats.ClaudeStats"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Ghostty", isDirectory: true)
            .appendingPathComponent("config.ghostty")
    }

    private static func ensureConfigFile(at url: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            updateExistingConfigFile(at: url)
            return
        }

        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try """
            # Claude Stats embedded Ghostty terminal configuration.
            # This file is intentionally separate from your standalone Ghostty config.

            macos-titlebar-style = hidden
            window-decoration = false

            \(managedAppearanceBlock)
            """.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            assertionFailure("Failed to create embedded Ghostty config: \(error)")
        }
    }

    private static func updateExistingConfigFile(at url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let repaired = repairLegacyConfig(contents)
        let updated = replacingManagedAppearanceBlock(in: repaired)
        guard updated != contents else { return }
        try? updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func repairLegacyConfig(_ contents: String) -> String {
        contents
            .replacingOccurrences(of: "\ntheme = dark:Builtin Dark,light:Builtin Light", with: "")
            .replacingOccurrences(of: "theme = dark:Builtin Dark,light:Builtin Light\n", with: "")
    }

    private static func replacingManagedAppearanceBlock(in contents: String) -> String {
        if
            let startRange = contents.range(of: managedAppearanceStart),
            let endRange = contents.range(
                of: managedAppearanceEnd,
                range: startRange.upperBound..<contents.endIndex
            )
        {
            var updated = contents
            updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: managedAppearanceBlock)
            return updated
        }

        return contents.trimmingTrailingNewlines + "\n\n" + managedAppearanceBlock + "\n"
    }

    private static func resourcesDirectoryURL() -> URL {
        let bundle = Bundle(for: BundleToken.self)
        return (bundle.resourceURL ?? bundle.bundleURL)
            .appendingPathComponent("Resources", isDirectory: true)
    }

    private static let managedAppearanceStart = "# Claude Stats terminal appearance: begin"
    private static let managedAppearanceEnd = "# Claude Stats terminal appearance: end"
    private static let managedAppearanceBlock = """
    \(managedAppearanceStart)
    background = 0b0d10
    foreground = e9eef5
    cursor-color = f06b1f
    selection-background = 385763
    selection-foreground = f7fbff
    font-size = 13
    window-padding-x = 12
    window-padding-y = 10
    \(managedAppearanceEnd)
    """
}

extension EmbeddedTerminalStore: @preconcurrency GhosttyAppDelegate {
    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        ghosttySurface(id: uuid)
    }
}

extension EmbeddedTerminalStore: @preconcurrency Ghostty.Delegate {}

private enum GhosttyRuntime {
    private static var initialized = false

    static func initializeIfNeeded(resourcesURL: URL) {
        guard !initialized else { return }
        initialized = true

        setenv("GHOSTTY_RESOURCES_DIR", resourcesURL.path, 1)

        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            assertionFailure("ghostty_init failed")
        }
    }
}

private final class BundleToken {}

final class EmbeddedTerminalController: BaseTerminalController {
    let id = UUID()
    let createdAt = Date()
    var onDisplayChange: (() -> Void)?
    private var surfaceCancellables: Set<AnyCancellable> = []

    var tabItem: EmbeddedTerminalTabItem {
        let title = titleOverride?.nilIfEmpty
            ?? focusedSurface?.title.nilIfEmpty
            ?? surfaceTree.root?.leftmostLeaf().title.nilIfEmpty
            ?? "claude-stats"
        let subtitle = focusedSurface?.pwd?.nilIfEmpty
        return EmbeddedTerminalTabItem(
            id: id,
            title: title,
            subtitle: subtitle,
            needsAttention: bell
        )
    }

    var needsCloseConfirmation: Bool {
        surfaceTree.contains { $0.needsConfirmQuit }
    }

    init(_ ghostty: Ghostty.App, baseConfig: Ghostty.SurfaceConfiguration? = nil) {
        super.init(ghostty, baseConfig: baseConfig)
        if case let .leaf(view) = surfaceTree.root {
            focusedSurface = view
        }
        updateOverlayIsVisible = false
        observeSurfaces()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func surfaceTreeDidChange(from: SplitTree<Ghostty.SurfaceView>, to: SplitTree<Ghostty.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)
        observeSurfaces()
        onDisplayChange?()
    }

    override func focusedSurfaceDidChange(to: Ghostty.SurfaceView?) {
        super.focusedSurfaceDidChange(to: to)
        onDisplayChange?()
    }

    override func syncFocusToSurfaceTree() {
        for surfaceView in surfaceTree {
            let focused = surfaceView == focusedSurface && surfaceView.isFirstResponder
            surfaceView.focusDidChange(focused)
        }
    }

    override func defaultUpdateOverlayVisibility() -> Bool {
        false
    }

    func closeAllSurfaces() {
        guard let root = surfaceTree.root else { return }
        closeSurface(root, withConfirmation: false)
    }

    private func observeSurfaces() {
        surfaceCancellables.removeAll()
        for surface in surfaceTree {
            surface.objectWillChange.sink { [weak self] _ in
                self?.onDisplayChange?()
            }
            .store(in: &surfaceCancellables)
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmingTrailingNewlines: String {
        var copy = self
        while copy.last == "\n" || copy.last == "\r" {
            copy.removeLast()
        }
        return copy
    }
}
