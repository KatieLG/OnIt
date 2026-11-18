import SwiftUI

struct TopBar: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    BoardTab(title: "All", color: nil, id: nil, shortcut: 1)
                    ForEach(Array(store.boards.enumerated()), id: \.element.id) { index, board in
                        BoardTab(title: board.name, color: Color(hex: board.colorHex), id: board.id, shortcut: index + 2)
                    }
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter…", text: $ui.filter.text)
                    .textFieldStyle(.plain)
                    .focused(focus, equals: .filter)
                    .accessibilityLabel("Filter tasks")
                if ui.filter.isActive {
                    Button { ui.filter = TaskFilter() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Clear all filters (Esc)")
                        .accessibilityLabel("Clear filters")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 190)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

            FilterMenu(title: "Size", options: TaskSize.allCases.map(Optional.some) + [nil], selection: $ui.filter.sizes,
                       optionsEnabled: store.showsSizes(boardId: ui.selectedBoardId), header: AnyView(ShowSizesToggle())) {
                $0?.label ?? "Unsized"
            }
            FilterMenu(title: "#Tag", options: store.allTags, selection: $ui.filter.tags) { "#\($0)" }
            Button { ui.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct BoardTab: View {
    @Environment(BoardUIState.self) private var ui
    let title: String, color: Color?, id: UUID?, shortcut: Int

    var body: some View {
        let selected = ui.selectedBoardId == id, tint = color ?? .accentColor
        Button { ui.selectBoard(id) } label: {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(selected ? 0.22 : 0)))
            .overlay(Capsule().strokeBorder(tint.opacity(selected ? 0.6 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(shortcut <= 9 ? "\(title) (⌘\(shortcut))" : title)
        .accessibilityLabel(id == nil ? "All boards" : "\(title) board")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The board's "Show sizes" setting, at the top of the Size menu. All has no single board to change.
private struct ShowSizesToggle: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui

    var body: some View {
        if let board = store.board(id: ui.selectedBoardId) {
            Toggle("Show Sizes on \(board.name)", isOn: Binding(get: { board.showsSizes }, set: { on in
                store.updateBoard(board.id) { $0.showsSizes = on }
                if !on { ui.filter.sizes = [] } // don't leave a size filter on that can't be seen
            }))
        } else {
            Text("Choose a board to show or hide sizes")
        }
    }
}

/// A multi-select filter menu, e.g. sizes or tags.
private struct FilterMenu<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Set<Value>
    var optionsEnabled = true
    var header: AnyView?
    let label: (Value) -> String

    var body: some View {
        Menu {
            if let header {
                header
                Divider()
            }
            if options.isEmpty { Text("Nothing to filter yet") }
            ForEach(options, id: \.self) { option in
                Toggle(label(option), isOn: Binding(
                    get: { selection.contains(option) },
                    set: { if $0 { selection.insert(option) } else { selection.remove(option) } }
                ))
                .disabled(!optionsEnabled)
            }
            if !selection.isEmpty {
                Divider()
                Button("Clear") { selection = [] }
            }
        } label: {
            Text(selection.isEmpty ? title : "\(title) (\(selection.count))")
        }
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("\(title) filter")
    }
}
