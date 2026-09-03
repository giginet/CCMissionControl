import AppKit

/// Locates on-screen WezTerm windows using the CoreGraphics window list.
/// No accessibility permission is required for window bounds.
enum WezTermWindowLocator {
    static let bundleIdentifier = "com.github.wez.wezterm"

    /// A window of our own whose AppKit frame is known. Used to calibrate the mapping
    /// from window-server (CoreGraphics) coordinates back to AppKit coordinates.
    struct ReferenceWindow {
        let windowNumber: Int
        let frame: NSRect
    }

    /// The frontmost on-screen WezTerm window.
    struct WindowInfo {
        /// Frame in AppKit screen coordinates.
        let frame: NSRect
        /// Window-server window number, usable with `NSWindow.order(_:relativeTo:)`.
        let windowNumber: Int
        /// True when the reference window is not immediately above the WezTerm window
        /// in z-order (i.e. it is behind WezTerm, or another normal window sits between them).
        let referenceNeedsReordering: Bool
    }

    /// Frame (in AppKit screen coordinates) of the frontmost on-screen WezTerm window.
    /// Returns nil when WezTerm has no visible window on the current Space.
    static func frontmostWindowFrame(reference: ReferenceWindow? = nil) -> NSRect? {
        frontmostWindow(reference: reference)?.frame
    }

    /// Finds the frontmost on-screen WezTerm window.
    /// Returns nil when WezTerm has no visible window on the current Space.
    static func frontmostWindow(reference: ReferenceWindow? = nil) -> WindowInfo? {
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .map(\.processIdentifier)
        )
        guard !pids.isEmpty else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        var wezTermBounds: CGRect?
        var wezTermWindowNumber: Int?
        var referenceBounds: CGRect?
        // Position of each window among layer-0 (normal) windows, front-to-back.
        var normalWindowIndex = 0
        var referenceOrder: Int?
        var wezTermOrder: Int?

        // Window list is ordered front-to-back; the first matching window is frontmost.
        for info in infos {
            guard
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            let layer = info[kCGWindowLayer as String] as? Int
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let isNormalWindow = layer == 0 && alpha > 0
            defer { if isNormalWindow { normalWindowIndex += 1 } }

            if let reference, referenceBounds == nil,
                (info[kCGWindowNumber as String] as? Int) == reference.windowNumber
            {
                referenceBounds = bounds
                referenceOrder = normalWindowIndex
                continue
            }

            guard
                wezTermBounds == nil,
                isNormalWindow,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                pids.contains(pid),
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                bounds.width >= 100, bounds.height >= 100
            else { continue }

            wezTermBounds = bounds
            wezTermWindowNumber = windowNumber
            wezTermOrder = normalWindowIndex
        }

        guard let wezTermBounds, let wezTermWindowNumber, let wezTermOrder else { return nil }

        var transform = FollowLayout.CoordinateTransform.identity
        if let reference, let referenceBounds {
            transform = FollowLayout.CoordinateTransform(
                appKitFrame: reference.frame,
                cgBounds: referenceBounds,
                primaryScreenHeight: primaryScreenHeight
            )
        }
        let frame = FollowLayout.appKitRect(
            fromCGBounds: wezTermBounds,
            primaryScreenHeight: primaryScreenHeight,
            transform: transform
        )

        // The reference is in place only when it is the normal window directly in front of WezTerm.
        let needsReordering: Bool
        if let referenceOrder {
            needsReordering = referenceOrder != wezTermOrder - 1
        } else {
            needsReordering = false
        }

        return WindowInfo(
            frame: frame,
            windowNumber: wezTermWindowNumber,
            referenceNeedsReordering: needsReordering
        )
    }
}

/// Pure geometry helpers for the "Follow WezTerm" window mode.
enum FollowLayout {
    /// Affine mapping between flipped AppKit coordinates (top-left origin) and the
    /// coordinates reported by `CGWindowListCopyWindowInfo`.
    ///
    /// On most systems this is the identity. Some display configurations report
    /// window bounds in a uniformly scaled and offset space, so the mapping is
    /// calibrated from a window whose AppKit frame is known.
    struct CoordinateTransform: Equatable {
        var scaleX: CGFloat
        var scaleY: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat

