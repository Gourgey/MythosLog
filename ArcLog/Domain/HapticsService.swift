import Foundation

#if canImport(UIKit)
import UIKit

enum HapticsService {
    static func impact() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func logSuccess() {
        impact(style: .rigid)
        success()
    }

    static func rankPulse(intensity: Int) {
        switch intensity {
        case 0:
            impact(style: .soft)
        case 1:
            impact(style: .medium)
        default:
            impact(style: .rigid)
        }
    }

    static func rankDropPulse(intensity: Int) {
        switch intensity {
        case 0:
            impact(style: .soft)
        default:
            impact(style: .light)
        }
    }
}
#else
enum HapticsService {
    static func impact() {}
    static func impact(style: Any) {}
    static func success() {}
    static func logSuccess() {}
    static func rankPulse(intensity: Int) {}
    static func rankDropPulse(intensity: Int) {}
}
#endif
