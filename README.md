<p align="center">
  <img src="OnIt/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="112" alt="OnIt app icon">
</p>

<h1 align="center">OnIt</h1>

<p align="center"><strong>Every “on it”, on one board.</strong><br>
A native macOS board for all the small things you've said you'll do.</p>

---

“Can you send that over?” *On it.* “Could you take a look?” *On it.*

Small asks land all day, at work and at home, and they live in your head until one slips. OnIt gives them
somewhere to go. Type one line and it's on your board, sized and sorted. At a glance you can see what's
waiting, what you're doing, what you finished this week, and whether you've taken on too much.

## In your menu bar, or full screen

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/onit-panel.png" alt="OnIt's translucent board dropping down from the menu bar"></td>
    <td width="50%"><img src="docs/screenshots/onit-window.png" alt="OnIt's full app window with Todo, In Progress, Done and Later columns"></td>
  </tr>
  <tr>
    <td align="center">Click the ✓ in the menu bar for a translucent board over whatever you're doing.</td>
    <td align="center">Or open OnIt as an app for a full window you can resize or take full screen.</td>
  </tr>
</table>

## Home and work, kept apart

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/onit-home.png" alt="OnIt showing only the Home board"></td>
    <td width="50%"><img src="docs/screenshots/onit-work.png" alt="OnIt showing only the Work board"></td>
  </tr>
  <tr>
    <td align="center"><b>Home</b>: errands, admin, plans.</td>
    <td align="center"><b>Work</b>: everything you've said yes to.</td>
  </tr>
</table>

Switch boards with one click (or ⌘1–⌘9), see them all together in **All**, and add as many boards as you like.

## What makes it different

- **Sizes you can see.** Every task is XS (minutes) to XL (days), shown as a colour stripe and a label.
  Columns add up their load, and In Progress turns orange when you're carrying too much.
- **Shorthand capture.** `Send invoice @work !s #billing` puts it on Work, sized S, tagged *billing*.
  Use `@` for the board, `!` for the size and `#` for tags, or none of them.
- **Keyboard first, drag friendly.** Arrow keys to move around, ⌘-arrows to move cards, ⌥1–5 to size them,
  ⌘Z to undo. Or just drag.
- **Tidies itself.** Done tasks move to the Archive after a week, so the board stays about now.
- **Private by design.** No account, no cloud, no tracking. One readable JSON file on your Mac, with
  automatic backups.

## Install

You need macOS 14 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -scheme OnIt -configuration Release -destination 'platform=macOS' -derivedDataPath build build
cp -R build/Build/Products/Release/OnIt.app /Applications/
```

Open OnIt from Applications. Turn on **Launch at login** in **Settings → General** to keep it in your menu bar.

## Works great with Raycast (optional)

If you use [Raycast](https://www.raycast.com), the two script commands in [`raycast/`](raycast) add global
shortcuts. **Add OnIt Task** captures a task from anywhere without leaving what you're doing, and
**Toggle OnIt** shows or hides the board. From this repo's root:

```sh
mkdir -p ~/.config/raycast/scripts
ln -sf "$(pwd)/raycast/add-onit-task.sh" "$(pwd)/raycast/open-onit.sh" ~/.config/raycast/scripts/
```

Then in **Raycast Settings → Extensions**, click **+ → Add Script Directory**, choose
`~/.config/raycast/scripts` (press ⌘⇧G to type the path), and give both commands a hotkey.
The links mean the scripts stay up to date when you pull changes.

---

<sub>Your data lives in `~/Library/Application Support/OnIt/onit.json`. Automation: `onit://add?text=…`,
`onit://open` and `onit://toggle`. Developers: run tests with `xcodebuild -scheme OnIt -destination 'platform=macOS' test`.
Design decisions are in [`docs/IMPLEMENTATION_NOTES.md`](docs/IMPLEMENTATION_NOTES.md); the original
brief is [`STACKBAN_SPEC.md`](STACKBAN_SPEC.md).</sub>
