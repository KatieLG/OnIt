import AppKit
import SwiftUI

/// The main board, Settings and Archive windows. While any is open OnIt is a regular app (Dock
/// icon, ⌘-Tab, full screen); once they're all closed it goes back to living in the menu bar.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: AppStore
    /// The main window's own selection and filters; the data is shared with the panel.
    private let mainUI: BoardUIState
    private var windows: [String: NSWindow] = [:]
    private var keyRouter: KeyboardRouter?

    init(store: AppStore, openSettings: @escaping () -> Void) {
        self.store = store
        mainUI = BoardUIState(store: store)
        mainUI.openSettings = openSettings
    }

    /// The full board in a large, resizable, full-screen-capable window.
    func showMain() {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let window = present("", content: RootView().environment(mainUI), fitsContent: false,
                             defaultSize: NSSize(width: min(visible.width * 0.85, 1600), height: min(visible.height * 0.85, 1000)))
        if keyRouter == nil {
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.contentMinSize = PanelMetrics.minSize
            keyRouter = KeyboardRouter(ui: mainUI, window: window, closesOnEscape: false) { window.performClose(nil) }
        }
        DispatchQueue.main.async { [mainUI] in mainUI.focusRequest = .board }
    }

    func showSettings() { present("Settings", content: SettingsView()) }
    func showArchive() { present("Archive", content: ArchiveView()) }

    @discardableResult
    private func present(_ name: String, content: some View, fitsContent: Bool = true, defaultSize: NSSize? = nil) -> NSWindow {
        let window = windows[name] ?? {
            let controller = NSHostingController(rootView: content.environment(store))
            if !fitsContent { controller.sizingOptions = [] }
            let window = NSWindow(contentViewController: controller)
            window.title = name.isEmpty ? "OnIt" : "OnIt \(name)"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.tabbingMode = .disallowed
            window.isReleasedWhenClosed = false
            window.delegate = self
            if !window.setFrameUsingName("OnIt\(name)") {
                if let defaultSize { window.setContentSize(defaultSize) }
                window.center()
            }
            window.setFrameAutosaveName("OnIt\(name)")
            windows[name] = window
            return window
        }()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === windows[""] { mainUI.commitEdit() }
        if !windows.values.contains(where: { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
