import AppKit
import Carbon.HIToolbox

/// The popover's keyboard map (spec §8.3), handled in one place at the AppKit level so it
/// behaves the same regardless of which SwiftUI view has focus.
@MainActor
final class KeyboardRouter {
    private let ui: BoardUIState
    private weak var window: NSWindow?
    private let close: () -> Void
    private let closesOnEscape: Bool

    /// - Parameters:
    ///   - close: Closes the hosting surface (⌘W, and before opening Settings).
    ///   - closesOnEscape: Whether Esc with nothing left to cancel closes it (panel: yes, window: no).
    init(ui: BoardUIState, window: NSWindow, closesOnEscape: Bool, close: @escaping () -> Void) {
        self.ui = ui
        self.window = window
        self.closesOnEscape = closesOnEscape
        self.close = close
    }

    /// True while a text field (filter, add, inline edit) is being typed into.
    private var isTyping: Bool {
        window?.firstResponder is NSText
    }

    /// Returns true if the event was handled and should be swallowed.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let keyCode = Int(event.keyCode)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if keyCode == kVK_Escape {
            if !ui.handleEscape() {
                guard closesOnEscape else { return false }
                close()
            }
            return true
        }

        // Shortcuts that are safe even while typing.
        if flags == .command {
            if let digit = Int(chars), (1...9).contains(digit) {
                ui.selectBoard(atShortcutIndex: digit)
                return true
            }
            switch chars {
            case "n":
                ui.focusRequest = .field(.add)
                return true
            case "l":
                ui.toggleLater()
                return true
            case ",":
                if closesOnEscape { close() }
                ui.openSettings()
                return true
            case "w":
                close()
                return true
            default:
                break
            }
        }

        if isTyping { return false }

        switch (flags, keyCode) {
        case ([], kVK_UpArrow): ui.moveSelection(by: -1); return true
        case ([], kVK_DownArrow): ui.moveSelection(by: 1); return true
        case ([], kVK_LeftArrow): ui.moveSelectionToAdjacentColumn(-1); return true
        case ([], kVK_RightArrow): ui.moveSelectionToAdjacentColumn(1); return true
        case (.command, kVK_LeftArrow): ui.moveSelectedToAdjacentColumn(-1); return true
        case (.command, kVK_RightArrow): ui.moveSelectedToAdjacentColumn(1); return true
        case (.command, kVK_UpArrow): ui.reorderSelected(-1); return true
        case (.command, kVK_DownArrow): ui.reorderSelected(1); return true
        case ([], kVK_Return), ([], kVK_ANSI_KeypadEnter): ui.editSelected(); return true
        case ([], kVK_Delete), ([], kVK_ForwardDelete): ui.deleteSelected(); return true
        default: break
        }

        if flags == .option, let digit = Int(chars), (0...5).contains(digit) {
            ui.setSizeOnSelected(digit == 0 ? nil : TaskSize.allCases[digit - 1])
            return true
        }

        if flags == .command, chars == "z" { ui.undo(); return true }
        if flags == [.command, .shift], chars == "z" { ui.redo(); return true }

        if flags.isEmpty {
            switch chars {
            case "e": ui.editSelected(); return true
            case "/": ui.focusRequest = .field(.filter); return true
            default: break
            }
        }

        return false
    }
}
