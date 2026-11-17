# Stackban: Product & Technical Spec

> A native macOS menu bar kanban board for the stream of small asks that land on you every day. Capture a task from anywhere with one Raycast shortcut and a line of shorthand. It shows up on the right board, sized and colour-coded, and you can drag it through Todo → In Progress → Done (or park it in Later).

This document is the full brief for building v1 with Claude Code. Build exactly what is specified, flag any ambiguity as a short note in the PR or README rather than silently deviating, and treat everything in **§14 Out of scope** as off-limits for v1.

---

## 1. Goals and principles

1. **Capture in under 3 seconds.** Raycast hotkey → type one line → done. The board never needs to be opened to add a task.
2. **Glanceable load.** Task size is visible through colour (and a small chip), and each column shows its total load, so you can tell at a glance whether you are overcommitted.
3. **Multiple boards, user-configurable.** For example "Internal" and one board per client, each with its own aliases and colour. Nothing about boards is hard-coded.
4. **Local-first, boringly reliable.** All data lives in one human-readable JSON file. No account, no network, no telemetry.
5. **Feels native.** SwiftUI, system fonts and materials, light/dark mode, keyboard-first, accessible.

---

## 2. Platform and technical choices

| Item | Decision |
|---|---|
| Language | Swift 6 (strict concurrency on) |
| UI | SwiftUI, with AppKit interop only where needed (see gotchas) |
| Minimum macOS | 14.0 (Sonoma): needed for `@Observable`, `openSettings`, and modern `MenuBarExtra` behaviour |
| App type | Menu bar–only agent: `LSUIElement = YES` (no Dock icon, no app switcher entry) |
| Menu bar | `MenuBarExtra` with `.menuBarExtraStyle(.window)` |
| State | One `@MainActor @Observable` `AppStore` that owns all data and is created at app launch, **not** inside any view |
| Persistence | Single JSON file (see §6). `Codable`, atomic writes |
| Sandbox | **App Sandbox OFF** (personal tool; keeps the data path real and inspectable). Hardened runtime not required. Sign to run locally |
| Dependencies | None. No third-party packages in v1 |
| Project generation | Use **XcodeGen** (`project.yml`) so the project can be regenerated and built from the CLI. Commit `project.yml`; git-ignore the generated `.xcodeproj` |
| Tests | Swift Testing (`import Testing`) for the parser, store logic and persistence |
| Bundle ID | `com.example.stackban` (placeholder; I will change it) |
| Display name | Stackban |

### Critical implementation gotchas (read before coding)

