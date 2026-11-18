import HarborCore
import SwiftUI

/// How a roaming pet looks while it plays in the weather: rolling over through a pile, holding a snowball,
/// the flick of a throw, a pounce, shaking itself off or sniffing a flower. Layered over the whole figure
/// so the pet's own view stays as it is; frames only run while a pose is showing.
struct RoamPlayEffect: ViewModifier {
    let driver: RoamDriver

    private struct Look {
        var angle = 0.0
        var sx = 1.0
        var sy = 1.0
        var dx = 0.0
        var dy = 0.0
    }

    func body(content: Content) -> some View {
        let play = driver.play
        let unit = driver.unit
        // The feet sit half a unit below the middle of the window, which is where a crouch presses down.
        let feet = UnitPoint(x: 0.5, y: 0.5 + 0.5 * unit / driver.side)
        // Always wrapped the same way, so the pet's own view keeps its state when a pose starts or ends.
        return TimelineView(.animation(minimumInterval: nil, paused: play == .none)) { context in
            let look = Self.look(play, at: context.date, driver: driver)
            content
                .scaleEffect(x: look.sx, y: look.sy, anchor: play == .roll ? .center : feet)
                .rotationEffect(.degrees(look.angle))
                .offset(x: look.dx * unit, y: look.dy * unit)
                .overlay {
                    if play == .carry, driver.playBall > 0 {
                        let r = min(driver.playBall, Double(unit) * 0.45)
                        Circle()
                            .fill(RadialGradient(colors: [.white, Color(red: 0.78, green: 0.83, blue: 0.93)],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: r * 1.4))
                            .overlay(Circle().stroke(Color(red: 0.6, green: 0.66, blue: 0.78).opacity(0.6), lineWidth: 0.6))
                            .frame(width: r * 2, height: r * 2)
                            .offset(x: driver.facing * Double(unit) * 0.3, y: Double(unit) * 0.5 - r * 0.9)
                    }
                }
        }
    }

    private static func look(_ play: WeatherPetPose, at date: Date, driver: RoamDriver) -> Look {
        let t = max(0, date.timeIntervalSince(driver.playStart))
        let span = max(0.01, driver.playUntil.timeIntervalSince(driver.playStart))
        let p = min(t / span, 1)
        let facing = driver.facing
        var look = Look()
        switch play {
        case .none:
            break
        case .roll:
            // Over and over the way it is going, squashed a little and sunk into the pile.
            look.angle = facing * 360 * 1.4 * t
            look.sx = 1.08
            look.sy = 0.88
            look.dy = 0.1
        case .carry:
            look.angle = -facing * 6
            look.sy = 1.03
        case .toss:
            let flick = sin(p * .pi)
            look.angle = facing * 24 * flick
            look.sy = 1 + 0.1 * flick
            look.sx = 1 - 0.05 * flick
        case .pounce:
            if p < 0.4 {
                let crouch = p / 0.4
                look.sy = 1 - 0.18 * crouch
                look.sx = 1 + 0.1 * crouch
            } else {
                look.sy = 1.12
                look.sx = 0.92
                look.angle = facing * 12
            }
        case .shake:
            let wiggle = sin(t * 2 * .pi * 9) * (1 - p)
            look.angle = wiggle * 12
            look.dx = wiggle * 0.04
        case .sniff:
            look.angle = facing * 14 * min(1, t * 4)
            look.dy = 0.04 + sin(t * 12) * 0.01
        }
        return look
    }
}
