import Foundation

struct IngredientExtraction {
    let cleanedText: String
    let ingredients: [ProductIngredient]
    let isValid: Bool
}

enum IngredientExtractor {
    static func extract(_ rawText: String, source: String = "Open Food Facts text") -> IngredientExtraction {
        let bounded = ingredientSection(from: rawText)
        let cleaned = cleanText(bounded.text)
        let tokens = tokenize(cleaned)
            .filter { isLikelyIngredientToken($0) }

        let ingredients = tokens.map { token in
            ProductIngredient(
                originalText: token,
                normalizedKey: normalize(token),
                displayNameDE: displayName(from: token),
                displayNameEN: nil,
                percent: percent(from: token),
                source: source
            )
        }

        let cleanedText = ingredients.map(\.originalText).joined(separator: ", ")
        let valid = isValidIngredientList(
            cleanedText,
            tokens: ingredients.map(\.originalText),
            hadMarker: bounded.hadMarker,
            structured: false,
            sourceText: bounded.text
        )

        return IngredientExtraction(cleanedText: cleanedText, ingredients: ingredients, isValid: valid)
    }

    static func isValidIngredientList(
        _ text: String,
        tokens: [String],
        hadMarker: Bool,
        structured: Bool,
        sourceText: String = ""
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if structured {
            return tokens.contains { isLikelyIngredientToken($0) }
        }
        guard hadMarker || tokens.count >= 2 else { return false }

        let normalized = normalize(trimmed)
        let sourceNormalized = normalize(sourceText.isEmpty ? trimmed : sourceText)
        let junkHits = junkPhrases.filter { normalized.contains($0) }.count
        let sourceJunkHits = junkPhrases.filter { sourceNormalized.contains($0) }.count
        let ingredientHits = ingredientClues.filter { normalized.contains($0) }.count
        let numberLike = tokens.filter { isMostlyNumberOrCode($0) }.count

        guard tokens.count >= 2 else { return ingredientHits >= 1 && junkHits == 0 }
        if numberLike >= max(2, tokens.count / 2) { return false }
        if junkHits > ingredientHits && ingredientHits == 0 { return false }
        if !hadMarker, sourceJunkHits >= 2, ingredientHits < 3 { return false }
        if !hadMarker, tokens.count <= 2, sourceJunkHits > 0 { return false }

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        guard letters >= 6, letters >= digits else { return false }

        return ingredientHits > 0 || tokens.count >= 3
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "[‐‑‒–—−]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9%]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ingredientSection(from rawText: String) -> (text: String, hadMarker: Bool) {
        let normalized = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return ("", false) }

        let markerPattern = #"(?i)\b(zutaten|inhaltsstoffe|ingredients|inci|composition|ingr[eé]dients|ingredienzen|ingredienti|içindekiler)\s*:"#
        if let range = normalized.range(of: markerPattern, options: .regularExpression) {
            let after = String(normalized[range.upperBound...])
            return (cutAtEndMarker(after), true)
        }

        let loosePattern = #"(?i)\b(zutaten|inhaltsstoffe|ingredients|inci|composition|ingr[eé]dients|ingredienzen|ingredienti|içindekiler)\b"#
        if let range = normalized.range(of: loosePattern, options: .regularExpression) {
            let after = String(normalized[range.upperBound...])
            return (cutAtEndMarker(after), true)
        }

