import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            BoardsSettingsView()
                .tabItem { Label("Boards", systemImage: "rectangle.stack") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            DataSettingsView()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 680, height: 500)
        .padding(.top, 8)
    }
}
