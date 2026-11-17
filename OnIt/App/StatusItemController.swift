import AppKit

/// The menu bar icon: badge count, click handling and the add-feedback pulse.
@MainActor
final class StatusItemController: NSObject {
    private let store: AppStore
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let menu: NSMenu
    private var pulseGeneration = 0

    var button: NSStatusBarButton? { statusItem.button }

    init(store: AppStore, menu: NSMenu, onToggle: @escaping () -> Void) {
        self.store = store
        self.menu = menu
        self.onToggle = onToggle
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "OnIt")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "OnIt"
        }
        statusItem.autosaveName = "OnItStatusItem"

        observeContinuously { [weak self] in self?.updateBadge() }
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        let count: Int? = switch store.settings.badgeMode {
        case .doing: store.activeCount(in: .doing)
        case .todo: store.activeCount(in: .todo)
        case .off: nil
        }
        if let count, count > 0 {
            button.title = "\(count)"
            button.imagePosition = .imageLeading
            let label = store.settings.badgeMode == .doing ? "in progress" : "to do"
            button.setAccessibilityLabel("OnIt, \(count) \(label)")
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("OnIt")
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// ~600 ms tint pulse after a task is added via URL. With Reduce Motion, tint only.
    func pulse() {
        guard let button = statusItem.button else { return }
        pulseGeneration += 1
        let generation = pulseGeneration
        button.contentTintColor = .controlAccentColor

        if !BoardUIState.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                button.animator().alphaValue = 0.35
            } completionHandler: {
                MainActor.assumeIsolated {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        button.animator().alphaValue = 1
                    }
                }
            }
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.pulseGeneration == generation else { return }
            button.contentTintColor = nil
            button.alphaValue = 1
        }
    }
}
