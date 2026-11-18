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
            setupTrafficLightsLiquidGlassPill(for: window)
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
    
    private func setupTrafficLightsLiquidGlassPill(for window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              window.standardWindowButton(.zoomButton) != nil,
              let superview = close.superview else { return }
        
        superview.postsFrameChangedNotifications = true
        
        if let existing = superview.subviews.first(where: { $0.identifier?.rawValue == "TrafficLightLiquidGlassPill" }) as? TrafficLightLiquidGlassPillView {
            existing.updatePillFrame()
            return
        }
        
        let pill = TrafficLightLiquidGlassPillView()
        pill.identifier = NSUserInterfaceItemIdentifier("TrafficLightLiquidGlassPill")
        superview.addSubview(pill, positioned: .below, relativeTo: close)
        pill.updatePillFrame()
        
        DispatchQueue.main.async {
            pill.updatePillFrame()
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

// MARK: - Traffic Light Liquid Glass Capsule Pill View
private final class TrafficLightLiquidGlassPillView: NSView {
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?
    private var observers: [Any] = []
    private var localMouseMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        clearObservers()
        guard let superview = self.superview else { return }

        superview.postsFrameChangedNotifications = true
        let obs = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: superview,
            queue: .main
        ) { [weak self] _ in
            self?.updatePillFrame()
        }
        observers.append(obs)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let existing = localMouseMonitor {
            NSEvent.removeMonitor(existing)
            localMouseMonitor = nil
        }
        
        guard let window = self.window else { return }

        let notifs = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        for n in notifs {
            let obs = NotificationCenter.default.addObserver(
                forName: n,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.updatePillFrame()
                self?.needsDisplay = true
            }
            observers.append(obs)
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self = self else { return event }
            let local = self.convert(event.locationInWindow, from: nil)
            self.setHovered(self.bounds.contains(local))
            return event
        }

        updatePillFrame()
    }

    deinit {
        clearObservers()
    }

    private func clearObservers() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
        
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    func updatePillFrame() {
        guard let window = self.window,
              let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              close.superview === self.superview else { return }

        if window.styleMask.contains(.fullScreen) {
            if !self.isHidden {
                self.isHidden = true
            }
            return
        }

        if self.isHidden {
            self.isHidden = false
        }

        // Standard macOS traffic light dots are 12pt diameter centered inside 14pt frames.
        // We pad 8.0pt left/right from the outer circle edges and 7.0pt top/bottom,
        // resulting in a perfectly balanced 26pt-height capsule pill (13pt corner radius).
        let dotLeft = close.frame.minX + 1.0
        let dotRight = zoom.frame.maxX - 1.0
        let dotSpan = dotRight - dotLeft
        let horizontalPadding: CGFloat = 8.0
        let pillHeight: CGFloat = 26.0

        let minX = round(dotLeft - horizontalPadding)
        let width = round(dotSpan + (horizontalPadding * 2))
        let midY = close.frame.midY
        let minY = round(midY - (pillHeight / 2.0))

        let newFrame = NSRect(x: minX, y: minY, width: width, height: pillHeight)
        if self.frame != newFrame {
            self.frame = newFrame
            self.needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let local = self.convert(event.locationInWindow, from: nil)
        if !self.bounds.contains(local) {
            setHovered(false)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let local = self.convert(event.locationInWindow, from: nil)
        setHovered(self.bounds.contains(local))
    }

    private func setHovered(_ hovered: Bool) {
        if isHovered != hovered {
            isHovered = hovered
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let cornerRadius = bounds.height / 2.0
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        let isKey = window?.isKeyWindow ?? true

        // 1. Sleek Graphite / Slate 3-Stop Gradient Fill (exact match for reference screenshot)
        let topColor = isHovered ?
            NSColor(red: 173/255, green: 173/255, blue: 174/255, alpha: 0.98) :
            NSColor(red: 128/255, green: 128/255, blue: 130/255, alpha: 0.96)

        let midColor = isHovered ?
            NSColor(red: 95/255, green: 96/255, blue: 98/255, alpha: 0.98) :
            NSColor(red: 62/255, green: 63/255, blue: 66/255, alpha: 0.96)

        let botColor = isHovered ?
            NSColor(red: 71/255, green: 71/255, blue: 74/255, alpha: 0.98) :
            NSColor(red: 46/255, green: 47/255, blue: 50/255, alpha: 0.98)

        let cTop = isKey ? topColor : (topColor.blended(withFraction: 0.40, of: .darkGray) ?? topColor)
        let cMid = isKey ? midColor : (midColor.blended(withFraction: 0.40, of: .darkGray) ?? midColor)
        let cBot = isKey ? botColor : (botColor.blended(withFraction: 0.40, of: .darkGray) ?? botColor)

        let fillGradient = NSGradient(
            colorsAndLocations:
                (cTop, 0.0),
                (cMid, 0.45),
                (cBot, 1.0)
        )
        fillGradient?.draw(in: path, angle: 270)

        // 2. Subtle 1px Highlight Rim / Border
        let strokePath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius - 0.5,
            yRadius: cornerRadius - 0.5
        )
        strokePath.lineWidth = 1.0

        let strokeTop = isHovered ?
            NSColor(white: 1.0, alpha: 0.35) :
            NSColor(white: 1.0, alpha: 0.22)

        let strokeBot = isHovered ?
            NSColor(white: 0.0, alpha: 0.30) :
            NSColor(white: 0.0, alpha: 0.45)

        let strokeGradient = NSGradient(
            colorsAndLocations:
                (isKey ? strokeTop : strokeTop.withAlphaComponent(0.10), 0.0),
                (NSColor(white: 0.5, alpha: 0.08), 0.45),
                (isKey ? strokeBot : strokeBot.withAlphaComponent(0.20), 1.0)
        )
        strokeGradient?.draw(in: strokePath, angle: 270)
    }
}
