import SwiftUI

enum ThemeStyle: String, Codable, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case night = "night"
}

extension Color {
    // Ported Tailwind Colors
    static let plGray50 = Color(red: 0.98, green: 0.98, blue: 0.99)
    static let plGray100 = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let plGray200 = Color(red: 0.90, green: 0.91, blue: 0.93)
    static let plGray300 = Color(red: 0.82, green: 0.84, blue: 0.86)
    static let plGray400 = Color(red: 0.61, green: 0.64, blue: 0.69)
    static let plGray500 = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let plGray700 = Color(red: 0.22, green: 0.24, blue: 0.27)
    static let plGray800 = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let plGray900 = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let plGray950 = Color(red: 0.05, green: 0.06, blue: 0.07)
    
    // Core brand accents
    static let plBlue = Color(red: 0.23, green: 0.51, blue: 0.96) // #3b82f6
    static let plRed = Color(red: 0.94, green: 0.27, blue: 0.27) // #ef4444
    static let plGreen = Color(red: 0.06, green: 0.73, blue: 0.51) // #10b981
    static let plPurple = Color(red: 0.55, green: 0.36, blue: 0.96) // #8b5cf6
    static let plTeal = Color(red: 0.08, green: 0.72, blue: 0.65) // #14b8a6
    
    // Hex string initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct BrandColors {
    var theme: ThemeStyle
    
    var isNight: Bool { theme == .night }
    
    var red: Color { isNight ? .plGray300 : .plRed }
    var blue: Color { isNight ? .white : .plBlue }
    var green: Color { isNight ? .plGray400 : .plGreen }
    var purple: Color { isNight ? .plGray300 : .plPurple }
    var teal: Color { isNight ? .plGray200 : .plTeal }
    
    var whiteText: Color {
        switch theme {
        case .light:
            return .plGray950
        case .night:
            return .plGray300
        case .dark:
            return .white
        case .system:
            return .primary
        }
    }
    var timerBackground: Color { isNight ? .plGray800 : .plBlue }
    var darkBgText: Color { isNight ? .plGray300 : .white }
}

struct ThemeBackgroundModifier: ViewModifier {
    var style: ThemeStyle
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(backgroundColor.edgesIgnoringSafeArea(.all))
    }
    
    private var backgroundColor: Color {
        switch style {
        case .light:
            return .plGray50
        case .dark:
            return .plGray950
        case .night:
            return .black
        case .system:
            return colorScheme == .dark ? .plGray950 : .plGray50
        }
    }
}

struct GlassCardModifier: ViewModifier {
    var style: ThemeStyle
    var accentColor: Color? = nil
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(cardBackgroundColor)
            .cornerRadius(24)
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(borderColor, lineWidth: 1.5)
            )
    }
    
    private var isDark: Bool {
        switch style {
        case .light: return false
        case .dark, .night: return true
        case .system: return colorScheme == .dark
        }
    }
    
    private var isNight: Bool {
        switch style {
        case .night: return true
        case .system, .light, .dark: return false
        }
    }
    
    private var cardBackgroundColor: Color {
        if isNight {
            return Color(red: 0.05, green: 0.06, blue: 0.07) // #0d0e11
        }
        if isDark {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(0.85)
    }
    
    private var borderColor: Color {
        if isNight {
            return Color(red: 0.18, green: 0.19, blue: 0.21) // #2e3035
        }
        if isDark {
            return Color.white.opacity(0.12)
        }
        return Color.black.opacity(0.06)
    }
    
    private var shadowColor: Color {
        if isNight {
            return Color.black.opacity(0.95)
        }
        return Color.black.opacity(0.04)
    }
    
    private var shadowRadius: CGFloat { isNight ? 24 : 12 }
    private var shadowY: CGFloat { isNight ? 12 : 6 }
}

extension View {
    func plBackground(style: ThemeStyle) -> some View {
        self.modifier(ThemeBackgroundModifier(style: style))
    }
    
    func glassCard(style: ThemeStyle, accentColor: Color? = nil) -> some View {
        self.modifier(GlassCardModifier(style: style, accentColor: accentColor))
    }
}
