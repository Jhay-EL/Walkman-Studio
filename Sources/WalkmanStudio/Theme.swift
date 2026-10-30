import SwiftUI
import AppKit

// =============================================================================
// WALKMAN STUDIO DESIGN SYSTEM LANGUAGE
//
// Core Principles:
// 1. Zero Background Gradients:
//    All main backdrops, sidebars, panels, and view containers use pure, solid
//    matte obsidian (#101114) and dark card surfaces (#18191D). Ambient gradient
//    washes, atmospheric caustics, and background gradients are strictly avoided.
// 2. Zero Glow / Bloom Effects:
//    No colored luminescence, neon aura, or glowing shadows. The interface
//    embraces the authentic, tactile industrial design of Sony Walkman hardware
//    (brushed aluminum, matte finishes, crisp borders).
// 3. Tactile Physical Depth:
//    Spatial depth is achieved exclusively through subtle, neutral black drop
//    shadows (Color.black) and crisp, precise physical borders.
// =============================================================================

public enum WalkmanTheme {
    // Sony Walkman NW-A55 Ash Grey & Silver Palette
    public static let silver = Color(red: 220 / 255, green: 224 / 255, blue: 232 / 255) // #DCE0E8 Minimal Crisp Silver
    public static let silverLight = Color(red: 242 / 255, green: 244 / 255, blue: 248 / 255) // #F2F4F8 Clean Platinum
    public static let silverMuted = Color(red: 155 / 255, green: 160 / 255, blue: 172 / 255) // #9BA0AC Brushed Aluminum Grey
    public static let silverDark = Color(red: 95 / 255, green: 100 / 255, blue: 112 / 255) // #5F6470 Graphite Accent
    
