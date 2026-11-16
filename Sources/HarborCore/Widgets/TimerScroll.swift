import Foundation

/// Rules for changing a timer's duration by scrolling over it.
public enum TimerScroll {
    public static let shiftMultiplier = 5
    /// A running timer never drops below this, so a scroll cannot end it by accident.
    public static let minimumRemaining: TimeInterval = 5

    public static func adjusted(minutes: Int, steps: Int, shift: Bool) -> Int {
        ToolLogic.clamp(minutes + steps * (shift ? shiftMultiplier : 1), TimerLogic.minuteRange)
    }

    public struct Running: Equatable, Sendable {
        public let end: Date
        public let total: TimeInterval
    }

    /// Moves a running timer by the same amount the duration changed. The total moves too, so the
    /// ring does not jump to a fraction the scroll never asked for.
    public static func shifted(end: Date, total: TimeInterval, now: Date, byMinutes delta: Int) -> Running {
        let remaining = TimerLogic.remaining(end: end, now: now)
        let newRemaining = max(minimumRemaining, remaining + Double(delta) * 60)
        return Running(end: now.addingTimeInterval(newRemaining), total: max(newRemaining, total + (newRemaining - remaining)))
    }
}
