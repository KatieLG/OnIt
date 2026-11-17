import SwiftUI

@main
struct StackbanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The real Settings and Archive windows are AppKit-hosted SwiftUI windows managed by
        // `WindowCoordinator` (see README: "Deviations"). This scene only exists because an
        // `App` needs one; its menu command is redirected to our window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}
