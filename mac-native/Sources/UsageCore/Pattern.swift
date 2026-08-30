import Foundation

/// A thin `NSRegularExpression` wrapper that keeps the ported parsers reading
/// like their JavaScript originals.
///
/// Deliberately *not* Swift's built-in `Regex` literal type: every pattern
/// here was transliterated from a JS source file, and keeping them as strings
/// means a future fix can be diffed against the JS line it came from rather
/// than mentally re-derived. Compilation is cached per call site by holding
/// these in `static let`s.
public struct Pattern {
    private let regex: NSRegularExpression?

    public init(_ pattern: String, options: NSRegularExpression.Options = []) {
        self.regex = try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// One match's capture groups, indexed the way JS's match arrays are:
    /// `m[0]` is the whole match, `m[1]` the first group. A group that did not
    /// participate reads back as `nil`.
    public struct Match {
        private let groups: [String?]
        init(groups: [String?]) { self.groups = groups }
        public subscript(_ i: Int) -> String? {
            i >= 0 && i < groups.count ? groups[i] : nil
        }
        public var count: Int { groups.count }
    }

    public func firstMatch(_ s: String) -> Match? {
        guard let regex else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String?] = []
        groups.reserveCapacity(m.numberOfRanges)
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
        }
        return Match(groups: groups)
    }

    public func matches(_ s: String) -> Bool {
        firstMatch(s) != nil
    }

    /// Replaces only the first match — the ported call sites all use this to
    /// strip a known prefix (`^Resets\s*`), never to rewrite globally.
    public func replacingFirst(in s: String, with replacement: String) -> String {
        guard let regex else { return s }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return s
        }
        return ns.replacingCharacters(in: m.range, with: replacement)
    }

    /// Replaces every match. Used by the reset-time prettifier, which is the
    /// one place a global replace was in the original.
    public func replacingAll(in s: String, with template: String) -> String {
        guard let regex else { return s }
        let ns = s as NSString
        return regex.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}
