import Foundation

#if canImport(UIKit)
import UIKit

enum HapticsService {
    static func impact() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
#else
enum HapticsService {
    static func impact() {}
    static func success() {}
}
#endif
