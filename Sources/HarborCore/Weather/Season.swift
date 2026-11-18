import Foundation

public enum Season: String, CaseIterable, Codable, Sendable {
    case spring, summer, autumn, winter

    public var title: String { rawValue.capitalized }

    /// Meteorological seasons: whole months, March to May is northern spring.
    public static func on(_ date: Date, southern: Bool, calendar: Calendar = .current) -> Season {
        let north: Season = switch calendar.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
        guard southern else { return north }
        return switch north {
        case .spring: .autumn
        case .summer: .winter
        case .autumn: .spring
        case .winter: .summer
        }
    }

    /// Fireflies come out between dusk and dawn.
    public static func isEvening(hour: Int) -> Bool { hour >= 19 || hour < 5 }
}

public enum SeasonChoice: String, CaseIterable, Codable, Sendable {
    case auto, spring, summer, autumn, winter

    public var title: String { self == .auto ? "Automatic" : rawValue.capitalized }
}

/// How smoothly the weather moves against what it costs. Every frame makes the window server recomposite
/// the screen, so the frame rate is most of the cost.
public enum WeatherQuality: String, CaseIterable, Codable, Sendable {
    case smooth, balanced, light

    public var title: String { rawValue.capitalized }

    /// Frames a second for weather that only drifts; each divides common refresh rates so frames land evenly.
    public var driftRate: Double {
        switch self {
        case .smooth: 30
        case .balanced: 20
        case .light: 15
        }
    }

    /// Frames a second while something is held, thrown or blown.
    public var playRate: Double { self == .light ? 30 : 60 }

    /// Share of the usual amount that falls.
    public var detail: Double { self == .light ? 0.5 : 1 }
}

/// Settings › Seasons.
public struct WeatherSettings: Codable, Hashable, Sendable {
    public var enabled = true
    public var season: SeasonChoice = .auto
    public var southernHemisphere = false
    /// 0...1; how much falls.
    public var intensity = 0.5
    public var accumulation = true
    public var interactions = true
    public var sounds = false
    public var quality: WeatherQuality = .balanced

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c(.enabled, d.enabled)
        season = c(.season, d.season)
        southernHemisphere = c(.southernHemisphere, d.southernHemisphere)
        intensity = c(.intensity, d.intensity)
        accumulation = c(.accumulation, d.accumulation)
        interactions = c(.interactions, d.interactions)
        sounds = c(.sounds, d.sounds)
        quality = c(.quality, d.quality)
    }

    public func season(at date: Date, calendar: Calendar = .current) -> Season {
        switch season {
        case .auto: Season.on(date, southern: southernHemisphere, calendar: calendar)
        case .spring: .spring
        case .summer: .summer
        case .autumn: .autumn
        case .winter: .winter
        }
    }
}
