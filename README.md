# OnIt

A native macOS menu bar kanban board for the stream of small asks that land on you every day.
Capture a task from anywhere with one Raycast shortcut and a line of shorthand; drag it through
Todo → In Progress → Done (or park it in Later). See [`STACKBAN_SPEC.md`](STACKBAN_SPEC.md) for the full brief.

> **Renamed from Stackban.** The spec uses the working name *Stackban*. The app is now **OnIt**
> (`onit://`, `com.example.onit`). On first launch, OnIt copies any data from
> `~/Library/Application Support/Stackban/` into its own folder, renaming `stackban.*.json` to
> `onit.*.json`. The old folder is left untouched, so delete it by hand once you're happy.

## Build and run

Requires macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -scheme OnIt -destination 'platform=macOS' build
xcodebuild -scheme OnIt -destination 'platform=macOS' test
```

Or open `OnIt.xcodeproj` after `xcodegen generate` and press ⌘R. The `.xcodeproj` is generated
and git-ignored; edit `project.yml` instead.

The app is ad-hoc signed ("Sign to Run Locally") and unsandboxed. There are two ways to see the board:

- **Menu bar panel.** Click the tick-in-a-circle icon in the menu bar for a drop-down panel. Right-click
  (or ⌥-click) shows *Open OnIt · Open in Window · Archive… · Settings… · Quit*.
- **Full window.** Opening OnIt as an app (Finder, Spotlight, Launchpad, or opening it again while
  it's running) shows a large, centred, resizable window that supports full screen (⌃⌘F or the
  green button). While it's open, OnIt has a Dock icon and app menu. Closing it returns OnIt
  to menu bar only. Its size and position are remembered. Launches from a `onit://` link (Raycast)
  or at login stay silent and don't open it.

The bundle ID is the placeholder `com.example.onit` (in `project.yml`).

## Shorthand

```
Draft Acme proposal @acme !L #sales
```

| Token | Meaning |
|---|---|
| `@alias` | Board, by alias or by name with spaces as `-` (`@acme-co`). Case-insensitive; last valid one wins. Unknown boards stay in the title, the task goes to the default board, and you're told. |
| `!size` | `xs` `s` `m` `l` `xl`, case-insensitive; last valid one wins. |
| `#tag` | `[A-Za-z0-9_-]+`, stored lowercase, de-duplicated. |
| `\@` `\!` `\#` | Keep the sigil literally. |

Sigils only count at the start of a word, so `me@acme.com` is plain text. Unrecognised tokens
(`!urgent`, `@nobody`, a bare `#`) stay in the title. Titles are capped at 280 characters.
The same shorthand works in the in-app "+ Add task…" field and when editing a card's title.

## URL scheme

| URL | Action |
|---|---|
| `onit://add?text=<percent-encoded line>` | Parse and add the task, without opening the board. |
| `onit://open` | Show the board. |
| `onit://open?board=<alias>` | Show the board with that board selected. |
| `onit://toggle` | Show or hide the board. |

`+` in the query is a literal plus, not a space. Invalid links post a notification instead of
failing silently.

```sh
open -g "onit://add?text=Draft%20proposal%20%40c%20%21L%20%23sales"
```

## Raycast setup

1. In OnIt: **Settings → Data → Open Raycast Script Folder** (or use `raycast/` in this repo).
2. Copy `add-onit-task.sh` and `open-onit.sh` into a folder Raycast watches for script
   commands (Raycast → Extensions → Script Commands → Add Directories). Make sure they're
   executable: `chmod +x *.sh`.
3. Assign hotkeys in Raycast: e.g. ⌥⌘Space for *Add OnIt Task* and ⌥⌘K for *Toggle OnIt*.

Both scripts use `open -g`, so capture never steals focus. If OnIt isn't running, the add
command launches it silently and the task is still added.

## Data

Everything lives in one human-readable file:

```
~/Library/Application Support/OnIt/onit.json
```

- Writes are atomic (temp file + rename), debounced ~300 ms, and flushed on quit.
- `onit.backup-1…3.json` are rotated once per launch.
- A file that fails to decode is never overwritten: it's moved to `onit.corrupt-<timestamp>.json`
  and the newest valid backup is loaded, with a one-time alert.
- Hand edits (or a sync tool) are picked up live; the app ignores its own writes.
- **Import** saves `onit.pre-import-<timestamp>.json` before replacing anything.

## Keyboard (board focused)

