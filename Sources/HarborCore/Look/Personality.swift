import Foundation

/// How much character Harbor shows. Each case is a starting bundle; every setting it
/// touches can still be changed on its own afterwards.
public enum Personality: String, Codable, CaseIterable, Sendable { case calm, balanced, playful }

public enum PetEnergy: String, Codable, CaseIterable, Sendable { case mellow, normal, lively }

extension Personality {
    /// Overwrites the settings this personality owns, leaving everything else alone.
    public func apply(to settings: inout AppSettings) {
        settings.personality = self
        switch self {
        case .calm:
            settings.palette = .system
            settings.categoryColors = false
            settings.paletteGlass = false
            settings.playfulCopy = false
            settings.celebrations = false
            settings.openAnimation = false
            settings.openSound = false
            settings.roundedType = false
            settings.petEnergy = .mellow
        case .balanced:
            settings.palette = .pastel
            settings.categoryColors = true
            settings.paletteGlass = false
            settings.playfulCopy = true
            settings.celebrations = true
            settings.openAnimation = true
            settings.openEffect = .plop
            settings.openSound = false
            settings.roundedType = true
            settings.petEnergy = .normal
        case .playful:
            settings.palette = .sunset
            settings.categoryColors = true
            settings.paletteGlass = true
            settings.playfulCopy = true
            settings.celebrations = true
            settings.openAnimation = true
            settings.openEffect = .plop
            settings.openSound = true
            settings.openSoundVolume = 0.4
            settings.roundedType = true
            settings.petEnergy = .lively
        }
    }

    public var title: String {
        switch self {
        case .calm: "Calm"
        case .balanced: "Balanced"
        case .playful: "Playful"
        }
    }

    public var summary: String {
        switch self {
        case .calm: "Quiet and plain. System colours, no extras."
        case .balanced: "A little colour and warmth, never in the way."
        case .playful: "Bright, bouncy and a bit cheeky."
        }
    }
}