1. **URL handling must not live in a SwiftUI view.** `MenuBarExtra` window content is created lazily, so `.onOpenURL` on it will not fire while the popover is closed, which is the main use case. Use `@NSApplicationDelegateAdaptor` with an `NSApplicationDelegate` that implements `application(_ application: NSApplication, open urls: [URL])`, and forward to the shared `AppStore`. Also register the handler early enough that a URL which *launches* the app is not lost.
2. **The store must exist before any view.** Create the `AppStore` in the `App` struct / delegate and inject it with `.environment(store)`. Never rely on view `.onAppear` for loading data or archive sweeps.
3. **Settings from an `LSUIElement` app.** Use the `Settings` scene and `@Environment(\.openSettings)`. Before opening it, call `NSApp.activate()` (and temporarily set `NSApp.setActivationPolicy(.regular)` if the window won't come to the front, reverting to `.accessory` when it closes).
4. **Popover focus.** The window-style popover must be able to become key so that the search field and keyboard shortcuts work. Verify arrow keys, typing and Esc behave.
5. **Fire-and-forget capture.** The Raycast script uses `open -g` so adding a task never steals focus.

---

## 3. Core concepts

- **Board:** a named, coloured container of tasks, with one or more *aliases* used in shorthand (`@acme`). Exactly one board is the **default board**, which receives tasks with no `@board` token.
- **Task:** a title, a board, a size, a column, and optional tags.
- **Column:** fixed in v1: `todo`, `doing` ("In Progress"), `done`, `later`. The same four columns apply to every board.
- **Size:** `XS`, `S`, `M`, `L`, `XL`, or none. Each size maps to a colour and to load points (§7).
- **Tag:** a lowercase label on a task (`#urgent`, `#invoice`), filterable.

### Seed data on first launch
- Boards: **Internal** (alias `int`, `i`; default board) and **Client** (alias `client`, `c`). Both are renamable and deletable.
- No tasks, except one welcome card in Todo on the default board: "Press your Raycast hotkey and try: `Draft proposal @c !L #sales`".

---

## 4. Shorthand notation (the parser)

Input is a single line of text from Raycast (or the in-app add field). The parser is a **pure function** with no UI or store dependencies, and it must be exhaustively unit-tested.

### Grammar

A **token** is a whitespace-delimited word that begins with a sigil. A sigil only counts if it is at the start of the string or preceded by whitespace (so `me@acme.com` is plain text).

| Token | Meaning | Rules |
|---|---|---|
| `@alias` | Board | Matches against board names and aliases, case-insensitive. Last valid one wins if several are given. |
| `!size` | Size | One of `xs s m l xl`, case-insensitive. Last valid one wins. |
| `#tag` | Tag | `[A-Za-z0-9_-]+`, stored lowercase, de-duplicated, order preserved. Multiple allowed. |

- Recognised tokens are **removed** from the title. Whitespace is then collapsed and trimmed.
- **Unrecognised sigil tokens stay in the title verbatim** (for example `!urgent`, `@nobody`, `#`, `!`). Nothing the user typed is silently lost.
- If `@alias` is unknown, the task goes to the default board and the title keeps the `@alias` text. The add confirmation (§9.4) reports "No board '@alias'" so the user notices.
- **Escape:** a backslash before a sigil keeps it literal: `\@acme` stays `@acme` in the title, with the backslash removed.
- If the resulting title is empty, the task is rejected (nothing is added), and the failure is reported (§9.4).
- Titles are capped at 280 characters (truncate with no ellipsis).
- If no `!size` is given, use the global default size from Settings (default: **none**, shown as a neutral grey).

### Result type

```swift
struct ParsedTask: Equatable {
    var title: String
    var boardAlias: String?     // raw alias as typed, nil if absent
    var size: TaskSize?         // nil if absent
    var tags: [String]
    var unknownBoardAlias: String?  // set when @alias was given but didn't resolve (resolution happens in the store, so the parser takes a closure or the store sets this)
}
```

The parser takes the list of valid board aliases as input so it can tell known from unknown, for example `parse(_ input: String, knownBoards: [BoardAliasEntry]) -> ParsedTask`.

### Required test cases (minimum)

| Input | Title | Board | Size | Tags |
|---|---|---|---|---|
| `Draft Acme proposal @acme !L` | Draft Acme proposal | acme | L | – |
| `!s fix invoice bug @int #billing #urgent` | fix invoice bug | int | S | billing, urgent |
| `Email me@acme.com about thing` | Email me@acme.com about thing | – | – | – |
| `Call Sam \@acme about lunch` | Call Sam @acme about lunch | – | – | – |
| `Ship it !XL !m` | Ship it | – | M | – |
| `Review PR @nobody` (no such board) | Review PR @nobody | default + unknown flagged | – | – |
| `Tidy desk #Home #home` | Tidy desk | – | – | home |
| `   !s   ` | rejected (empty title) | | | |
| `Plan Q1 !huge` | Plan Q1 !huge | – | – | – |
| `Café ☕ run @int` | Café ☕ run | int | – | – |

---

## 5. Capture flow (URL scheme + Raycast)

### URL scheme: `stackban://`

Register under `CFBundleURLTypes` with scheme `stackban`.

| URL | Action |
|---|---|
| `stackban://add?text=<percent-encoded line>` | Parse the shorthand and add the task. **Does not open the popover.** |
| `stackban://open` | Show the popover (and bring it to front). |
| `stackban://toggle` | Toggle the popover open/closed. |
| `stackban://open?board=<alias>` | Show the popover with that board selected. |

- Handle invalid or missing parameters gracefully (log, show failure feedback, never crash).
- Percent-decoding must correctly handle UTF-8, `+` (treat as a literal plus, not a space), and very long input (apply the title cap).
- Programmatically opening the `MenuBarExtra` window is not officially supported. Implement `open`/`toggle` by locating the status item's button (via `NSStatusBar` / the `NSStatusBarButton` of the app's status item window) and performing a click, **or** by adopting an `NSStatusItem` + `NSPopover` implementation if the SwiftUI route proves unreliable. Prefer whichever is robust. If `NSStatusItem` + `NSPopover` + `NSHostingController` is the only robust option, use it. The UI is still SwiftUI.

### Raycast script command (ship in `/raycast/add-stackban-task.sh`)

