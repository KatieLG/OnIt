import SwiftUI

struct ColumnsView: View {
    @Environment(AppStore.self) private var store
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: PanelMetrics.columnSpacing) {
            if store.settings.laterExpanded {
                ColumnView(column: .later, focus: focus).transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                LaterStrip()
            }
            ForEach([Column.todo, .doing, .done]) { ColumnView(column: $0, focus: focus) }
        }
        .padding(PanelMetrics.outerPadding)
    }
}

struct ColumnView: View {
    @Environment(BoardUIState.self) private var ui
    let column: Column
    var focus: FocusState<FocusField?>.Binding
    /// Where a dragged card would land: before this card, or (nil while targeted) at the end.
    @State private var dropTarget: UUID?
    @State private var isTargeted = false

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
                                .overlay(alignment: .top) { if dropTarget == task.id { InsertionIndicator().offset(y: -4) } }
                                .dropDestination(for: String.self) { items, _ in
                                    dropTarget = nil
                                    return ui.drop(items, in: column, at: .before(task.id))
                                } isTargeted: { if $0 { dropTarget = task.id } else if dropTarget == task.id { dropTarget = nil } }
                        }
                        if isTargeted, dropTarget == nil { InsertionIndicator() }
                        if column == .todo { AddTaskRow(focus: focus) }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .onChange(of: ui.selectedTaskId) { _, id in
                    if let id, tasks.contains(where: { $0.id == id }) { withAnimation(BoardUIState.cardAnimation) { proxy.scrollTo(id) } }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if column == .later {
                Button { ui.animate(ui.toggleLater) } label: {
                    Image(systemName: "chevron.left").font(.caption.weight(.semibold)).padding(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Collapse Later (⌘L)")
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in ui.drop(items, in: column) } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column")
    }
}

private struct ColumnHeader: View {
    let column: Column
    let tasks: [TaskItem]

    var body: some View {
        let points = AppStore.loadPoints(tasks)
        let heavy = column == .doing && points > SizeStyle.doingWarning
        HStack(spacing: 4) {
            Text(column.title).font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text("· \(tasks.count) ·").foregroundStyle(.secondary)
            Text(Formatting.points(points))
                .foregroundStyle(heavy ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .fontWeight(heavy ? .semibold : .regular)
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 2)
        .padding(.trailing, column == .later ? 18 : 0)
        .help(heavy ? "Heavy load: over \(SizeStyle.doingWarning) points in progress" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(column.title), \(tasks.count) cards, \(Formatting.points(points))\(heavy ? ", heavy load" : "")")
    }
}

private struct InsertionIndicator: View {
    var body: some View {
        Capsule().fill(Color.accentColor).frame(height: 3).padding(.horizontal, 2).accessibilityHidden(true)
    }
}

/// Later, collapsed: a slim strip that expands on click and still accepts dropped cards.
private struct LaterStrip: View {
    @Environment(BoardUIState.self) private var ui
    @State private var isTargeted = false

    var body: some View {
        let count = ui.visibleTasks(in: .later).count
        Button { ui.animate(ui.toggleLater) } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                Text("Later")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .fixedSize()
                    .frame(width: 18, height: 44)
                    .rotationEffect(.degrees(90))
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 10)
            .frame(width: PanelMetrics.laterStripWidth)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(isTargeted ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand Later (⌘L)")
        .dropDestination(for: String.self) { items, _ in ui.drop(items, in: .later) } isTargeted: { isTargeted = $0 }
        .accessibilityLabel("Later, \(count) cards, collapsed")
        .accessibilityHint("Expands the Later column. Drop a card here to move it to Later.")
    }
}

private struct AddTaskRow: View {
    @Environment(BoardUIState.self) private var ui
    var focus: FocusState<FocusField?>.Binding

    var body: some View {
        @Bindable var ui = ui
        let focused = focus.wrappedValue == .add
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
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(focused ? 0.5 : 0.2), style: StrokeStyle(lineWidth: 1, dash: focused ? [] : [4, 3])))
                .help("Shorthand works here: @board !size #tag (⌘N)")
                .accessibilityLabel("Add task")
            if let message = ui.addFeedback {
                Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal, 4)
            }
        }
        .padding(.top, 2)
    }
}
