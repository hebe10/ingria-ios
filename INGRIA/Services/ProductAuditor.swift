import Foundation

struct ProductAuditor {
    var guide: IngredientGuideStore

    func audit(product: RawProduct) -> ProductAudit {
        let tokens = (product.ingredients.isEmpty
            ? parseIngredients(product.cleanedIngredientsText.isEmpty ? product.ingredientsText : product.cleanedIngredientsText)
            : product.ingredients.map(\.originalText))
            .map(cleanDisplayToken)
            .filter { !$0.isEmpty }
        let hasReadableIngredients = product.confidence == .structured || product.confidence == .extractedFromText

        let tagCandidates = hasReadableIngredients ? (product.ingredientTags + product.additiveTags)
            .map { $0.replacingOccurrences(of: #"^[a-z]{2}:"# , with: "", options: .regularExpression) }
            .map { $0.replacingOccurrences(of: "-", with: " ") } : []
        let guideCandidates = hasReadableIngredients ? (tokens.isEmpty ? tagCandidates : tokens) : []

        var seen = Set<String>()
        var matches: [IngredientGuideEntry] = []
        var directMatches: [AuditedIngredient] = []
        var tokenStatuses: [String: IngredientStatus] = [:]
        var resolvedCandidateCache: [String: [IngredientGuideEntry]] = [:]
        var directRuleCache: [String: DirectIngredientRule?] = [:]

        func cachedDirectRule(for token: String) -> DirectIngredientRule? {
            let key = IngredientExtractor.normalize(token)
            if let cached = directRuleCache[key] {
                return cached
            }
            let resolved = directRuleMatch(for: token)
            directRuleCache[key] = resolved
            return resolved
        }

        func cachedGuideCandidates(for token: String) -> [IngredientGuideEntry] {
            let key = "\(product.category)|\(IngredientExtractor.normalize(token))"
            if let cached = resolvedCandidateCache[key] {
                return cached
            }
            let resolved = guide.resolveCandidates(in: token, preferredCategory: product.category)
            resolvedCandidateCache[key] = resolved
            return resolved
        }

        for token in hasReadableIngredients ? tokens : [] {
            if let direct = cachedDirectRule(for: token), !seen.contains(direct.id) {
                seen.insert(direct.id)
                directMatches.append(AuditedIngredient(
                    id: direct.id,
                    name: direct.displayName,
                    nameDE: direct.displayNameDE,
                    nameEN: direct.displayNameEN,
                    status: direct.status,
                    reason: direct.reason,
                    reasonDE: direct.reasonDE,
                    reasonEN: direct.reasonEN,
                    euStatus: "",
                    processingLevel: processingLevel(for: direct.status),
                    alternatives: []
                ))
                tokenStatuses[IngredientExtractor.normalize(token)] = direct.status
            }
        }

        for candidate in guideCandidates {
            if cachedDirectRule(for: candidate) != nil {
                continue
            }
            for match in cachedGuideCandidates(for: candidate) where !seen.contains(match.id) {
                seen.insert(match.id)
                matches.append(match)
            }
        }

        let flaggedFromGuide = matches
            .filter { $0.status == .avoid || $0.status == .watch }
            .map {
                AuditedIngredient(
                    id: $0.id,
                    name: $0.name,
                    nameDE: $0.name_de,
                    nameEN: $0.name_en ?? $0.name,
                    status: $0.status,
                    reason: guide.shortReason(for: $0, language: nil),
                    reasonDE: guide.shortReason(for: $0, language: .german),
                    reasonEN: guide.shortReason(for: $0, language: .englishUK),
                    euStatus: $0.regulatory?.eu ?? "",
                    processingLevel: processingLevel(for: $0),
                    alternatives: guide.alternatives(for: $0)
                )
            }
        let flagged = (directMatches + flaggedFromGuide)
            .filter { $0.status == .avoid || $0.status == .watch }

        let displayIngredients: [DisplayIngredient] = (hasReadableIngredients ? (tokens.isEmpty ? matches.map(\.name) : tokens) : []).map { token in
            let normalizedToken = IngredientExtractor.normalize(token)
            if let status = tokenStatuses[normalizedToken] ?? cachedDirectRule(for: token)?.status {
                return DisplayIngredient(label: token, status: status)
            }

            let resolvedIDs = Set(cachedGuideCandidates(for: token).map(\.id))
            let matched = matches.first { resolvedIDs.contains($0.id) }

            return DisplayIngredient(
                label: token,
                status: matched?.status ?? .neutral
            )
        }

        let avoidCount = flagged.filter { $0.status == .avoid }.count
        let watchCount = flagged.filter { $0.status == .watch }.count

        // Coverage tracking — every parsed token must resolve to one of:
        // matched_avoid, matched_review, matched_clean, or unknown. Tokens
        // marked .neutral by direct rules are still considered recognized
        // (we have a deliberate stance on them — they are not a black box).
        let totalCount = displayIngredients.count
        let recognizedCount = displayIngredients.filter { $0.status != .insufficientData }.count
            // .neutral is treated as recognized; only .insufficientData would
            // be unrecognized, but display tokens never get that status today.
            // We compute "unknown" below from the actual token-resolution path.
        let unknownTokens: [String] = displayIngredients.compactMap { item in
            // A display ingredient is "unknown" when it has neutral status
            // AND was not produced by a direct rule (direct rules are an
            // explicit decision; neutral-from-no-match is the silent skip).
            guard item.status == .neutral else { return nil }
            let normalized = IngredientExtractor.normalize(item.label)
            if tokenStatuses[normalized] != nil { return nil }
            // If the guide returned no candidates, the token is unknown.
            let candidates = resolvedCandidateCache["\(product.category)|\(normalized)"] ?? []
            return candidates.isEmpty ? item.label : nil
        }
        let unknownCount = unknownTokens.count
        // Recognized = total minus unknown. Use this for the coverage signal
        // shown in the UI — it answers "what fraction of the label did we
        // actually evaluate?".
        let recognizedAdjusted = max(0, totalCount - unknownCount)
        _ = recognizedCount // reserved for future telemetry
        let coverageRatio: Double = totalCount > 0 ? Double(recognizedAdjusted) / Double(totalCount) : 0
        let cleanCount = max(0, recognizedAdjusted - avoidCount - watchCount)

        // Verdict gating. Rules:
        //   - No tokens at all → INSUFFICIENT_DATA
        //   - Any AVOID match → AVOID (severity wins)
        //   - Any REVIEW match (and no AVOID) → REVIEW (.watch in the enum)
        //   - Coverage < 0.60 → INSUFFICIENT_DATA (not enough data to claim CLEAN)
        //   - Coverage < 0.80 → REVIEW (partial — never CLEAN)
        //   - Coverage ≥ 0.80, no AVOID/REVIEW hits → CLEAN
        let finalStatus: IngredientStatus
        let summary: String
        let isPartial: Bool

        if !hasReadableIngredients || totalCount == 0 {
            finalStatus = .insufficientData
            summary = "Ingredient list unclear. Scan or paste the ingredients to check this product."
            isPartial = true
        } else if avoidCount > 0 {
            finalStatus = .avoid
            summary = "INGRIA found a significant concern based on its screening criteria."
            isPartial = coverageRatio < 0.60
        } else if watchCount > 0 {
            finalStatus = .watch
            summary = coverageRatio < 0.80
                ? "More information or human review may be needed. Some ingredients were not recognized."
                : "More information or human review may be needed."
            isPartial = coverageRatio < 0.80
        } else if coverageRatio < 0.60 {
            finalStatus = .insufficientData
            summary = "Most ingredients on this label could not be matched against the INGRIA database. Result is not reliable yet."
            isPartial = true
        } else if coverageRatio < 0.80 {
            finalStatus = .watch
            summary = "Partial result. \(unknownCount) ingredient\(unknownCount == 1 ? "" : "s") could not be verified, so INGRIA cannot mark this as fully clean."
            isPartial = true
        } else {
            finalStatus = .clean
            summary = "No obvious concern found from the available ingredient data."
            isPartial = false
        }

        let score = computeScore(
            finalStatus: finalStatus,
            coverageRatio: coverageRatio,
            avoidCount: avoidCount,
            watchCount: watchCount,
            totalCount: totalCount
        )

        return ProductAudit(
            barcode: product.barcode,
            productName: product.name,
            brand: product.brand,
            store: nil,
            imageURL: product.imageURL,
            finalStatus: finalStatus,
            summaryLine: summary,
            avoidCount: avoidCount,
            watchCount: watchCount,
            cleanCount: cleanCount,
            displayIngredients: displayIngredients,
            flaggedIngredients: flagged,
            rawIngredientsText: product.ingredientsText,
            cleanedIngredientsText: product.cleanedIngredientsText,
            source: sourceDescription(for: product),
            productCategory: product.category == "beauty" ? "Beauty / personal care" : "Food",
            checkedAt: Date(),
            confidence: product.confidence,
            totalIngredientCount: totalCount,
            recognizedIngredientCount: recognizedAdjusted,
            unknownIngredientCount: unknownCount,
            coverageRatio: coverageRatio,
            unknownIngredients: unknownTokens,
            isPartialResult: isPartial,
            score: score
        )
    }

    /// Rough 0–100 product score. Anchored on coverage + severity. Not a
    /// medical claim — purely a transparency signal so users can compare
    /// products at a glance.
    private func computeScore(
        finalStatus: IngredientStatus,
        coverageRatio: Double,
        avoidCount: Int,
        watchCount: Int,
        totalCount: Int
    ) -> Int? {
        guard totalCount > 0 else { return nil }
        if finalStatus == .insufficientData { return nil }

        let avoidPenalty = min(80, avoidCount * 22)
        let watchPenalty = min(40, watchCount * 8)
        let coverageBoost = Int(coverageRatio * 25)
        let raw = 75 - avoidPenalty - watchPenalty + coverageBoost
        return max(0, min(100, raw))
    }

    func auditLabelText(_ text: String, productName: String = "Scanned label", category: String = "food") -> ProductAudit {
        let extraction = IngredientExtractor.extract(text, source: "Manual ingredient text")
        return audit(product: RawProduct(
            barcode: "",
            name: productName,
            brand: "User scan",
            imageURL: nil,
            ingredientsImageURL: nil,
            ingredientsText: text,
            cleanedIngredientsText: extraction.cleanedText,
            ingredients: extraction.ingredients,
            ingredientTags: [],
            additiveTags: [],
            ingredientsAnalysisTags: [],
            novaGroup: nil,
            category: category,
            confidence: extraction.isValid ? .extractedFromText : .unusableData,
            productExists: true,
            source: "Manual ingredient text"
        ))
    }

    private func parseIngredients(_ text: String) -> [String] {
        // Delegate to the paren-aware tokenizer in IngredientExtractor so
        // every entry point uses the same parser and we don't keep two
        // implementations in sync.
        IngredientExtractor.tokenize(text)
            .map(cleanDisplayToken)
            .filter { !$0.isEmpty }
    }

    private func cleanDisplayToken(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[_]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,;:.])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,;:.])\s*"#, with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:-–—")))
    }

    private func isReadableIngredientList(_ text: String, tokens: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }

        let lowered = trimmed.lowercased()
        let missingMarkers = [
            "not indicated",
            "not specified",
            "ingredients missing",
            "no ingredients",
            "unknown",
            "n/a"
        ]
        if missingMarkers.contains(where: { lowered.contains($0) }) { return false }
        if trimmed.contains("�") || trimmed.contains("???") { return false }

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 3 else { return false }

        let latinOrGermanLetters = letters.filter { scalar in
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZäöüÄÖÜßéèêáàâíìîóòôúùûçÇñÑ").contains(scalar)
        }
        let latinRatio = Double(latinOrGermanLetters.count) / Double(letters.count)
        guard latinRatio >= 0.68 else { return false }

        if tokens.count >= 2 { return true }

        let normalized = trimmed
            .replacingOccurrences(of: #"^\s*(ingredients?|zutaten|ingr[eé]dients?|ingrediënten)\s*:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = normalized.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount <= 8 || lowered.contains("ingredients") || lowered.contains("zutaten")
    }

    private func processingLevel(for entry: IngredientGuideEntry) -> Int {
        switch entry.status {
        case .avoid: return 4
        case .watch: return 3
        case .clean: return 1
        case .insufficientData, .neutral: return 0
        }
    }

    private func processingLevel(for status: IngredientStatus) -> Int {
        switch status {
        case .avoid: return 4
        case .watch: return 3
        case .clean: return 1
        case .insufficientData, .neutral: return 0
        }
    }

    private func sourceDescription(for product: RawProduct) -> String {
        if product.barcode.isEmpty { return product.source }
        return "\(product.source) · \(product.confidence.rawValue)"
    }

    private func directRuleMatch(for token: String) -> DirectIngredientRule? {
        let normalized = IngredientExtractor.normalize(token)
        guard !normalized.isEmpty else { return nil }
        return Self.directRules.first { rule in
            rule.terms.contains { term in
                containsTerm(term, in: normalized)
            }
        }
    }

    private func containsTerm(_ term: String, in normalized: String) -> Bool {
        let normalizedTerm = IngredientExtractor.normalize(term)
        guard !normalizedTerm.isEmpty else { return false }
        let pattern = #"(^|\s)"# + NSRegularExpression.escapedPattern(for: normalizedTerm) + #"($|\s|\d|%)"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private func severityRank(_ status: IngredientStatus) -> Int {
        switch status {
        case .avoid: return 0
        case .watch: return 1
        case .clean: return 2
        case .insufficientData, .neutral: return 3
        }
    }

    private static let directRules: [DirectIngredientRule] = [
        DirectIngredientRule(id: "de_glucose_fructose_syrup", displayName: "Glukose-Fruktose-Sirup", status: .avoid, reason: "Raffinierter Sirup; typischer Marker fuer stark verarbeitete Produkte.", terms: ["Glukose-Fruktose-Sirup", "Glucose-Fructose-Sirup", "Fruktose-Glukose-Sirup"]),
        DirectIngredientRule(id: "de_glucose_syrup", displayName: "Glukosesirup", status: .avoid, reason: "Raffinierter Sirup; typischer Marker fuer stark verarbeitete Produkte.", terms: ["Glukosesirup", "Glucose syrup"]),
        DirectIngredientRule(id: "de_invert_sugar_syrup", displayName: "Invertzuckersirup", status: .avoid, reason: "Raffinierter Sirup; typischer Marker fuer stark verarbeitete Produkte.", terms: ["Invertzuckersirup", "Invertzucker"]),
        DirectIngredientRule(id: "de_maltodextrin", displayName: "Maltodextrin", status: .avoid, reason: "Stark verarbeiteter Staerkezucker fuer Suessung, Volumen oder Textur.", terms: ["Maltodextrin"]),
        DirectIngredientRule(id: "de_dextrose", displayName: "Dextrose", status: .avoid, reason: "Raffinierter Suessungsstoff; meist ein Marker fuer verarbeitete Produkte.", terms: ["Dextrose", "Traubenzucker"]),
        DirectIngredientRule(id: "de_sugar", displayName: "Zucker", status: .avoid, reason: "Raffinierter Suessungsstoff; vor allem ein Marker fuer staerker verarbeitete Produkte.", terms: ["Zucker", "Cane sugar", "Sugar", "Rohrzucker", "Weisszucker", "Karamellsirup", "Sucre"]),
        DirectIngredientRule(id: "de_palm_kernel_oil", displayName: "Palmkernöl", status: .avoid, reason: "Palm-basiertes Fett; haeufig verarbeitet und fuer Textur oder Haltbarkeit eingesetzt.", terms: ["Palmkernöl", "Palmkernfett"]),
        DirectIngredientRule(id: "de_palm_oil", displayName: "Palmöl", status: .avoid, reason: "Palmöl oder Palmfett; haeufig verarbeitet und fuer Textur, Kosten oder Haltbarkeit eingesetzt.", terms: ["Palmöl", "Palmfett", "Palm oil", "huile de palme"]),
        DirectIngredientRule(id: "de_hardened_fat", displayName: "Gehärtetes Fett", status: .avoid, reason: "Stark verarbeitetes Fett; INGRIA markiert es als deutlichen Rezepturhinweis.", terms: ["gehärtetes Fett", "teilweise gehärtetes Fett", "hydrogenated fat"]),
        DirectIngredientRule(id: "de_rapeseed_oil", displayName: "Rapsöl", status: .avoid, reason: "Raffiniertes Saatöl; INGRIA markiert es als Hinweis auf eine staerker verarbeitete Rezeptur.", terms: ["Rapsöl", "Canola oil"]),
        DirectIngredientRule(id: "de_sunflower_oil", displayName: "Sonnenblumenöl", status: .avoid, reason: "Raffiniertes Saatöl; INGRIA markiert es als Hinweis auf eine staerker verarbeitete Rezeptur.", terms: ["Sonnenblumenöl", "Sunflower oil"]),
        DirectIngredientRule(id: "de_corn_oil", displayName: "Maiskeimöl", status: .avoid, reason: "Raffiniertes Saatöl; INGRIA markiert es als Hinweis auf eine staerker verarbeitete Rezeptur.", terms: ["Maiskeimöl", "Maisöl", "Corn oil"]),
        DirectIngredientRule(id: "de_vegetable_oil", displayName: "Pflanzenöl", status: .avoid, reason: "Unklar benanntes Pflanzenöl; meist raffinierte Oelquelle ohne genaue Qualitaetsangabe.", terms: ["Pflanzenöl", "Pflanzliche Öle", "pflanzliches Öl", "vegetable oil"]),
        DirectIngredientRule(id: "de_vanillin", displayName: "Vanillin", status: .avoid, reason: "Aromaangabe mit begrenzter Transparenz; sauberere Rezepturen nennen die echte Quelle.", terms: ["Vanillin", "Vanilline", "Ethylvanillin"]),
        DirectIngredientRule(id: "de_aroma", displayName: "Aroma", status: .avoid, reason: "Aromaangabe mit begrenzter Transparenz; die genaue Zusammensetzung ist nicht klar erkennbar.", terms: ["Aroma", "Aromen", "Arôme", "Arômes", "natürliches Aroma", "natürliches Vanillearoma", "Raucharoma", "Flavouring", "Flavoring"]),
        DirectIngredientRule(id: "de_sucralose", displayName: "Sucralose", status: .avoid, reason: "Künstlicher Süßstoff; häufig in stark formulierten Produkten eingesetzt.", terms: ["Sucralose", "E955"]),
        DirectIngredientRule(id: "de_aspartame", displayName: "Aspartam", status: .avoid, reason: "Künstlicher Süßstoff; häufig in stark formulierten Produkten eingesetzt.", terms: ["Aspartam", "Aspartame", "E951"]),
        DirectIngredientRule(id: "de_acesulfame_k", displayName: "Acesulfam K", status: .avoid, reason: "Künstlicher Süßstoff; häufig in stark formulierten Produkten eingesetzt.", terms: ["Acesulfam K", "Acesulfame K", "Ace-K", "E950"]),
        DirectIngredientRule(id: "de_carrageenan", displayName: "Carrageen", status: .avoid, reason: "Stabilisator fuer technische Textur; INGRIA markiert ihn als deutlichen Prüfpunkt.", terms: ["Carrageen", "Carrageenan", "E407"]),
        DirectIngredientRule(id: "de_mono_diglycerides", displayName: "Mono- und Diglyceride von Speisefettsäuren", status: .avoid, reason: "Emulgator fuer Textur und Haltbarkeit in verarbeiteten Produkten.", terms: ["Mono- und Diglyceride von Speisefettsäuren", "E471"]),
        DirectIngredientRule(id: "de_sorbit", displayName: "Sorbit", status: .avoid, reason: "Zuckeralkohol oder Feuchthaltemittel; häufig in stärker formulierten Produkten eingesetzt.", terms: ["Sorbit", "Sorbitol", "E420"]),
        DirectIngredientRule(id: "de_maltit", displayName: "Maltit", status: .avoid, reason: "Zuckeralkohol; häufig in stärker formulierten Produkten eingesetzt.", terms: ["Maltit", "Maltitol", "E965"]),
        DirectIngredientRule(id: "de_skim_milk_powder", displayName: "Magermilchpulver", status: .watch, reason: "Verarbeitetes Milchpulver; meist fuer Textur, Suessung oder Volumen eingesetzt.", terms: ["Magermilchpulver", "Skim milk powder", "Skimmed milk powder", "lait écrémé en poudre", "lait ecreme en poudre"]),
        DirectIngredientRule(id: "de_milk_powder", displayName: "Milchpulver", status: .neutral, reason: "Milchpulver wird ohne weitere Auffälligkeit nicht automatisch markiert.", terms: ["Milchpulver", "Vollmilchpulver", "Buttermilchpulver"]),
        DirectIngredientRule(id: "de_whey_powder", displayName: "Molkenpulver", status: .watch, reason: "Verarbeiteter Molkenbestandteil; meist fuer Textur, Suessung oder Volumen eingesetzt.", terms: ["Molkenpulver", "Süßmolkenpulver", "Süssmolkenpulver", "Whey powder", "lactosérum en poudre", "lactoserum en poudre"]),
        DirectIngredientRule(id: "de_lecithin", displayName: "Lecithine", status: .watch, reason: "Emulgator zur Stabilisierung der Textur; ein Hinweis auf eine stärker formulierte Rezeptur.", terms: ["Lecithin", "Lecithine", "Lécithine", "Lécithines", "Sojalecithin", "Sonnenblumenlecithin", "E322"]),
        DirectIngredientRule(id: "de_emulsifier", displayName: "Emulgator", status: .watch, reason: "Emulgator mit unklarer genauer Art; Quelle und Rezeptur sollten geprüft werden.", terms: ["Emulgator", "Emulgatoren", "émulsifiant", "émulsifiants", "emulsifiant", "emulsifiants"]),
        DirectIngredientRule(id: "de_wheat_flour", displayName: "Weizenmehl", status: .neutral, reason: "Grundbestandteil; wird ohne weitere Auffälligkeit nicht automatisch markiert.", terms: ["Weizenmehl", "Wheat flour", "farine de blé", "farine de ble"]),
        DirectIngredientRule(id: "de_wheat_gluten", displayName: "Weizengluten", status: .neutral, reason: "Grundbestandteil; wird ohne weitere Auffälligkeit nicht automatisch markiert.", terms: ["Weizengluten", "gluten de blé", "gluten de ble"]),
        DirectIngredientRule(id: "de_starch", displayName: "Stärke", status: .neutral, reason: "Texturgebender Grundbestandteil; wird ohne Datenbanktreffer nicht automatisch markiert.", terms: ["Stärke", "Maisstärke", "Kartoffelstärke", "Speisestärke"]),
        DirectIngredientRule(id: "de_gelatin", displayName: "Gelatine", status: .watch, reason: "Kontextabhängige Zutat; Quelle und Produktart sollten geprüft werden.", terms: ["Gelatine", "Speisegelatine"]),
        DirectIngredientRule(id: "de_water", displayName: "Wasser", status: .neutral, reason: "Grundbestandteil; nicht automatisch markiert.", terms: ["Wasser", "Eau", "Water", "Aqua"]),
        DirectIngredientRule(id: "de_yeast", displayName: "Hefe", status: .neutral, reason: "Grundbestandteil; nicht automatisch markiert.", terms: ["Hefe", "Levure", "Yeast"]),
        DirectIngredientRule(id: "de_cocoa_butter", displayName: "Kakaobutter", status: .neutral, reason: "Kakaobestandteil; nicht automatisch markiert.", terms: ["Kakaobutter", "Cocoa butter"]),
        DirectIngredientRule(id: "de_corn_semolina", displayName: "Maisgrieß", status: .neutral, reason: "Grundbestandteil; nicht automatisch markiert.", terms: ["Maisgrieß", "Maisgriess"]),
        DirectIngredientRule(id: "de_alcohol", displayName: "Alkohol", status: .neutral, reason: "Kontextabhängiger Grundbestandteil; nicht automatisch markiert.", terms: ["Alkohol", "Alcool", "Alcohol"]),
        DirectIngredientRule(id: "de_pasteurized_milk", displayName: "Pasteurisierte Kuhmilch", status: .neutral, reason: "Einfacher Milchbestandteil ohne offensichtlichen Prüfpunkt.", terms: ["pasteurisierte Kuhmilch", "pasteurisierte Milch"]),
        DirectIngredientRule(id: "de_salt", displayName: "Speisesalz", status: .neutral, reason: "Einfacher Grundbestandteil ohne offensichtlichen Prüfpunkt.", terms: ["Speisesalz", "Salz", "Sel"]),
        DirectIngredientRule(id: "de_rennet", displayName: "Mikrobielles Lab", status: .neutral, reason: "Typischer Käsebestandteil ohne offensichtlichen Prüfpunkt.", terms: ["mikrobielles Lab", "Lab"]),
        DirectIngredientRule(id: "de_cultures", displayName: "Milchsäurekulturen", status: .neutral, reason: "Typischer Fermentationsbestandteil ohne offensichtlichen Prüfpunkt.", terms: ["Milchsäurekulturen", "Milchsaeurekulturen"])
    ]
}

