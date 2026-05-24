import Foundation

enum TermNormalizer {
    private static let protectedPluralTokens: Set<String> = [
        "css", "ios", "macos", "watchos", "tvos", "visionos", "xcode",
    ]

    static func normalizedKey(_ value: String) -> String {
        tokens(in: value).joined(separator: " ")
    }

    static func normalizedSearchText(_ value: String) -> String {
        " \(normalizedKey(value)) "
    }

    static func tokens(in value: String) -> [String] {
        let separated = separateScripts(insertCamelBoundaries(value))
        let folded = separated.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let cleaned = String(folded.unicodeScalars.map { scalar in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
                || isCJK(scalar) {
                return Character(scalar)
            }
            return " "
        })
        return cleaned
            .split(whereSeparator: \.isWhitespace)
            .map { singularized(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func phraseMatches(candidate: [String], text: [String], allowsFuzzy: Bool) -> Bool {
        guard candidate.count == text.count else { return false }
        if candidate == text { return true }
        guard allowsFuzzy, candidate.count >= 2 else { return false }

        var editCount = 0
        for (lhs, rhs) in zip(candidate, text) {
            if lhs == rhs { continue }
            guard lhs.count >= 4 || rhs.count >= 4 else { return false }
            guard isDistanceAtMostOne(lhs, rhs) else { return false }
            editCount += 1
            guard editCount <= 1 else { return false }
        }
        return editCount == 1
    }

    static func isDistanceAtMostOne(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let a = Array(lhs)
        let b = Array(rhs)
        let delta = a.count - b.count
        guard abs(delta) <= 1 else { return false }

        if delta == 0 {
            let mismatches = zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
            if mismatches.count == 1 { return true }
            if mismatches.count == 2 {
                let first = mismatches[0]
                let second = mismatches[1]
                return second == first + 1 && a[first] == b[second] && a[second] == b[first]
            }
            return false
        }

        let longer = delta > 0 ? a : b
        let shorter = delta > 0 ? b : a
        var i = 0
        var j = 0
        var skipped = false
        while i < longer.count, j < shorter.count {
            if longer[i] == shorter[j] {
                i += 1
                j += 1
            } else if skipped {
                return false
            } else {
                skipped = true
                i += 1
            }
        }
        return true
    }

    private static func insertCamelBoundaries(_ value: String) -> String {
        let firstPass = value.replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return firstPass.replacingOccurrences(
            of: #"([A-Z]+)([A-Z][a-z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
    }

    private static func separateScripts(_ value: String) -> String {
        var out = ""
        var previousKind: ScriptKind?
        for character in value {
            let kind = scriptKind(for: character)
            if let previousKind, let kind, previousKind != kind, !out.hasSuffix(" ") {
                out.append(" ")
            }
            out.append(character)
            previousKind = kind
        }
        return out
    }

    private static func scriptKind(for character: Character) -> ScriptKind? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        if isCJK(scalar) { return .cjk }
        if CharacterSet.alphanumerics.contains(scalar) { return .latin }
        return nil
    }

    private static func singularized(_ token: String) -> String {
        guard token.count > 3, !protectedPluralTokens.contains(token) else { return token }
        if token.hasSuffix("ies"), token.count > 4 {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }
        return token
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
            || (0xF900...0xFAFF).contains(Int(scalar.value))
    }

    private enum ScriptKind {
        case cjk
        case latin
    }
}
