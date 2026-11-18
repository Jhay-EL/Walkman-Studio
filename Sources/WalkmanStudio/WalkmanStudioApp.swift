import SwiftUI
import AppKit
import ObjectiveC

extension Notification.Name {
    public static let showAboutWalkmanStudio = Notification.Name("showAboutWalkmanStudio")
    public static let checkForUpdates = Notification.Name("WalkmanStudio.checkForUpdates")
    public static let trackMetadataDidUpdate = Notification.Name("WalkmanStudio.trackMetadataDidUpdate")
    public static let manageLocalFolders = Notification.Name("WalkmanStudio.manageLocalFolders")
}

private var mainWindowDelegateKey: UInt8 = 0

private final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?

    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        let proposed = originalDelegate?.window?(window, willPositionSheet: sheet, using: rect) ?? rect
        let fullWidth = window.contentView?.bounds.width ?? window.frame.width
        return NSRect(x: 0, y: proposed.origin.y, width: fullWidth, height: proposed.height)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.window(_:willPositionSheet:using:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return originalDelegate
    }
}

public struct WindowConfigurator: NSViewRepresentable {
    public init() {}
    
    public static func ensureSheetCenteringDelegate(for window: NSWindow) {
        if !(window.delegate is MainWindowDelegateProxy) {
            let proxy = MainWindowDelegateProxy()
            proxy.originalDelegate = window.delegate
            objc_setAssociatedObject(window, &mainWindowDelegateKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            window.delegate = proxy
        }
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = view.window {
                configure(window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
        Self.ensureSheetCenteringDelegate(for: window)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 16/255, green: 17/255, blue: 20/255, alpha: 1.0)
        
        // Enforce 1200x660 minimum window size constraint
        let minW: CGFloat = 1200
        let minH: CGFloat = 660
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
            hideSidebarToggleButtons(in: themeFrame)
            setupTrafficLightsScaler(for: window)
        }
        
        // Strip any synthesized or residual sidebar toggle toolbar items from window toolbar
        if let toolbar = window.toolbar {
            for (idx, item) in toolbar.items.enumerated().reversed() {
                if item.itemIdentifier == .toggleSidebar || item.itemIdentifier.rawValue.localizedCaseInsensitiveContains("toggleSidebar") || item.itemIdentifier.rawValue.localizedCaseInsensitiveContains("sidebarToggle") {
                    toolbar.removeItem(at: idx)
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
    
    private func hideSidebarToggleButtons(in view: NSView) {
        if let btn = view as? NSButton {
            let actionName = btn.action.map { NSStringFromSelector($0) } ?? ""
            let tooltip = btn.toolTip ?? ""
            let accessibility = btn.accessibilityLabel() ?? ""
            if actionName.localizedCaseInsensitiveContains("toggleSidebar") ||
               tooltip.localizedCaseInsensitiveContains("sidebar") ||
               accessibility.localizedCaseInsensitiveContains("sidebar") {
                btn.isHidden = true
                btn.alphaValue = 0.0
                btn.frame = .zero
                btn.isEnabled = false
            }
        }
        for sub in view.subviews {
            hideSidebarToggleButtons(in: sub)
        }
    }
    
    private func configureSplitViews(in view: NSView, isRoot: Bool = true) {
        if let splitView = view as? NSSplitView, splitView.isVertical, splitView.subviews.count >= 2 {
            if let controller = splitView.delegate as? NSSplitViewController {
                // When NSSplitView is managed by an NSSplitViewController, setting holding priorities
                // directly on the NSSplitView throws an NSInternalInconsistencyException.
                // We must configure holdingPriority on NSSplitViewItem instead.
                if controller.splitViewItems.count >= 2 {
                    if isRoot {
                        controller.splitViewItems[0].holdingPriority = .defaultHigh
                        controller.splitViewItems[0].canCollapse = false
                        controller.splitViewItems[0].isCollapsed = false
                        controller.splitViewItems[0].minimumThickness = 260
                        controller.splitViewItems[0].maximumThickness = 260
                        controller.splitViewItems[1].holdingPriority = .defaultLow
                        
                        for sub in splitView.subviews {
                            configureSplitViews(in: sub, isRoot: false)
                        }
                        return
                    } else {
                        controller.splitViewItems[0].holdingPriority = .defaultLow
                        controller.splitViewItems[1].holdingPriority = .defaultHigh
                    }
                }
            } else {
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
        }
        for sub in view.subviews {
            configureSplitViews(in: sub, isRoot: isRoot)
        }
    }
    
    private func setupTrafficLightsScaler(for window: NSWindow) {
        TrafficLightsScaler.setup(for: window)
    }
}

@main
struct WalkmanStudioApp: App {
    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOfFile: iconURL.path) {
            NSApplication.shared.applicationIconImage = img
        } else if let fallback = NSImage(contentsOfFile: "assets/icon.png") {
            NSApplication.shared.applicationIconImage = fallback
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1200, idealWidth: 1360, minHeight: 660, idealHeight: 820)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1360, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Walkman Studio") {
                    NotificationCenter.default.post(name: .showAboutWalkmanStudio, object: nil)
                }
                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: .checkForUpdates, object: nil)
                }
                Divider()
                Button("Manage Local Folders...") {
                    NotificationCenter.default.post(name: .manageLocalFolders, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {
                Button("Manage Local Folders...") {
                    NotificationCenter.default.post(name: .manageLocalFolders, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Traffic Light Buttons Scaler
private final class TrafficLightsScalerAnchorView: NSView {
    var scaler: TrafficLightsScaler?
}

private final class TrafficLightsScaler: NSObject {
    private weak var window: NSWindow?
    private var observers: [Any] = []

    static func setup(for window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let superview = close.superview else { return }

        superview.postsFrameChangedNotifications = true

        if let existing = superview.subviews.first(where: { $0 is TrafficLightsScalerAnchorView }) as? TrafficLightsScalerAnchorView {
            existing.scaler?.apply()
            return
        }

        let anchor = TrafficLightsScalerAnchorView(frame: .zero)
        anchor.isHidden = true
        superview.addSubview(anchor)

        let scaler = TrafficLightsScaler(window: window)
        anchor.scaler = scaler
        scaler.apply()

        DispatchQueue.main.async {
            scaler.apply()
        }
    }

    init(window: NSWindow) {
        self.window = window
        super.init()

        guard let close = window.standardWindowButton(.closeButton),
              let superview = close.superview else { return }

        let notif1 = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: superview,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.apply()
            }
        }
        observers.append(notif1)

        let notif2 = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.apply()
            }
        }
        observers.append(notif2)

        let notif3 = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.apply()
            }
        }
        observers.append(notif3)
    }

    deinit {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func apply() {
        guard let window = self.window,
              !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              close.superview != nil else { return }

        // Scales traffic light buttons from standard 12pt diameter up to ~15.6pt (+30% larger)
        // with comfortable 24pt center-to-center spacing.
        let scale: CGFloat = 1.30
        let spacing: CGFloat = 24.0
        let startX: CGFloat = 11.0
        let midY = round(close.frame.midY)
        let btnH: CGFloat = 14.0
        let btnW: CGFloat = 14.0
        let originY = round(midY - (btnH / 2.0))

        let buttons = [close, mini, zoom]
        for (i, btn) in buttons.enumerated() {
            btn.wantsLayer = true
            btn.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            btn.layer?.transform = CATransform3DMakeScale(scale, scale, 1.0)

            let x = startX + (CGFloat(i) * spacing)
            let newFrame = NSRect(x: x, y: originY, width: btnW, height: btnH)
            if btn.frame != newFrame {
                btn.frame = newFrame
            }
        }
    }
}
