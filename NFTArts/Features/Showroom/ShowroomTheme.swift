import Foundation
import UIKit

/// Visual theme for the 3D showroom. Each theme bundles wall/floor/frame colors,
/// lighting parameters and decor flags so the room can be re-skinned wholesale.
enum ShowroomTheme: String, CaseIterable, Identifiable, Codable {
    case louvre
    case modern
    case loft
    case cyberpunk

    var id: String { rawValue }

    /// Localized display name shown in the picker.
    var displayName: String {
        switch self {
        case .louvre:    return "Лувр"
        case .modern:    return "Современная"
        case .loft:      return "Лофт"
        case .cyberpunk: return "Cyberpunk"
        }
    }

    var icon: String {
        switch self {
        case .louvre:    return "building.columns"
        case .modern:    return "square.split.2x2"
        case .loft:      return "house"
        case .cyberpunk: return "bolt.fill"
        }
    }

    struct Palette {
        // Environment
        let background: UIColor
        let wallColor: UIColor
        let wallRoughness: CGFloat
        let floorColor: UIColor
        let floorRoughness: CGFloat
        let ceilingColor: UIColor
        let trimColor: UIColor

        // Frame
        let frameDiffuse: UIColor
        let frameMetalness: CGFloat
        let frameRoughness: CGFloat

        // Lighting
        let ambientIntensity: CGFloat
        let ambientColor: UIColor
        let fillIntensity: CGFloat
        let pictureIntensity: CGFloat
        let pictureColor: UIColor

        // Decor
        let rugColor: UIColor
        let showLouvreDecor: Bool   // chandelier, pedestals, vases, benches
    }

    var palette: Palette {
        switch self {
        case .louvre:
            return Palette(
                background:       UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1.0),
                wallColor:        UIColor(red: 0.78, green: 0.71, blue: 0.60, alpha: 1.0),
                wallRoughness:    0.95,
                floorColor:       UIColor(red: 0.32, green: 0.22, blue: 0.14, alpha: 1.0),
                floorRoughness:   0.85,
                ceilingColor:     UIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1.0),
                trimColor:        UIColor(red: 0.20, green: 0.13, blue: 0.08, alpha: 1.0),
                frameDiffuse:     UIColor(red: 0.62, green: 0.48, blue: 0.18, alpha: 1.0),
                frameMetalness:   0.75,
                frameRoughness:   0.35,
                ambientIntensity: 320,
                ambientColor:     UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0),
                fillIntensity:    350,
                pictureIntensity: 25,
                pictureColor:     UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1.0),
                rugColor:         UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0),
                showLouvreDecor:  true
            )
        case .modern:
            return Palette(
                background:       UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
                wallColor:        UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0),
                wallRoughness:    0.5,
                floorColor:       UIColor(red: 0.82, green: 0.80, blue: 0.78, alpha: 1.0),
                floorRoughness:   0.4,
                ceilingColor:     UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                trimColor:        UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0),
                frameDiffuse:     UIColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0),
                frameMetalness:   0.2,
                frameRoughness:   0.6,
                ambientIntensity: 700,
                ambientColor:     UIColor(white: 1.0, alpha: 1.0),
                fillIntensity:    600,
                pictureIntensity: 10,
                pictureColor:     UIColor(red: 1.0, green: 0.99, blue: 0.96, alpha: 1.0),
                rugColor:         UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0),
                showLouvreDecor:  false
            )
        case .loft:
            return Palette(
                background:       UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1.0),
                wallColor:        UIColor(red: 0.55, green: 0.40, blue: 0.32, alpha: 1.0), // exposed brick
                wallRoughness:    0.85,
                floorColor:       UIColor(red: 0.28, green: 0.20, blue: 0.14, alpha: 1.0),
                floorRoughness:   0.7,
                ceilingColor:     UIColor(red: 0.35, green: 0.32, blue: 0.28, alpha: 1.0),
                trimColor:        UIColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1.0),
                frameDiffuse:     UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1.0),
                frameMetalness:   0.55,
                frameRoughness:   0.55,
                ambientIntensity: 240,
                ambientColor:     UIColor(red: 1.0, green: 0.90, blue: 0.78, alpha: 1.0),
                fillIntensity:    280,
                pictureIntensity: 80,
                pictureColor:     UIColor(red: 1.0, green: 0.85, blue: 0.60, alpha: 1.0), // edison bulb glow
                rugColor:         UIColor(red: 0.35, green: 0.28, blue: 0.22, alpha: 1.0),
                showLouvreDecor:  false
            )
        case .cyberpunk:
            return Palette(
                background:       UIColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1.0),
                wallColor:        UIColor(red: 0.08, green: 0.06, blue: 0.16, alpha: 1.0),
                wallRoughness:    0.4,
                floorColor:       UIColor(red: 0.05, green: 0.04, blue: 0.10, alpha: 1.0),
                floorRoughness:   0.2,
                ceilingColor:     UIColor(red: 0.04, green: 0.03, blue: 0.08, alpha: 1.0),
                trimColor:        UIColor(red: 0.85, green: 0.10, blue: 0.55, alpha: 1.0), // magenta neon trim
                frameDiffuse:     UIColor(red: 0.10, green: 0.85, blue: 0.95, alpha: 1.0), // cyan
                frameMetalness:   0.95,
                frameRoughness:   0.15,
                ambientIntensity: 120,
                ambientColor:     UIColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 1.0), // violet
                fillIntensity:    160,
                pictureIntensity: 120,
                pictureColor:     UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1.0), // cyan
                rugColor:         UIColor(red: 0.80, green: 0.10, blue: 0.55, alpha: 1.0),
                showLouvreDecor:  false
            )
        }
    }
}
