import SwiftUI

struct BoardsSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: UUID?
    @State private var pendingDelete: Board?
    @State private var undoBanner: (entryID: UUID, message: String)?
    @State private var bannerTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                boardList
                    .frame(width: 210)
                Divider()
                Group {
                    if let board = store.board(id: selection) {
                        BoardEditor(board: board) { pendingDelete = board }
                            .id(board.id)
                    } else {
                        Text("Select a board")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let banner = undoBanner {
                Divider()
                HStack {
                    Text(banner.message)
                    Spacer()
                    Button("Undo") {
                        if store.undo(ifTop: banner.entryID) { selection = selection ?? store.boards.last?.id }
                        dismissBanner()
                    }
                }
                .padding(10)
                .background(.yellow.opacity(0.15))
            }
        }
        .onAppear { selection = selection ?? store.boards.first?.id }
        .sheet(item: $pendingDelete) { board in
            DeleteBoardSheet(board: board) { entryID in
                selection = store.boards.first?.id
                if let entryID { showBanner(entryID: entryID, message: "Deleted board “\(board.name)”.") }
            }
        }
    }

    private var boardList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.boards) { board in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: board.colorHex) ?? .gray).frame(width: 10, height: 10)
                        Text(board.name.isEmpty ? "Untitled" : board.name)
                            .lineLimit(1)
                        Spacer()
                        if board.isDefault {
                            Text("Default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(board.id)
                }
                .onMove { source, destination in
                    store.moveBoards(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            HStack(spacing: 0) {
                Button {
                    selection = store.addBoard().id
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 20)
                }
                .help("Add board")
                Button {
                    if let board = store.board(id: selection) { pendingDelete = board }
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 20)
                }
                .disabled(store.board(id: selection)?.isDefault ?? true)
                .help(store.board(id: selection)?.isDefault == true
                      ? "Make another board the default before deleting this one"
                      : "Delete board")
                Spacer()
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
    }

    private func showBanner(entryID: UUID, message: String) {
        bannerTask?.cancel()
        undoBanner = (entryID, message)
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            undoBanner = nil
        }
    }

    private func dismissBanner() {
        bannerTask?.cancel()
        undoBanner = nil
    }
}

struct BoardEditor: View {
    @Environment(AppStore.self) private var store
    let board: Board
    let onDelete: () -> Void

    @State private var newAlias = ""
    @State private var aliasError: String?

    var body: some View {
        Form {
            TextField("Name", text: Binding(
                get: { board.name },
                set: { store.renameBoard(board.id, to: $0) }
            ))
            LabeledContent("Shorthand name") {
                Text("@\(board.nameSlug)").foregroundStyle(.secondary).textSelection(.enabled)
            }

            LabeledContent("Colour") {
                HStack(spacing: 6) {
                    ForEach(AppStore.boardPalette, id: \.self) { hex in
                        Button {
                            store.setBoardColor(board.id, hex: hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 18, height: 18)
                                .overlay {
                                    Circle().strokeBorder(Color.primary.opacity(board.colorHex.uppercased() == hex ? 0.8 : 0), lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(hex)")
                    }
                    ColorPicker("Custom colour", selection: Binding(
                        get: { Color(hex: board.colorHex) ?? .gray },
                        set: { if let hex = $0.hexString { store.setBoardColor(board.id, hex: hex) } }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }

            LabeledContent("Aliases") {
                VStack(alignment: .leading, spacing: 6) {
                    FlowLayout(spacing: 6) {
                        ForEach(board.aliases, id: \.self) { alias in
                            HStack(spacing: 3) {
                                Text("@\(alias)")
                                Button {
                                    store.removeAlias(alias, from: board.id)
                                } label: {
                                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove alias \(alias)")
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    TextField("Add alias and press Return", text: $newAlias)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addAlias)
                        .onChange(of: newAlias) { _, value in
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            let body = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
                            aliasError = body.isEmpty ? nil : store.validateAlias(body, for: board.id)?.errorDescription
                        }
                    if let aliasError {
                        Text(aliasError).font(.caption).foregroundStyle(.red)
                    } else {
                        Text("Lowercase letters, digits, _ and -. Must be unique across boards.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Radio semantics: exactly one board is default, so it can only be switched on.
            Picker("Default board", selection: Binding(
                get: { store.defaultBoard?.id },
                set: { if let id = $0 { store.setDefaultBoard(id) } }
            )) {
                ForEach(store.boards) { other in
                    Text(other.name.isEmpty ? "Untitled" : other.name).tag(Optional(other.id))
                }
            }
            .pickerStyle(.radioGroup)
            .help("Tasks without an @board go to the default board")

            Section {
                HStack {
                    Spacer()
                    Button("Delete Board…", role: .destructive, action: onDelete)
                        .disabled(board.isDefault)
                        .help(board.isDefault ? "Make another board the default before deleting this one" : "")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addAlias() {
        var value = newAlias.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("@") { value.removeFirst() }
        if let error = store.addAlias(value, to: board.id) {
            aliasError = error.errorDescription
        } else {
            newAlias = ""
            aliasError = nil
        }
    }
}

struct DeleteBoardSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let board: Board
    /// Called with the undo entry ID after a successful delete.
    let onDeleted: (UUID?) -> Void

    @State private var moveTarget: UUID?
    @State private var error: String?

    var body: some View {
        let taskCount = store.taskCount(onBoard: board.id)
        let others = store.boards.filter { $0.id != board.id }
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete “\(board.name)”?").font(.headline)
            if taskCount > 0 {
                Text("This board has \(taskCount) task\(taskCount == 1 ? "" : "s") (including archived). What should happen to \(taskCount == 1 ? "it" : "them")?")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Move tasks to", selection: $moveTarget) {
                    ForEach(others) { other in
                        Text(other.name).tag(Optional(other.id))
                    }
                }
            } else {
                Text("This board has no tasks.")
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Text("You can undo this for a short time afterwards.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if taskCount > 0 {
                    Button("Delete Board and Tasks", role: .destructive) { perform(.deleteTasks) }
                    Button("Move Tasks and Delete") {
                        if let target = moveTarget { perform(.moveTasks(to: target)) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(moveTarget == nil)
                } else {
                    Button("Delete", role: .destructive) { perform(.deleteTasks) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { moveTarget = store.defaultBoard?.id ?? others.first?.id }
    }

    private func perform(_ disposition: BoardDeletion) {
        do {
            let entryID = try store.deleteBoard(board.id, tasks: disposition)
            dismiss()
            onDeleted(entryID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Simple wrapping layout for alias chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for (index, point) in rows.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (positions: [CGPoint], width: CGFloat, height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (positions, maxX, subviews.isEmpty ? 0 : y + rowHeight)
    }
}