```bash
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add Stackban Task
# @raycast.mode silent
# @raycast.packageName Stackban
# @raycast.icon 📌

# Optional parameters:
# @raycast.argument1 { "type": "text", "placeholder": "Task @board !size #tag" }

encoded=$(printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9_.~-])/sprintf("%%%02X", ord($1))/ge')
open -g "stackban://add?text=${encoded}"
```

A second tiny script `open-stackban.sh` should run `open -g "stackban://toggle"`. In Raycast, the user assigns hotkeys or aliases to both.

---

## 6. Data model and persistence

### File
`~/Library/Application Support/Stackban/stackban.json`

- Written **atomically** (write to temp file in same directory, then rename).
- Writes are debounced (about 300 ms) and also flushed on app termination and when the app resigns active.
- Keep the **3 most recent backups** as `stackban.backup-1.json … -3.json`, rotated at most once per app launch.
- On launch: if the file is missing, create it with seed data. If it fails to decode, **do not overwrite it**: move it to `stackban.corrupt-<timestamp>.json`, load the newest valid backup, and show a one-time alert explaining what happened.
- Watch the file for external changes (`DispatchSource` file-system object or similar) and reload when modified by something other than the app, so hand-edits or a synced folder work. Ignore changes caused by our own writes.
- Include `schemaVersion: 1` and write the migration scaffolding (a `migrate(from:)` switch), even though only v1 exists.

### Schema

```jsonc
{
  "schemaVersion": 1,
  "boards": [
    {
      "id": "UUID",
      "name": "Acme Co",
      "aliases": ["acme", "a"],        // lowercase, unique across ALL boards, [a-z0-9_-]+
      "colorHex": "#5B8DEF",
      "isDefault": false,
      "sortOrder": 1
    }
  ],
  "tasks": [
    {
      "id": "UUID",
      "boardId": "UUID",
      "title": "Draft Acme proposal",
      "size": "l",                     // "xs"|"s"|"m"|"l"|"xl"|null
      "column": "todo",                // "todo"|"doing"|"done"|"later"
      "tags": ["sales"],
      "order": 1024.0,                 // fractional index within (board, column)
      "createdAt": "ISO8601",
      "updatedAt": "ISO8601",
      "startedAt": null,               // set when first moved to doing
      "completedAt": null,             // set on entering done; cleared if moved out
      "archivedAt": null               // set by the auto-archive sweep
    }
  ],
  "settings": {
    "defaultSize": null,
    "archiveAfterDays": 7,
    "badgeMode": "doing",              // "doing"|"todo"|"off"
    "notifyOnAdd": false,
    "launchAtLogin": false,
    "laterExpanded": false,
    "lastSelectedBoardId": null        // null = All boards
  }
}
```

### Rules
- Invariant: exactly one board has `isDefault = true`. Deleting the default board is not allowed until another is made default.
- Aliases are unique across boards (case-insensitive). A board's name is also matched in shorthand (spaces replaced by `-`, e.g. `@acme-co`).
- **Ordering:** use fractional `order` values. Moving a card between neighbours sets its order to the midpoint. Renormalise a column if gaps drop below an epsilon. New tasks go to the **bottom** of their column.
- **Deleting a board** that has tasks prompts: *move tasks to another board* (choose which) or *delete the tasks too*. This is undoable for a short time (see §9.6).
- Moving a task to `doing` for the first time sets `startedAt`. Moving to `done` sets `completedAt`. Moving out of `done` clears `completedAt` and `archivedAt`.
- **Auto-archive sweep:** tasks in `done` with `completedAt` older than `archiveAfterDays` get `archivedAt = now` and disappear from the board. Run on launch, on wake from sleep, and hourly. Archived tasks are not deleted.

---

## 7. Size → colour → load

| Size | Meaning (guide) | Colour (hex) | Load points |
|---|---|---|---|
| XS | A few minutes | `#34C3A0` teal-green | 1 |
| S | Under an hour | `#8BC34A` lime | 2 |
| M | Half a day | `#F2C14E` amber | 3 |
| L | Most of a day | `#F28C38` orange | 5 |
| XL | Multi-day | `#E5484D` red | 8 |
| none | unsized | system grey (`.secondary`) | 0 |

- Colours must meet reasonable contrast for the chip text in both light and dark mode (use dark text on lime/amber, white on the others, or tune accordingly). **Never rely on colour alone**: every card also shows its size as a text chip (`XS`…`XL`).
- Each column header shows: **name · card count · total load points** (for example `In Progress · 4 · 11 pts`). When the column's load exceeds a soft threshold (configurable constant, default 13 pts for `doing`), tint the points figure orange/red as a gentle warning. This is cosmetic only, with no blocking.
- Colour and point values live in a single `SizeStyle` definition so they are easy to change.

