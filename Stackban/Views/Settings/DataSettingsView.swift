import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?

    var body: some View {
        Form {
            Section("Data file") {
                LabeledContent("Location") {
                    Text(dataFileURL?.path(percentEncoded: false) ?? "In memory")
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Show in Finder") {
                        if let url = dataFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button("Export JSON…", action: exportJSON)
                    Button("Import JSON…", action: importJSON)
                }
                .disabled(dataFileURL == nil)
            }

            Section("Raycast") {
                Text("Copy these two script commands into a Raycast script directory, then assign hotkeys to them in Raycast.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Raycast Script Folder") {
                    if let url = Bundle.main.url(forResource: "raycast", withExtension: nil) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dataFileURL: URL? { store.persistence?.fileURL }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "stackban-export.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            message = "Exported to \(url.lastPathComponent)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let snapshot: Snapshot
        do {
            snapshot = try Snapshot.decode(Data(contentsOf: url))
        } catch {
            message = "That file isn't a valid Stackban export: \(error.localizedDescription)"
            return
        }

        let alert = NSAlert()
        alert.messageText = "Replace all boards and tasks?"
        alert.informativeText = """
        Importing “\(url.lastPathComponent)” (\(snapshot.boards.count) boards, \(snapshot.tasks.count) tasks) \
        replaces everything currently in Stackban. A backup of your current data is saved first.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.flush(synchronously: true)
        let backup = store.persistence?.writePreImportBackup()
        store.replaceAll(with: snapshot)
        message = "Imported \(url.lastPathComponent)." + (backup.map { " Previous data saved as \($0.lastPathComponent)." } ?? "")
    }
}
