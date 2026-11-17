import AppKit
import SwiftUI

private final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_: Any?) {} // Esc is handled by KeyboardRouter
}

/// The menu bar board: a non-activating, resizable, translucent panel under the status item.
/// (`MenuBarExtra` can't be opened from a link, resized or given a right-click menu.)
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let ui: BoardUIState
    weak var anchor: NSStatusBarButton?
    private let store: AppStore
    private let panel: Panel
    private var keyRouter: KeyboardRouter?
    private var laterExpanded: Bool

    init(store: AppStore, openSettings: @escaping () -> Void) {
        self.store = store
        ui = BoardUIState(store: store)
        laterExpanded = store.settings.laterExpanded
        let saved = UserDefaults.standard.array(forKey: "PanelSize") as? [Double] ?? []
        panel = Panel(contentRect: NSRect(origin: .zero, size: saved.count == 2 ? NSSize(width: saved[0], height: saved[1]) : PanelMetrics.defaultSize),
                      styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        ui.openSettings = openSettings
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.minSize = PanelMetrics.minSize
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }

        let effect = NSVisualEffectView()
        (effect.material, effect.blendingMode, effect.state) = (.popover, .behindWindow, .active)
        let hosting = NSHostingView(rootView: RootView().environment(store).environment(ui))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = [] // the title bar is invisible; don't inset below it
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        panel.contentView = effect

        keyRouter = KeyboardRouter(ui: ui, window: panel, closesOnEscape: true) { [weak self] in self?.close() }
        // Clicks in other apps close the panel, like a popover.
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessSheet() }
        }
        observeContinuously { [weak self] in self?.laterChanged() }
    }

    func toggle() { panel.isVisible ? close() : show() }

    func show() {
        place()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DispatchQueue.main.async { [ui] in if ui.editingTaskId == nil { ui.focusRequest = .board } }
        store.sweepArchive()
    }

    func close() {
        guard panel.isVisible else { return }
        ui.commitEdit()
        panel.orderOut(nil)
        store.flush()
    }

    /// Being non-activating, the panel can still be key after OnIt deactivates; only close if not.
    func closeUnlessKey() { if !panel.isKeyWindow { closeUnlessSheet() } }
    private func closeUnlessSheet() { if panel.attachedSheet == nil { close() } }

    /// Centres the panel under the status item. Just after a cold launch the item isn't in the menu
    /// bar yet, so the panel starts top-right and moves under the icon once it's placed.
    private func place(attempt: Int = 0) {
        guard let visible = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = NSSize(width: min(panel.frame.width, visible.width - 16), height: min(panel.frame.height, visible.height - 16))
        let icon = anchor?.window?.frame ?? .zero
        let ready = icon.width > 0 && icon.minY >= visible.maxY - 4
        let x = (ready ? icon.midX - size.width / 2 : visible.maxX).clamped(to: visible.minX + 8 ... visible.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: visible.maxY - size.height - 6, width: size.width, height: size.height), display: true)
        if !ready, attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if self?.panel.isVisible == true { self?.place(attempt: attempt + 1) }
            }
        }
    }

    /// Expanding Later widens the panel by a column; collapsing narrows it back.
    private func laterChanged() {
        guard store.settings.laterExpanded != laterExpanded else { return }
        laterExpanded.toggle()
        let frame = panel.frame, strip = PanelMetrics.laterStripWidth
        let columns = frame.width - PanelMetrics.outerPadding * 2 - PanelMetrics.columnSpacing * 3
        let width = laterExpanded ? frame.width - strip + (columns - strip) / 3 : frame.width - columns / 4 + strip
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height),
                       display: true, animate: panel.isVisible && !BoardUIState.reduceMotion)
        saveSize()
    }

    func windowDidEndLiveResize(_: Notification) { saveSize() }
    private func saveSize() { UserDefaults.standard.set([panel.frame.width, panel.frame.height], forKey: "PanelSize") }
}
