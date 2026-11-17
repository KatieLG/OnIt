import AppKit
import SwiftUI

/// A panel that can take keyboard focus without being a regular document window.
final class OnItPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Esc is handled by the keyboard router; swallow the default beep/close.
    override func cancelOperation(_ sender: Any?) {}
}

/// The "popover": an `NSPanel` hosting SwiftUI, positioned under the status item.
///
/// `MenuBarExtra` can't be opened programmatically, resized by the user, or given a right-click
/// menu, so this uses `NSStatusItem` + a panel (spec §5 allows this). The UI is still SwiftUI.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: AppStore
    private let ui: BoardUIState
    private let panel: OnItPanel
    private weak var anchorButton: NSStatusBarButton?
    private var keyRouter: KeyboardRouter!
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var lastLaterExpanded: Bool

    private static let sizeDefaultsKey = "PanelSize"

    var isVisible: Bool { panel.isVisible }

    init(store: AppStore, ui: BoardUIState) {
        self.store = store
        self.ui = ui
        self.lastLaterExpanded = store.settings.laterExpanded

        panel = OnItPanel(
            contentRect: NSRect(origin: .zero, size: Self.savedSize()),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.minSize = PanelMetrics.minSize
        panel.maxSize = PanelMetrics.maxSize
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        panel.setAccessibilityTitle("OnIt")

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active

        let hosting = NSHostingView(
            rootView: RootView()
                .environment(store)
                .environment(ui)
        )
        hosting.sizingOptions = []
        // The panel's title bar is invisible, so don't let SwiftUI inset the content below it.
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        keyRouter = KeyboardRouter(ui: ui, window: panel, closesOnEscape: true, close: { [weak self] in self?.close() })

        observeContinuously { [weak self] in self?.laterExpandedChanged() }
    }

    // MARK: Showing and hiding

    func toggle() {
        isVisible ? close() : show()
    }

    func setAnchor(_ button: NSStatusBarButton?) {
        anchorButton = button
    }

    func show() {
        positionPanel(size: panel.frame.size)
        if anchorFrame == nil { repositionWhenAnchorIsReady() }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        installMonitors()
        // Start with the board focused (not a text field) so arrow keys work immediately.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if ui.editingTaskId == nil { ui.focusRequest = .board }
        }
        store.sweepArchive()
    }

    func close() {
        guard panel.isVisible else { return }
        if ui.editingTaskId != nil { ui.commitEdit() }
        panel.orderOut(nil)
        removeMonitors()
        store.flush()
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.keyRouter.handle(event)
            }
            return handled ? nil : event
        }
        // Clicks in other apps (including the desktop) close the panel, like a popover.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfNoChildUI() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        keyMonitor = nil
        outsideClickMonitor = nil
    }

    private func closeIfNoChildUI() {
        // Leave the panel up while it has a sheet (e.g. the tag editor) open.
        guard panel.attachedSheet == nil else { return }
        close()
    }

    func appDidResignActive() {
        // A nonactivating panel can be key while another app is active, so only close if the
        // panel itself has also lost key status (the user went somewhere else).
        if !panel.isKeyWindow { closeIfNoChildUI() }
    }

    // MARK: Geometry

    /// After a cold launch the status item takes a moment to be placed in the menu bar; until then
    /// the panel sits at the top-right fallback. Move it under the icon as soon as that's known.
    private func repositionWhenAnchorIsReady(attempt: Int = 0) {
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if self.anchorFrame != nil {
                self.positionPanel(size: self.panel.frame.size)
            } else {
                self.repositionWhenAnchorIsReady(attempt: attempt + 1)
            }
        }
    }

    /// The status item's frame in screen coordinates, or nil if it isn't laid out in the menu bar
    /// yet. Right after a cold launch (e.g. from `onit://open`) its window can still be at the origin.
    private var anchorFrame: NSRect? {
        guard let window = anchorButton?.window, let screen = window.screen else { return nil }
        let frame = window.frame
        guard frame.width > 0, frame.minY >= screen.visibleFrame.maxY - 4 else { return nil }
        return frame
    }

    private func positionPanel(size: NSSize) {
        let screen = anchorButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        var size = size
        size.width = min(max(size.width, PanelMetrics.minSize.width), visible.width - 16)
        size.height = min(max(size.height, PanelMetrics.minSize.height), visible.height - 16)

        var origin: NSPoint
        if let buttonFrame = anchorFrame {
            origin = NSPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - size.height - 6)
        } else {
            origin = NSPoint(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - 6)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Later expanding/collapsing animates the panel wider/narrower by one column.
    private func laterExpandedChanged() {
        let expanded = store.settings.laterExpanded
        guard expanded != lastLaterExpanded else { return }
        lastLaterExpanded = expanded

        let frame = panel.frame
        let inner = frame.width - PanelMetrics.outerPadding * 2 - PanelMetrics.columnSpacing * 3
        let newWidth: CGFloat
        if expanded {
            let columnWidth = (inner - PanelMetrics.laterStripWidth) / 3
            newWidth = frame.width - PanelMetrics.laterStripWidth + columnWidth
        } else {
            let columnWidth = inner / 4
            newWidth = frame.width - columnWidth + PanelMetrics.laterStripWidth
        }
        let size = NSSize(width: newWidth, height: frame.height)
        saveSize(size)

        guard panel.isVisible else {
            panel.setContentSize(size)
            return
        }
        let target = targetFrame(for: size)
        panel.setFrame(target, display: true, animate: !BoardUIState.reduceMotion)
    }

    private func targetFrame(for size: NSSize) -> NSRect {
        let current = panel.frame
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? current
        let width = min(max(size.width, PanelMetrics.minSize.width), min(PanelMetrics.maxSize.width, visible.width - 16))
        var x = current.midX - width / 2
        if let buttonFrame = anchorFrame { x = buttonFrame.midX - width / 2 }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        return NSRect(x: x, y: current.maxY - size.height, width: width, height: size.height)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveSize(panel.frame.size)
    }

    private func saveSize(_ size: NSSize) {
        UserDefaults.standard.set([Double(size.width), Double(size.height)], forKey: Self.sizeDefaultsKey)
    }

    private static func savedSize() -> NSSize {
        if let values = UserDefaults.standard.array(forKey: sizeDefaultsKey) as? [Double], values.count == 2 {
            return NSSize(width: values[0], height: values[1])
        }
        return PanelMetrics.defaultSize
    }
}
