import SwiftUI
import AppKit

/// A responsive, animated search bar wrapped in Walkman Studio's Liquid Glass styling.
/// When idle, it rests as a 38x38 pt circular liquid glass button with a magnifying glass icon.
/// When clicked, it smoothly expands with spring physics into a rounded pill/capsule search bar with text input and clear button.
/// When the user clicks outside the search bar or presses Escape, it shrinks back into the circular icon.
/// If an active query is present while collapsed, a gold accent indicator dot is shown and the query filter is preserved.
public struct ExpandableLiquidGlassSearchBar: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    let placeholder: String
    var expandedWidth: CGFloat = 220
    var helpText: String = "Search"
    
    @FocusState private var isFieldFocused: Bool
    @State private var isHovered: Bool = false
    
    public init(
        text: Binding<String>,
        isExpanded: Binding<Bool>,
        placeholder: String,
        expandedWidth: CGFloat = 220,
        helpText: String = "Search"
    ) {
        self._text = text
        self._isExpanded = isExpanded
        self.placeholder = placeholder
        self.expandedWidth = expandedWidth
        self.helpText = helpText
    }
    
    public var body: some View {
        HStack(spacing: isExpanded ? 6 : 0) {
            // Magnifying glass icon (clickable button)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        isFieldFocused = false
                    }
                }
                if isExpanded {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        isFieldFocused = true
                    }
                }
            } label: {
                ZStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            !text.isEmpty
                            ? WalkmanTheme.hiResGoldLight
                            : (isExpanded && isFieldFocused
                               ? WalkmanTheme.silverLight
                               : (isHovered ? .white : WalkmanTheme.silverMuted))
                        )
                        .frame(width: 24, height: 24)
                    
                    // Subtle glowing gold dot when collapsed with an active query
                    if !isExpanded && !text.isEmpty {
                        Circle()
                            .fill(WalkmanTheme.hiResGold)
                            .frame(width: 5.5, height: 5.5)
                            .shadow(color: WalkmanTheme.hiResGold.opacity(0.8), radius: 2)
                            .offset(x: 8, y: -7)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                !isExpanded && !text.isEmpty
                ? "Active search: \"\(text)\" (Click to expand or edit)"
                : (isExpanded ? "Search" : helpText)
            )
            
            // Text field and clear button revealed upon expansion
            if isExpanded {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($isFieldFocused)
                    .onExitCommand {
                        if !text.isEmpty {
                            text = ""
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                                isExpanded = false
                                isFieldFocused = false
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                
                if !text.isEmpty {
                    Button {
                        text = ""
                        isFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .padding(.horizontal, isExpanded ? 10 : 7)
        .frame(width: isExpanded ? expandedWidth : 38, height: 38)
        .background(
            OutsideClickDetector(isExpanded: isExpanded) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    isExpanded = false
                    isFieldFocused = false
                }
            }
        )
        .background(
            ZStack {
                Color.white.opacity(isHovered ? 0.12 : (isExpanded ? 0.08 : 0.06))
                    .background(.ultraThinMaterial.opacity(0.35))
                
                // Top optical specular sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.22 : 0.14), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity((isFieldFocused || !text.isEmpty) ? 0.45 : (isHovered ? 0.30 : 0.16)), location: 0.0),
                            .init(color: Color.white.opacity((isFieldFocused || !text.isEmpty) ? 0.25 : 0.10), location: 0.5),
                            .init(color: Color.white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 2.5, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
            if hovering && !isExpanded {
                NSCursor.pointingHand.push()
            } else if !hovering {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered && !isExpanded {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Outside Click Tracking
private struct OutsideClickDetector: NSViewRepresentable {
    let isExpanded: Bool
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> OutsideClickTrackingNSView {
        let view = OutsideClickTrackingNSView()
        view.onOutsideClick = onOutsideClick
        view.isExpanded = isExpanded
        return view
    }

    func updateNSView(_ nsView: OutsideClickTrackingNSView, context: Context) {
        nsView.onOutsideClick = onOutsideClick
        nsView.isExpanded = isExpanded
    }
}

private final class OutsideClickTrackingNSView: NSView {
    var onOutsideClick: (() -> Void)?
    var isExpanded: Bool = false {
        didSet {
            if isExpanded != oldValue {
                updateMonitor()
            }
        }
    }
    
    private var eventMonitor: Any?

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Transparent to all mouse hit testing so underlying and sibling views receive events naturally
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    private func updateMonitor() {
        if window != nil && isExpanded {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isExpanded, let currentWindow = self.window else {
                return event
            }
            
            if let eventWindow = event.window, eventWindow == currentWindow {
                let locationInView = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(locationInView) {
                    DispatchQueue.main.async {
                        self.onOutsideClick?()
                    }
                }
            } else {
                // Clicked in a separate sheet, popover, or window
                DispatchQueue.main.async {
                    self.onOutsideClick?()
                }
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
