import HarborCore
import SwiftUI

extension Tokens {
    enum System {
        /// Ring thickness and glyph sizes as fractions of the gauge diameter.
        static let ringWidth: CGFloat = 0.075
        static let symbolScale: CGFloat = 0.2
        static let digitScale: CGFloat = 0.34
        static let labelScale: CGFloat = 0.14
        static let trackOpacity: Double = 0.16
        static let offlineOpacity: Double = 0.4
        static let valueEase: Double = 0.25

        static func color(for level: SystemLogic.Level) -> Color {
            switch level {
            case .good: Tokens.success
            case .warn: Tokens.warning
            case .critical: Tokens.danger
            }
        }
    }
}