        return (cutAtEndMarker(normalized), false)
    }

    private static func cutAtEndMarker(_ value: String) -> String {
        let markers = [
            "Nährwerte", "Nutrition", "Durchschnittliche Nährwerte", "Allergene",
            "Kann Spuren enthalten", "Kann enthalten", "Aufbewahrung", "Aufbewahren",
            "Kühl und trocken", "Nach dem Öffnen", "Mindestens haltbar", "MHD",
            "Unter Schutzatmosphäre", "Vor Wärme schützen", "Vor Waerme schuetzen",
            "Zubereitung", "Zubereitungsempfehlung", "Serviervorschlag", "Hergestellt",
            "Hersteller", "Vertrieb", "Adresse", "Kontakt", "Recycling", "Entsorgen",
            "Flasche", "Etikett", "Rezyklat", "Recyclat", "Richtig trennen",
            "Gilt in DE", "Sprühkopf", "Spruehkopf", "Material ohne",
            "Gelbe Tonne", "Grüner Punkt", "DE-ÖKO", "Rainforest Alliance", "Fairtrade",
            "RSPO", "FSC", "EAN", "Losnummer", "Chargennummer", "L-Nr", "LOT", "Batch",
            "Superfood", "reich an", "von Natur aus", "Müsli", "Muesli", "für zwisch",
            "fuer zwisch", "trocken lagern", "hergestellt fuer", "hergestellt für"
        ]

        var output = value
        for marker in markers {
            if let range = output.range(of: "\\b\(NSRegularExpression.escapedPattern(for: marker))\\b", options: [.regularExpression, .caseInsensitive]) {
                output = String(output[..<range.lowerBound])
            }
        }
        return output
    }

    private static func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[_\*•·]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,;:.])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—.")))
    }

    /// Splits an ingredient list into tokens at the top level only, preserving
    /// nested parenthetical content as part of the parent token, and emitting
    /// each interior sub-ingredient as a separate token as well.
    ///
    /// Examples:
    ///   "Modified starch (tapioca, corn, wheat)"
    ///     -> ["modified starch (tapioca corn wheat)", "tapioca", "corn", "wheat"]
    ///   "Chocolate coating (sugar, cocoa butter, emulsifier: lecithin (soya))"
    ///     -> ["chocolate coating ...", "sugar", "cocoa butter", "emulsifier: lecithin (soya)", "lecithin", "soya"]
    ///   "Aqua/Water, Glycerin"
    ///     -> ["aqua", "water", "glycerin"]
    static func tokenize(_ value: String) -> [String] {
        let decimalProtected = value.replacingOccurrences(
            of: #"(\d),(\d)"#,
            with: "$1§$2",
            options: .regularExpression
        )

        var topLevelTokens: [String] = []
        var current = ""
        var depth = 0
        let openers: Set<Character> = ["(", "[", "{"]
        let closers: Set<Character> = [")", "]", "}"]
        let separators: Set<Character> = [",", ";", "•", "·"]

        for char in decimalProtected {
            if openers.contains(char) {
                depth += 1
                current.append(char)
            } else if closers.contains(char) {
                depth = max(0, depth - 1)
                current.append(char)
            } else if separators.contains(char), depth == 0 {
                let restored = current.replacingOccurrences(of: "§", with: ",")
                topLevelTokens.append(restored)
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            topLevelTokens.append(current.replacingOccurrences(of: "§", with: ","))
        }

        var emitted: [String] = []
        var seenNormalized = Set<String>()

        func emit(_ raw: String) {
            let cleaned = cleanToken(raw)
            guard !cleaned.isEmpty else { return }
            for variant in expandTokenVariants(cleaned) {
                let key = normalize(variant)
                guard !key.isEmpty, !seenNormalized.contains(key) else { continue }
                seenNormalized.insert(key)
                emitted.append(variant)
            }
        }

        for token in topLevelTokens {
            // Emit the token with its parenthetical content kept (cleaned)
            // so the auditor can match phrases like "palm kernel oil".
            emit(token)
            // Also emit each sub-ingredient inside parens so we don't miss them.
            for sub in extractParentheticalChildren(token) {
                emit(sub)
            }
        }

        return emitted
    }

    /// Pulls out comma/semicolon-separated sub-ingredients from inside any
    /// parentheses or brackets. Recurses one level so "lecithin (soya)" still
    /// surfaces "soya".
    private static func extractParentheticalChildren(_ value: String) -> [String] {
        guard value.contains("(") || value.contains("[") || value.contains("{") else { return [] }

        var children: [String] = []
        var buffer = ""
        var depth = 0
        let openers: Set<Character> = ["(", "[", "{"]
        let closers: Set<Character> = [")", "]", "}"]

        for char in value {
            if openers.contains(char) {
                if depth >= 1 {
                    buffer.append(char)
                }
                depth += 1
            } else if closers.contains(char) {
                depth -= 1
                if depth == 0 {
                    let inner = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inner.isEmpty {
                        // Re-tokenize the inner section (handles nesting).
                        children.append(contentsOf: tokenize(inner))
                    }
                    buffer = ""
                } else if depth >= 1 {
                    buffer.append(char)
                }
            } else if depth >= 1 {
                buffer.append(char)
            }
        }

        return children
    }

    /// Expands tokens into matchable variants:
    /// - `Aqua/Water` → ["Aqua", "Water"]
    /// - `E471-E473` → ["E471", "E472", "E473"]
    /// - everything else passes through unchanged.
    private static func expandTokenVariants(_ token: String) -> [String] {
        var variants: [String] = []

        // E-number range expansion.
        if let range = token.range(of: #"E\s*\d{3,4}\s*[-–—]\s*E?\s*\d{3,4}"#, options: [.regularExpression, .caseInsensitive]) {
            let span = String(token[range])
            let numbers = span.components(separatedBy: CharacterSet(charactersIn: "Ee -–—"))
                .compactMap { Int($0) }
            if numbers.count == 2, numbers[0] <= numbers[1], numbers[1] - numbers[0] <= 20 {
                for n in numbers[0]...numbers[1] {
                    variants.append("E\(n)")
                }
                let rest = token.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { variants.append(rest) }
                return variants
            }
        }

        // Slash variants: "Aqua/Water/Eau" → ["Aqua", "Water", "Eau"]
        // Only split at slashes that look like full-word separators (not e.g. "vitamin a/c" inside chemistry).
        if token.contains("/") {
            let parts = token.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2, parts.allSatisfy({ part in
                // Each side should look like a real word, not a fragment.
                part.count >= 2 && part.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            }) {
                return parts
            }
        }

        variants.append(token)
        return variants
    }

    private static func cleanToken(_ value: String) -> String {
        value
            // Strip leading bracketed prefixes like "[Zutaten:" / "(INCI:" left over from cleanText.
            .replacingOccurrences(of: #"^\s*[\[\(\{]\s*(zutaten|inhaltsstoffe|ingredients?|inci|composition|ingr[eé]dients?|ingredientes)\s*:?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*(zutaten|ingredients?)\s*:?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*(inhaltsstoffe|inci|composition|ingr[eé]dients?|ingredientes)\s*:?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            // Footnote/asterisk markers ("Sunflower oil*", "rapeseed oil**", "Sugar†").
            .replacingOccurrences(of: #"[\*†‡§¶]+"#, with: " ", options: .regularExpression)
            // Percentage callouts: "(50%)", " 50 %", "30%".
            .replacingOccurrences(of: #"\(\s*\d+([.,]\d+)?\s*%\s*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\d+([.,]\d+)?\s*%"#, with: " ", options: .regularExpression)
            // Trailing/orphan brackets.
            .replacingOccurrences(of: #"^\s*[\)\]\}]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[\(\[\{]+\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:-–—()[]{}")))
    }

    private static func isLikelyIngredientToken(_ token: String) -> Bool {
        let normalized = normalize(token)
        guard normalized.count >= 2 else { return false }
        if isMostlyNumberOrCode(token) { return false }
        if junkPhrases.contains(where: { normalized.contains($0) }) { return false }
        if token.split(whereSeparator: { $0.isWhitespace }).count > 8 && !ingredientClues.contains(where: { normalized.contains($0) }) {
            return false
        }
        if normalized.range(of: #"^\d+(\s|$)|^\d+[a-z]?\s*$"#, options: .regularExpression) != nil { return false }
        if normalized.range(of: #"\b\d{4,}\b"#, options: .regularExpression) != nil && !normalized.contains("%") { return false }
        if normalized.contains("strasse") || normalized.contains("straße") || normalized.contains("sonnenallee") || normalized.contains("berlin") { return false }
        return token.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private static func isMostlyNumberOrCode(_ value: String) -> Bool {
        let cleaned = value.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        if cleaned.range(of: #"^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$"#, options: .regularExpression) != nil { return true }
        if cleaned.range(of: #"^(L|LOT|Batch)?[A-Z0-9]{6,}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let scalars = Array(cleaned.unicodeScalars)
        guard !scalars.isEmpty else { return true }
        let digits = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        return Double(digits) / Double(scalars.count) > 0.65 && !cleaned.contains("%")
    }

    private static func displayName(from token: String) -> String {
        token
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func percent(from token: String) -> String? {
        token.range(of: #"\d+([,.]\d+)?\s*%"#, options: .regularExpression).map { String(token[$0]) }
    }

    private static let junkPhrases: [String] = [
        "kuhl und trocken", "nach dem offnen", "mindestens haltbar", "zubereitung",
        "serviervorschlag", "aufbewahren", "aufbewahrung", "gelbe tonne",
        "gruner punkt", "recycling", "entsorgen", "rainforest alliance", "fairtrade",
        "rspo", "fsc", "hergestellt", "hersteller", "vertrieb", "adresse",
        "kontakt", "portionen", "packung enthalt", "barcode", "ean", "chargennummer",
        "losnummer", "nahrwerte", "nutrition", "durchschnittliche nahrwerte",
        "flasche", "etikett", "rezyklat", "recyclat", "richtig trennen", "gilt in de",
        "spruhkopf", "spruehkopf", "material ohne", "superfood", "fruchtige",
        "macht", "kleine", "grosse", "große", "perfel", "zwischen", "fur zwisch",
        "fuer zwisch", "muesli", "musli", "halten", "reich an", "ballaststoffen",
        "von natur aus", "kann spuren von", "trocken lagern", "isernhagen", "gmbh",
        "plz", "tel", "www"
    ]

    private static let ingredientClues: [String] = [
        "zucker", "sirup", "glukose", "fruktose", "dextrose", "sucre", "sirop", "ol", "fett",
        "palm", "raps", "sonnenblumen", "mais", "weizen", "mehl", "milch",
        "pulver", "kakao", "haselnuss", "soja", "lecithin", "emulgator",
        "aroma", "vanillin", "salz", "lab", "kulturen", "gelatine", "starke",
        "thunfisch", "bohnen", "karotten", "paprika", "wasser", "butter",
        "farine", "ble", "gluten", "levure", "sel", "eau", "alcool", "aqua",
        "parfum", "fragrance", "sodium", "sulfate", "dimethicone", "peg"
    ]
}
