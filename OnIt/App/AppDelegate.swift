import AppKit
import os
import ServiceManagement

/// Owns the store and all AppKit controllers. URL handling lives here (not in a view) so that
/// `onit://add` works while the popover is closed and when the URL launches the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: AppStore
    let ui: BoardUIState
    let notifier = Notifier()

    private var statusController: StatusItemController?
    private var panelController: PanelController?
    private var windows: WindowCoordinator?
    private var hourlySweep: Timer?
    private var pendingURLs: [URL] = []
    private var didFinishLaunching = false
    private let logger = Logger(subsystem: "com.example.onit", category: "app")

    /// Unit tests run inside the app process; they must never touch the real data file or menu bar.
    static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }()

    override init() {
        // The store exists before any view, scene or URL event.
        if Self.isRunningTests {
            store = AppStore(snapshot: Snapshot.seed())
        } else {
            let persistence = Persistence()
            persistence.importLegacyDataIfNeeded()
            store = AppStore(persistence: persistence)
        }
        ui = BoardUIState(store: store)
        super.init()
    }

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        let mainUI = BoardUIState(store: store)
        let windows = WindowCoordinator(store: store, notifier: notifier, mainUI: mainUI)
        self.windows = windows
        ui.openSettings = { [weak self] in self?.showSettings() }
        mainUI.openSettings = { [weak self] in self?.showSettings() }

        let panel = PanelController(store: store, ui: ui)
        panelController = panel

        let status = StatusItemController(store: store, menu: makeStatusMenu()) { [weak self] in
            self?.panelController?.toggle()
        }
        statusController = status
        panel.setAnchor(status.button)

        store.sweepArchive()
        store.startWatchingFile()
        startArchiveSchedule()
        observeSystemEvents()
        reconcileLaunchAtLogin()

        didFinishLaunching = true
        let queued = pendingURLs
        pendingURLs.removeAll()
        queued.forEach(handle)

        // Opened as an app (Finder, Spotlight, Launchpad, `open -a`): show the full window.
        // Launches caused by a onit:// URL (Raycast) or a login item stay silent.
        if Self.isDefaultLaunch(notification), queued.isEmpty {
            windows.showMainWindow()
        }

        if let issue = store.launchIssue {
            store.launchIssue = nil
            DispatchQueue.main.async { Self.showAlert(title: "OnIt recovered your data", message: issue) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush(synchronously: true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        store.flush()
        panelController?.appDidResignActive()
    }

    /// Opening OnIt again while it's running (Finder, Spotlight, Dock) brings up the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    /// AppKit sets `launchIsDefault` to false for launches that open a URL or document.
    /// Login-item launches are excluded too, so launch-at-login stays menu bar only.
    private static func isDefaultLaunch(_ notification: Notification) -> Bool {
        let isDefault = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? false
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let asLoginItem = launchEvent?.eventID == kAEOpenApplication
            && launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        return isDefault && !asLoginItem
    }

    // MARK: URL handling

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didFinishLaunching else {
            // A URL that launches the app can arrive before launch finishes: keep it.
            pendingURLs.append(contentsOf: urls)
            return
        }
        urls.forEach(handle)
    }

    private func handle(_ url: URL) {
        logger.info("Handling URL \(url.absoluteString, privacy: .private)")
        switch URLRouter.route(url) {
        case .add(let text):
            report(store.add(text: text))
        case .open(let alias):
            if let alias {
                if let id = ShorthandParser.resolveBoard(alias, in: store.aliasEntries) {
                    ui.selectBoard(id)
                } else {
                    notifier.post(title: "No board '@\(alias)'", body: "Showing your current board instead.")
                }
            }
            panelController?.show()
        case .toggle:
            panelController?.toggle()
        case .invalid(let reason):
            logger.error("Invalid URL: \(reason, privacy: .public)")
            notifier.post(title: "OnIt couldn't use that link", body: reason)
        }
    }

    /// Feedback for silent capture (spec §8.4).
    private func report(_ result: AddResult) {
        switch result {
        case .added(let task, let board):
            statusController?.pulse()
            if store.settings.notifyOnAdd {
                notifier.post(title: "Added to \(board.name)", body: Self.summary(task))
            }
        case .addedWithWarning(let task, _, let message):
            statusController?.pulse()
            // Always shown (even with notifications off) so a mis-typed board isn't missed.
            notifier.post(title: message, body: Self.summary(task))
        case .rejected(let reason):
            notifier.post(title: "Task not added", body: reason.message)
        }
    }

    private static func summary(_ task: TaskItem) -> String {
        [task.size?.label, task.title].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Menu

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open OnIt", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open in Window", action: #selector(openMainWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Archive…", action: #selector(openArchive), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OnIt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openPanel() { panelController?.show() }
    @objc private func openMainWindow() { showMainWindow() }

    func showMainWindow() {
        panelController?.close()
        windows?.showMainWindow()
    }
    @objc private func openArchive() {
        panelController?.close()
        windows?.showArchive()
    }
    @objc private func openSettingsFromMenu() { showSettings() }

    func showSettings() {
        panelController?.close()
        windows?.showSettings()
    }

    // MARK: Background work

    private func startArchiveSchedule() {
        let timer = Timer(timeInterval: 3_600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.store.sweepArchive() }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        hourlySweep = timer
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.store.sweepArchive() }
        }
    }

    private func reconcileLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        if store.settings.launchAtLogin != enabled {
            store.updateSettings { $0.launchAtLogin = enabled }
        }
    }

    static func showAlert(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
