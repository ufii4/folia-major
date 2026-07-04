import FoliaUI
import SwiftUI

@main
struct FoliaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        Settings {
            SettingsView().frame(width: 420)
        }
        #endif
    }
}
