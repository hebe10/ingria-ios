import Foundation

struct IngredientGuideStore {
    private(set) var entries: [IngredientGuideEntry] = []
    private(set) var sortedEntries: [IngredientGuideEntry] = []
    private(set) var aliases: [String: [String]] = [:]

    nonisolated init() {}

    nonisolated static func loadFromBundle() throws -> IngredientGuideStore {
        var store = IngredientGuideStore()
        try store.load()
        return store
    }

    nonisolated static func loadFromBundleInBackground() async throws -> IngredientGuideStore {
        try await Task.detached(priority: .userInitiated) {
            try loadFromBundle()
        }.value
    }

    nonisolated mutating func load() throws {
        let decoder = JSONDecoder()
        let foodURL = try Self.url(named: "ingredients.food", ext: "json")
        let beautyURL = try Self.url(named: "ingredients.beauty", ext: "json")
        let aliasesURL = try Self.url(named: "aliases", ext: "json")

        let food = try decoder.decode([IngredientGuideEntry].self, from: Data(contentsOf: foodURL))
        let beauty = try decoder.decode([IngredientGuideEntry].self, from: Data(contentsOf: beautyURL))
        let aliasMap = try decoder.decode([String: [String]].self, from: Data(contentsOf: aliasesURL))

        self.entries = food + beauty
        self.sortedEntries = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.aliases = aliasMap
    }

