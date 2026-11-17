import AppKit

/// The menu bar icon: a badge count, left-click to toggle the panel, right-click (or ⌥/⌃-click) for the menu.
@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let menu: NSMenu
    private let onToggle: () -> Void
    private var pulses = 0
    var button: NSStatusBarButton? { item.button }

    init(store: AppStore, menu: NSMenu, onToggle: @escaping () -> Void) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        (self.menu, self.onToggle) = (menu, onToggle)
        super.init()
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "OnIt")
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        observeContinuously {
            let mode = store.settings.badgeMode
            let count = mode == .off ? 0 : store.activeCount(in: mode == .doing ? .doing : .todo)
            button.title = count > 0 ? "\(count)" : ""
            button.imagePosition = count > 0 ? .imageLeading : .imageOnly
            button.setAccessibilityLabel(count > 0 ? "OnIt, \(count) \(mode == .doing ? "in progress" : "to do")" : "OnIt")
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.intersection([.option, .control]).isEmpty == false else {
            return onToggle()
        }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    /// A brief tint (and fade, unless Reduce Motion is on) after a silent add.
    func pulse() {
        guard let button = item.button else { return }
        pulses += 1
        let pulse = pulses
        button.contentTintColor = .controlAccentColor
        if !BoardUIState.reduceMotion {
            button.alphaValue = 0.35
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                button.animator().alphaValue = 1
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if pulses == pulse { button.contentTintColor = nil }
        }
    }
}
