# Implementation notes

OnIt was built from [`STACKBAN_SPEC.md`](../STACKBAN_SPEC.md), which uses the working name *Stackban*.
This file records where the implementation departs from the spec, and decisions the spec left open.

## Renamed from Stackban

The app is **OnIt** (`onit://`, bundle ID `com.example.onit`). On first launch, OnIt copies any data from
`~/Library/Application Support/Stackban/` into its own folder, renaming `stackban.*.json` to `onit.*.json`.
The old folder is left untouched.

## Deviations and decisions

1. **`NSStatusItem` + `NSPanel` instead of `MenuBarExtra`.** §5 allows this. `MenuBarExtra` can't be
   opened programmatically (`open`/`toggle`), resized, or given a right-click menu, and has no badge
   API. The panel is a non-activating, resizable `NSPanel` hosting SwiftUI (`RootView`). It closes on
   outside clicks or Esc, and remembers its size in `UserDefaults` (UI state, not user data).
2. **A full app window as well as the panel.** Opening OnIt as an app shows a large, resizable,
   full-screen-capable window with the same board. `onit://` and login-item launches stay silent.
3. **Settings and Archive are AppKit-hosted SwiftUI windows, not the `Settings` scene.**
   `openSettings` only works from views inside SwiftUI scenes, and the panel is AppKit-hosted. The
   activation-policy approach from gotcha 3 is kept: `.regular` while a window is open, back to
   `.accessory` when it closes. ⌘, is redirected to the same window.
4. **Unknown-board warnings always notify**, even with "Notify when a task is added" off. Otherwise
   a mistyped `@board` from Raycast would only show as an icon pulse. Failures always notify, as specified.
5. **§9.6 doesn't exist** (it's referenced for board-deletion undo). Board deletion is on the normal
   ⌘Z stack, and Settings shows an **Undo** banner for 10 seconds after a delete.
6. **Undo is stored as before/after states** of boards and tasks (capped at 50), not hand-written
   inverse operations. It's simpler and can't drift out of sync. Settings, and board
   rename/colour/alias edits, aren't undoable, because per-keystroke renames would flood the stack.
   History is cleared when an external file change is loaded.
7. **Ordering is per column across all boards.** This is a superset of "within (board, column)", so the
   All view and single-board views always agree on order.
8. **Aliases also may not collide with another board's name slug**, because `@name` resolves too.
   Aliases are checked before names.
9. **Editing an existing title** pre-fills it with escapes (`\@acme`) for any word that would otherwise
   be re-parsed as a token, so committing an unchanged title is lossless. An edit that's only tokens
   (`!l`) keeps the title and applies the tokens. `@board` in an edit moves the card.
10. **Filters:** text terms must all match (title or tags; `#term` matches tags only). Selected tags and
    sizes match *any* (OR). The size filter includes "unsized".
11. **Starting boards are Home (`@home`, `@h`) and Work (`@work`, `@w`)**, not the spec's Internal and
    Client. Work is the default board. Each starts with one plain example task instead of the spec's
    Raycast welcome card.
12. **Acceptance criterion 1 uses `@acme`**, which isn't a starting board. Add an Acme board
    (or an `acme` alias) first, or try `@home`.
13. **Later is the leftmost column**, before Todo, rather than after Done as in §8.2. It's the backlog
    that work is picked up from, so the board reads Later → Todo → In Progress → Done, and ⌘← on a
    Todo card defers it to Later. It still collapses to a slim strip by default and accepts drops.
14. **Tests run hosted in the app.** `AppDelegate` detects the XCTest environment and uses an in-memory
    store, so tests never touch your real data file or menu bar.
