import SwiftUI
import AppKit

extension Notification.Name {
    public static let showAboutWalkmanStudio = Notification.Name("showAboutWalkmanStudio")
}

public struct WindowConfigurator: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
    
    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 16/255, green: 17/255, blue: 20/255, alpha: 1.0)
        window.toolbar?.showsBaselineSeparator = false
    }
}

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
                .background(WindowConfigurator())
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            InspectorCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Walkman Studio") {
                    NotificationCenter.default.post(name: .showAboutWalkmanStudio, object: nil)
                }
            }
        }
    }
}
