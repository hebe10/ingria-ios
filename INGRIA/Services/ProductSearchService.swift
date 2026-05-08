import Foundation

struct ProductSearchService {
    func search(query: String) async throws -> [ProductSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let intent = ProductSearchIntent.detect(trimmed)
        LookupLogger.log("search_start", [
            "query": trimmed,
            "intent": intent.rawValue
        ])

        let localResults = await Self.localSearch(query: trimmed, intent: intent, limit: 16)

        if intent == .barcode {
            let barcode = BarcodeValueNormalizer.normalize(trimmed)
            LookupLogger.log("barcode_search", ["barcode": barcode])
            if let local = localResults.first(where: { $0.barcode == barcode }) {
                return [local]
            }
            if let product = try? await fetchProduct(barcode: barcode) {
                return [ProductSearchItem(
                    id: product.barcode,
                    barcode: product.barcode,
                    name: product.name,
                    brand: product.brand,
                    imageURL: product.imageURL,
                    category: product.category,
                    ingredientsText: product.cleanedIngredientsText.isEmpty ? product.ingredientsText : product.cleanedIngredientsText,
                    sourceStatus: product.source.lowercased().contains("beauty") ? .openBeautyFacts : .openFoodFacts,
                    matchSource: .barcode
                )]
            }
        }

        let merged: [ProductSearchItem]
        if localResults.count >= 8 {
            merged = []
        } else {
            async let food = safeSearchFood(query: trimmed, intent: intent)
            async let beauty = safeSearchBeauty(query: trimmed, intent: intent)
            merged = await food + beauty
        }

        var seen = Set<String>()
        let ranked = (localResults + merged)
            .sorted { lhs, rhs in
                rank(lhs, for: trimmed) < rank(rhs, for: trimmed)
            }
            .filter { item in
                guard !seen.contains(item.barcode) else { return false }
                seen.insert(item.barcode)
                return true
            }
        LookupLogger.log("search_done", [
            "query": trimmed,
            "intent": intent.rawValue,
            "local_count": "\(localResults.count)",
            "public_count": "\(merged.count)",
            "ranked_count": "\(ranked.count)"
        ])
        let germanResults = ranked.filter { $0.category.contains(":de") }
        return germanResults.isEmpty ? Array(ranked.prefix(12)) : Array(germanResults.prefix(12))
    }

    func localSuggestions(query: String, limit: Int = 5) async -> [ProductSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await Self.localSearch(query: trimmed, intent: ProductSearchIntent.detect(trimmed), limit: limit)
    }

    func fetchProduct(barcode: String) async throws -> RawProduct? {
        let normalizedBarcode = BarcodeValueNormalizer.normalize(barcode)
        LookupLogger.log("barcode_lookup_start", ["barcode": normalizedBarcode])
        async let foodLookup = safeFetchProduct(barcode: normalizedBarcode, category: "food")
        async let beautyLookup = safeFetchProduct(barcode: normalizedBarcode, category: "beauty")

        let food = await foodLookup
        let beauty = await beautyLookup

        if let food, food.confidence != .unusableData {
            LookupLogger.log("barcode_lookup_hit", ["barcode": normalizedBarcode, "source": food.source, "confidence": food.confidence.rawValue])
            return food
        }
        if let beauty {
            LookupLogger.log("barcode_lookup_hit", ["barcode": normalizedBarcode, "source": beauty.source, "confidence": beauty.confidence.rawValue])
            return beauty
        }
        LookupLogger.log("barcode_lookup_miss", ["barcode": normalizedBarcode])
        return food
    }

