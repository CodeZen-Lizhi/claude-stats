import AppKit
import GhosttyEmbed

/// Owns the ``AppEnvironment`` and kicks off the first scan once AppKit has
/// finished launching. `MenuBarExtra`'s label/window views don't run a normal
/// `onAppear`/`task` lifecycle at launch, so the kickoff lives here instead.
final class AppDelegate: GhosttyEmbed.AppDelegate {
    let env: AppEnvironment

    override init() {
        let terminalStore = MainActor.assumeIsolated {
            EmbeddedTerminalStore()
        }
        self.env = MainActor.assumeIsolated {
            AppEnvironment(terminalStore: terminalStore)
        }
        super.init(terminalStore: terminalStore)
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        super.applicationDidFinishLaunching(notification)
        MainActor.assumeIsolated {
            Theme.registerFonts()
            env.start()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
