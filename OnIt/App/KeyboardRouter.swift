import AppKit
import Carbon.HIToolbox

/// The board's keyboard shortcuts for one window, handled at the AppKit level so they work
/// whichever SwiftUI view has focus.
@MainActor
final class KeyboardRouter {
    private let ui: BoardUIState
    private weak var window: NSWindow?
    private let closesOnEscape: Bool
    private let close: () -> Void

    init(ui: BoardUIState, window: NSWindow, closesOnEscape: Bool, close: @escaping () -> Void) {
        (self.ui, self.window, self.closesOnEscape, self.close) = (ui, window, closesOnEscape, close)
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self.map { event.window === $0.window && $0.handle(event) } ?? false }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = Int(event.keyCode), chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if key == kVK_Escape {
            if ui.handleEscape() { return true }
            if closesOnEscape { close() }
            return closesOnEscape
        }
        // These work even while typing.
        let commands: [String: @MainActor () -> Void] = [
            "n": { self.ui.focusRequest = .field(.add) }, "l": { self.ui.toggleLater() }, "w": { self.close() },
            ",": { if self.closesOnEscape { self.close() }; self.ui.openSettings() },
        ]
        if flags == .command, let digit = Int(chars), digit > 0 { ui.selectBoard(atShortcutIndex: digit); return true }
        if flags == .command, let command = commands[chars] { command(); return true }
        guard !(window?.firstResponder is NSText) else { return false }

        let arrows = [kVK_UpArrow: -1, kVK_DownArrow: 1, kVK_LeftArrow: -1, kVK_RightArrow: 1]
        if let delta = arrows[key], flags.isEmpty || flags == .command {
            switch (flags == .command, key == kVK_UpArrow || key == kVK_DownArrow) {
            case (false, true): ui.moveSelection(by: delta)
            case (false, false): ui.moveSelectionToAdjacentColumn(delta)
            case (true, true): ui.reorderSelected(delta)
            case (true, false): ui.moveSelectedToAdjacentColumn(delta)
            }
            return true
        }
        if flags == .option, let digit = Int(chars), digit <= 5 {
            ui.setSizeOnSelected(digit == 0 ? nil : TaskSize.allCases[digit - 1])
            return true
        }
        if chars == "z", flags == .command || flags == [.command, .shift] {
            flags.contains(.shift) ? ui.redo() : ui.undo()
            return true
        }
        guard flags.isEmpty else { return false }
        switch (key, chars) {
        case (kVK_Return, _), (kVK_ANSI_KeypadEnter, _), (_, "e"): ui.editSelected()
        case (kVK_Delete, _), (kVK_ForwardDelete, _): ui.deleteSelected()
        case (_, "/"): ui.focusRequest = .field(.filter)
        default: return false
        }
        return true
    }
}
