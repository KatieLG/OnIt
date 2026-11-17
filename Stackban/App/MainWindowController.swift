import AppKit
import SwiftUI

/// The full-size board window shown when Stackban is opened as an app (Finder, Spotlight,
/// Launchpad, or opened again while running). Same `RootView` as the menu bar panel, but in a
/// standard, resizable window that supports full screen.
///
/// It has its own `BoardUIState`, so selection, filters and editing are independent of the panel;
/// the data (`AppStore`) is shared.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let autosaveName = "StackbanMainWindow"

    let window: NSWindow
    private let ui: BoardUIState
    private var keyRouter: KeyboardRouter!
    private var keyMonitor: Any?
    /// Called after the window closes (used to drop the Dock icon again).
    var onClose: () -> Void = {}

    init(store: AppStore, ui: BoardUIState) {
        self.ui = ui
        let hosting = NSHostingController(
            rootView: RootView()
                .environment(store)
                .environment(ui)
        )
        hosting.sizingOptions = []
        window = NSWindow(contentViewController: hosting)
        super.init()

        window.title = "Stackban"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentMinSize = PanelMetrics.minSize
        window.delegate = self

        if !window.setFrameUsingName(Self.autosaveName) {
            window.setFrame(Self.defaultFrame(), display: false)
        }
        window.setFrameAutosaveName(Self.autosaveName)

        keyRouter = KeyboardRouter(ui: ui, window: window, closesOnEscape: false) { [weak self] in
            self?.window.performClose(nil)
        }
    }

    /// Large and centred on the main screen: 85% of the usable area, capped at 1600×1000.
    private static func defaultFrame() -> NSRect {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(visible.width * 0.85, PanelMetrics.minSize.width), 1600)
        let height = min(max(visible.height * 0.85, PanelMetrics.minSize.height), 1000)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    func show() {
        installKeyMonitor()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.ui.editingTaskId == nil else { return }
            self.ui.focusRequest = .board
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.window else { return false }
                return self.keyRouter.handle(event)
            }
            return handled ? nil : event
        }
    }

    func windowWillClose(_ notification: Notification) {
        if ui.editingTaskId != nil { ui.commitEdit() }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        onClose()
    }
}
