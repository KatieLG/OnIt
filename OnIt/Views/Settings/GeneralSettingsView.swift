import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var loginError: String?

    private static let shortcuts = [
        ("↑ ↓ ← →", "Move between cards and columns"), ("⌘← / ⌘→", "Move card to previous / next column"),
        ("⌘↑ / ⌘↓", "Reorder card"), ("⌥1…⌥5, ⌥0", "Set size XS…XL, clear size"), ("Return or E", "Edit title"),
        ("⌫", "Delete card (undoable)"), ("⌘Z / ⇧⌘Z", "Undo / redo"), ("⌘N", "Add a task"), ("⌘L", "Show or hide Later"),
        ("/", "Filter"), ("⌘1…⌘9", "Switch board (⌘1 is All)"), ("Esc", "Clear filter, cancel edit, or close"),
    ]
    private static let links = [
        ("onit://add?text=Pick%20up%20dry%20cleaning%20%40home%20%21s", "Add “Pick up dry cleaning” to Home, size S"),
        ("onit://open", "Show the board"), ("onit://open?board=work", "Show the board with Work selected"),
        ("onit://toggle", "Show or hide the board"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Default size for unsized tasks", selection: setting(\.defaultSize)) {
                    Text("None").tag(TaskSize?.none)
                    ForEach(TaskSize.allCases) { Text($0.label).tag(Optional($0)) }
                }
                Stepper("Auto-archive Done after \(store.settings.archiveAfterDays) day\(store.settings.archiveAfterDays == 1 ? "" : "s")",
                        value: setting(\.archiveAfterDays), in: AppSettings.archiveDaysRange)
                Picker("Menu bar badge", selection: setting(\.badgeMode)) {
                    ForEach(BadgeMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Theme", selection: setting(\.theme)) {
                    ForEach(Theme.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Notify when a task is added", isOn: setting(\.notifyOnAdd))
                    .onChange(of: store.settings.notifyOnAdd) { _, on in if on { Task { await Notifier.shared.requestPermission() } } }
                Toggle("Launch at login", isOn: Binding(get: { store.settings.launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Keyboard shortcuts") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(Self.shortcuts.indices, id: \.self) { i in
                        GridRow {
                            Text(Self.shortcuts[i].0).monospaced().foregroundStyle(.secondary)
                            Text(Self.shortcuts[i].1)
                        }
                    }
                }
                .font(.callout)
            }
            Section("Links") {
                ForEach(Self.links.indices, id: \.self) { i in
                    let (url, meaning) = Self.links[i]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url).monospaced().textSelection(.enabled)
                            Text(meaning).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setting<Value>(_ path: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: path] }, set: { value in store.updateSettings { $0[keyPath: path] = value } })
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        store.updateSettings { $0.launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}
