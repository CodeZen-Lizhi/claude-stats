import SwiftUI

public struct AtollIslandHostView: View {
    private let bridge: AtollIslandRuntimeBridge

    public init(bridge: AtollIslandRuntimeBridge) {
        self.bridge = bridge
    }

    public var body: some View {
        bridge.makeContentView()
            .environmentObject(bridge.environmentViewModel())
            .environmentObject(bridge.environmentWebcamManager())
            .onAppear {
                bridge.start()
            }
            .onDisappear {
                bridge.stop()
            }
    }
}
