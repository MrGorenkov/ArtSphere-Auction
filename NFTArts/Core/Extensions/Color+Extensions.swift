import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
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

// Allow Color static properties to be used in ShapeStyle context (foregroundStyle)
extension ShapeStyle where Self == Color {
    static var nftPurple: Color { Color.nftPurple }
    static var nftBlue: Color { Color.nftBlue }
    static var nftPink: Color { Color.nftPink }
    static var nftGreen: Color { Color.nftGreen }
    static var nftOrange: Color { Color.nftOrange }
}

extension LinearGradient {
    static let nftPrimary = LinearGradient(
        colors: [Color.nftPurple, Color.nftBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nftWarm = LinearGradient(
        colors: [Color.nftOrange, Color.nftPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nftCool = LinearGradient(
        colors: [Color.nftBlue, Color.nftGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