private struct DirectIngredientRule {
    let id: String
    let displayName: String
    var displayNameDE: String { displayName }
    var displayNameEN: String { englishName(for: id, fallback: displayName) }
    let status: IngredientStatus
    let reason: String
    var reasonDE: String { reason }
    var reasonEN: String { englishReason(for: id, fallback: reason) }
    let terms: [String]

    private func englishName(for id: String, fallback: String) -> String {
        switch id {
        case "de_glucose_fructose_syrup": return "Glucose-fructose syrup"
        case "de_glucose_syrup": return "Glucose syrup"
        case "de_invert_sugar_syrup": return "Invert sugar syrup"
        case "de_dextrose": return "Dextrose"
        case "de_sugar": return "Sugar"
        case "de_palm_kernel_oil": return "Palm kernel oil"
        case "de_palm_oil": return "Palm oil"
        case "de_hardened_fat": return "Hydrogenated fat"
        case "de_rapeseed_oil": return "Rapeseed oil"
        case "de_sunflower_oil": return "Sunflower oil"
        case "de_corn_oil": return "Corn oil"
        case "de_vegetable_oil": return "Vegetable oil"
        case "de_aroma": return "Flavouring"
        case "de_aspartame": return "Aspartame"
        case "de_acesulfame_k": return "Acesulfame K"
        case "de_carrageenan": return "Carrageenan"
        case "de_mono_diglycerides": return "Mono- and diglycerides of fatty acids"
        case "de_maltit": return "Maltitol"
        case "de_skim_milk_powder": return "Skimmed milk powder"
        case "de_milk_powder": return "Milk powder"
        case "de_whey_powder": return "Whey powder"
        case "de_lecithin": return "Lecithins"
        case "de_emulsifier": return "Emulsifier"
        case "de_wheat_flour": return "Wheat flour"
        case "de_wheat_gluten": return "Wheat gluten"
        case "de_starch": return "Starch"
        case "de_gelatin": return "Gelatine"
        case "de_water": return "Water"
        case "de_yeast": return "Yeast"
        case "de_cocoa_butter": return "Cocoa butter"
        case "de_corn_semolina": return "Corn semolina"
        case "de_alcohol": return "Alcohol"
        case "de_pasteurized_milk": return "Pasteurised cow's milk"
        case "de_salt": return "Salt"
        case "de_rennet": return "Microbial rennet"
        case "de_cultures": return "Lactic cultures"
        default: return fallback
        }
    }