        nonisolated static let identity = CoordinateTransform(
            scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)

        /// Derives the transform from a window with a known AppKit frame and its CG bounds.
        nonisolated init(appKitFrame: NSRect, cgBounds: CGRect, primaryScreenHeight: CGFloat) {
            guard appKitFrame.width > 0, appKitFrame.height > 0 else {
                self = .identity
                return
            }
            let flippedY = primaryScreenHeight - appKitFrame.maxY
            let sx = cgBounds.width / appKitFrame.width
            let sy = cgBounds.height / appKitFrame.height
            self.init(
                scaleX: sx,
                scaleY: sy,
                offsetX: cgBounds.minX - appKitFrame.minX * sx,
                offsetY: cgBounds.minY - flippedY * sy
            )
            if isNearlyIdentity {
                self = .identity
            }
        }

        nonisolated init(scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.offsetX = offsetX
            self.offsetY = offsetY
        }

        nonisolated private var isNearlyIdentity: Bool {
            abs(scaleX - 1) < 0.005 && abs(scaleY - 1) < 0.005
                && abs(offsetX) < 2 && abs(offsetY) < 2
        }

        /// Maps CG bounds back to flipped AppKit coordinates (top-left origin).
        nonisolated func flippedRect(fromCGBounds bounds: CGRect) -> CGRect {
            CGRect(
                x: (bounds.minX - offsetX) / scaleX,
                y: (bounds.minY - offsetY) / scaleY,
                width: bounds.width / scaleX,
                height: bounds.height / scaleY
            )
        }
    }

    /// Converts CoreGraphics (top-left origin) bounds to AppKit (bottom-left origin) coordinates.
    nonisolated static func appKitRect(
        fromCGBounds bounds: CGRect,
        primaryScreenHeight: CGFloat,
        transform: CoordinateTransform = .identity
    ) -> NSRect {
        let flipped = transform.flippedRect(fromCGBounds: bounds)
        return NSRect(
            x: flipped.minX,
            y: primaryScreenHeight - flipped.maxY,
            width: flipped.width,
            height: flipped.height
        )
    }

    /// A window is treated as full screen when it spans the whole screen width and
    /// its height fills the screen (allowing for the notch safe area on the top edge).
    nonisolated static func isFullScreen(
        windowFrame: NSRect, screenFrame: NSRect, topSafeAreaInset: CGFloat
    ) -> Bool {
        abs(windowFrame.width - screenFrame.width) <= 2
            && windowFrame.height >= screenFrame.height - topSafeAreaInset - 2
    }

    /// Computes the panel frame attached to the left edge of `target` with the same height.
    /// Falls back to the right edge when the panel would not fit on any screen,
    /// and clamps to the screen's left edge when neither side fits.
    nonisolated static func panelFrame(
        attachedTo target: NSRect,
        panelWidth: CGFloat,
        screenFrames: [NSRect],
        targetScreenFrame: NSRect
    ) -> NSRect {
        let left = NSRect(
            x: target.minX - panelWidth, y: target.minY, width: panelWidth, height: target.height)
        if screenFrames.contains(where: { $0.contains(left) }) {
            return left
        }

        let right = NSRect(x: target.maxX, y: target.minY, width: panelWidth, height: target.height)
        if screenFrames.contains(where: { $0.contains(right) }) {
            return right
        }

        return NSRect(
            x: targetScreenFrame.minX, y: target.minY, width: panelWidth, height: target.height)
    }

    /// Whether two frames differ enough to warrant moving the panel.
    /// Calibrated coordinates carry sub-pixel noise; ignore tiny differences to avoid jitter.
    nonisolated static func needsUpdate(from current: NSRect, to proposed: NSRect) -> Bool {
        let tolerance: CGFloat = 1.5
        return abs(current.minX - proposed.minX) > tolerance
            || abs(current.minY - proposed.minY) > tolerance
            || abs(current.width - proposed.width) > tolerance
            || abs(current.height - proposed.height) > tolerance
    }
}
