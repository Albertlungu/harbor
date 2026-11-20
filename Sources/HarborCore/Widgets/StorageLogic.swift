import Foundation

/// Pure helpers behind the storage widgets, kept free of AppKit so they can be tested.
public enum StorageLogic {
    /// Turns what a person typed into a web URL, adding https:// when no scheme was given.
    public static func normalizedURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasScheme = trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*://"#, options: .regularExpression) != nil
        let full = hasScheme ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Where to look for a site's icon directly. The page itself is parsed separately for an
    /// apple-touch-icon, which usually looks better than the tiny favicon.
    public static func faviconCandidates(for url: URL) -> [URL] {
        guard let host = url.host else { return [] }
        let scheme = url.scheme == "http" ? "http" : "https"
        return [URL(string: "\(scheme)://\(host)/favicon.ico")].compactMap { $0 }
    }

    /// Finds the href of an apple-touch-icon link in page markup, resolved against the page URL.
    public static func appleTouchIcon(inHTML html: String, base: URL) -> URL? {
        for tag in html.matches(of: /<link\b[^>]*>/.ignoresCase()) {
            let text = String(tag.output)
            guard text.range(of: #"rel\s*=\s*["'][^"']*apple-touch-icon"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = text.firstMatch(of: /href\s*=\s*["']([^"']+)["']/.ignoresCase())?.1 else { continue }
            if let resolved = URL(string: String(href), relativeTo: base)?.absoluteURL { return resolved }
        }
        return nil
    }

    /// A name that does not clash with `existing`, numbering from 2 like Finder does.
    public static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !existing.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Setting value clamped to the range the App Stack grid supports.
    public static func clampedColumns(_ value: Double) -> Int { min(8, max(3, Int(value.rounded()))) }
}
