import SwiftUI

enum PanelMetrics {
    static let defaultSize = CGSize(width: 820, height: 540)
    static let minSize = CGSize(width: 600, height: 360)
    static let laterStripWidth: CGFloat = 36
    static let columnSpacing: CGFloat = 8
    static let outerPadding: CGFloat = 8
}

/// The board, shared by the menu bar panel and the main window: top bar plus columns.
struct RootView: View {
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
            if old == .edit, new != .edit { ui.commitEdit() } // clicking away saves the edit
        }
        .onChange(of: ui.focusRequest) { _, request in
            guard let request else { return }
            if case .field(let field) = request { focus = field } else { focus = nil }
            ui.focusRequest = nil
        }
        .alert("Edit Tags", isPresented: Binding(get: { ui.tagEditingTaskId != nil }, set: { if !$0 { ui.tagEditingTaskId = nil } })) {
            TextField("#tag #another", text: $ui.tagEditText)
            Button("Save", action: ui.commitTagEdit)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Separate tags with spaces or commas.")
        }
    }
}
