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
        
        // Enforce 1320x720 minimum window size constraint to support 13" Intel and Apple Silicon MacBooks seamlessly
        let minW: CGFloat = 1320
        let minH: CGFloat = 720
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
        
        // Lock leading sidebar split view item so opening the inspector never shrinks or animates the sidebar
        if let contentView = window.contentView {
            configureSplitViews(in: contentView)
        }
    }
    
    private func configureSplitViews(in view: NSView) {
        if let splitView = view as? NSSplitView, splitView.isVertical, splitView.subviews.count >= 2 {
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
            splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        }
        for sub in view.subviews {
            configureSplitViews(in: sub)
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
                .frame(minWidth: 1320, idealWidth: 1440, minHeight: 720, idealHeight: 880)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1440, height: 880)
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
