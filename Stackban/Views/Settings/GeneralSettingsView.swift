import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.notifier) private var notifier
    @State private var loginError: String?

    private static let sizeOptions: [TaskSize?] = [nil] + TaskSize.allCases.map { Optional($0) }

    var body: some View {
        Form {
            Section {
                Picker("Default size for unsized tasks", selection: Binding(
                    get: { store.settings.defaultSize },
                    set: { value in store.updateSettings { $0.defaultSize = value } }
                )) {
                    ForEach(Self.sizeOptions, id: \.self) { size in
                        Text(size?.label ?? "None").tag(size)
                    }
                }

                Stepper(value: Binding(
                    get: { store.settings.archiveAfterDays },
                    set: { value in store.updateSettings { $0.archiveAfterDays = value } }
                ), in: AppSettings.archiveDaysRange) {
                    Text("Auto-archive Done after \(store.settings.archiveAfterDays) day\(store.settings.archiveAfterDays == 1 ? "" : "s")")
                }

                Picker("Menu bar badge", selection: Binding(
                    get: { store.settings.badgeMode },
                    set: { value in store.updateSettings { $0.badgeMode = value } }
                )) {
                    ForEach(BadgeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Notify when a task is added", isOn: Binding(
                    get: { store.settings.notifyOnAdd },
                    set: { value in
                        store.updateSettings { $0.notifyOnAdd = value }
                        if value { Task { await notifier?.requestPermissionIfNeeded() } }
                    }
                ))

                Toggle("Launch at login", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Keyboard shortcuts") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(Self.shortcuts, id: \.keys) { item in
                        GridRow {
                            Text(item.keys).monospaced().foregroundStyle(.secondary)
                            Text(item.action)
                        }
                    }
                }
                .font(.callout)
            }

            Section("URL scheme") {
                ForEach(Self.urlExamples, id: \.url) { example in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.url).monospaced().textSelection(.enabled)
                            Text(example.meaning).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(example.url, forType: .string)
                        }
                        .controlSize(.small)
                    }
                }
                Text("Shorthand: @board picks a board, !xs…!xl sets the size, #tag adds tags. Prefix a sigil with \\ to keep it literal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        store.updateSettings { $0.launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private struct Shortcut { let keys: String; let action: String }

    private static let shortcuts: [Shortcut] = [
        Shortcut(keys: "↑ / ↓", action: "Select previous / next card"),
        Shortcut(keys: "← / →", action: "Select card in adjacent column"),
        Shortcut(keys: "⌘← / ⌘→", action: "Move card to previous / next column"),
        Shortcut(keys: "⌘↑ / ⌘↓", action: "Reorder card within column"),
        Shortcut(keys: "⌥1…⌥5", action: "Set size XS…XL (⌥0 clears)"),
        Shortcut(keys: "Return or E", action: "Edit title"),
        Shortcut(keys: "⌫", action: "Delete card (undoable)"),
        Shortcut(keys: "⌘Z / ⇧⌘Z", action: "Undo / redo"),
        Shortcut(keys: "⌘N", action: "Focus “Add task…”"),
        Shortcut(keys: "⌘L", action: "Expand / collapse Later"),
        Shortcut(keys: "/", action: "Focus filter"),
        Shortcut(keys: "⌘1…⌘9", action: "Switch board (1 = All)"),
        Shortcut(keys: "Esc", action: "Clear filter / cancel edit / close"),
    ]

    private struct URLExample { let url: String; let meaning: String }

    private static let urlExamples: [URLExample] = [
        URLExample(url: "stackban://add?text=Draft%20proposal%20%40c%20%21L%20%23sales",
                   meaning: "Add “Draft proposal” to Client, size L, tagged sales"),
        URLExample(url: "stackban://open", meaning: "Show the board"),
        URLExample(url: "stackban://toggle", meaning: "Show or hide the board"),
        URLExample(url: "stackban://open?board=int", meaning: "Show the board with Internal selected"),
    ]
}