    private func englishReason(for id: String, fallback: String) -> String {
        switch id {
        case "de_glucose_fructose_syrup", "de_glucose_syrup", "de_invert_sugar_syrup":
            return "Refined syrup; a common marker of highly processed products."
        case "de_maltodextrin":
            return "Highly processed starch-derived ingredient used for sweetness, bulk, or texture."
        case "de_dextrose":
            return "Refined sweetener; often used in processed products."
        case "de_sugar":
            return "Refined sweetener; mainly a marker of a more processed product."
        case "de_palm_kernel_oil":
            return "Palm-derived fat commonly used for texture and shelf stability."
        case "de_palm_oil":
            return "Palm oil or palm fat; often used for texture, cost, or shelf stability."
        case "de_hardened_fat":
            return "Highly processed fat; a clear formulation marker."
        case "de_rapeseed_oil", "de_sunflower_oil", "de_corn_oil":
            return "Refined seed oil; marked as a sign of a more processed formula."
        case "de_vegetable_oil":
            return "Generic vegetable oil; the exact oil source and quality are unclear."
        case "de_vanillin":
            return "Isolated vanilla-like flavouring; cleaner labels name a real vanilla source."
        case "de_aroma":
            return "Vague flavouring term; the exact composition is not transparent."
        case "de_sucralose", "de_aspartame", "de_acesulfame_k":
            return "Artificial sweetener; commonly used in highly formulated products."
        case "de_carrageenan":
            return "Thickener used for technical texture; a strict review trigger."
        case "de_mono_diglycerides":
            return "Emulsifier used for texture and shelf life in processed products."
        case "de_sorbit":
            return "Sugar alcohol or humectant; often used in more formulated products."
        case "de_maltit":
            return "Sugar alcohol; often used in more formulated products."
        case "de_skim_milk_powder":
            return "Processed dairy powder usually used for texture, sweetness, or bulk."
        case "de_whey_powder":
            return "Processed whey ingredient usually used for texture, sweetness, or bulk."
        case "de_lecithin":
            return "Emulsifier used to stabilise texture; a formulation marker."
        case "de_emulsifier":
            return "Unspecified emulsifier; source and exact type should be reviewed."
        case "de_gelatin":
            return "Context-dependent ingredient; source and product type should be reviewed."
        default:
            return fallback
        }
    }
}