---

## 8. Information architecture and UI

### 8.1 Menu bar item
- SF Symbol icon: `square.stack.3d.up` (template image, adapts to the menu bar).
- Optional **badge count** to the right of the icon, controlled by `badgeMode`: number of tasks In Progress (default), number in Todo, or off.
- **Left-click** toggles the popover. **Right-click (or ⌥-click)** shows a small menu: *Open Stackban · Archive… · Settings… · Quit*.
- Brief feedback pulse (about 600 ms icon animation or tint change) when a task is added via URL. See §9.4.

### 8.2 Popover (main window)

Default size about **820 × 540 pt** with Later collapsed. It is resizable within sensible min/max limits and the size is remembered. Material background (`.regularMaterial`), rounded corners from the system.

```
┌──────────────────────────────────────────────────────────────────────┐
│ [All] [Internal] [Acme] [Globex]      🔍 filter…    [size ▾] [#tag ▾]│  ← top bar
├───────────────┬───────────────┬───────────────┬──────────────────────┤
│ Todo  5 · 9pt │ In Progress   │ Done  3 · 6pt │ ⟩ Later (2)          │
│               │ 2 · 8 pts     │               │ (collapsed strip)    │
│ ┃▌ Draft…  L  │ ┃▌ Fix inv… S │ ┃▌ Send inv…  │                      │
│ ┃▌ Call…  XS  │ ┃▌ Review… M  │               │                      │
│ + Add task…   │               │               │                      │
└───────────────┴───────────────┴───────────────┴──────────────────────┘
```

**Top bar**
- **Board switcher:** pill tabs: *All* plus one per board (board colour dot + name), in `sortOrder`. Selection persists (`lastSelectedBoardId`). `⌘1…⌘9` jump to All / board N.
- **Filter field:** free text over title and tags. `/` focuses it, Esc clears it.
- **Size filter** (multi-select popover) and **Tag filter** (multi-select of existing tags). Active filters show a clear (×) affordance.

**Columns**
- Four columns: Todo, In Progress, Done, Later. In v1 the widths are equal. **Later is collapsed by default** into a slim vertical strip (about 36 pt) showing a chevron, the label rotated 90°, and the card count. Clicking the strip (or pressing `⌘L`) expands it as a fourth full column, and the popover animates wider to fit. The expanded/collapsed state persists (`laterExpanded`). A collapsed strip is still a **drop target**: dragging a card onto it moves the card to Later.
- Each column header: name · count · load points (§7).
- Todo has an inline **"+ Add task…"** row at the bottom that uses the same parser (so `@board !size #tag` work there too). In a specific board view, it defaults to that board. In All view, it uses the default board unless `@` is given.

**Card**
- Left edge **size stripe** (4 pt, size colour). Title (up to 2 lines, then truncated). Row below: **size chip**, **tag pills** (max 2 visible plus "+N"), and in *All* view a small **board dot + short name**. In-progress cards show elapsed time since `startedAt` ("2d"). Done cards show the completion time ("yesterday").
- Hover reveals a small "…" button, with the same options as the context menu.
- **Context menu:** Edit title · Set size ▸ (XS…XL, none) · Move to ▸ (columns) · Change board ▸ · Edit tags · Delete.
- **Editing:** double-click or `Return` edits the title inline. The edit field accepts the same shorthand (so typing `!l` changes the size and `#x` adds a tag when committed). `Esc` cancels.
- Selected card has a clear focus ring.

### 8.3 Interactions

**Drag and drop**
- Drag a card between columns and to reorder within a column, using `Transferable` / `draggable` + `dropDestination` with a visible insertion indicator.
- Dropping on the collapsed Later strip moves the card to Later.
- Moving between columns is animated (spring, short).

**Keyboard** (popover focused; make this discoverable via a "Keyboard shortcuts" item in Settings → General)

| Keys | Action |
|---|---|
| `↑` / `↓` | Select previous / next card in column |
| `←` / `→` | Move selection to adjacent column |
| `⌘←` / `⌘→` | Move selected card to the previous / next column |
| `⌘↑` / `⌘↓` | Reorder selected card within column |
| `⌥1`…`⌥5` | Set size XS…XL on selected card (`⌥0` clears) |
| `Return` or `E` | Edit title |
| `⌫` | Delete selected card (undoable) |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `⌘N` | Focus the "Add task…" field |
| `⌘L` | Expand/collapse Later |
| `/` | Focus filter |
| `⌘1`…`⌘9` | Switch board (1 = All) |
| `Esc` | Clear filter / cancel edit / close popover (in that priority order) |

