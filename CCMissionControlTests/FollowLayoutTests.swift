import CoreGraphics
import Foundation
import Testing

@testable import CCMissionControl

struct FollowLayoutTests {
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func convertsCGBoundsToAppKitCoordinates() {
        let cg = CGRect(x: 100, y: 50, width: 800, height: 600)
        let rect = FollowLayout.appKitRect(fromCGBounds: cg, primaryScreenHeight: 1080)
        #expect(rect == NSRect(x: 100, y: 1080 - 650, width: 800, height: 600))
    }

    @Test func attachesToLeftWithSameHeight() {
        let target = NSRect(x: 800, y: 100, width: 900, height: 700)
        let frame = FollowLayout.panelFrame(
            attachedTo: target, panelWidth: 480, screenFrames: [screen], targetScreenFrame: screen)
        #expect(frame == NSRect(x: 320, y: 100, width: 480, height: 700))
    }

    @Test func fallsBackToRightWhenLeftDoesNotFit() {
        let target = NSRect(x: 100, y: 100, width: 900, height: 700)
        let frame = FollowLayout.panelFrame(
            attachedTo: target, panelWidth: 480, screenFrames: [screen], targetScreenFrame: screen)
        #expect(frame == NSRect(x: 1000, y: 100, width: 480, height: 700))
    }

    @Test func clampsToScreenEdgeWhenNeitherSideFits() {
        let target = NSRect(x: 100, y: 100, width: 1700, height: 700)
        let frame = FollowLayout.panelFrame(
            attachedTo: target, panelWidth: 480, screenFrames: [screen], targetScreenFrame: screen)
        #expect(frame == NSRect(x: 0, y: 100, width: 480, height: 700))
    }

    @Test func usesLeftSideOnAdjacentDisplay() {
        let leftScreen = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let target = NSRect(x: 0, y: 100, width: 900, height: 700)
        let frame = FollowLayout.panelFrame(
            attachedTo: target, panelWidth: 480, screenFrames: [screen, leftScreen],
            targetScreenFrame: screen)
        #expect(frame == NSRect(x: -480, y: 100, width: 480, height: 700))
    }

    @Test func avoidsStraddlingTwoDisplays() {
        let leftScreen = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let target = NSRect(x: 100, y: 100, width: 900, height: 700)
        let frame = FollowLayout.panelFrame(
            attachedTo: target, panelWidth: 480, screenFrames: [screen, leftScreen],
            targetScreenFrame: screen)
        #expect(frame == NSRect(x: 1000, y: 100, width: 480, height: 700))
    }

    @Test func detectsFullScreenWindow() {
        #expect(
            FollowLayout.isFullScreen(
                windowFrame: screen, screenFrame: screen, topSafeAreaInset: 0))
    }

    @Test func detectsFullScreenBelowNotch() {
        let window = NSRect(x: 0, y: 0, width: 1920, height: 1080 - 37)
        #expect(
            FollowLayout.isFullScreen(
                windowFrame: window, screenFrame: screen, topSafeAreaInset: 37))
    }

    @Test func maximizedWindowIsNotFullScreen() {
        // Menu bar visible: window height is smaller than the screen height.
        let window = NSRect(x: 0, y: 0, width: 1920, height: 1080 - 25)
        #expect(
            !FollowLayout.isFullScreen(
                windowFrame: window, screenFrame: screen, topSafeAreaInset: 0))
    }
}

struct CoordinateTransformTests {
    @Test func identityWhenCGMatchesAppKit() {
        let frame = NSRect(x: 100, y: 200, width: 480, height: 400)
        let cg = CGRect(x: 100, y: 1080 - 600, width: 480, height: 400)
        let t = FollowLayout.CoordinateTransform(
            appKitFrame: frame, cgBounds: cg, primaryScreenHeight: 1080)
        #expect(t == .identity)
    }

    @Test func calibratesScaledAndOffsetCoordinates() {
        // Window server reports a 0.9x scaled, centered space on a 3200x1350 display.
        let screenHeight: CGFloat = 1350
        func toCG(_ r: NSRect) -> CGRect {
            let flippedY = screenHeight - r.maxY
            return CGRect(
                x: r.minX * 0.9 + 160, y: flippedY * 0.9 + 67.5,
                width: r.width * 0.9, height: r.height * 0.9)
        }
        let panel = NSRect(x: 1009, y: 459, width: 480, height: 807)
        let t = FollowLayout.CoordinateTransform(
            appKitFrame: panel, cgBounds: toCG(panel), primaryScreenHeight: screenHeight)

        let wezTerm = NSRect(x: 1476, y: 459, width: 1280, height: 896)
        let recovered = FollowLayout.appKitRect(
            fromCGBounds: toCG(wezTerm), primaryScreenHeight: screenHeight, transform: t)
        #expect(abs(recovered.minX - wezTerm.minX) < 0.01)
        #expect(abs(recovered.minY - wezTerm.minY) < 0.01)
        #expect(abs(recovered.width - wezTerm.width) < 0.01)
        #expect(abs(recovered.height - wezTerm.height) < 0.01)
    }

    @Test func needsUpdateIgnoresSubPixelNoise() {
        let a = NSRect(x: 100, y: 100, width: 480, height: 800)
        let b = NSRect(x: 100.8, y: 99.4, width: 480.6, height: 800.9)
        #expect(!FollowLayout.needsUpdate(from: a, to: b))
        #expect(FollowLayout.needsUpdate(from: a, to: a.offsetBy(dx: 3, dy: 0)))
    }
}

struct FollowPanelWidthTests {
    @Test func clampsToRange() {
        #expect(FollowPanelWidth.clamped(100) == FollowPanelWidth.range.lowerBound)
        #expect(FollowPanelWidth.clamped(5000) == FollowPanelWidth.range.upperBound)
        #expect(FollowPanelWidth.clamped(600) == 600)
    }
}
