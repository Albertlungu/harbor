import CoreGraphics
import Foundation

/// One accessibility element seen inside another app, in AppKit coordinates (y up).
public struct RoamElementCandidate: Equatable, Sendable {
    public var role: String
    public var subrole: String?
    public var frame: CGRect
    /// The window, menu or popover the element belongs to; candidates are grouped and capped by it.
    public var windowFrame: CGRect
    /// Steps from the window down to the element.
    public var depth: Int

    public init(role: String, subrole: String? = nil, frame: CGRect, windowFrame: CGRect, depth: Int) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.windowFrame = windowFrame
        self.depth = depth
    }
}

/// Decides which elements inside a window are prominent enough to act as ledges for the roaming pet.
/// Only large panes, text areas, lists, menus and the like count; controls and small pieces never do.
public enum RoamElements {
    public static let minWidth = 120.0
    /// A ledge must also span this share of its window, so wide windows ignore mid-sized pieces.
    public static let minWidthFraction = 0.15
    public static let minHeight = 18.0
    /// Text fields are thin, so only wide ones (search fields, message boxes) are worth standing on.
    public static let minTextFieldWidth = 240.0
    /// Tops closer than this to each other or to the window top count as the same ledge.
    public static let topSlack = 4.0
    public static let maxPerWindow = 6

    /// Roles that open their own surface rather than sitting inside a window.
    static let floatingRoles: Set<String> = ["AXMenu", "AXSheet", "AXPopover"]

    /// How strongly a role reads as a main part of the interface; roles not listed are never ledges.
    static func weight(role: String, subrole: String?) -> Double? {
        switch role {
        case "AXTextArea": 1.0
        case "AXMenu": 0.95
        case "AXSheet", "AXPopover": 0.85
        case "AXScrollArea": 0.8
        case "AXTable", "AXOutline", "AXList", "AXBrowser": 0.75
        case "AXTextField", "AXComboBox": 0.7
        case "AXWebArea": 0.6
        case "AXTabGroup": 0.6
        case "AXToolbar": 0.5
        case "AXSplitGroup": 0.45
        case "AXGroup": subrole.map { $0.hasPrefix("AXLandmark") || $0 == "AXDocumentArticle" } == true ? 0.55 : 0.4
        default: nil
        }
    }

    /// The element's merit as a ledge, or nil when it should never be stood on.
    public static func score(_ candidate: RoamElementCandidate) -> Double? {
        guard let weight = weight(role: candidate.role, subrole: candidate.subrole) else { return nil }
        let frame = candidate.frame
        let window = candidate.windowFrame
        let floating = floatingRoles.contains(candidate.role)
        guard frame.height >= minHeight, window.width > 0 else { return nil }
        let span = floating ? frame.width : frame.intersection(window).width
        guard span >= max(minWidth, minWidthFraction * window.width) else { return nil }
        if candidate.role == "AXTextField" || candidate.role == "AXComboBox" {
            guard span >= minTextFieldWidth else { return nil }
        }
        // Plain groups are layout wrappers unless they hold a sizeable block of content.
        if candidate.role == "AXGroup", frame.height < 60 { return nil }
        if !floating {
            let top = frame.maxY
            // A top in the title strip or outside the window would put the pet on the window edge or in the air.
            guard top <= window.maxY - RoamSurfaces.titleBarHeight + topSlack, top > window.minY + topSlack else {
                return nil
            }
            let wholeWindow = frame.width >= window.width * 0.95 && frame.height >= window.height * 0.9
            guard !wholeWindow else { return nil }
        }
        let share = min(span / max(window.width, 1), 1)
        // Deeper elements are usually finer pieces of a pane already found higher up.
        let depthPenalty = min(Double(candidate.depth), 20) * 0.01
        return weight * (0.6 + 0.4 * share) - depthPenalty
    }

    /// The ledges worth standing on: the best few per window, without near-duplicate tops.
    /// Frames are clipped to their window horizontally; floating surfaces keep their own frame.
    public static func ledges(_ candidates: [RoamElementCandidate], maxPerWindow: Int = maxPerWindow) -> [CGRect] {
        let scored = candidates.compactMap { candidate -> (RoamElementCandidate, Double)? in
            score(candidate).map { (candidate, $0) }
        }
        .sorted { $0.1 > $1.1 }
        var kept: [(window: CGRect, frame: CGRect)] = []
        for (candidate, _) in scored {
            var frame = candidate.frame
            if !floatingRoles.contains(candidate.role) {
                let clipped = frame.intersection(candidate.windowFrame)
                frame = CGRect(x: clipped.minX, y: frame.minY, width: clipped.width, height: frame.height)
            }
            let sameWindow = kept.filter { $0.window == candidate.windowFrame }
            guard sameWindow.count < maxPerWindow,
                  !kept.contains(where: { duplicates($0.frame, frame) }) else { continue }
            kept.append((candidate.windowFrame, frame))
        }
        return kept.map(\.frame)
    }

    /// Two ledges at nearly the same height that mostly overlap read as one; the better one is kept.
    static func duplicates(_ a: CGRect, _ b: CGRect) -> Bool {
        guard abs(a.maxY - b.maxY) <= topSlack else { return false }
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return overlap > 0.5 * min(a.width, b.width)
    }
}
