import SwiftUI

public struct EmbeddedTerminalPaneView: View {
    @ObservedObject private var store: EmbeddedTerminalStore

    public init(store: EmbeddedTerminalStore) {
        self.store = store
    }

    public var body: some View {
        if let controller = store.controller(id: store.selectedTabID) {
            EmbeddedTerminalControllerView(
                ghostty: store.ghostty,
                controller: controller
            )
        } else {
            Color.clear
        }
    }
}

private struct EmbeddedTerminalControllerView: View {
    @ObservedObject var ghostty: Ghostty.App
    @ObservedObject var controller: EmbeddedTerminalController

    var body: some View {
        TerminalView(
            ghostty: ghostty,
            viewModel: controller,
            delegate: controller
        )
    }
}
