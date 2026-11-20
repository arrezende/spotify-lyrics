import AppKit
import SwiftUI
import Combine

/// A borderless, non-activating panel that behaves like the system picture-in-picture window:
/// floats above everything, follows the user across Spaces and full-screen apps,
/// drags from any point, snaps to screen corners and has no title bar.
final class PiPPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PiPPanelController: NSObject, NSWindowDelegate {
    private let model: PlayerModel
    private var panel: PiPPanel?
    private var grip: ResizeGripView?
    private var snapWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var expandedFrame: NSRect?
    private(set) var isVisible = false

    private let defaultSize = NSSize(width: 420, height: 176)
    private let minSize = NSSize(width: 300, height: 132)
    private let collapsedHeight: CGFloat = 36

    init(model: PlayerModel) {
        self.model = model
        super.init()

        model.$isCollapsed
            .removeDuplicates()
            .sink { [weak self] collapsed in self?.applyCollapsed(collapsed) }
            .store(in: &cancellables)

        model.$windowAlpha
            .removeDuplicates()
            .sink { [weak self] alpha in self?.panel?.alphaValue = CGFloat(alpha) }
            .store(in: &cancellables)
    }

    // MARK: - Window lifecycle

    func present() {
        let panel = makePanel()
        self.panel = panel
        panel.alphaValue = CGFloat(model.windowAlpha)
        panel.orderFrontRegardless()
        isVisible = true
        if model.isCollapsed { applyCollapsed(true) }
    }

    private func makePanel() -> PiPPanel {
        let frame = restoredFrame() ?? defaultFrame()
        let panel = PiPPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let host = NSHostingView(rootView: LyricsRootView(model: model, controller: self))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(host)

        // Resize handle in the bottom-right corner, above the SwiftUI content so the drag
        // is not swallowed by the "move window from background" behaviour.
        let grip = ResizeGripView(frame: NSRect(x: frame.width - 24, y: 0, width: 24, height: 24))
        grip.autoresizingMask = [.minXMargin, .maxYMargin]
        grip.controller = self
        container.addSubview(grip)
        self.grip = grip

        panel.contentView = container
        return panel
    }

    func toggle() {
        guard let panel else { present(); return }
        if isVisible {
            panel.orderOut(nil)
            isVisible = false
        } else {
            panel.orderFrontRegardless()
            isVisible = true
        }
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    var window: NSWindow? { panel }

    // MARK: - Collapse (the "minimize" of a borderless PiP window)

    private func applyCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        grip?.isHidden = collapsed

        var target = panel.frame
        if collapsed {
            if expandedFrame == nil { expandedFrame = panel.frame }
            target.size.height = collapsedHeight
            target.origin.y = panel.frame.maxY - collapsedHeight
        } else if let restored = expandedFrame {
            target.size = NSSize(width: max(restored.width, minSize.width), height: max(restored.height, minSize.height))
            target.origin.y = panel.frame.maxY - target.height
        } else {
            target.size = defaultSize
            target.origin.y = panel.frame.maxY - defaultSize.height
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            self?.saveFrame()
        }
    }

    // MARK: - Frame

    private func defaultFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let bounds = screen.map { placementBounds(for: $0) } ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: bounds.maxX - defaultSize.width - 20,
            y: bounds.minY + bottomMargin(),
            width: defaultSize.width,
            height: defaultSize.height
        )
    }

    /// Area the panel may snap into. With `bottomOverDock` on the Dock strip stops being
    /// reserved, so the panel can sit on the physical bottom edge of the display.
    private func placementBounds(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let bottom = model.bottomOverDock ? screen.frame.minY : visible.minY
        return NSRect(x: visible.minX, y: bottom, width: visible.width, height: visible.maxY - bottom)
    }

    private func bottomMargin() -> CGFloat {
        model.bottomOverDock ? 6 : 20
    }

    /// Re-applies the corner snapping, e.g. after changing the bottom placement preference.
    func refreshPlacement() {
        guard panel != nil else { return }
        snapWork?.cancel()
        snapToNearestCorner()
    }

    private func restoredFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: "panelFrame") else { return nil }
        let frame = NSRectFromString(raw)
        guard frame.width >= minSize.width, frame.height >= minSize.height else { return nil }
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        return onScreen ? frame : nil
    }

    private func saveFrame() {
        guard let panel, !model.isCollapsed else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
    }

    func resetSize() {
        guard let panel else { return }
        var target = panel.frame
        target.size = defaultSize
        target.origin.y = panel.frame.maxY - defaultSize.height
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            self?.saveFrame()
        }
    }

    /// Screen-space delta from the grip drag: dragging down (negative dy) grows the panel.
    func resize(byDelta delta: CGSize) {
        guard let panel, !model.isCollapsed else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.width = max(minSize.width, frame.width + delta.width)
        frame.size.height = max(minSize.height, frame.height - delta.height)
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true)
    }

    // MARK: - Snapping like video PiP

    func windowDidMove(_ notification: Notification) {
        saveFrame()
        guard !model.isCollapsed else { return }
        snapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapToNearestCorner() }
        snapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func snapToNearestCorner() {
        guard let panel else { return }
        let current = panel.frame
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(current) }) ?? NSScreen.main else { return }
        let bounds = placementBounds(for: screen)

        let margin: CGFloat = 20
        let left = bounds.minX + margin
        let right = bounds.maxX - current.width - margin
        let bottom = bounds.minY + bottomMargin()
        let top = bounds.maxY - current.height - margin

        let target = NSRect(
            x: abs(current.minX - left) < abs(current.minX - right) ? left : right,
            y: abs(current.minY - bottom) < abs(current.minY - top) ? bottom : top,
            width: current.width,
            height: current.height
        )
        guard !NSEqualRects(target, current) else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            self?.saveFrame()
        }
    }
}

/// Visible 24×24 corner handle that resizes the panel; keeps the top-left corner pinned.
final class ResizeGripView: NSView {
    weak var controller: PiPPanelController?
    private var lastPoint: NSPoint = .zero
    private var trackingArea: NSTrackingArea?
    private var hovered = false

    /// Without this the window drags itself instead of delivering mouseDown to us.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hovered ? 0.65 : 0.30).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        for index in 0..<3 {
            let offset = CGFloat(index) * 5
            path.move(to: NSPoint(x: bounds.maxX - 13 + offset, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + 13 - offset))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let delta = CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y)
        lastPoint = point
        guard delta != .zero else { return }
        controller?.resize(byDelta: delta)
    }
}
