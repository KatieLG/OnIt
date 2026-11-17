import SwiftUI

struct BoardsSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: UUID?
    @State private var deleting: Board?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.boards) { board in
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: board.colorHex)).frame(width: 10, height: 10)
                            Text(board.name.isEmpty ? "Untitled" : board.name).lineLimit(1)
                            Spacer()
                            if board.isDefault { Text("Default").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .tag(board.id)
                    }
                    .onMove { store.moveBoards(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
                HStack(spacing: 0) {
                    Button { selection = store.addBoard().id } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help("Add board")
                    Button { deleting = store.board(id: selection) } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(store.board(id: selection)?.isDefault ?? true)
                        .help("Delete board (make another board the default first)")
                    Spacer()
                    Text("Drag to reorder").font(.caption).foregroundStyle(.secondary).padding(.trailing, 8)
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 210)
            Divider()
            if let board = store.board(id: selection) {
                BoardEditor(board: board) { deleting = board }.id(board.id)
            } else {
                Text("Select a board").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? store.boards.first?.id }
        .sheet(item: $deleting) { DeleteBoardSheet(board: $0) { selection = store.boards.first?.id } }
    }
}

private struct BoardEditor: View {
    @Environment(AppStore.self) private var store
    let board: Board
    let onDelete: () -> Void
    @State private var aliases = ""
    @State private var aliasError: String?

    var body: some View {
        Form {
            TextField("Name", text: Binding(get: { board.name }, set: { name in store.updateBoard(board.id) { $0.name = name } }))
            LabeledContent("Colour") {
                HStack(spacing: 6) {
                    ForEach(AppStore.boardPalette, id: \.self) { hex in
                        Button { setColor(hex) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.primary.opacity(board.colorHex == hex ? 0.8 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    ColorPicker("Custom colour", selection: Binding(get: { Color(hex: board.colorHex) }, set: { if let hex = $0.hex { setColor(hex) } }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
            }
            LabeledContent("Aliases") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("e.g. work, w", text: $aliases).onSubmit(saveAliases)
                    Text(aliasError ?? "@\(board.nameSlug) always works too. Separate with commas; use a–z, 0–9, _ and -.")
                        .font(.caption)
                        .foregroundStyle(aliasError == nil ? .secondary : Color.red)
                }
            }
            Picker("Default board", selection: Binding(get: { store.defaultBoard.id }, set: { store.setDefaultBoard($0) })) {
                ForEach(store.boards) { Text($0.name.isEmpty ? "Untitled" : $0.name).tag($0.id) }
            }
            .pickerStyle(.radioGroup)
            .help("Tasks without an @board go to the default board")
            Section {
                Button("Delete Board…", role: .destructive, action: onDelete)
                    .disabled(board.isDefault)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
        .onAppear { aliases = board.aliases.joined(separator: ", ") }
        .onDisappear(perform: saveAliases)
    }

    private func setColor(_ hex: String) { store.updateBoard(board.id) { $0.colorHex = hex } }

    private func saveAliases() {
        do {
            try store.setAliases(aliases, for: board.id)
            aliasError = nil
        } catch {
            aliasError = error.localizedDescription
        }
    }
}

private struct DeleteBoardSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let board: Board
    let onDeleted: () -> Void
    @State private var target: UUID?
    @State private var error: String?

    var body: some View {
        let count = store.tasks.count(where: { $0.boardId == board.id })
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete “\(board.name)”?").font(.headline)
            if count > 0 {
                Text("It has \(count) task\(count == 1 ? "" : "s"), including archived ones. Move them to another board, or delete them too.")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Move tasks to", selection: $target) {
                    ForEach(store.boards.filter { $0.id != board.id }) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("You can undo this with ⌘Z on the board.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(count > 0 ? "Delete Board and Tasks" : "Delete", role: .destructive) { delete(movingTo: nil) }
                if count > 0 {
                    Button("Move Tasks and Delete") { delete(movingTo: target) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(target == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { target = store.defaultBoard.id }
    }

    private func delete(movingTo target: UUID?) {
        do {
            try store.deleteBoard(board.id, moveTasksTo: target)
            dismiss()
            onDeleted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
