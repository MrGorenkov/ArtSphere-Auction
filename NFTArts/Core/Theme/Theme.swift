import SwiftUI

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    @AppStorage("appTheme") var selectedTheme: AppTheme = .system

    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }

        var iconName: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }
    }
}

// MARK: - Color Palette

extension Color {
    // Brand colors
    static let nftPrimary = Color("NFTPrimary")
    static let nftSecondary = Color("NFTSecondary")
    static let nftAccent = Color("NFTAccent")

    // Fallback programmatic colors
    static let nftPurple = Color(red: 0.55, green: 0.27, blue: 0.96)
    static let nftBlue = Color(red: 0.24, green: 0.47, blue: 0.96)
    static let nftPink = Color(red: 0.93, green: 0.27, blue: 0.63)
    static let nftGreen = Color(red: 0.18, green: 0.84, blue: 0.55)
    static let nftOrange = Color(red: 1.0, green: 0.58, blue: 0.0)

    static let nftGradient = LinearGradient(
        colors: [.nftPurple, .nftBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nftCardGradient = LinearGradient(
        colors: [.nftPurple.opacity(0.3), .nftBlue.opacity(0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Adaptive Colors

struct AdaptiveColors {
    @Environment(\.colorScheme) static var colorScheme

    static var cardBackground: Color {
        Color(.systemBackground)
    }

    static var secondaryBackground: Color {
        Color(.secondarySystemBackground)
    }

    static var tertiaryBackground: Color {
        Color(.tertiarySystemBackground)
    }

    static var primaryText: Color {
        Color(.label)
    }

    static var secondaryText: Color {
        Color(.secondaryLabel)
    }

    static var separator: Color {
        Color(.separator)
    }
}

// MARK: - Typography

struct NFTTypography {
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
    static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)

    static let price = Font.system(size: 20, weight: .bold, design: .monospaced)
    static let bid = Font.system(size: 16, weight: .semibold, design: .monospaced)
    static let timer = Font.system(size: 14, weight: .medium, design: .monospaced)
}