    // Authentic Sony Hi-Res Audio Gold Palette
    public static let hiResGold = Color(red: 232 / 255, green: 185 / 255, blue: 68 / 255) // #E8B944 Classic Sony Hi-Res Gold
    public static let hiResGoldLight = Color(red: 248 / 255, green: 212 / 255, blue: 112 / 255) // #F8D470 Highlight
    public static let hiResGoldDark = Color(red: 196 / 255, green: 148 / 255, blue: 38 / 255) // #C49426 Shadow
    public static let hiResGoldGradient = LinearGradient(
        colors: [hiResGoldLight, hiResGoldDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Direct Silver Aliases
    public static let gold = hiResGold
    public static let brass = silverMuted
    public static let goldLight = hiResGoldLight
    // Deprecated glow alias: design system strictly enforces zero glow
    public static let goldGlow = Color.clear

    // Obsidian & Slate Surface Palette (Clean, Flat, Non-Gradient Solids)
    public static let obsidian = Color(red: 16 / 255, green: 17 / 255, blue: 20 / 255) // #101114 Deep matte body
    public static let background = obsidian
    public static let card = Color(red: 24 / 255, green: 25 / 255, blue: 29 / 255) // #18191D Minimal card
    public static let surface = card
    public static let cardHover = Color(red: 32 / 255, green: 33 / 255, blue: 38 / 255)
    public static let border = Color.white.opacity(0.08)
    public static let input = Color(red: 20 / 255, green: 21 / 255, blue: 25 / 255)

    // Brushed Silver & Aluminium Gradients (No Glow, Clean & Tactile)
    public static let silverGradient = LinearGradient(
        colors: [Color(white: 0.90), Color(white: 0.78)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let goldGradient = silverGradient // Alias

    public static let storageGradient = LinearGradient(
        colors: [Color(white: 0.60), Color(white: 0.85)],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    public static let cardHeaderGradient = LinearGradient(
        colors: [Color(white: 0.24), Color(white: 0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public enum WalkmanFont {
    // Large & Section Headings
    public static let title1 = Font.system(size: 22, weight: .bold)
    public static let title2 = Font.system(size: 18, weight: .bold)
    public static let title = title2
    public static let title3 = Font.system(size: 15, weight: .semibold)
    public static let headline = Font.system(size: 14, weight: .semibold)

    // Primary Body Text (macOS standard 13pt)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let bodyMedium = Font.system(size: 13, weight: .medium)
    public static let bodyBold = Font.system(size: 13, weight: .semibold)

    // Secondary & Callouts
    public static let callout = Font.system(size: 12, weight: .regular)
    public static let calloutMedium = Font.system(size: 12, weight: .medium)
    public static let calloutBold = Font.system(size: 12, weight: .semibold)

    // Subheadlines & Captions
    public static let subheadline = Font.system(size: 11.5, weight: .regular)
    public static let subheadlineMedium = Font.system(size: 11.5, weight: .medium)
    public static let subheadlineBold = Font.system(size: 11.5, weight: .bold)
    public static let caption = Font.system(size: 11, weight: .regular)
    public static let captionBold = Font.system(size: 11, weight: .bold)
    public static let sectionHeader = Font.system(size: 11, weight: .bold)

    // Monospaced Audio Metadata & Timestamps
    public static let mono = Font.system(size: 11.5, design: .monospaced)
    public static let monoSmall = Font.system(size: 10.5, design: .monospaced)

    // Compact Badges & Hardware Indicators
    public static let badge = Font.system(size: 9.5, weight: .bold, design: .monospaced)
    public static let pillCounter = Font.system(size: 10, weight: .bold, design: .rounded)
}

public struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var borderOpacity: Double = 0.35
    var hasGoldGlow: Bool = false // Deprecated: design system enforces zero glow
    var isSelected: Bool = false
    var isHovered: Bool = false
    var tint: Color? = nil

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(
                ZStack {
                    WalkmanTheme.card.opacity(0.68)
                    if let tint = tint {
                        tint.opacity(0.12)
                    }
                    if isSelected {
                        Color.white.opacity(0.04)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // Clean tactile physical rim (No glow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? WalkmanTheme.silverLight.opacity(borderOpacity * 0.95) : Color.white.opacity(borderOpacity * (isHovered ? 0.35 : 0.20)),
                        lineWidth: isSelected ? 1.5 : 1.0
                    )
                    .allowsHitTesting(false)
            )
            // Multi-depth soft spatial shadow (Neutral tactile depth only - NO GLOW)
            .shadow(
                color: Color.black.opacity(0.24),
                radius: isHovered ? 10 : 6,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .shadow(
                color: Color.black.opacity(0.12),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 12,
        borderOpacity: Double = 0.35,
        hasGoldGlow: Bool = false,
        isSelected: Bool = false,
        isHovered: Bool = false,
        tint: Color? = nil
    ) -> some View {
        self.modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            borderOpacity: borderOpacity,
            hasGoldGlow: hasGoldGlow,
            isSelected: isSelected,
            isHovered: isHovered,
            tint: tint
        ))
    }

    func studioGlassCard(cornerRadius: CGFloat = 14) -> some View {
        self.modifier(StudioGlassCardModifier(cornerRadius: cornerRadius))
    }

    func modalGlassChassis(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(ModalGlassChassisModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Studio Glass Card Modifier (§5)
public struct StudioGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14

    public init(cornerRadius: CGFloat = 14) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    WalkmanTheme.card.opacity(0.85)
                        .background(.ultraThinMaterial)

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.16), location: 0.0),
                                .init(color: Color.white.opacity(0.03), location: 0.5),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 8)
                        Spacer(minLength: 0)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.24), location: 0.0),
                                .init(color: Color.white.opacity(0.10), location: 0.5),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Modal Glass Chassis Modifier (§9)
public struct ModalGlassChassisModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    WalkmanTheme.card.opacity(0.92)
                        .background(.ultraThinMaterial)

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.24), location: 0.0),
                                .init(color: Color.white.opacity(0.05), location: 0.5),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 10)
                        Spacer(minLength: 0)
                    }
                }
                .ignoresSafeArea()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.35), location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.5),
                                .init(color: Color.white.opacity(0.06), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 28, x: 0, y: 12)
    }
}

