import AppKit
import SwiftUI

final class FloatingPanelController {
    private var panel: NSPanel?
    private let contentView: NSView

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

    func show(relativeTo statusItemButton: NSStatusBarButton?) {
        let panel = makeOrReusePanel()

        let isFloating =
            WindowMode.current == .floating

        if isFloating {
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.styleMask.insert(.titled)
            panel.title = "CCMissionControl"
            panel.setFrameAutosaveName("FloatingPanel")

            if !panel.isVisible && !panel.setFrameUsingName("FloatingPanel") {
                panel.center()
            }
        } else {
            panel.level = .statusBar
            panel.hidesOnDeactivate = true
            panel.styleMask.remove(.titled)

            if let button = statusItemButton {
                let buttonRect =
                    button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
                let panelWidth = panel.frame.width
                let x = buttonRect.midX - panelWidth / 2
                let y = buttonRect.minY - panel.frame.height
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
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

        self.panel = panel
        return panel
    }
}
