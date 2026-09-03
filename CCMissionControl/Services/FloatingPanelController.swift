import AppKit
import SwiftUI

final class FloatingPanelController {
    private var panel: NSPanel?
    private let contentView: NSView
    private var followTimer: Timer?
    private var resizeObserver: (any NSObjectProtocol)?

    init<Content: View>(@ViewBuilder content: () -> Content) {
        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 400)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(relativeTo statusItemButton: NSStatusBarButton?) {
        if isVisible {
            close()
        } else {
            show(relativeTo: statusItemButton)
        }
    }

    /// Re-applies the current `WindowMode` to an already visible panel
    /// (e.g. after the user changes the mode in Settings).
    func applyCurrentMode(relativeTo statusItemButton: NSStatusBarButton?) {
        guard isVisible else { return }
        show(relativeTo: statusItemButton, activate: false)
    }

    func show(relativeTo statusItemButton: NSStatusBarButton?, activate: Bool = true) {
        let panel = makeOrReusePanel()
        stopFollowing()

        switch WindowMode.current {
        case .floating:
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.minSize = NSSize(width: 480, height: 200)
            panel.styleMask.insert(.titled)
            panel.title = "CCMissionControl"
            panel.setFrameAutosaveName("FloatingPanel")

            if !panel.isVisible && !panel.setFrameUsingName("FloatingPanel") {
                panel.center()
            }

        case .followWezTerm:
            // Live in the normal window layer and stay directly above the WezTerm window
            // in z-order, so the panel is covered and revealed together with WezTerm.
            panel.level = .normal
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            panel.minSize = NSSize(width: FollowPanelWidth.range.lowerBound, height: 200)
            panel.styleMask.insert(.titled)
            panel.title = "CCMissionControl"
            // Do not persist frames that were dictated by the WezTerm window.
            panel.setFrameAutosaveName("")

            if !snapToWezTerm(panel), !panel.isVisible {
                panel.center()
            }
            startFollowing()

        case .dropdown:
            panel.level = .statusBar
            panel.hidesOnDeactivate = true
            panel.isMovableByWindowBackground = true
            panel.minSize = NSSize(width: 480, height: 200)
            panel.styleMask.remove(.titled)
            panel.setFrameAutosaveName("")

            if let button = statusItemButton {
                let buttonRect =
                    button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
                let panelWidth = panel.frame.width
                let x = buttonRect.midX - panelWidth / 2
                let y = buttonRect.minY - panel.frame.height
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        if activate {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFront(nil)
        }
    }

    func close() {
        stopFollowing()
        panel?.orderOut(nil)
    }

    // MARK: - Follow WezTerm

    private func startFollowing() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func followTick() {
        // Let the user drag-resize freely; the new width is persisted when the resize ends.
        guard let panel, panel.isVisible, !panel.inLiveResize else { return }
        snapToWezTerm(panel)
    }

    /// Persists the width chosen by drag-resizing the panel while following WezTerm.
    private func panelDidEndLiveResize(_ panel: NSPanel) {
        guard WindowMode.current == .followWezTerm else { return }
        FollowPanelWidth.current = panel.frame.width
    }

    /// Moves the panel next to the frontmost WezTerm window.
    /// Returns false when no suitable window exists (not running, or full screen).
    @discardableResult
    private func snapToWezTerm(_ panel: NSPanel) -> Bool {
        // Calibrate CG -> AppKit coordinates against our own panel once it is on screen.
        let reference =
            panel.isVisible
            ? WezTermWindowLocator.ReferenceWindow(
                windowNumber: panel.windowNumber, frame: panel.frame)
            : nil
        guard let wezTerm = WezTermWindowLocator.frontmostWindow(reference: reference)
        else { return false }
        let target = wezTerm.frame

        let screens = NSScreen.screens
        let targetScreen =
            screens.max { lhs, rhs in
                lhs.frame.intersection(target).area < rhs.frame.intersection(target).area
            } ?? NSScreen.main
        guard let targetScreen else { return false }

        if FollowLayout.isFullScreen(
            windowFrame: target,
            screenFrame: targetScreen.frame,
            topSafeAreaInset: targetScreen.safeAreaInsets.top
        ) {
            return false
        }

        let frame = FollowLayout.panelFrame(
            attachedTo: target,
            panelWidth: FollowPanelWidth.current,
            screenFrames: screens.map(\.frame),
            targetScreenFrame: targetScreen.frame
        )
        if FollowLayout.needsUpdate(from: panel.frame, to: frame) {
            panel.setFrame(frame, display: true)
        }
        if wezTerm.referenceNeedsReordering {
            panel.order(.above, relativeTo: wezTerm.windowNumber)
        }
        return true
    }

    private func makeOrReusePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = contentView
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.minSize = NSSize(width: 480, height: 200)

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.panelDidEndLiveResize(panel)
            }
        }

        self.panel = panel
        return panel
    }
}

extension NSRect {
    fileprivate var area: CGFloat {
        isNull ? 0 : width * height
    }
}