### 8.4 Add confirmation (for `stackban://add`)
Because capture is silent, give clear feedback:
- **Always:** pulse the menu bar icon, and update the badge if applicable.
- **If `notifyOnAdd` is on:** post a local `UserNotification` such as "Added to Acme · L · Draft Acme proposal", or "No board '@acmee'. Added to Internal".
- **On failure** (empty title, malformed URL): always show a notification (requesting permission lazily the first time it is needed) so a dropped task is never silent.

### 8.5 Archive view
Menu item *Archive…* opens a separate small window: a searchable list of archived tasks (title, board, size, completed date). Actions: *Restore to Todo*, *Delete permanently*. Grouped by completion week.

### 8.6 Settings window (`Settings` scene, tabbed)

**Boards**
- List of boards (drag to reorder). Add / delete.
- Per board: name, colour (preset palette of 8 plus custom `ColorPicker`), aliases (token-style editor), and a "Default board" radio.
- Validation messages for duplicate or invalid aliases.

**General**
- Default size for unsized tasks (None / XS…XL).
- Auto-archive Done after N days (1–60, default 7).
- Menu bar badge: In Progress / Todo / Off.
- Notify when a task is added (toggle; requests notification permission).
- Launch at login (via `SMAppService.mainApp`).
- A read-only list of keyboard shortcuts and the URL scheme with copy-able examples.

