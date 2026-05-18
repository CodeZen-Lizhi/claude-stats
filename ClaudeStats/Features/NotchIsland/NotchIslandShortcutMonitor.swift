import AppKit

@MainActor
final class NotchIslandShortcutMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var action: (() -> Void)?

    var isRunning: Bool {
        localMonitor != nil || globalMonitor != nil
    }

    func start(action: @escaping () -> Void) {
        stop()
        self.action = action
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matchesShortcut(event) else { return event }
            self?.action?()
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matchesShortcut(event) else { return }
            Task { @MainActor in
                self?.action?()
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        action = nil
    }

    private static func matchesShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == [.command, .option] && event.charactersIgnoringModifiers?.lowercased() == "n"
    }
}
