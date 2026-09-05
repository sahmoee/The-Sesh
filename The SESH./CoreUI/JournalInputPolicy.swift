import Foundation

/// Pure presentation policy. Never changes persisted schemas or sends journal data.
enum JournalInputPolicy {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ query: String, fields: [String], locale: Locale = .current) -> Bool {
        let needle = trimmed(query)
        return needle.isEmpty || fields.contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
        }
    }

    /// Accept a complete, nonnegative localized decimal, not a numeric prefix.
    /// Group separators, signs, exponent notation and pasted unit suffixes are
    /// rejected rather than silently rewriting a user's historical record.
    static func decimal(_ text: String, locale: Locale = .current) -> Double? {
        let value = trimmed(text)
        guard !value.isEmpty else { return nil }
        let separator = locale.decimalSeparator ?? "."
        let pieces = value.components(separatedBy: separator)
        guard pieces.count <= 2 else { return nil }
        var hasDigit = false
        var normalized: [String] = []
        for piece in pieces {
            var digits = ""
            for character in piece {
                guard character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                      let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
                hasDigit = true
                digits += String(digit)
            }
            normalized.append(digits)
        }
        guard hasDigit, let number = Double(normalized.joined(separator: ".")), number.isFinite, number >= 0 else { return nil }
        return number
    }

    static func editableDecimal(_ number: Double, locale: Locale = .current) -> String {
        guard number.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 324
        formatter.maximumIntegerDigits = 309
        return formatter.string(from: NSNumber(value: number)) ?? ""
    }

    /// Length-prefixing avoids delimiter collisions in draft-change detection.
    static func fingerprint(_ fields: [String]) -> String {
        fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

    /// Missing metrics (thoughts or historical entries without a price) sort
    /// after rated/priced sessions. Equal values use date, then stable identity.
    static func precedes(metric: Double?, date: Date, id: String,
                         otherMetric: Double?, otherDate: Date, otherID: String,
                         usesMetric: Bool) -> Bool {
        if usesMetric {
            switch (metric, otherMetric) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
        }
        return date == otherDate ? id < otherID : date > otherDate
    }
}
