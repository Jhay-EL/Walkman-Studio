import SwiftUI
import AppKit

@main
struct WalkmanStudioApp: App {
    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = img
        } else if let fallback = NSImage(contentsOfFile: "assets/icon.png") {
            NSApplication.shared.applicationIconImage = fallback
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1060, minHeight: 680)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            InspectorCommands()
        }
    }
}
