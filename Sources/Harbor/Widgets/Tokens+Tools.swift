import SwiftUI

extension Tokens {
    /// Proportions shared by the tool widgets so they read as one family.
    enum Tool {
        static func unit(_ size: CGSize) -> CGFloat { max(min(size.width, size.height), 1) }
        static func chipRadius(_ unit: CGFloat) -> CGFloat { unit * 0.22 }
        static func ringWidth(_ unit: CGFloat) -> CGFloat { max(unit * 0.09, 2) }
        static let ringTrack = Tokens.border
        static let pop = 1.08
        static let popSpring = Animation.spring(response: 0.22, dampingFraction: 0.55)
    }
}
