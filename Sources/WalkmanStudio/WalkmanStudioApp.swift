import SwiftUI
import AppKit

extension Notification.Name {
    public static let showAboutWalkmanStudio = Notification.Name("showAboutWalkmanStudio")
    public static let trackMetadataDidUpdate = Notification.Name("WalkmanStudio.trackMetadataDidUpdate")
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
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 16/255, green: 17/255, blue: 20/255, alpha: 1.0)
        
        // Enforce 1690x800 minimum window size constraint so buttons, navigation, and labels display properly
        let minW: CGFloat = 1690
        let minH: CGFloat = 800
        window.minSize = NSSize(width: minW, height: minH)
        window.contentMinSize = NSSize(width: minW, height: minH)
        
        var frame = window.frame
        var needsResize = false
        if frame.size.width < minW {
            frame.size.width = minW
            needsResize = true
        }
        if frame.size.height < minH {
            frame.origin.y -= (minH - frame.size.height)
            frame.size.height = minH
            needsResize = true
        }
        if needsResize {
            window.setFrame(frame, display: true, animate: false)
        }
        
        // Ensure the titlebar/toolbar container background and decoration views are transparent
        if let contentView = window.contentView, let themeFrame = contentView.superview {
            for sub in themeFrame.subviews {
                if let titlebarContainer = NSClassFromString("NSTitlebarContainerView"), sub.isKind(of: titlebarContainer) {
                    for child in sub.subviews {
                        if let bgClass = NSClassFromString("NSTitlebarBackgroundView"), child.isKind(of: bgClass) {
                            child.isHidden = true
                            child.alphaValue = 0.0
                        }
                        if let decorClass = NSClassFromString("_NSTitlebarDecorationView"), child.isKind(of: decorClass) {
                            child.isHidden = true
                            child.alphaValue = 0.0
                        }
                    }
                }
            }
        }
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
                .frame(minWidth: 1690, idealWidth: 1720, minHeight: 800, idealHeight: 920)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1720, height: 920)
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
