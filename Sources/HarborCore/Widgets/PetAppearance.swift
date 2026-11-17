import Foundation

public enum PetSpecies: String, CaseIterable, Sendable {
    case seal, cat, dog, fox, bunny, penguin, frog, owl, hamster

    public var title: String {
        switch self {
        case .seal: "Seal"
        case .cat: "Cat"
        case .dog: "Dog"
        case .fox: "Fox"
        case .bunny: "Bunny"
        case .penguin: "Penguin"
        case .frog: "Frog"
        case .owl: "Owl"
        case .hamster: "Hamster"
        }
    }

    /// How the legs move on a walk. Seals have none and galumph on their flippers.
    public var gait: PetGait.Kind {
        switch self {
        case .seal: .galumph
        case .penguin: .waddle
        case .bunny, .frog: .hop
        default: .walk
        }
    }

    /// Curated body colours; the first is the default.
    public var swatches: [PetSwatch] {
        switch self {
        case .seal: [.init("snow", "Snow", 0xEDE8E0), .init("silver", "Silver", 0xC9CDD3),
                     .init("slate", "Slate", 0x8E96A6), .init("cocoa", "Cocoa", 0xB39883)]
        case .cat: [.init("ginger", "Ginger", 0xF2B37A), .init("grey", "Grey", 0xBCC0C8),
                    .init("cream", "Cream", 0xF4E6D2), .init("black", "Black", 0x4C4752)]
        case .dog: [.init("golden", "Golden", 0xEBC690), .init("chocolate", "Chocolate", 0xA2735A),
                    .init("white", "White", 0xF5F1EB), .init("grey", "Grey", 0xADA7A0)]
        case .fox: [.init("red", "Red", 0xF0904E), .init("arctic", "Arctic", 0xF2F2F5),
                    .init("silver", "Silver", 0x938E9A), .init("fennec", "Fennec", 0xF1D2A4)]
        case .bunny: [.init("snow", "Snow", 0xF6F2EE), .init("brown", "Brown", 0xC9A68A),
                      .init("grey", "Grey", 0xB9B5B8), .init("peach", "Peach", 0xF5D0BC)]
        case .penguin: [.init("navy", "Navy", 0x46536A), .init("black", "Black", 0x3C3B44),
                        .init("blue", "Blue", 0x5E83AD), .init("pink", "Pink", 0xE8A9BA)]
        case .frog: [.init("green", "Green", 0x92CC6E), .init("lime", "Lime", 0xC2DE76),
                     .init("blue", "Blue", 0x82B9E2), .init("pink", "Pink", 0xF2AABC)]
        case .owl: [.init("brown", "Brown", 0xB58E6C), .init("snowy", "Snowy", 0xF2F0EA),
                    .init("grey", "Grey", 0xA19FA8), .init("tawny", "Tawny", 0xD6A562)]
        case .hamster: [.init("golden", "Golden", 0xF1C38E), .init("white", "White", 0xF6F1EA),
                        .init("grey", "Grey", 0xBBB6B0), .init("cinnamon", "Cinnamon", 0xDA9C68)]
        }
    }
}

public struct PetSwatch: Equatable, Sendable {
    public let id: String
    public let name: String
    /// 0xRRGGBB of the fur in light appearance; the dark appearance is derived from it.
    public let hex: UInt32

    init(_ id: String, _ name: String, _ hex: UInt32) {
        self.id = id
        self.name = name
        self.hex = hex
    }
}

public struct PetRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

public enum PetColor: Equatable, Sendable {
    case swatch(String)
    case custom(PetRGB)
}

public enum PetPattern: String, CaseIterable, Sendable {
    case plain, belly, spots, stripes, patches

    public var title: String {
        switch self {
        case .plain: "Plain"
        case .belly: "Belly patch"
        case .spots: "Spots"
        case .stripes: "Stripes"
        case .patches: "Patches"
        }
    }
}

public enum PetEyeStyle: String, CaseIterable, Sendable {
    case round, sparkly, sleepy

    public var title: String {
        switch self {
        case .round: "Round"
        case .sparkly: "Sparkly"
        case .sleepy: "Sleepy"
        }
    }
}

public enum PetAccessory: String, CaseIterable, Sendable {
    case none, bow, scarf, hat, glasses, flowerCrown

    public var title: String {
        switch self {
        case .none: "None"
        case .bow: "Bow"
        case .scarf: "Scarf"
        case .hat: "Little hat"
        case .glasses: "Glasses"
        case .flowerCrown: "Flower crown"
        }
    }
}