    func groupedEntries(category: String = "all", query: String = "") -> [IngredientGuideEntry] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = search(query: query, category: category)
            return matches.map(\.entry)
        }
        guard category != "all" else { return sortedEntries }
        return sortedEntries.filter { matchesCategory($0.category, requested: category) }
    }

    func search(query: String, category: String = "all", limit: Int = 50) -> [IngredientMatch] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var exactName: [IngredientMatch] = []
        var exactAlias: [IngredientMatch] = []
        var startsWith: [IngredientMatch] = []
        var includes: [IngredientMatch] = []
        var seen = Set<String>()

        for entry in entries {
            if category != "all", !matchesCategory(entry.category, requested: category) { continue }

            let name = normalize(entry.name)
            let allAliases = normalizedAliases(for: entry)
            let matchesExactName = name == normalizedQuery
            let matchesExactAlias = allAliases.contains(normalizedQuery)
            let matchesStartsWith = name.hasPrefix(normalizedQuery) || allAliases.contains(where: { $0.hasPrefix(normalizedQuery) })
            let matchesIncludes = name.contains(normalizedQuery) || allAliases.contains(where: { $0.contains(normalizedQuery) })

            guard matchesExactName || matchesExactAlias || matchesStartsWith || matchesIncludes else { continue }
            guard !seen.contains(entry.id) else { continue }
            seen.insert(entry.id)

            let match = IngredientMatch(entry: entry)
            if matchesExactName { exactName.append(match) }
            else if matchesExactAlias { exactAlias.append(match) }
            else if matchesStartsWith { startsWith.append(match) }
            else { includes.append(match) }
        }

        return Array((exactName + exactAlias + startsWith + includes).prefix(limit))
    }

    func resolveCandidates(in text: String, preferredCategory: String? = nil) -> [IngredientGuideEntry] {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return [] }

        let filtered = entries.filter { entry in
            guard let preferredCategory else { return true }
            return matchesCategory(entry.category, requested: preferredCategory)
        }
        let matches = filtered.compactMap { entry -> (entry: IngredientGuideEntry, score: Int, phraseLength: Int)? in
            let name = normalize(entry.name)
            let aliases = normalizedAliases(for: entry)

            if name == normalizedText {
                return (entry, 0, name.count)
            }
            if aliases.contains(normalizedText) {
                return (entry, 1, normalizedText.count)
            }
            if containsIngredientPhrase(name, in: normalizedText) {
                return (entry, 2, name.count)
            }
            if let alias = aliases.first(where: { containsIngredientPhrase($0, in: normalizedText) }) {
                return (entry, 3, alias.count)
            }

            return nil
        }

        return matches.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            if severityRank($0.entry.status) != severityRank($1.entry.status) {
                return severityRank($0.entry.status) < severityRank($1.entry.status)
            }
            return $0.phraseLength > $1.phraseLength
        }.map(\.entry)
    }

    func normalizedAliases(for entry: IngredientGuideEntry) -> [String] {
        let aliasValues = entry.aliases + (aliases[entry.id] ?? [])
        return Array(Set(aliasValues.map(normalize))).filter { alias in
            !alias.isEmpty && !ignoredMatchingAliases.contains(alias)
        }
    }

    func shortReason(for entry: IngredientGuideEntry, language: AppLanguage? = nil) -> String {
        if let language {
            let localized = language == .german ? entry.reason_de : entry.reason_en
            if let localized, !localized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanReason(localized, for: entry)
            }
        }

        if let specificReason = specificShortReason(for: entry, language: language) {
            return specificReason
        }

        let rawReason = entry.why_bad?.first
            ?? entry.why_moderate?.first
            ?? entry.why_good?.first
            ?? entry.verdict
            ?? "No explanation added yet."

        return cleanReason(rawReason, for: entry)
    }

    func alternatives(for entry: IngredientGuideEntry) -> [String] {
        switch entry.id {
        case "vanillin":
            return ["Vanilla extract", "Vanilla bean", "Vanilla powder"]
        case "generic_flavorings", "natural_flavors", "artificial_flavors":
            return ["Unflavored version", "Shorter ingredient formula"]
        case "e476_pgpr":
            return ["Chocolate without E476", "Shorter ingredient chocolate"]
        case "palm_oil":
            return ["Cocoa butter", "Extra virgin olive oil"]
        case "sugar", "cane_sugar":
            return ["Whole-fruit sweetened option", "Lower-sugar version"]
        default:
            return []
        }
    }

    private nonisolated static func url(named: String, ext: String) throws -> URL {
        if let url = Bundle.main.url(forResource: named, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: named, withExtension: ext, subdirectory: "Resources") {
            return url
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let activeProjectFallback = root.appendingPathComponent("INGRIA/INGRIA/Resources/\(named).\(ext)")
        if FileManager.default.fileExists(atPath: activeProjectFallback.path) {
            return activeProjectFallback
        }
        let fallback = root.appendingPathComponent("IngriaIOS/Resources/\(named).\(ext)")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        throw NSError(domain: "IngriaGuideStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "\(named).\(ext) not found"])
    }

    func normalize(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[‐‑‒–—−]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[.,/()]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ignoredMatchingAliases: Set<String> {
        [
            "sugar",
            "processed sugar",
            "sugar alcohol",
            "processed oil",
            "seed oil",
            "artificial color",
            "artificial sweetener",
            "preservative",
            "emulsifier",
            "gum",
            "fiber",
            "protein",
            "flavor",
            "fragrance",
            "surfactant"
        ]
    }

    private func containsIngredientPhrase(_ phrase: String, in normalizedText: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        let pattern = #"(^|\s)"# + NSRegularExpression.escapedPattern(for: phrase) + #"($|\s)"#
        return normalizedText.range(of: pattern, options: .regularExpression) != nil
    }

    private func matchesCategory(_ entryCategory: String, requested: String) -> Bool {
        entryCategory == requested || entryCategory == "both"
    }

    private func specificShortReason(for entry: IngredientGuideEntry, language: AppLanguage? = nil) -> String? {
        let normalizedName = normalize(entry.name)

        if language == .german {
            switch entry.id {
            case "sugar":
                return "Raffinierter Süßungsstoff; vor allem ein Marker für stärker verarbeitete Produkte."
            case "palm_oil":
                return "Palmöl oder Palmfett; häufig verarbeitet und für Textur, Kosten oder Haltbarkeit eingesetzt."
            case "vanillin":
                return "Isolierter vanilleähnlicher Aromastoff. Transparentere Rezepturen nennen echte Vanille."
            case "generic_flavorings", "natural_flavors", "artificial_flavors":
                return "Vage Aromaangabe. Die genaue Zusammensetzung ist nicht klar erkennbar."
            default:
                break
            }
        }

        switch entry.id {
        case "sugar":
            return "Refined sweetener used mainly for taste, not ingredient quality."
        case "cane_sugar", "raw_cane_sugar", "organic_cane_sugar":
            return "Still a refined or concentrated sweetener, even when the label sounds more natural."
        case "palm_oil":
            return "Processed fat commonly used in packaged foods for texture, cost, and shelf stability."
        case "palm_kernel_oil":
            return "Refined palm-derived fat often used to create a cheaper, more shelf-stable texture."
        case "vanillin":
            return "Isolated vanilla-like flavoring. Cleaner labels use real vanilla or clearly name the source."
        case "vanilla_extract":
            return "Flavoring entry needs review. Real vanilla extract is usually acceptable when clearly listed."
        case "generic_flavorings", "natural_flavors", "artificial_flavors":
            return "Vague flavor label. It does not tell you exactly what substances were used."
        case "maltodextrin":
            return "Highly processed starch-derived ingredient used for sweetness, bulk, or texture."
        case "glucose_syrup", "glucose_fructose_syrup", "high_fructose_corn_syrup", "invert_sugar_syrup", "corn_syrup", "dextrose":
            return "Processed sweetener used in formulated foods for sweetness, bulk, or browning."
        case "carrageenan":
            return "Processed seaweed-derived thickener used to change texture in packaged products."
        case "guar_gum", "xanthan_gum", "locust_bean_gum", "acacia_fiber", "acacia_gum":
            return "Texture builder used to thicken or stabilize products. It can signal a more engineered formula."
        case "e476_pgpr":
            return "Industrial emulsifier used to adjust texture and reduce cocoa butter needs in chocolate."
        case "skim_milk_powder":
            return "Powdered dairy used for texture and sweetness. Simpler labels usually use milk or cream."
        case "whey_powder":
            return "Processed dairy powder used to build texture, sweetness, or bulk."
        case "whey_protein":
            return "Processed dairy isolate used to raise protein or change texture."
        case "soy_lecithin":
            return "Soy-based emulsifier used to keep fat and water mixed in a processed formula."
        case "sunflower_lecithin":
            return "Emulsifier used to keep texture stable. Lower concern, but still a formulation marker."
        case "mono_and_diglycerides":
            return "Emulsifier used to improve texture and shelf life in processed foods."
        case "polysorbate_80":
            return "Synthetic emulsifier used to keep mixtures stable in processed products."
        case "carboxymethylcellulose":
            return "Processed cellulose thickener used to create a smoother, more stable texture."
        case "bha", "bht", "tbhq":
            return "Synthetic preservative used to slow fat oxidation and extend shelf life."
        case "sodium_nitrite", "sodium_nitrate":
            return "Curing preservative used in processed meats for color and shelf life."
        case "acesulfame_potassium", "aspartame", "sucralose", "saccharin":
            return "Artificial sweetener used to create sweetness without sugar in highly formulated products."
        case "red_40", "yellow_5", "yellow_6", "blue_1", "blue_2", "acid_violet_43":
            return "Synthetic color added for appearance only."
        default:
            break
        }

        if normalizedName.contains("skim") && normalizedName.contains("milk") && normalizedName.contains("powder") {
            return "Powdered dairy used for texture and sweetness. Simpler labels usually use milk or cream."
        }
        if normalizedName.contains("milk powder") || normalizedName.contains("milchpulver") {
            return "Powdered dairy ingredient used to build texture in a more processed formula."
        }
        if normalizedName.contains("whey") || normalizedName.contains("molken") {
            return "Processed dairy ingredient used for texture, sweetness, or protein content."
        }
        if normalizedName.contains("lecithin") || normalizedName.contains("lecithine") || normalizedName.contains("lecithin") {
            return "Emulsifier used to keep texture stable. Lower concern, but still a formulation marker."
        }
        if normalizedName.contains("palm") && normalizedName.contains("oil") {
            return "Processed fat commonly used in packaged foods for texture, cost, and shelf stability."
        }
        if normalizedName == "flavorings" || normalizedName == "flavourings" || normalizedName == "aroma" || normalizedName.contains("flavoring") || normalizedName.contains("flavouring") {
            return "Vague flavor label. It does not tell you exactly what substances were used."
        }
        if normalizedName.contains("emulsifier") || normalizedName.contains("emulgator") {
            return "Processing aid used to keep ingredients mixed and texture stable."
        }

        let tags = Set((entry.tags ?? []).map(normalize))
        let mechanism = normalize(entry.mechanism ?? "")

        if tags.contains("seed oil") || mechanism == "seed oil" {
            return "Refined seed oil used for neutral taste, cost, and shelf stability."
        }
        if tags.contains("processed oil") || mechanism == "processed oil" {
            return "Processed oil used for texture, cost, or shelf stability rather than ingredient quality."
        }
        if tags.contains("artificial sweetener") || mechanism == "artificial sweetener" {
            return "Artificial sweetener commonly found in highly formulated products."
        }
        if tags.contains("artificial color") || mechanism == "artificial color" {
            return "Synthetic color added for appearance only. It does not improve the food or formula itself."
        }
        if tags.contains("preservative") || mechanism == "preservative" {
            return "Preservative used to extend shelf life in a more formulated product."
        }
        if tags.contains("flavor") || mechanism == "flavor" {
            return "Flavoring system with limited transparency. Cleaner labels name the real source."
        }
        if tags.contains("gum") || mechanism == "gum" {
            return "Thickener or stabilizer used to engineer texture in processed products."
        }

        return nil
    }

    private func cleanReason(_ reason: String, for entry: IngredientGuideEntry) -> String {
        var cleaned = IngredientCopyFormatter.clean(reason)
            .replacingOccurrences(of: #"(?i)^INGRIA flags\s+.+?\s+because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA marks\s+.+?\s+as questionable because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA treats\s+.+?\s+as clean because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is flagged as an avoid ingredient because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is flagged as avoid\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is a questionable ingredient\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+A cleaner product would normally avoid this ingredient or use a simpler named source\.?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i),?\s+so it is a strict clean-label red flag\.?"#, with: ".", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstrict clean-label standards\b"#, with: "the ingredient standard", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstrict clean-label\b"#, with: "ingredient", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bdepends on context\b"#, with: "context matters", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bavoid additive\b"#, with: "additive", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bavoid ingredient\b"#, with: "ingredient", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.range(of: #"^[a-z]"#, options: .regularExpression) != nil {
            cleaned.replaceSubrange(cleaned.startIndex...cleaned.startIndex, with: String(cleaned[cleaned.startIndex]).uppercased())
        }

        if !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") && !cleaned.hasSuffix("?") {
            cleaned += "."
        }

        return cleaned
    }

    private func severityRank(_ status: IngredientStatus) -> Int {
        switch status {
        case .avoid: return 0
        case .watch: return 1
        case .clean: return 2
        case .insufficientData, .neutral: return 3
        }
    }
}

struct IngredientMatch: Identifiable {
    let id = UUID()
    let entry: IngredientGuideEntry
}
