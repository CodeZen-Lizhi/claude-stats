import CoreGraphics
import Foundation
import Testing
@testable import ClaudeStats

@Suite("FloatingPanelDragMotion")
struct FloatingPanelDragMotionTests {
    private let startFrame = CGRect(x: 800, y: 300, width: 44, height: 132)
    private let startMouse = CGPoint(x: 830, y: 360)

    @Test("Below threshold does not move the frame")
    func belowThresholdDoesNotMove() {
        let currentMouse = CGPoint(x: 840, y: 368)
        let frame = FloatingPanelDragMotion.activatedFrame(
            startFrame: startFrame,
            startMouse: startMouse,
            currentMouse: currentMouse,
            activationDistance: 22
        )

        #expect(frame == nil)
    }

    @Test("Crossing threshold returns start frame plus full delta")
    func crossingThresholdUsesFullDelta() throws {
        let currentMouse = CGPoint(x: 856, y: 384)
        let frame = try #require(FloatingPanelDragMotion.activatedFrame(
            startFrame: startFrame,
            startMouse: startMouse,
            currentMouse: currentMouse,
            activationDistance: 22
        ))

        #expect(frame.origin.x == startFrame.origin.x + 26)
        #expect(frame.origin.y == startFrame.origin.y + 24)
    }

    @Test("Active drag follows absolute screen-coordinate delta")
    func activeDragFollowsAbsoluteDelta() {
        let currentMouse = CGPoint(x: 790, y: 420)
        let frame = FloatingPanelDragMotion.frame(
            startFrame: startFrame,
            startMouse: startMouse,
            currentMouse: currentMouse
        )

        #expect(frame.origin.x == startFrame.origin.x - 40)
        #expect(frame.origin.y == startFrame.origin.y + 60)
    }
}