public struct LiquidGlassButtonStyle: ButtonStyle {
    public enum Variant {
        case prominent   // Crisp silver/platinum glass
        case gold        // Authentic Hi-Res gold glass
        case glass       // Translucent clear liquid glass
        case capsule     // Pill-shaped translucent glass
        case subtle      // Subtle low-contrast frosted glass
        case destructive // Red-tinted warning/delete liquid glass
    }
    
    public var variant: Variant
    public var cornerRadius: CGFloat
    
    public init(variant: Variant = .prominent, cornerRadius: CGFloat = 8) {
        self.variant = variant
        self.cornerRadius = cornerRadius
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonBody(
            configuration: configuration,
            variant: variant,
            cornerRadius: cornerRadius
        )
    }
    
    private struct LiquidGlassButtonBody: View {
        let configuration: Configuration
        let variant: Variant
        let cornerRadius: CGFloat
        @State private var isHovered = false
        
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.955 : (isHovered ? 1.02 : 1.0))
                .opacity(configuration.isPressed ? 0.85 : 1.0)
                .background(
                    ZStack {
                        switch variant {
                        case .prominent:
                            LinearGradient(
                                stops: [
                                    .init(color: Color(red: 245/255, green: 247/255, blue: 252/255), location: 0.0),
                                    .init(color: Color(red: 215/255, green: 220/255, blue: 230/255), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        case .gold:
                            WalkmanTheme.hiResGoldGradient
                        case .glass, .capsule:
                            Color.white.opacity(isHovered ? 0.14 : 0.08)
                        case .subtle:
                            Color.white.opacity(isHovered ? 0.10 : 0.05)
                        case .destructive:
                            Color.red.opacity(isHovered ? 0.22 : 0.12)
                        }
                        
                        // Surface optical liquid gloss (top specular reflection)
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(variant == .prominent ? 0.65 : (variant == .destructive ? 0.28 : 0.35)), location: 0.0),
                                    .init(color: Color.white.opacity(0.0), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 12)
                            Spacer(minLength: 0)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            variant == .destructive ?
                            LinearGradient(
                                stops: [
                                    .init(color: Color.red.opacity(isHovered ? 0.55 : 0.30), location: 0.0),
                                    .init(color: Color.red.opacity(isHovered ? 0.25 : 0.10), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isHovered ? 0.60 : 0.38), location: 0.0),
                                    .init(color: Color.white.opacity(isHovered ? 0.28 : 0.14), location: 0.5),
                                    .init(color: Color.white.opacity(0.05), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                )
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.25 : 0.14),
                    radius: isHovered ? 6 : 3,
                    x: 0,
                    y: isHovered ? 3 : 1.5
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.025 : 1.0))
                .animation(.spring(response: 0.22, dampingFraction: 0.70), value: configuration.isPressed)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { hovering in
                    guard isHovered != hovering else { return }
                    isHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onDisappear {
                    if isHovered {
                        isHovered = false
                        NSCursor.pop()
                    }
                }
        }
    }
}

public struct WalkmanPressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

public struct WalkmanSideActionButtonStyle: ButtonStyle {
    public var isFullWidth: Bool
    public var cornerRadius: CGFloat

    public init(isFullWidth: Bool = false, cornerRadius: CGFloat = 6) {
        self.isFullWidth = isFullWidth
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        WalkmanSideActionButton(
            configuration: configuration,
            isFullWidth: isFullWidth,
            cornerRadius: cornerRadius
        )
    }

    private struct WalkmanSideActionButton: View {
        let configuration: Configuration
        let isFullWidth: Bool
        let cornerRadius: CGFloat
        @State private var isHovered: Bool = false

        var body: some View {
            configuration.label
                .frame(maxWidth: isFullWidth ? .infinity : nil)
                // Minimal & simple click animation (scale down on press, bounce back on release)
                .scaleEffect(configuration.isPressed ? 0.95 : (isHovered ? 1.015 : 1.0))
                .opacity(configuration.isPressed ? 0.82 : 1.0)
                // Minimal & simple hover effect (brighten slightly + crisp border glow)
                .brightness(isHovered ? 0.08 : 0.0)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.35 : 0.0), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.28 : 0.12),
                    radius: isHovered ? 6 : 2,
                    x: 0,
                    y: isHovered ? 2 : 1
                )
                .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.14), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { hovering in
                    guard isHovered != hovering else { return }
                    isHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onDisappear {
                    if isHovered {
                        isHovered = false
                        NSCursor.pop()
                    }
                }
        }
    }
}