    private func searchFood(query: String, intent: ProductSearchIntent) async throws -> [ProductSearchItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let fields = "code,product_name,brands,image_front_small_url,image_small_url,image_url,countries_tags,ingredients_text,ingredients_text_de,ingredients_text_en,ingredients_tags,additives_tags"
        let directURL = URL(string: "https://de.openfoodfacts.org/api/v2/search?search_terms=\(encoded)&countries_tags_en=Germany&page_size=16&fields=\(fields)")!
        let (data, _) = try await fetchData(from: directURL)
        let decoded = try JSONDecoder().decode(ProductSearchResponse.self, from: data)
        var results: [ProductSearchItem] = decoded.products.compactMap { product in
            let imageString = product.image_url ?? product.image_small_url ?? ""
            guard let code = product.code, let name = product.product_name else { return nil }
            let ingredientsText = firstNonEmpty([product.ingredients_text_de, product.ingredients_text, product.ingredients_text_en]) ?? ""
            let matchSource = matchSource(for: query, productName: name, brand: product.brands ?? "", ingredientsText: ingredientsText, barcode: code, intent: intent)
            guard shouldKeepSearchResult(intent: intent, query: query, matchSource: matchSource, ingredientsText: ingredientsText) else { return nil }
            return ProductSearchItem(
                id: code,
                barcode: code,
                name: name,
                brand: product.brands ?? "Unknown brand",
                imageURL: URL(string: imageString),
                category: germanCategory(base: "food", countries: product.countries_tags),
                ingredientsText: ingredientsText,
                ingredientTags: product.ingredients_tags ?? [],
                additiveTags: product.additives_tags ?? [],
                sourceStatus: .openFoodFacts,
                matchSource: matchSource,
                matchedIngredient: matchSource == .ingredient ? query : nil
            )
        }

        do {
            let fallbackURL = URL(string: "https://world.openfoodfacts.org/api/v2/search?search_terms=\(encoded)&countries_tags_en=Germany&page_size=8&fields=\(fields)")!
            let (fallbackData, _) = try await fetchData(from: fallbackURL)
            let fallback = try JSONDecoder().decode(ProductSearchResponse.self, from: fallbackData)
            results += fallback.products.compactMap { product in
                let imageString = product.image_url ?? product.image_small_url ?? ""
                guard let code = product.code, let name = product.product_name else { return nil }
                let ingredientsText = firstNonEmpty([product.ingredients_text_de, product.ingredients_text, product.ingredients_text_en]) ?? ""
                let matchSource = matchSource(for: query, productName: name, brand: product.brands ?? "", ingredientsText: ingredientsText, barcode: code, intent: intent)
                guard shouldKeepSearchResult(intent: intent, query: query, matchSource: matchSource, ingredientsText: ingredientsText) else { return nil }
                return ProductSearchItem(
                    id: code,
                    barcode: code,
                    name: name,
                    brand: product.brands ?? "Unknown brand",
                    imageURL: URL(string: imageString),
                    category: germanCategory(base: "food", countries: product.countries_tags),
                    ingredientsText: ingredientsText,
                    ingredientTags: product.ingredients_tags ?? [],
                    additiveTags: product.additives_tags ?? [],
                    sourceStatus: .openFoodFacts,
                    matchSource: matchSource,
                    matchedIngredient: matchSource == .ingredient ? query : nil
                )
            }
        } catch {
            // The country-filtered API can be slower/less reliable; keep direct results instead of failing search.
        }
        return results
    }