| Keys | Action |
|---|---|
| ↑ / ↓ | Select previous / next card |
| ← / → | Select card in adjacent column |
| ⌘← / ⌘→ | Move card to previous / next column |
| ⌘↑ / ⌘↓ | Reorder card |
| ⌥1…⌥5, ⌥0 | Set size XS…XL, clear size |
| Return or E | Edit title |
| ⌫ | Delete (undoable) |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘N | Focus "Add task…" |
| ⌘L | Expand / collapse Later |
| / | Focus filter |
| ⌘1…⌘9 | Switch board (1 = All) |
| Esc | Clear filter → cancel edit → leave text field → close (panel only) |
| ⌘W | Close the panel or window |

## Project layout

```
project.yml            XcodeGen spec
raycast/               Raycast script commands (also bundled into the app's Resources)
OnIt/App/          App entry, AppDelegate (URL handling), status item, panel, keyboard, windows
OnIt/Model/        Board, TaskItem, TaskSize, Column, AppSettings, Snapshot
OnIt/Parsing/      ShorthandParser (pure)
OnIt/Store/        AppStore, Persistence, Undo, ArchiveSweeper, Migrations, TaskFilter
OnIt/Capture/      URLRouter (pure)
OnIt/Views/        Popover, Archive and Settings SwiftUI views
OnIt/Support/      SizeStyle, colours, formatting, notifications
OnItTests/         Swift Testing suites
```

## Notes, deviations and ambiguities

The spec asked for these to be flagged rather than silently decided:

1. **`NSStatusItem` + `NSPanel` instead of `MenuBarExtra`.** §5 allows this. `MenuBarExtra` can't be
   opened programmatically (`open`/`toggle`), resized, or given a right-click menu, and has no badge
   API. The popover is a non-activating, resizable `NSPanel` hosting SwiftUI (`RootView`); it closes on
   outside clicks or Esc, and remembers its size in `UserDefaults` (UI state, not user data).
2. **Settings and Archive are AppKit-hosted SwiftUI windows, not the `Settings` scene.**
   `openSettings` only works from views inside SwiftUI scenes, and the popover is AppKit-hosted. The
   activation-policy approach from gotcha 3 is kept: `.regular` while a window is open, back to
   `.accessory` when it closes. ⌘, is redirected to the same window.
3. **Unknown-board warnings always notify**, even with "Notify when a task is added" off. Otherwise
   a mistyped `@board` from Raycast would only show as an icon pulse. Failures always notify, as specified.
4. **§9.6 doesn't exist** (it's referenced for board-deletion undo). Board deletion is on the normal
   ⌘Z stack, and Settings shows an **Undo** banner for 10 seconds after a delete.
5. **Undo is stored as before/after states** of boards and tasks (capped at 50), not hand-written
   inverse operations. It's simpler and can't drift out of sync. Settings, and board
   rename/colour/alias edits, aren't undoable, because per-keystroke renames would flood the stack.
   History is cleared when an external file change is loaded.
6. **Ordering is per column across all boards.** This is a superset of "within (board, column)", so the
   All view and single-board views always agree on order.
7. **Aliases also may not collide with another board's name slug**, because `@name` resolves too.
   Aliases are checked before names.
8. **Editing an existing title** pre-fills it with escapes (`\@acme`) for any word that would otherwise
   be re-parsed as a token, so committing an unchanged title is lossless. An edit that's only tokens
   (`!l`) keeps the title and applies the tokens. `@board` in an edit moves the card.
9. **Filters:** text terms must all match (title or tags; `#term` matches tags only). Selected tags and
   sizes match *any* (OR). The size filter includes "unsized".
10. **Starting boards are Home (`@home`, `@h`) and Work (`@work`, `@w`)**, not the spec's Internal and Client.
    Work is the default board. The welcome card reads "Press your Raycast hotkey and try: Pick up dry cleaning @home !s #errands".
11. **Acceptance criterion 1 uses `@acme`**, which isn't a starting board. Add an Acme board
    (or an `acme` alias) first, or try `@home`.
12. **Tests run hosted in the app.** `AppDelegate` detects the XCTest environment and uses an in-memory
    store, so tests never touch your real data file or menu bar.

## Verification status

Verified automatically (85 tests) and by hand on the built app: the parser table and edge cases,
store operations, ordering and renormalisation, undo/redo, board invariants, archive sweep with an
injected clock, persistence round-trip, backup rotation, corruption recovery, file watching, and
URL routing. Also verified on the built app: cold launch via the Raycast script adds the task
without a Dock icon, warm adds, unknown-board and empty-title handling, UTF-8, `+` and `%`
round-trips, and live pickup of hand edits. The board UI was rendered offscreen in light and dark
mode to check layout.

**Not yet exercised interactively** (needs a person at the keyboard): drag and drop, the keyboard
map and popover focus behaviour, the right-click menu, the Settings and Archive windows,
notification banners, and launch at login.
