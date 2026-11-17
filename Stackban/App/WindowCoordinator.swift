import AppKit
import SwiftUI

/// Opens the main board, Settings and Archive windows from an `LSUIElement` app.
///
/// While any of them is open the app temporarily becomes a regular app (Dock icon, app menu,
/// ⌘-Tab, full screen) so windows reliably come to the front; it reverts to an accessory
/// (menu bar only) app when they all close.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: AppStore
    private let notifier: Notifier
    private let mainUI: BoardUIState
    private var mainWindow: MainWindowController?
    private var settingsWindow: NSWindow?
    private var archiveWindow: NSWindow?

    init(store: AppStore, notifier: Notifier, mainUI: BoardUIState) {
        self.store = store
        self.notifier = notifier
        self.mainUI = mainUI
    }

    func showMainWindow() {
        if mainWindow == nil {
            let controller = MainWindowController(store: store, ui: mainUI)
            controller.onClose = { [weak self, weak controller] in
                self?.revertActivationPolicyIfNeeded(closing: controller?.window)
            }
            mainWindow = controller
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        mainWindow?.show()
        mainWindow?.window.orderFrontRegardless()
    }

    func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
                .environment(store)
                .environment(\.notifier, notifier)
            settingsWindow = makeWindow(title: "Stackban Settings", autosave: "StackbanSettings", content: view)
        }
        present(settingsWindow)
    }

    func showArchive() {
        if archiveWindow == nil {
            let view = ArchiveView().environment(store)
            archiveWindow = makeWindow(title: "Stackban Archive", autosave: "StackbanArchive", content: view)
            archiveWindow?.styleMask.insert(.resizable)
        }
        present(archiveWindow)
    }

    private func makeWindow<Content: View>(title: String, autosave: String, content: Content) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        revertActivationPolicyIfNeeded(closing: notification.object as? NSWindow)
    }

    private func revertActivationPolicyIfNeeded(closing: NSWindow?) {
        let open = [mainWindow?.window, settingsWindow, archiveWindow]
            .compactMap { $0 }
            .filter { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }
        if open.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct NotifierKey: EnvironmentKey {
    static let defaultValue: Notifier? = nil
}

extension EnvironmentValues {
    var notifier: Notifier? {
        get { self[NotifierKey.self] }
        set { self[NotifierKey.self] = newValue }
    }
}