    private func searchBeauty(query: String, intent: ProductSearchIntent) async throws -> [ProductSearchItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let fields = "code,product_name,brands,image_front_small_url,image_small_url,image_url,countries_tags,ingredients_text,ingredients_text_de,ingredients_text_en,ingredients_text_fr"
        let endpoints = [
            "https://de.openbeautyfacts.org/api/v2/search?search_terms=\(encoded)&page_size=14&fields=\(fields)",
            "https://world.openbeautyfacts.org/api/v2/search?search_terms=\(encoded)&page_size=18&fields=\(fields)",
            "https://world.openbeautyfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=18&fields=\(fields)"
        ]

        var results: [ProductSearchItem] = []
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                let (data, _) = try await fetchData(from: url)
                let decoded = try JSONDecoder().decode(ProductSearchResponse.self, from: data)
                results += decoded.products.compactMap {
                    guard let code = $0.code, let name = $0.product_name else { return nil }
                    let ingredientsText = firstNonEmpty([$0.ingredients_text_de, $0.ingredients_text, $0.ingredients_text_en, $0.ingredients_text_fr]) ?? ""
                    let matchSource = matchSource(for: query, productName: name, brand: $0.brands ?? "", ingredientsText: ingredientsText, barcode: code, intent: intent)
                    guard shouldKeepSearchResult(intent: intent, query: query, matchSource: matchSource, ingredientsText: ingredientsText) else { return nil }
                    return ProductSearchItem(
                        id: code,
                        barcode: code,
                        name: name,
                        brand: $0.brands ?? "Unknown brand",
                        imageURL: URL(string: $0.image_url ?? $0.image_small_url ?? ""),
                        category: germanCategory(base: "beauty", countries: $0.countries_tags),
                        ingredientsText: ingredientsText,
                        sourceStatus: .openBeautyFacts,
                        matchSource: matchSource,
                        matchedIngredient: matchSource == .ingredient ? query : nil
                    )
                }
                LookupLogger.log("beauty_search_source", ["endpoint": url.host ?? "", "query": query, "count": "\(results.count)"])
            } catch {
                LookupLogger.log("beauty_search_failed", ["endpoint": url.host ?? "", "query": query, "error": error.localizedDescription])
                continue
            }
        }

        var seen = Set<String>()
        return results
            .sorted { rank($0, for: query) < rank($1, for: query) }
            .filter { item in
                guard !seen.contains(item.barcode) else { return false }
                seen.insert(item.barcode)
                return true
            }
    }

    private func safeFetchProduct(barcode: String, category: String) async -> RawProduct? {
        do {
            return try await fetchProduct(barcode: barcode, category: category)
        } catch {
            LookupLogger.log("barcode_source_failed", ["barcode": barcode, "category": category, "error": error.localizedDescription])
            return nil
        }
    }

    private func fetchProduct(barcode: String, category: String) async throws -> RawProduct? {
        let bases = category == "food"
            ? ["https://de.openfoodfacts.org", "https://world.openfoodfacts.org"]
            : ["https://world.openbeautyfacts.org", "https://de.openbeautyfacts.org"]
        let fields = category == "food"
            ? "code,product_name,product_name_de,brands,image_url,image_small_url,image_front_url,image_ingredients_url,ingredients,ingredients_text,ingredients_text_de,ingredients_text_en,ingredients_tags,ingredients_hierarchy,ingredients_original_tags,additives_tags,ingredients_analysis_tags,nova_group,categories_tags,lang"
            : "code,product_name,product_name_de,brands,image_url,image_small_url,image_front_url,image_ingredients_url,ingredients,ingredients_text,ingredients_text_de,ingredients_text_en,ingredients_tags,ingredients_hierarchy,ingredients_original_tags,additives_tags,ingredients_analysis_tags,nova_group,categories_tags,lang"

        var candidates: [RawProduct] = []
        for base in bases {
            guard let url = URL(string: "\(base)/api/v2/product/\(barcode).json?fields=\(fields)") else { continue }
            do {
                let (data, _) = try await fetchData(from: url)
                let decoded = try JSONDecoder().decode(ProductLookupResponse.self, from: data)
                guard decoded.status == 1, let product = decoded.product else { continue }
                candidates.append(makeRawProduct(from: product, barcode: barcode, category: category))
                LookupLogger.log("barcode_source_checked", ["barcode": barcode, "source": base, "result": "hit"])
            } catch {
                LookupLogger.log("barcode_source_checked", ["barcode": barcode, "source": base, "result": "failed", "error": error.localizedDescription])
                continue
            }
        }

        LookupLogger.log("barcode_source_done", ["barcode": barcode, "category": category, "candidate_count": "\(candidates.count)"])
        return candidates.sorted { productQualityScore($0) > productQualityScore($1) }.first
    }

    private func makeRawProduct(from product: ProductLookupPayload, barcode: String, category: String) -> RawProduct {
        let structuredIngredients = usableStructuredIngredients(from: product.ingredients)
        let rawText = firstRawIngredientText(from: product)
        let extraction = rawText.isEmpty ? nil : IngredientExtractor.extract(rawText, source: "Open product data text")

        let confidence: ProductDataConfidence
        let ingredients: [ProductIngredient]
        let cleanedIngredientsText: String

        if let extraction, shouldPreferExtractedText(extraction, rawText: rawText, structuredIngredients: structuredIngredients) {
            confidence = .extractedFromText
            ingredients = extraction.ingredients
            cleanedIngredientsText = extraction.cleanedText
        } else if !structuredIngredients.isEmpty {
            confidence = .structured
            ingredients = structuredIngredients
            cleanedIngredientsText = structuredIngredients.map(\.originalText).joined(separator: ", ")
        } else if let extraction, extraction.isValid {
            confidence = .extractedFromText
            ingredients = extraction.ingredients
            cleanedIngredientsText = extraction.cleanedText
        } else {
            confidence = .unusableData
            ingredients = []
            cleanedIngredientsText = ""
        }

        return RawProduct(
            barcode: product.code ?? barcode,
            name: product.product_name_de ?? product.product_name ?? "Unknown product",
            brand: product.brands ?? "Unknown brand",
            imageURL: URL(string: product.image_front_url ?? product.image_url ?? product.image_small_url ?? ""),
            ingredientsImageURL: URL(string: product.image_ingredients_url ?? ""),
            ingredientsText: rawText,
            cleanedIngredientsText: cleanedIngredientsText,
            ingredients: ingredients,
            ingredientTags: product.ingredients_tags ?? product.ingredients_hierarchy ?? product.ingredients_original_tags ?? [],
            additiveTags: product.additives_tags ?? [],
            ingredientsAnalysisTags: product.ingredients_analysis_tags ?? [],
            novaGroup: product.nova_group,
            category: category,
            confidence: confidence,
            productExists: true,
            source: category == "beauty" ? "Open Beauty Facts" : "Open Food Facts"
        )
    }

    private func productQualityScore(_ product: RawProduct) -> Int {
        var score = 0
        switch product.confidence {
        case .structured: score += 80
        case .extractedFromText: score += 70
        case .unusableData: score += 10
        case .productNotFound: score -= 100
        }
        score += min(product.ingredients.count * 4, 40)
        score += min(product.cleanedIngredientsText.count / 12, 30)
        if product.imageURL != nil { score += 5 }
        if product.ingredientsText.range(of: #"\b(Zucker|Palmöl|Vanillin|Aqua|Glycerin|Parfum|Sodium)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 8
        }
        return score
    }

    private func shouldPreferExtractedText(
        _ extraction: IngredientExtraction,
        rawText: String,
        structuredIngredients: [ProductIngredient]
    ) -> Bool {
        guard extraction.isValid else { return false }
        if structuredIngredients.isEmpty { return true }
        if extraction.ingredients.count > structuredIngredients.count { return true }

        let normalizedRaw = IngredientExtractor.normalize(rawText)
        let germanSignals = ["zucker", "palmol", "palmfett", "magermilchpulver", "vanillin", "lecithine", "haselnusse"]
        let hasGermanSignals = germanSignals.contains { normalizedRaw.contains($0) }
        let extractedIsCloseEnough = extraction.ingredients.count + 2 >= structuredIngredients.count

        // Germany-first: if OFF gives a fuller German text field and a structured array in another language,
        // use the German text so the visible ingredients and highlighted concerns stay understandable.
        return hasGermanSignals && extractedIsCloseEnough
    }

    private func safeSearchFood(query: String, intent: ProductSearchIntent) async -> [ProductSearchItem] {
        do {
            let results = try await searchFood(query: query, intent: intent)
            LookupLogger.log("food_search_done", ["query": query, "intent": intent.rawValue, "count": "\(results.count)"])
            return results
        } catch {
            LookupLogger.log("food_search_failed", ["query": query, "intent": intent.rawValue, "error": error.localizedDescription])
            return []
        }
    }

    private func safeSearchBeauty(query: String, intent: ProductSearchIntent) async -> [ProductSearchItem] {
        do {
            let results = try await searchBeauty(query: query, intent: intent)
            LookupLogger.log("beauty_search_done", ["query": query, "intent": intent.rawValue, "count": "\(results.count)"])
            return results
        } catch {
            LookupLogger.log("beauty_search_failed", ["query": query, "intent": intent.rawValue, "error": error.localizedDescription])
            return []
        }
    }

    private static func localSearch(query: String, intent: ProductSearchIntent, limit: Int) async -> [ProductSearchItem] {
        return await Task.detached(priority: .userInitiated) {
            searchLocalGermanProducts(query: query, intent: intent, limit: limit, index: localGermanProductIndex)
        }.value
    }

    nonisolated private static func searchLocalGermanProducts(
        query: String,
        intent: ProductSearchIntent,
        limit: Int,
        index: [IndexedLocalGermanProduct]
    ) -> [ProductSearchItem] {
        let normalizedQuery = normalizeValue(query)
        guard normalizedQuery.count >= 2 else { return [] }
        let matches = index.compactMap { indexed -> (ProductSearchItem, Int)? in
            let matchesIngredient = containsIngredient(indexed.ingredients, query: query)
            let matchesName = indexed.name.contains(normalizedQuery)
            let matchesBrand = indexed.brand.contains(normalizedQuery)
            let matchesBarcode = indexed.product.code == BarcodeValueNormalizer.normalize(query)
            if intent == .ingredient {
                guard matchesIngredient else { return nil }
            } else {
                guard indexed.haystack.contains(normalizedQuery) || matchesBarcode else { return nil }
            }
            let score: Int
            if matchesBarcode { score = 0 }
            else if matchesIngredient { score = intent == .ingredient ? 0 : 4 }
            else if indexed.name == normalizedQuery || indexed.brand == normalizedQuery { score = 0 }
            else if indexed.name.hasPrefix(normalizedQuery) || indexed.brand.hasPrefix(normalizedQuery) { score = 1 }
            else if indexed.name.contains(normalizedQuery) || indexed.brand.contains(normalizedQuery) { score = 2 }
            else { score = 5 }
            let product = indexed.product
            let source = matchesBarcode ? ProductSearchMatchSource.barcode : (matchesIngredient ? .ingredient : (matchesBrand ? .brand : .productName))
            let item = ProductSearchItem(
                id: product.code,
                barcode: product.code,
                name: product.name,
                brand: product.brand,
                imageURL: URL(string: product.image_url ?? ""),
                category: "\(product.category):de:local",
                ingredientsText: product.ingredients_text ?? "",
                ingredientTags: product.ingredients_tags ?? [],
                additiveTags: product.additives_tags ?? [],
                sourceStatus: .localSeed,
                matchSource: source,
                matchedIngredient: source == .ingredient ? query : nil
            )
            return (item, score + (product.ingredients_text?.isEmpty == false ? 0 : 2))
        }
        return matches
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func normalize(_ value: String) -> String {
        Self.normalizeValue(value)
    }

    nonisolated private static func normalizeValue(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("INGRIA/1.0 contact@email.com", forHTTPHeaderField: "User-Agent")
        return try await Self.session.data(for: request)
    }

    private func firstRawIngredientText(from product: ProductLookupPayload) -> String {
        let candidates = [
            (product.ingredients_text_de, 30),
            (product.ingredients_text, 20),
            (product.ingredients_text_en, 10)
        ]
        return candidates
            .compactMap { value, priority -> (String, Int)? in
                guard let cleaned = cleanRawIngredientText(value), !cleaned.isEmpty else { return nil }
                return (cleaned, priority + rawIngredientTextScore(cleaned))
            }
            .sorted { $0.1 > $1.1 }
            .first?.0 ?? ""
    }

    private func cleanRawIngredientText(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[_]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:-–—")))
    }

    private func rawIngredientTextScore(_ value: String) -> Int {
        let extraction = IngredientExtractor.extract(value, source: "candidate")
        var score = extraction.isValid ? 50 : 0
        score += min(extraction.ingredients.count * 5, 45)
        score += min(value.count / 18, 25)
        if value.range(of: #"\b(Zucker|Palmöl|Haseln|Magermilch|Vanillin|Aqua|Glycerin|Parfum|Fragrance|Sodium)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 12
        }
        if value.range(of: #"(haltbar|aufbewahren|recycling|adresse|nutrition|nährwerte)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score -= 35
        }
        return score
    }

    private func usableStructuredIngredients(from payload: [OFFIngredient]?) -> [ProductIngredient] {
        guard let payload else { return [] }
        let ingredients = payload.compactMap { item -> ProductIngredient? in
            let original = (item.text_de ?? item.text ?? item.text_en ?? item.id ?? "")
                .replacingOccurrences(of: #"^[a-z]{2}:"# , with: "", options: .regularExpression)
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: #"[_]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:-–—")))
            guard !original.isEmpty else { return nil }
            return ProductIngredient(
                originalText: original,
                normalizedKey: IngredientExtractor.normalize(original),
                displayNameDE: item.text_de ?? item.text ?? original,
                displayNameEN: item.text_en,
                percent: item.percent.map { "\($0)%" },
                source: "Open product data structured"
            )
        }

        let tokens = ingredients.map(\.originalText)
        return IngredientExtractor.isValidIngredientList(
            tokens.joined(separator: ", "),
            tokens: tokens,
            hadMarker: true,
            structured: true
        ) ? ingredients : []
    }

    private func rank(_ item: ProductSearchItem, for query: String) -> Int {
        let normalizedQuery = query.lowercased()
        let name = item.name.lowercased()
        let brand = item.brand.lowercased()
        let germanyBoost = item.category.contains(":de") ? -2 : 0
        let imageBoost = item.imageURL != nil ? 0 : 3
        let ingredientBoost = item.ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 3 : -2
        if name == normalizedQuery || brand == normalizedQuery { return germanyBoost + imageBoost + ingredientBoost }
        if name.hasPrefix(normalizedQuery) || brand.hasPrefix(normalizedQuery) { return 10 + germanyBoost + imageBoost + ingredientBoost }
        if name.contains(normalizedQuery) || brand.contains(normalizedQuery) { return 20 + germanyBoost + imageBoost + ingredientBoost }
        return 100 + imageBoost + ingredientBoost
    }

    private func germanCategory(base: String, countries: [String]?) -> String {
        let isGerman = countries?.contains { $0.lowercased() == "en:germany" || $0.lowercased() == "de:deutschland" } == true
        return isGerman ? "\(base):de" : base
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func matchSource(
        for query: String,
        productName: String,
        brand: String,
        ingredientsText: String,
        barcode: String,
        intent: ProductSearchIntent
    ) -> ProductSearchMatchSource {
        if intent == .barcode || BarcodeValueNormalizer.normalize(query) == barcode {
            return .barcode
        }
        if Self.containsIngredient(Self.normalizeValue(ingredientsText), query: query) {
            return .ingredient
        }

        let normalizedQuery = Self.normalizeValue(query)
        let normalizedBrand = Self.normalizeValue(brand)
        let normalizedName = Self.normalizeValue(productName)
        if normalizedBrand.contains(normalizedQuery) { return .brand }
        if normalizedName.contains(normalizedQuery) { return .productName }
        return .relatedProductName
    }

    private func shouldKeepSearchResult(
        intent: ProductSearchIntent,
        query: String,
        matchSource: ProductSearchMatchSource,
        ingredientsText: String
    ) -> Bool {
        if intent == .ingredient {
            return matchSource == .ingredient && Self.containsIngredient(Self.normalizeValue(ingredientsText), query: query)
        }
        return true
    }

    nonisolated private static func containsIngredient(_ normalizedIngredients: String, query: String) -> Bool {
        let normalizedQuery = normalizeValue(query)
        guard !normalizedQuery.isEmpty, !normalizedIngredients.isEmpty else { return false }
        if normalizedIngredients.contains(normalizedQuery) { return true }

        let variants = ingredientQueryVariants(for: normalizedQuery)
        return variants.contains { !($0.isEmpty) && normalizedIngredients.contains($0) }
    }

    nonisolated private static func ingredientQueryVariants(for normalizedQuery: String) -> [String] {
        var variants = Set([normalizedQuery])
        let synonymGroups: [[String]] = [
            ["glucose syrup", "glucosesyrup", "glukosesirup", "glukose sirup", "sirop de glucose"],
            ["maltodextrin", "maltodextrine"],
            ["sucralose", "sucralose"],
            ["phenoxyethanol", "phenoxyethanol"],
            ["parfum", "fragrance", "aroma"],
            ["aroma", "flavouring", "flavoring", "arome", "arome naturel"],
            ["palm oil", "palmoil", "palmol", "palm fett", "palmfett", "huile de palme"],
            ["carrageenan", "carrageen", "e407"],
            ["alcohol denat", "alcoholdenat", "alcohol denatured"],
            ["limonene", "limonene"],
            ["linalool", "linalool"]
        ]

        for group in synonymGroups {
            let normalizedGroup = group.map(normalizeValue)
            if normalizedGroup.contains(normalizedQuery) {
                variants.formUnion(normalizedGroup)
            }
        }
        return Array(variants)
    }

    nonisolated private static let localGermanProducts: [LocalGermanProduct] = {
        let decoder = JSONDecoder()
        let url = Bundle.main.url(forResource: "german_products", withExtension: "json")
            ?? Bundle.main.url(forResource: "german_products", withExtension: "json", subdirectory: "Resources")
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([LocalGermanProduct].self, from: data)) ?? []
    }()

    nonisolated private static let localGermanProductIndex: [IndexedLocalGermanProduct] = {
        localGermanProducts.map { product in
            let name = normalizeValue(product.name)
            let brand = normalizeValue(product.brand)
            let stores = normalizeValue(product.stores ?? "")
            let ingredients = normalizeValue(product.ingredients_text ?? "")
            return IndexedLocalGermanProduct(
                product: product,
                name: name,
                brand: brand,
                ingredients: ingredients,
                haystack: "\(name) \(brand) \(stores) \(ingredients)"
            )
        }
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "ingria-product-search"
        )
        return URLSession(configuration: configuration)
    }()
}

