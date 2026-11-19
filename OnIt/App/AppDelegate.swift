import AppKit
import ServiceManagement

/// Owns the store and the AppKit side. Links are handled here rather than in a view, so
/// `onit://add` works with nothing on screen, including when the link launches the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Tests run inside the app and must never touch the real data file or menu bar.
    static let isTesting = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        .contains { ProcessInfo.processInfo.environment[$0] != nil }

    /// Created before any view, scene or link.
    let store = isTesting ? AppStore(snapshot: .seed()) : AppStore(persistence: Persistence())
    private var windows: WindowCoordinator?
    private var panel: PanelController?
    private var statusItem: StatusItemController?
    /// Links that arrive before launch finishes; nil afterwards.
    private var pendingURLs: [URL]? = []
    private var archiveTimer: Timer?

    func applicationWillFinishLaunching(_: Notification) { NSApp.setActivationPolicy(.accessory) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTesting else { return }
        windows = WindowCoordinator(store: store) { [weak self] in self?.showSettings() }
        panel = PanelController(store: store) { [weak self] in self?.showSettings() }
        statusItem = StatusItemController(store: store, menu: menu()) { [weak self] in self?.panel?.toggle() }
        panel?.anchor = statusItem?.button
        observeContinuously { [weak self] in self?.applyTheme() }

        store.sweepArchive()
        store.startWatchingFile()
        // Re-sweep hourly and on wake, so old Done cards archive even if OnIt is never quit.
        archiveTimer = .scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.store.sweepArchive() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.store.sweepArchive() }
        }
        store.updateSettings { $0.launchAtLogin = SMAppService.mainApp.status == .enabled }

        let queued = pendingURLs ?? []
        pendingURLs = nil
        queued.forEach(handle)
        // Opened as an app (Finder, Spotlight, `open -a`): show the window. Link and login launches stay quiet.
        if queued.isEmpty, Self.isDefaultLaunch(notification) { showMainWindow() }

        if let issue = store.launchIssue {
            DispatchQueue.main.async {
                NSApp.activate()
                let alert = NSAlert()
                (alert.messageText, alert.informativeText) = ("OnIt recovered your data", issue)
                alert.runModal()
            }
        }
    }

    /// App-wide, so the panel, windows and Settings all follow it; `nil` tracks the system.
    /// Skips unchanged themes, since any settings change re-runs this.
    private func applyTheme() {
        let name: NSAppearance.Name? = switch store.settings.theme {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
        guard NSApp.appearance?.name != name else { return }
        NSApp.appearance = name.flatMap(NSAppearance.init(named:))
    }

    func applicationWillTerminate(_: Notification) { store.flush(synchronously: true) }

    func applicationDidResignActive(_: Notification) {
        store.flush()
        panel?.closeUnlessKey()
    }

    /// Opening OnIt again while it's running brings up the window.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showMainWindow()
        return false
    }

    /// False for launches that open a link or document, and for login items.
    private static func isDefaultLaunch(_ notification: Notification) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginItem = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        return notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true && !loginItem
    }

    // MARK: Links

    func application(_: NSApplication, open urls: [URL]) {
        guard pendingURLs == nil else { return pendingURLs!.append(contentsOf: urls) }
        urls.forEach(handle)
    }

    private func handle(_ url: URL) {
        let notifier = Notifier.shared
        switch URLRouter.route(url) {
        case .add(let text):
            do {
                let (task, board, warning) = try store.add(text: text)
                statusItem?.pulse()
                let summary = [board.showsSizes ? task.size?.label : nil, task.title].compactMap { $0 }.joined(separator: " · ")
                // Warnings always notify, so a mistyped @board isn't missed.
                if let warning {
                    notifier.post(warning, summary)
                } else if store.settings.notifyOnAdd {
                    notifier.post("Added to \(board.name)", summary)
                }
            } catch {
                notifier.post("Task not added", error.localizedDescription)
            }
        case .open(let alias):
            if let alias {
                if let id = ShorthandParser.resolveBoard(alias, in: store.boards) {
                    panel?.ui.selectBoard(id)
                } else {
                    notifier.post("No board '@\(alias)'", "Showing your current board instead.")
                }
            }
            panel?.show()
        case .toggle:
            panel?.toggle()
        case .invalid(let reason):
            notifier.post("OnIt couldn't use that link", reason)
        }
    }

    // MARK: Menu

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let items = [("Open OnIt", #selector(showPanel), ""), ("Open in Window", #selector(showMainWindow), ""),
                     ("Archive…", #selector(showArchive), ""), ("Settings…", #selector(showSettings), ",")]
        for (title, action, key) in items { menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OnIt", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        return menu
    }

    @objc private func showPanel() { panel?.show() }
    @objc func showMainWindow() { panel?.close(); windows?.showMain() }
    @objc func showArchive() { panel?.close(); windows?.showArchive() }
    @objc func showSettings() { panel?.close(); windows?.showSettings() }
}