/// How the pet looks, read from and written to the widget's settings. Missing keys fall back to the
/// original seal, so configs saved before appearance existed keep their pet unchanged.
public struct PetAppearance: Equatable, Sendable {
    public var species: PetSpecies = .seal
    public var color: PetColor = .swatch("snow")
    public var pattern: PetPattern = .belly
    public var eyes: PetEyeStyle = .round
    public var accessory: PetAccessory = .none

    public static let keys = ["species", "color", "customColor", "pattern", "eyeStyle", "accessory"]

    public init(species: PetSpecies = .seal, color: PetColor? = nil, pattern: PetPattern = .belly,
                eyes: PetEyeStyle = .round, accessory: PetAccessory = .none) {
        self.species = species
        self.color = color ?? .swatch(species.swatches[0].id)
        self.pattern = pattern
        self.eyes = eyes
        self.accessory = accessory
    }

    public init(_ widget: WidgetConfig) {
        let species = widget.settings["species"]?.stringValue.flatMap(PetSpecies.init(rawValue:)) ?? .seal
        var color = PetColor.swatch(species.swatches[0].id)
        if case .object(let o)? = widget.settings["customColor"], let r = o["r"]?.doubleValue,
           let g = o["g"]?.doubleValue, let b = o["b"]?.doubleValue {
            color = .custom(PetRGB(red: r, green: g, blue: b))
        } else if let id = widget.settings["color"]?.stringValue, species.swatches.contains(where: { $0.id == id }) {
            color = .swatch(id)
        }
        self.init(species: species, color: color,
                  pattern: widget.settings["pattern"]?.stringValue.flatMap(PetPattern.init(rawValue:)) ?? .belly,
                  eyes: widget.settings["eyeStyle"]?.stringValue.flatMap(PetEyeStyle.init(rawValue:)) ?? .round,
                  accessory: widget.settings["accessory"]?.stringValue.flatMap(PetAccessory.init(rawValue:)) ?? .none)
    }

    /// Settings entries for every appearance key; nil values remove a key.
    public var settings: [String: JSONValue?] {
        var swatch: JSONValue?
        var custom: JSONValue?
        switch color {
        case .swatch(let id): swatch = .string(id)
        case .custom(let rgb):
            custom = .object(["r": .number(rgb.red), "g": .number(rgb.green), "b": .number(rgb.blue), "a": .number(1)])
        }
        return ["species": .string(species.rawValue), "color": swatch, "customColor": custom,
                "pattern": .string(pattern.rawValue), "eyeStyle": .string(eyes.rawValue),
                "accessory": .string(accessory.rawValue)]
    }

    /// The fur colour to draw.
    public var fur: PetRGB {
        switch color {
        case .custom(let rgb): return rgb
        case .swatch(let id): return PetRGB(hex: (species.swatches.first { $0.id == id } ?? species.swatches[0]).hex)
        }
    }

    /// The untouched seal, which keeps the exact original artwork.
    public var isClassicSeal: Bool { species == .seal && color == .swatch("snow") }

    /// A random look from the curated options. `roll` returns a value in 0..<1 and is called once per choice.
    public static func random(_ roll: () -> Double) -> PetAppearance {
        func pick<T>(_ options: [T]) -> T { options[min(Int(roll() * Double(options.count)), options.count - 1)] }
        let species = pick(PetSpecies.allCases)
        return PetAppearance(species: species, color: .swatch(pick(species.swatches).id), pattern: pick(PetPattern.allCases),
                             eyes: pick(PetEyeStyle.allCases), accessory: pick(PetAccessory.allCases))
    }
}

/// Walk-cycle math, kept free of drawing so the timing can be tested.
public enum PetGait {
    public enum Kind: Sendable { case walk, waddle, hop, galumph }

    /// Ground covered by one full stride, as a fraction of the pet's size.
    public static let strideLength = 0.55

    /// Stride cycles per second for a walk speed in points per second; small pets take quicker steps.
    public static func strideRate(speed: Double, unit: Double) -> Double {
        guard speed > 0, unit > 0 else { return 0 }
        return min(max(speed / (unit * strideLength), 1.2), 4.5)
    }

    /// A foot's offset for a stride phase in radians, as fractions of the unit: it lifts and swings forward
    /// for the first half of the cycle and slides back along the ground for the second.
    public static func foot(phase: Double, reach: Double = 0.07, lift: Double = 0.05) -> (x: Double, y: Double) {
        (-cos(phase) * reach, -max(0, sin(phase)) * lift)
    }

    /// Eased turn toward a target, so the head swings round instead of snapping. `elapsed` is seconds since
    /// the target last changed and `from` is where the turn stood then.
    public static func turn(from: Double, to: Double, elapsed: Double, duration: Double = 0.28) -> Double {
        let p = min(max(elapsed / duration, 0), 1)
        let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        return from + (to - from) * eased
    }
}
