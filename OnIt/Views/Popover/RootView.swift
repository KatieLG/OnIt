import SwiftUI

/// The popover's content: top bar plus columns.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(BoardUIState.self) private var ui
    @FocusState private var focus: FocusField?

    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: 0) {
            TopBar(focus: $focus)
            Divider()
            ColumnsView(focus: $focus)
        }
        .frame(minWidth: PanelMetrics.minSize.width, minHeight: PanelMetrics.minSize.height)
        .onChange(of: focus) { old, new in
            ui.focus = new
            if old == .edit, new != .edit, ui.editingTaskId != nil {
                ui.commitEdit()
            }
        }
        .onChange(of: ui.focusRequest) { _, request in
            guard let request else { return }
            switch request {
            case .field(let field): focus = field
            case .board: focus = nil
            }
            ui.focusRequest = nil
        }
        .alert(
            "Edit Tags",
            isPresented: Binding(
                get: { ui.tagEditingTaskId != nil },
                set: { if !$0 { ui.tagEditingTaskId = nil } }
            )
        ) {
            TextField("#tag #another", text: $ui.tagEditText)
            Button("Save") { ui.commitTagEdit() }
            Button("Cancel", role: .cancel) { ui.tagEditingTaskId = nil }
        } message: {
            Text("Separate tags with spaces or commas.")
        }
    }
}

enum PanelMetrics {
    static let defaultSize = CGSize(width: 820, height: 540)
    static let minSize = CGSize(width: 600, height: 360)
    static let maxSize = CGSize(width: 1800, height: 1200)
    static let laterStripWidth: CGFloat = 36
    static let columnSpacing: CGFloat = 8
    static let outerPadding: CGFloat = 8
}
