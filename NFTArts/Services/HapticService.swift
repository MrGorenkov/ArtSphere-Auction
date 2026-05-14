import UIKit

/// Centralized haptic feedback. Generators are kept alive between calls so the first
/// invocation isn't delayed by allocation.
enum HapticService {
    static func tap() { selection.selectionChanged() }
    static func light() { lightImpact.impactOccurred() }
    static func medium() { mediumImpact.impactOccurred() }
    static func heavy() { heavyImpact.impactOccurred() }
    static func success() { notification.notificationOccurred(.success) }
    static func warning() { notification.notificationOccurred(.warning) }
    static func error() { notification.notificationOccurred(.error) }

    private static let selection = UISelectionFeedbackGenerator()
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()
}