**Data**
- Show data file in Finder. Export JSON. Import JSON (with confirmation and an automatic backup first).
- "Open Raycast script folder" helper that reveals the bundled `/raycast` scripts (copy these into the app bundle's Resources).

---

## 9. Store behaviour (summary of required operations)

`AppStore` exposes (names indicative):
- `add(parsed:)`, `add(text:)` → returns an `AddResult` (`.added(task, board)`, `.addedWithWarning(task, board, message)`, `.rejected(reason)`)
- `move(task, to column, before/after neighbour)`, `reorder`, `setSize`, `setBoard`, `editTitle(with shorthand)`, `setTags`, `delete`
- Board CRUD with the invariants from §6.
- `undo()` / `redo()` backed by a stack of inverse operations (cap 50), covering add, edit, move, size/board changes, delete, and board deletion. Undo history is in-memory only.
- Derived data for the UI: filtered/sorted tasks per column, load points per column, tag index.
- `sweepArchive(now:)`: pure and testable by injecting the clock.

All mutations go through the store, which schedules the debounced save. Views never write to disk.

---

## 10. Visual design direction

- Native and quiet. Use system fonts (SF Pro; `.rounded` design for column headers only if it looks right), system materials, `Color.accentColor` for selection.
- Cards: subtle fill (`.quaternary`-style), 8 pt corner radius, 4 pt size stripe on the leading edge, 10–12 pt padding. Compact density, because this is a utility you glance at.
- Board colours appear only as small dots and the active board pill, never as card backgrounds. Size colour owns the card.
- Full **light and dark mode**, **Dynamic Type–friendly** sizing where practical, VoiceOver labels on cards ("Draft Acme proposal, size L, Acme board, in Todo") and on the drag handles/actions, and respect **Reduce Motion**.
- App icon: a simple stacked-cards glyph. Produce a placeholder asset catalog icon; a final one will be supplied later.

---

## 11. Project structure

```
Stackban/
├─ project.yml                  # XcodeGen
├─ README.md                    # build/run, URL scheme docs, Raycast setup
├─ raycast/
│  ├─ add-stackban-task.sh
│  └─ open-stackban.sh
├─ Stackban/
│  ├─ App/                      # StackbanApp.swift, AppDelegate (URL handling)
│  ├─ Model/                    # Board, Task, TaskSize, Column, Settings, Snapshot (Codable)
│  ├─ Parsing/                  # ShorthandParser.swift
│  ├─ Store/                    # AppStore, Persistence, Undo, ArchiveSweeper, Migrations
│  ├─ Capture/                  # URLRouter (parses stackban:// URLs into actions)
│  ├─ Views/
│  │  ├─ Popover/               # RootView, TopBar, BoardTabs, ColumnView, CardView, LaterStrip
│  │  ├─ Archive/
│  │  └─ Settings/
│  ├─ Support/                  # SizeStyle, Colors, Formatting, Notifications
│  └─ Resources/                # Assets.xcassets, Info.plist additions, raycast scripts
└─ StackbanTests/               # ParserTests, StoreTests, PersistenceTests, URLRouterTests, ArchiveTests
```

Build and test should work from the command line:
```
xcodegen generate
xcodebuild -scheme Stackban -destination 'platform=macOS' build
xcodebuild -scheme Stackban -destination 'platform=macOS' test
```

---

## 12. Milestones (build in this order, and commit at each)

1. **Skeleton:** XcodeGen project, `LSUIElement`, `MenuBarExtra` with an empty popover, `AppStore` created at launch, README stub.
2. **Model + persistence:** schema, seed data, atomic JSON load/save, backups, corruption recovery, file watching. Tests.
3. **Parser:** `ShorthandParser` with the full test table from §4.
4. **URL scheme:** app-delegate URL handling, `URLRouter`, `add` end to end (including launching the app cold from a URL), feedback pulse/notification. Test the Raycast script.
5. **Board UI:** top bar, board tabs, four columns, cards with size stripe/chip/tags, column load totals, collapsed Later strip.
6. **Interactions:** drag and drop, keyboard map, inline edit with shorthand, context menu, undo/redo.
7. **Settings:** boards CRUD with validation, general options, launch at login, data tools.
8. **Archive:** sweep + Archive window.
9. **Polish:** filters, accessibility labels, Reduce Motion, light/dark pass, placeholder icon, `open`/`toggle` reliability, README.

---

## 13. Acceptance criteria (v1 is done when all are true)

- [ ] With the app **not running**, running the Raycast script with `Draft Acme proposal @acme !L #sales` launches the app silently (no Dock icon, no window), creates the task on the Acme board in Todo, sized L, tagged `sales`, and the popover shows it when opened.
- [ ] With the app running, the same command adds the task without stealing focus, and the menu bar icon gives feedback.
- [ ] Unknown `@board` falls back to the default board, keeps the token in the title, and reports it. An empty title is rejected with a visible notification.
- [ ] Boards, their colours and aliases can be added, edited, reordered and deleted in Settings, and the shorthand picks up changes immediately. Alias uniqueness is enforced.
- [ ] Tasks can be dragged between Todo, In Progress, Done and Later, and reordered, and the keyboard map in §8.3 works.
- [ ] Each card shows a size stripe and a text chip. Column headers show count and load points. All five sizes are visually distinct in light and dark mode.
- [ ] Later is collapsed by default as a slim strip with a count, expands and collapses, remembers its state, and accepts drops while collapsed.
- [ ] Done tasks older than the configured number of days disappear from the board, appear in Archive, and can be restored.
- [ ] Tag filtering and text filtering work in both All and single-board views.
- [ ] Data survives quit and relaunch. A hand-edit to the JSON while the app is running is picked up. A corrupted file is recovered from backup without data loss.
- [ ] Undo/redo works for add, move, edit, delete and size change.
- [ ] Unit tests pass (`xcodebuild test`), covering the parser table, store operations, ordering, archive sweep (with an injected clock), persistence round-trip and corruption recovery, and URL routing.
- [ ] No crashes, no main-thread file I/O jank, and idle CPU is effectively zero.

---

## 14. Out of scope for v1 (do not build)

Due dates · task notes/descriptions · subtasks · custom or per-board columns · customisable size colours or points · iCloud/CloudKit or any sync · a Raycast extension (TypeScript) with live preview · direct-to-column shorthand (for example `>later`) · recurring tasks · time tracking · global hotkey inside the app (Raycast owns hotkeys) · menu bar text other than the badge count · App Store distribution · localisation (English only) · analytics of any kind.

**Likely v2 ideas, for design awareness only:** `^fri` due dates, `>later` column shorthand, notes on cards, a Raycast extension with board autocomplete, iCloud sync via the JSON file in a user-chosen folder, a weekly "load" summary.

---

## 15. Decisions made on my behalf (flag if you disagree)

- The in-app "Add task…" row in Todo uses the same parser. This is small and handy, and it is not required for Raycast capture.
- Default size for unsized tasks is **none** (neutral grey) rather than M, so unsized work is visibly "not yet triaged".
- App Sandbox is **off** for simplicity and an inspectable data path.
- Load-point values (1/2/3/5/8) and the soft warning threshold for In Progress (13 pts) are placeholders for tuning.
