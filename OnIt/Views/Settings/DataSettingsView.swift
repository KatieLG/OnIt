import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?

    var body: some View {
        Form {
            if let url = store.persistence?.fileURL {
                Section("Data file") {
                    LabeledContent("Location") {
                        Text(url.path(percentEncoded: false)).font(.caption).textSelection(.enabled).truncationMode(.middle)
                    }
                    HStack {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Button("Export JSON…", action: export)
                        Button("Import JSON…", action: importJSON)
                    }
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        (panel.allowedContentTypes, panel.nameFieldStringValue) = ([.json], "onit-export.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.snapshot().encoded().write(to: url)
            message = "Exported to \(url.lastPathComponent)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let snapshot = try? Snapshot.decode(Data(contentsOf: url)) else { return message = "That file isn't an OnIt export." }

        let alert = NSAlert()
        alert.messageText = "Replace all boards and tasks?"
        alert.informativeText = "This imports \(snapshot.boards.count) boards and \(snapshot.tasks.count) tasks from “\(url.lastPathComponent)”, replacing everything in OnIt. Your current data is backed up first."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.flush(synchronously: true)
        let backup = store.persistence?.copyAside("pre-import")
        store.replaceAll(with: snapshot)
        message = "Imported. Your previous data was saved as \(backup?.lastPathComponent ?? "a backup")."
    }
}
