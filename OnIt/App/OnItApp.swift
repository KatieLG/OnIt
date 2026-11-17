import SwiftUI

@main
struct OnItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // An App needs a scene. Settings is an AppKit-hosted window, so ⌘, is pointed at that.
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.showSettings() }.keyboardShortcut(",")
                }
            }
    }
}
