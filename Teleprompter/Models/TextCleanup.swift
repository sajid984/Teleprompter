import Foundation

/// Script clean-up actions offered in the editor's Clean Up menu.
enum TextCleanup {
    /// Unifies line endings and strips invisible characters that pasted text often carries.
    static func normalize(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        for invisible in ["\u{200B}", "\u{FEFF}"] {
            s = s.replacingOccurrences(of: invisible, with: "")
        }
        return s
    }

    /// Trims spaces, then keeps at most one blank line between paragraphs.
    static func quickClean(_ text: String) -> String {
        removeExtraBlankLines(trimSpaces(text))
    }

    /// Collapses runs of blank lines into a single blank line and drops blank lines at the start and end.
    static func removeExtraBlankLines(_ text: String) -> String {
        var out: [String] = []
        for line in lines(text) {
            if isBlank(line) {
                if let last = out.last, !last.isEmpty { out.append("") }
            } else {
                out.append(line)
            }
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }

    static func removeAllBlankLines(_ text: String) -> String {
        lines(text).filter { !isBlank($0) }.joined(separator: "\n")
    }

    /// Joins hard-wrapped lines (common when copying from PDFs or email) back into paragraphs.
    /// Blank lines still separate paragraphs.
    static func joinBrokenLines(_ text: String) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty { paragraphs.append(current.joined(separator: " ")); current = [] }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs.map(collapseSpaces).joined(separator: "\n\n")
    }

    /// Puts exactly one blank line between every line of text.
    static func blankLineBetweenParagraphs(_ text: String) -> String {
        lines(text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Trims spaces at the start and end of every line and collapses repeated spaces.
    static func trimSpaces(_ text: String) -> String {
        lines(text)
            .map { collapseSpaces($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    /// Removes punctuation marks but keeps what reads naturally out loud:
    /// apostrophes and hyphens inside words (don't, well-known), number separators (3.5, 1,000, 10:30)
    /// and symbols that are spoken (& % @ # $). Dashes, slashes and ellipses become a space.
    static func removePunctuation(_ text: String) -> String {
        let source = normalize(text).replacingOccurrences(of: "\\.{2,}", with: " ", options: .regularExpression)
        let chars = Array(source)
        var out = String()
        out.reserveCapacity(source.utf8.count)

        for (i, c) in chars.enumerated() {
            guard c.isPunctuation, !spokenSymbols.contains(c) else {
                out.append(c)
                continue
            }
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let betweenWordChars = (prev.map(isWordChar) ?? false) && (next.map(isWordChar) ?? false)
            let betweenDigits = (prev?.isNumber ?? false) && (next?.isNumber ?? false)

            if apostrophes.contains(c) || hyphens.contains(c), betweenWordChars {
                out.append(c)
            } else if numberSeparators.contains(c), betweenDigits {
                out.append(c)
            } else if spacers.contains(c) || hyphens.contains(c) {
                out.append(" ")
            }
            // Everything else (. , ; : ! ? quotes brackets * …) is dropped.
        }
        return trimSpaces(out)
    }

    /// Removes [bracketed notes] and (stage directions) that should not be read aloud.
    static func removeBracketedNotes(_ text: String) -> String {
        let s = normalize(text)
            .replacingOccurrences(of: "\\[[^\\]\\n]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)\\n]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}\\n]*\\}", with: "", options: .regularExpression)
        return removeExtraBlankLines(trimSpaces(s))
    }

    static func uppercase(_ text: String) -> String {
        normalize(text).uppercased()
    }

    // MARK: - Helpers

    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}"]
    private static let hyphens: Set<Character> = ["-", "\u{2010}", "\u{2011}"]
    private static let numberSeparators: Set<Character> = [".", ",", ":"]
    private static let spacers: Set<Character> = ["\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "/", "\\", "|", "_", "\u{2026}", "~"]
    private static let spokenSymbols: Set<Character> = ["&", "%", "@", "#"]

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    private static func lines(_ text: String) -> [String] {
        normalize(text).components(separatedBy: "\n")
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func collapseSpaces(_ line: String) -> String {
        line.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
    }
}

enum TextStats {
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
