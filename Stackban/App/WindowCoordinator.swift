import AppKit
import SwiftUI

/// Opens the Settings and Archive windows from an `LSUIElement` app.
///
/// While either window is open the app temporarily becomes a regular app (Dock icon) so the
/// window reliably comes to the front; it reverts to an accessory app when they close.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: AppStore
    private let notifier: Notifier
    private var settingsWindow: NSWindow?
    private var archiveWindow: NSWindow?

    init(store: AppStore, notifier: Notifier) {
        self.store = store
        self.notifier = notifier
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
        let closing = notification.object as? NSWindow
        let others = [settingsWindow, archiveWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty {
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
