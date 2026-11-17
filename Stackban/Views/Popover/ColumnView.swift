import SwiftUI

struct ColumnsView: View {
    @Environment(AppStore.self) private var store
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: PanelMetrics.columnSpacing) {
            ColumnView(column: .todo, focus: focus)
            ColumnView(column: .doing, focus: focus)
            ColumnView(column: .done, focus: focus)
            if store.settings.laterExpanded {
                ColumnView(column: .later, focus: focus)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                LaterStrip()
            }
        }
        .padding(PanelMetrics.outerPadding)
    }
}

/// Drag payload: the task's UUID string. Unknown strings dropped from elsewhere are ignored.
enum CardDrag {
    static func taskID(from items: [String]) -> UUID? {
        items.lazy.compactMap { UUID(uuidString: $0) }.first
    }
}

struct ColumnView: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    let column: Column
    var focus: FocusState<FocusField?>.Binding

    @State private var dropTargetID: UUID?
    @State private var isEndTargeted = false

    var body: some View {
        let tasks = ui.visibleTasks(in: column)
        VStack(alignment: .leading, spacing: 6) {
            ColumnHeader(column: column, tasks: tasks)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks) { task in
                            CardView(task: task, focus: focus)
                                .id(task.id)
                                .overlay(alignment: .top) {
                                    if dropTargetID == task.id { InsertionIndicator().offset(y: -4) }
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    drop(items, at: .before(task.id))
                                } isTargeted: { targeted in
                                    if targeted { dropTargetID = task.id } else if dropTargetID == task.id { dropTargetID = nil }
                                }
                        }
                        if isEndTargeted, dropTargetID == nil {
                            InsertionIndicator()
                        }
                        if column == .todo {
                            AddTaskRow(focus: focus)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.automatic)
                .onChange(of: ui.selectedTaskId) { _, id in
                    guard let id, tasks.contains(where: { $0.id == id }) else { return }
                    withAnimation(BoardUIState.cardAnimation) { proxy.scrollTo(id) }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if column == .later {
                Button {
                    withAnimation(BoardUIState.cardAnimation) { ui.toggleLater() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Collapse Later (⌘L)")
                .accessibilityLabel("Collapse Later")
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            drop(items, at: .end)
        } isTargeted: { isEndTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column")
    }

    private func drop(_ items: [String], at position: InsertPosition) -> Bool {
        dropTargetID = nil
        isEndTargeted = false
        guard let id = CardDrag.taskID(from: items), store.task(id: id) != nil else { return false }
        withAnimation(BoardUIState.cardAnimation) {
            store.move(id, to: column, position: position)
        }
        ui.selectedTaskId = id
        return true
    }
}

struct ColumnHeader: View {
    let column: Column
    let tasks: [TaskItem]

    var body: some View {
        let points = AppStore.loadPoints(tasks)
        let overloaded = SizeStyle.warningThreshold(for: column).map { points > $0 } ?? false
        HStack(spacing: 4) {
            Text(column.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text("· \(tasks.count) ·")
                .foregroundStyle(.secondary)
            Text(Formatting.pointsLabel(points))
                .foregroundStyle(overloaded ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .fontWeight(overloaded ? .semibold : .regular)
                .help(overloaded ? "Heavy load: over \(SizeStyle.doingLoadWarningThreshold) points in progress" : "")
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 2)
        .padding(.trailing, column == .later ? 18 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(column.title), \(tasks.count) cards, \(Formatting.pointsLabel(points))\(overloaded ? ", heavy load" : "")")
    }
}

struct InsertionIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }
}

/// Later, collapsed: a slim vertical strip that expands on click and still accepts drops.
struct LaterStrip: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    @State private var isTargeted = false

    var body: some View {
        let count = ui.visibleTasks(in: .later).count
        Button {
            withAnimation(BoardUIState.cardAnimation) { ui.toggleLater() }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                Text("Later")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .fixedSize()
                    .frame(width: 18, height: 44)
                    .rotationEffect(.degrees(90))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 10)
            .frame(width: PanelMetrics.laterStripWidth)
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand Later (⌘L)")
        .dropDestination(for: String.self) { items, _ in
            isTargeted = false
            guard let id = CardDrag.taskID(from: items), store.task(id: id) != nil else { return false }
            withAnimation(BoardUIState.cardAnimation) {
                store.move(id, to: .later, position: .end)
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .accessibilityLabel("Later, \(count) cards, collapsed")
        .accessibilityHint("Expands the Later column. Drop a card here to move it to Later.")
    }
}

struct AddTaskRow: View {
    @Environment(BoardUIState.self) private var ui
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        @Bindable var ui = ui
        VStack(alignment: .leading, spacing: 4) {
            TextField("+ Add task…", text: $ui.addText)
                .textFieldStyle(.plain)
                .focused(focus, equals: .add)
                .onSubmit {
                    ui.submitAdd()
                    ui.focusRequest = .field(.add)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(focus.wrappedValue == .add ? 0.5 : 0.2),
                                      style: StrokeStyle(lineWidth: 1, dash: focus.wrappedValue == .add ? [] : [4, 3]))
                }
                .help("Shorthand works here: @board !size #tag (⌘N)")
                .accessibilityLabel("Add task")
            if let message = ui.addFeedback {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }
}
