import SwiftUI
import AppKit

public enum WalkmanTheme {
    // Sony Walkman NW-A55 Ash Grey & Silver Palette
    public static let silver = Color(red: 220 / 255, green: 224 / 255, blue: 232 / 255) // #DCE0E8 Minimal Crisp Silver
    public static let silverLight = Color(red: 242 / 255, green: 244 / 255, blue: 248 / 255) // #F2F4F8 Clean Platinum
    public static let silverMuted = Color(red: 155 / 255, green: 160 / 255, blue: 172 / 255) // #9BA0AC Brushed Aluminum Grey
    public static let silverDark = Color(red: 95 / 255, green: 100 / 255, blue: 112 / 255) // #5F6470 Graphite Accent
    
    // Direct Silver Aliases (Eliminates yellow/gold across the entire system)
    public static let gold = silver
    public static let brass = silverMuted
    public static let goldLight = silverLight
    public static let goldGlow = Color.clear // Zero glow

    // Obsidian & Slate Surface Palette
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

public struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var borderOpacity: Double = 0.35
    var hasGoldGlow: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(WalkmanTheme.card.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(borderOpacity * 0.3), lineWidth: 1)
            )
            // Clean, minimal shadow without any colored glow
            .shadow(
                color: Color.black.opacity(0.18),
                radius: 4,
                x: 0,
                y: 2
            )
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 12, borderOpacity: Double = 0.35, hasGoldGlow: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity, hasGoldGlow: false))
    }
}