// =============================================================================
// TABLE VIEW BOTTOM SCROLL INSET MODIFIER
// Ensures NSTableView in SwiftUI Table extends edge-to-edge behind floating
// player containers while preserving bottom padding so the final rows and
// scrollers are never obstructed.
// =============================================================================

public struct TableScrollInsetModifier: NSViewRepresentable {
    public var bottomInset: CGFloat = 88
    
    public init(bottomInset: CGFloat = 88) {
        self.bottomInset = bottomInset
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async { [weak view] in
            guard let view = view else { return }
            applyInset(from: view)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView = nsView else { return }
            applyInset(from: nsView)
        }
    }

    private func applyInset(from view: NSView) {
        var current: NSView? = view
        var attempts = 0
        while let c = current, attempts < 10 {
            if let tableView = findTableView(in: c), let scrollView = tableView.enclosingScrollView {
                scrollView.automaticallyAdjustsContentInsets = false
                if scrollView.contentInsets.bottom != bottomInset {
                    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
                }
                if scrollView.scrollerInsets.bottom != bottomInset {
                    scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
                }
                return
            }
            current = c.superview
            attempts += 1
        }
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let tv = view as? NSTableView {
            return tv
        }
        for sub in view.subviews {
            if let tv = findTableView(in: sub) {
                return tv
            }
        }
        return nil
    }
}

public extension View {
    func tableScrollBottomInset(_ inset: CGFloat = 88) -> some View {
        self.background(TableScrollInsetModifier(bottomInset: inset))
    }

    @_disfavoredOverload
    @ViewBuilder
    func onChange<V: Equatable>(of value: V, _ action: @escaping () -> Void) -> some View {
        self.onChange(of: value) { _ in
            action()
        }
    }

    @_disfavoredOverload
    @ViewBuilder
    func onChange<V: Equatable>(of value: V, _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        self.onChange(of: value) { newValue in
            action(newValue, newValue)
        }
    }
}

// MARK: - Liquid Glass Segmented Pill Backgrounds
public struct LiquidGlassActivePill: View {
    public let isHiRes: Bool
    public let isHovered: Bool
    
    public init(isHiRes: Bool = false, isHovered: Bool = false) {
        self.isHiRes = isHiRes
        self.isHovered = isHovered
    }
    
    public var body: some View {
        ZStack {
            // Liquid Glass Translucent Body Fill
            Color.white.opacity(isHiRes ? 0.13 : 0.16)
            
            // Top specular refraction sheen
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isHovered ? 0.42 : 0.35), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isHiRes ? WalkmanTheme.hiResGold.opacity(0.55) : Color.white.opacity(isHovered ? 0.45 : 0.34),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 3,
            x: 0,
            y: 1
        )
    }
}

public struct LiquidGlassHoverPill: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.white.opacity(0.09)
            
            // Subtle specular refraction on top edge
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.20), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5.5)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.85)
        )
        .shadow(
            color: Color.black.opacity(0.15),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Hi-Res Badge
public struct HiResBadge: View {
    public init() {}
    public var body: some View {
        Text("HR")
            .font(.system(size: 8.5, weight: .black, design: .serif))
            .foregroundStyle(.black)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(WalkmanTheme.hiResGoldGradient)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

// MARK: - Liquid Glass Icon Badge (§9)
public struct LiquidGlassIconBadge: View {
    public let icon: String
    public var size: CGFloat = 32
    public var cornerRadius: CGFloat = 9

    public init(icon: String, size: CGFloat = 32, cornerRadius: CGFloat = 9) {
        self.icon = icon
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.28), location: 0.0),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size * 0.32)
                Spacer(minLength: 0)
            }

            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.38), location: 0.0),
                            .init(color: Color.white.opacity(0.12), location: 0.5),
                            .init(color: Color.white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 3, y: 1.5)
    }
}
