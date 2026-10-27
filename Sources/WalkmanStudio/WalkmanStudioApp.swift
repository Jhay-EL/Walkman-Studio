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
        
        // Configure split view holding priorities so:
        // 1. Sidebar (leading) is rigid at 260pt.
        // 2. Main Content (center) absorbs all size changes without clipping.
        // 3. Inspector (trailing) is rigid at its configured width.
        if let contentView = window.contentView {
            configureSplitViews(in: contentView, isRoot: true)
        }
    }
    
    private func configureSplitViews(in view: NSView, isRoot: Bool = true) {
        if let splitView = view as? NSSplitView, splitView.isVertical, splitView.subviews.count >= 2 {
            // Configure split view controller items for fluid, jitter-free collapse & expansion
            if let svc = splitView.delegate as? NSSplitViewController {
                for item in svc.splitViewItems {
                    if item.behavior == .sidebar || item.behavior.rawValue == 3 /* .inspector */ {
                        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
                    }
                }
            }
            
            if isRoot {
                // Outermost split view (Sidebar vs Detail):
                // Sidebar (subview 0) is held rigid at fixed 260pt width.
                // Detail container (subview 1) absorbs all window resizing.
                splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
                splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
                
                // Recurse into subviews marking isRoot as false
                for sub in splitView.subviews {
                    configureSplitViews(in: sub, isRoot: false)
                }
                return
            } else {
                // Inner split view (Main Content vs Trailing Inspector):
                // Main Content (subview 0) absorbs size changes fluidly with zero resistance or clipping.
                // Trailing Inspector (subview 1) is held rigid at its configured column width.
                splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
                splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
            }
        }
        for sub in view.subviews {
            configureSplitViews(in: sub, isRoot: isRoot)
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
            if #available(macOS 14.0, *) {
                InspectorCommands()
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Walkman Studio") {
                    NotificationCenter.default.post(name: .showAboutWalkmanStudio, object: nil)
                }
            }
        }
    }
}
