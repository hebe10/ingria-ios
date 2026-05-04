import Foundation

enum BarcodeValueNormalizer {
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            let pathDigits = url.pathComponents
                .reversed()
                .map { digitsOnly($0) }
                .first { $0.count >= 8 }
            if let pathDigits {
                return cleanGTIN(pathDigits)
            }
        }

        if trimmed.lowercased().contains("http") {
            let candidates = trimmed.matches(for: #"\d{8,18}"#)
            if let candidate = candidates.max(by: { $0.count < $1.count }) {
                return cleanGTIN(candidate)
            }
        }

        return cleanGTIN(digitsOnly(trimmed))
    }

    private static func cleanGTIN(_ value: String) -> String {
        let digits = digitsOnly(value)
        if digits.count == 14, digits.hasPrefix("01") {
            return String(digits.dropFirst(2))
        }
        if digits.count > 14, let last = digits.suffix(14).nilIfEmpty {
            return cleanGTIN(String(last))
        }
        return digits
    }

    private static func digitsOnly(_ value: String) -> String {
        value.filter(\.isNumber)
    }
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap {
            Range($0.range, in: self).map { String(self[$0]) }
        }
    }
}

private extension String.SubSequence {
    var nilIfEmpty: String.SubSequence? {
        isEmpty ? nil : self
    }
}
