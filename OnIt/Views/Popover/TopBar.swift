import SwiftUI

struct TopBar: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        HStack(spacing: 8) {
            BoardTabs()
            Spacer(minLength: 8)
            FilterField(focus: focus)
            SizeFilterButton()
            TagFilterButton()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

struct BoardTabs: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                pill(title: "All", color: nil, id: nil, shortcut: 1)
                ForEach(Array(store.boards.enumerated()), id: \.element.id) { index, board in
                    pill(title: board.name, color: Color(hex: board.colorHex), id: board.id, shortcut: index + 2)
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(title: String, color: Color?, id: UUID?, shortcut: Int) -> some View {
        let selected = ui.selectedBoardId == id
        return Button {
            ui.selectBoard(id)
        } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(selected ? (color ?? .accentColor).opacity(0.22) : .clear)
            }
            .overlay {
                Capsule().strokeBorder(selected ? (color ?? .accentColor).opacity(0.6) : .clear, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(shortcut <= 9 ? "\(title) (⌘\(shortcut))" : title)
        .accessibilityLabel(id == nil ? "All boards" : "\(title) board")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FilterField: View {
    @Environment(BoardUIState.self) private var ui
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter…", text: $ui.filter.text)
                .textFieldStyle(.plain)
                .focused(focus, equals: .filter)
                .accessibilityLabel("Filter tasks")
            if ui.filter.isActive {
                Button {
                    ui.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all filters (Esc)")
                .accessibilityLabel("Clear filters")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 190)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SizeFilterButton: View {
    @Environment(BoardUIState.self) private var ui
    @State private var isPresented = false

    private static let options: [TaskSize?] = TaskSize.allCases.map { Optional($0) } + [nil]

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(ui.filter.sizes.isEmpty ? "Size" : "Size (\(ui.filter.sizes.count))")
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(ui.filter.sizes.isEmpty ? nil : .accentColor)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.options, id: \.self) { size in
                    Toggle(isOn: Binding(
                        get: { ui.filter.sizes.contains(size) },
                        set: { _ in ui.toggleSizeFilter(size) }
                    )) {
                        HStack(spacing: 6) {
                            SizeChip(size: size)
                            Text(SizeStyle.style(for: size).meaning).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                if !ui.filter.sizes.isEmpty {
                    Divider()
                    Button("Clear") { ui.filter.sizes.removeAll() }
                        .buttonStyle(.link)
                }
            }
            .padding(12)
        }
        .accessibilityLabel("Size filter")
    }
}

struct TagFilterButton: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(ui.filter.tags.isEmpty ? "#Tag" : "#Tag (\(ui.filter.tags.count))")
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(ui.filter.tags.isEmpty ? nil : .accentColor)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            let tags = store.allTags
            VStack(alignment: .leading, spacing: 6) {
                if tags.isEmpty {
                    Text("No tags yet. Add one with #tag.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Toggle("#\(tag)", isOn: Binding(
                                    get: { ui.filter.tags.contains(tag) },
                                    set: { _ in ui.toggleTagFilter(tag) }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                }
                if !ui.filter.tags.isEmpty {
                    Divider()
                    Button("Clear") { ui.filter.tags.removeAll() }
                        .buttonStyle(.link)
                }
            }
            .padding(12)
            .frame(minWidth: 160)
        }
        .accessibilityLabel("Tag filter")
    }
}
