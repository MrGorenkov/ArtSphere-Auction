import SwiftUI

extension View {
    func nftCardStyle() -> some View {
        self
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    func nftGlassStyle() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func applyTheme(_ theme: ThemeManager.AppTheme) -> some View {
        if let colorScheme = theme.colorScheme {
            self.preferredColorScheme(colorScheme)
        } else {
            self
        }
    }
}
