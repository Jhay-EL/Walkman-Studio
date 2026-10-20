import SwiftUI
import AppKit

public enum WalkmanTheme {
    // Sony Walkman Signature Series Gold Accents
    public static let gold = Color(red: 212 / 255, green: 175 / 255, blue: 55 / 255) // #D4AF37
    public static let brass = Color(red: 197 / 255, green: 160 / 255, blue: 89 / 255) // #C5A059
    public static let goldLight = Color(red: 243 / 255, green: 229 / 255, blue: 171 / 255) // #F3E5AB
    public static let goldGlow = Color(red: 212 / 255, green: 175 / 255, blue: 55 / 255).opacity(0.18)

    // Obsidian Palette & macOS Dynamic Materials
    public static let obsidian = Color(red: 12 / 255, green: 12 / 255, blue: 15 / 255)
    public static let background = obsidian
    public static let card = Color(red: 22 / 255, green: 22 / 255, blue: 26 / 255)
    public static let surface = card
    public static let cardHover = Color(red: 30 / 255, green: 30 / 255, blue: 36 / 255)
    public static let border = Color.white.opacity(0.08)
    public static let input = Color(red: 26 / 255, green: 26 / 255, blue: 32 / 255)

    // Gradients
    public static let goldGradient = LinearGradient(
        colors: [Color(red: 235 / 255, green: 185 / 255, blue: 55 / 255), Color(red: 195 / 255, green: 145 / 255, blue: 30 / 255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let storageGradient = LinearGradient(
        colors: [brass, gold],
        startPoint: .leading,
        endPoint: .trailing
    )
}

public struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var borderOpacity: Double = 0.35
    var hasGoldGlow: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(WalkmanTheme.card.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        hasGoldGlow
                            ? WalkmanTheme.gold.opacity(0.5)
                            : Color.white.opacity(borderOpacity * 0.4),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: hasGoldGlow ? WalkmanTheme.gold.opacity(0.12) : Color.black.opacity(0.2),
                radius: hasGoldGlow ? 10 : 5,
                x: 0,
                y: 2
            )
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 12, borderOpacity: Double = 0.35, hasGoldGlow: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity, hasGoldGlow: hasGoldGlow))
    }
}