enum LookupLogger {
    static func log(_ event: String, _ values: [String: String] = [:]) {
        #if DEBUG
        let detail = values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[INGRIA Lookup] \(event)\(detail.isEmpty ? "" : " \(detail)")")
        #endif
    }
}

private struct IndexedLocalGermanProduct: Sendable {
    let product: LocalGermanProduct
    let name: String
    let brand: String
    let ingredients: String
    let haystack: String
}

private struct LocalGermanProduct: Decodable, Sendable {
    let code: String
    let name: String
    let brand: String
    let category: String
    let image_url: String?
    let ingredients_text: String?
    let ingredients_tags: [String]?
    let additives_tags: [String]?
    let stores: String?
}

private struct OFFSearchResponse: Decodable {
    let hits: [OFFSearchHit]
}

private struct OFFSearchHit: Decodable {
    let code: String?
    let product_name: String?
    let brands: [String]?
    let image_url: String?
    let image_small_url: String?
    let countries_tags: [String]?
}

private struct ProductSearchResponse: Decodable {
    let products: [OpenFactsSearchProduct]
}

private struct OpenFactsSearchProduct: Decodable {
    let code: String?
    let product_name: String?
    let brands: String?
    let image_url: String?
    let image_small_url: String?
    let countries_tags: [String]?
    let ingredients_text: String?
    let ingredients_text_de: String?
    let ingredients_text_en: String?
    let ingredients_text_fr: String?
    let ingredients_tags: [String]?
    let additives_tags: [String]?
}

private struct ProductLookupResponse: Decodable {
    let status: Int
    let product: ProductLookupPayload?
}

private struct ProductLookupPayload: Decodable {
    let code: String?
    let product_name: String?
    let product_name_de: String?
    let brands: String?
    let image_url: String?
    let image_small_url: String?
    let image_front_url: String?
    let image_ingredients_url: String?
    let ingredients: [OFFIngredient]?
    let ingredients_text: String?
    let ingredients_text_de: String?
    let ingredients_text_en: String?
    let ingredients_tags: [String]?
    let ingredients_hierarchy: [String]?
    let ingredients_original_tags: [String]?
    let additives_tags: [String]?
    let ingredients_analysis_tags: [String]?
    let nova_group: Int?
}

private struct OFFIngredient: Decodable {
    let id: String?
    let text: String?
    let text_de: String?
    let text_en: String?
    let percent: Double?
}
