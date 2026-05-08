import Foundation
import Combine
import SwiftUI

@MainActor
final class IngriaViewModel: ObservableObject {
    @Published var selectedTab: IngriaTab = .home
    @Published var homeQuery = ""
    @Published var searchQuery = ""
    @Published var searchResults: [ProductSearchItem] = []
    @Published var searchFilter: SearchResultFilter = .all
    @Published var selectedStoreFilter: RetailerTag = .all
    @Published var categoryFilter = ""
    @Published var brandFilter = ""
    @Published var ingredientConcernFilter = ""
    @Published var availableNearbyOnly = false
    @Published var onlineOnly = false
    @Published var homeSuggestions: [ProductSearchItem] = []
    @Published var activeAudit: ProductAudit?
    @Published var activeAlternativeState: CleanAlternativeState = .none
    @Published var ingredientFilter: String = "all"
    @Published var ingredientQuery = ""
    @Published var searchStateText = "Type to search."
    @Published var scanBarcode = ""
    @Published var scannedLabelText = ""
    @Published var scanStateText = "Scan barcode, enter EAN, or paste label ingredients."
    @Published var ocrStateText = ""
    @Published var auditHistory: [ProductAudit] = []
    @Published var isSearching = false
    @Published var appLanguage: AppLanguage = .german
    @Published var savedLists: [SavedProductList] = [
        SavedProductList(name: "Clean picks", kind: .clean, isSystemList: true),
        SavedProductList(name: "Avoid list", kind: .avoid, isSystemList: true)
    ]

    private var guideStore = IngredientGuideStore()
    private let searchService = ProductSearchService()
    private let supabaseManager = SupabaseManager.shared
    private var auditor: ProductAuditor?
    private var auditCache: [String: ProductAudit] = [:]

    func bootstrap() async {
        do {
            let loadedGuideStore = try await IngredientGuideStore.loadFromBundleInBackground()
            guideStore = loadedGuideStore
            auditor = ProductAuditor(guide: loadedGuideStore)
        } catch {
            print("Failed to load ingredient guide: \(error)")
        }
    }

    func ingredientEntries() -> [IngredientGuideEntry] {
        guideStore.groupedEntries(category: ingredientFilter, query: ingredientQuery)
    }

    func searchFromHome() async {
        guard !homeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchQuery = homeQuery
        selectedTab = .search
        await runSearch(query: homeQuery)
    }

    func updateHomeSuggestions() async {
        let query = homeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            homeSuggestions = []
            return
        }
        homeSuggestions = await searchService.localSuggestions(query: query, limit: 5)
    }

    func runSearch(query: String? = nil) async {
        let value = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            searchResults = []
            searchStateText = localized(de: "Suchbegriff eingeben.", en: "Type to search.")
            return
        }

        isSearching = true
        searchStateText = localized(de: "Suche...", en: "Searching...")
        do {
            async let supabaseMatches = supabaseManager.searchProducts(
                query: value,
                filters: ProductSearchFilters(
                    result: searchFilter.status,
                    store: selectedStoreFilter,
                    category: categoryFilter,
                    brand: brandFilter,
                    ingredientConcern: ingredientConcernFilter,
                    onlineOnly: onlineOnly,
                    availableNearby: availableNearbyOnly
                )
            )
            async let publicMatches = searchService.search(query: value)
            let reviewedMatches = (try? await supabaseMatches) ?? []
            let merged = try await mergeSearchResults(reviewedMatches, publicMatches)
            searchResults = applyLocalSearchFilters(merged)
            searchStateText = searchResults.isEmpty ? localized(de: "Nichts gefunden.", en: "Nothing found.") : localized(de: "\(searchResults.count) Treffer", en: "\(searchResults.count) matches")
        } catch {
            do {
                searchResults = applyLocalSearchFilters(try await searchService.search(query: value))
                searchStateText = searchResults.isEmpty ? localized(de: "Nichts gefunden.", en: "Nothing found.") : localized(de: "\(searchResults.count) Treffer", en: "\(searchResults.count) matches")
            } catch {
                searchResults = []
                searchStateText = localized(de: "Suche fehlgeschlagen.", en: "Search failed.")
            }
        }
        isSearching = false
    }

    func selectProduct(_ item: ProductSearchItem) async {
        do {
            if let cached = auditCache[item.barcode] {
                showAudit(cached)
                return
            }
            if item.sourceStatus == .ingriaReviewed || item.reviewStatus == .approved || item.reviewStatus == .adminReviewed {
                let audit = auditFromReviewedSearchItem(item)
                auditCache[item.barcode] = audit
                showAudit(audit)
                homeSuggestions = []
                Task { await saveScanLog(audit, scanSource: "search_select") }
                return
            }
            if !item.ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let auditor {
                let category = item.category.replacingOccurrences(of: ":de", with: "").replacingOccurrences(of: ":local", with: "")
                let extraction = IngredientExtractor.extract(item.ingredientsText, source: "Local German product data")
                let raw = RawProduct(
                    barcode: item.barcode,
                    name: item.name,
                    brand: item.brand,
                    imageURL: item.imageURL,
                    ingredientsImageURL: nil,
                    ingredientsText: item.ingredientsText,
                    cleanedIngredientsText: extraction.cleanedText,
                    ingredients: extraction.ingredients,
                    ingredientTags: item.ingredientTags,
                    additiveTags: item.additiveTags,
                    ingredientsAnalysisTags: [],
                    novaGroup: nil,
                    category: category == "beauty" ? "beauty" : "food",
                    confidence: extraction.isValid ? .extractedFromText : .unusableData,
                    productExists: true,
                    source: "Local German product data"
                )
                var audit = auditor.audit(product: raw)
                audit.sourceStatus = .localSeed
                audit.reviewStatus = .unverifiedSourceData
                auditCache[item.barcode] = audit
                showAudit(audit)
                homeSuggestions = []
                Task { await saveScanLog(audit, scanSource: "local_search_select") }
                return
            }
            guard let raw = try await searchService.fetchProduct(barcode: item.barcode), let auditor else { return }
            var audit = auditor.audit(product: raw)
            audit.sourceStatus = raw.source.lowercased().contains("beauty") ? .openBeautyFacts : .openFoodFacts
            audit.reviewStatus = audit.confidence == .unusableData ? .missingIngredients : .unverifiedSourceData
            auditCache[item.barcode] = audit
            showAudit(audit)
            homeSuggestions = []
            Task {
                await savePublicProductIfNeeded(audit)
                await saveScanLog(audit, scanSource: "public_search_select")
            }
        } catch {
            print("Failed to fetch product: \(error)")
        }
    }

    func submitBarcode() async {
        let barcode = BarcodeValueNormalizer.normalize(scanBarcode)
        scanBarcode = barcode
        guard barcode.count >= 8 else {
            scanStateText = localized(de: "Bitte einen gültigen EAN/GTIN-Barcode eingeben.", en: "Enter a valid EAN/GTIN barcode.")
            return
        }

        scanStateText = localized(de: "INGRIA-Datenbank wird geprüft...", en: "Checking INGRIA database...")
        if let cached = auditCache[barcode] {
            showAudit(cached)
            scanStateText = localized(de: "Gespeichertes Ergebnis aus dem lokalen Cache geladen.", en: "Returned stored result from local cache.")
            return
        }

        do {
            if let supabaseProduct = try await supabaseManager.fetchProduct(barcode: barcode) {
                let audit = auditFromSupabaseRecord(supabaseProduct)
                auditCache[barcode] = audit
                showAudit(audit)
                scanStateText = localized(de: "INGRIA-geprüftes Ergebnis aus Supabase geladen.", en: "Loaded INGRIA reviewed result from Supabase.")
                await saveScanLog(audit, scanSource: "barcode_supabase")
                return
            }
        } catch {
            scanStateText = localized(de: "Supabase nicht erreichbar. Öffentliche Produktdaten werden geprüft...", en: "Supabase unavailable. Checking public product data...")
        }

        scanStateText = localized(de: "Open Food Facts / Beauty Facts wird geprüft...", en: "Calling Open Food Facts / Beauty Facts...")
        do {
            guard let raw = try await searchService.fetchProduct(barcode: barcode), let auditor else {
                let audit = missingIngredientAudit(
                    barcode: barcode,
                    productName: appLanguage == .german ? "Produkt nicht gefunden" : "Product not found",
                    brand: "",
                    source: "Barcode lookup"
                )
                showAudit(audit)
                scanStateText = localized(de: "Produkt nicht gefunden. Ein INGRIA-Prüfeintrag wurde erstellt.", en: "Product not found. Created a pending INGRIA submission.")
                await saveMissingSubmission(ProductSubmissionDraft(
                    barcode: barcode,
                    productName: audit.productName,
                    brand: audit.brand,
                    category: audit.productCategory,
                    ingredientsText: "",
                    sourceStatus: .pendingReview,
                    reviewStatus: .pending,
                    note: "Barcode scan did not find an approved product. Ingredient data needed."
                ))
                await saveScanLog(audit, scanSource: "barcode_missing_product")
                return
            }
            var audit = auditor.audit(product: raw)
            audit.sourceStatus = raw.source.lowercased().contains("beauty") ? .openBeautyFacts : .openFoodFacts
            audit.reviewStatus = audit.confidence == .unusableData ? .missingIngredients : .unverifiedSourceData
            auditCache[barcode] = audit
            showAudit(audit)
            scanStateText = audit.confidence == .unusableData
                ? localized(de: "Zutatendaten nötig. Bitte Etikett hochladen oder einfügen.", en: "Ingredient data needed. Upload or paste the label.")
                : localized(de: "Scan-Ergebnis gespeichert.", en: "Saved scan result.")
            await savePublicProductIfNeeded(audit)
            await saveScanLog(audit, scanSource: "barcode_public_source")
            if audit.confidence == .unusableData {
                await saveMissingSubmission(ProductSubmissionDraft(
                    barcode: barcode,
                    productName: audit.productName,
                    brand: audit.brand,
                    category: audit.productCategory,
                    ingredientsText: raw.ingredientsText,
                    sourceStatus: audit.sourceStatus,
                    reviewStatus: .missingIngredients,
                    note: "Public source product found, but ingredient data was missing or incomplete."
                ))
            }
        } catch {
            scanStateText = localized(de: "Suche fehlgeschlagen. Bitte Zutatenliste scannen.", en: "Lookup failed. Scan the ingredient label instead.")
        }
    }

    func auditLabelText() {
        let text = scannedLabelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, let auditor else {
            scanStateText = localized(de: "Bitte zuerst Zutaten einfügen oder per Foto erkennen.", en: "Paste or OCR ingredient text first.")
            return
        }

        var audit = auditor.auditLabelText(text, productName: "Label scan", category: "food")
        audit.sourceStatus = .manualEntry
        audit.reviewStatus = .userSubmitted
        showAudit(audit)
        scanStateText = localized(de: "Ergebnis aus Zutaten erstellt und zur Prüfung vorgemerkt.", en: "Created result from label text and saved a user submission.")
        Task {
            await saveMissingSubmission(ProductSubmissionDraft(
                barcode: scanBarcode,
                productName: audit.productName,
                brand: audit.brand,
                category: audit.productCategory,
                ingredientsText: text,
                sourceStatus: .manualEntry,
                reviewStatus: .userSubmitted,
                note: "Manual ingredient entry from iOS app.",
                resultStatus: audit.finalStatus,
                summaryLine: audit.summaryLine,
                cleanedIngredientsText: audit.cleanedIngredientsText,
                flaggedIngredientNames: audit.flaggedIngredients.map(\.name)
            ))
            await saveScanLog(audit, scanSource: "manual_ingredient_entry")
        }
    }

    func auditIngredientImage(_ image: UIImage, productName: String? = nil, brand: String? = nil, category: String = "food") async {
        guard let auditor else { return }
        let originalAudit = activeAudit
        let resolvedBarcode = originalAudit?.barcode ?? scanBarcode
        let resolvedProductName = productName ?? originalAudit?.productName ?? (appLanguage == .german ? "Zutatenfoto" : "Ingredient photo")
        let resolvedBrand = brand ?? originalAudit?.brand ?? "User scan"
        let resolvedCategory = originalAudit?.productCategory.lowercased().contains("beauty") == true ? "beauty" : category

        ocrStateText = appLanguage == .german ? "Zutaten werden gelesen…" : "Reading ingredients…"

        let initialPhotoDraft = ProductSubmissionDraft(
            barcode: resolvedBarcode,
            productName: resolvedProductName,
            brand: resolvedBrand,
            category: resolvedCategory,
            ingredientsText: "",
            sourceStatus: .userSubmitted,
            reviewStatus: .missingIngredients,
            note: "Ingredient photo uploaded from iOS app. OCR pending or may need human review."
        )

        // Always create a pending review entry and upload the image first.
        // OCR can fail, but the user's photo should still reach INGRIA/admin review.
        var didStorePhoto = false
        do {
            try await supabaseManager.saveMissingProductSubmission(initialPhotoDraft)
            _ = try await supabaseManager.uploadSubmissionImage(image, barcode: resolvedBarcode, purpose: "ingredients")
            didStorePhoto = true
        } catch {
            print("Supabase ingredient photo upload failed: \(error)")
        }

        guard didStorePhoto else {
            ocrStateText = appLanguage == .german
                ? "Foto konnte nicht hochgeladen werden. Bitte erneut versuchen."
                : "Photo could not be uploaded. Please try again."
            return
        }

        do {
            let text = try await OCRService.recognizeIngredientText(in: image)
            scannedLabelText = text
            ocrStateText = appLanguage == .german ? "Mit INGRIA-Datenbank abgeglichen…" : "Matching with INGRIA database…"
            let audit = auditor.auditLabelText(text, productName: resolvedProductName, category: resolvedCategory)
            let contextualAudit = ProductAudit(
                barcode: resolvedBarcode.isEmpty ? audit.barcode : resolvedBarcode,
                productName: resolvedProductName,
                brand: resolvedBrand,
                store: audit.store,
                imageURL: originalAudit?.imageURL ?? audit.imageURL,
                finalStatus: audit.finalStatus,
                summaryLine: audit.summaryLine,
                avoidCount: audit.avoidCount,
                watchCount: audit.watchCount,
                cleanCount: audit.cleanCount,
                displayIngredients: audit.displayIngredients,
                flaggedIngredients: audit.flaggedIngredients,
                rawIngredientsText: audit.rawIngredientsText,
                cleanedIngredientsText: audit.cleanedIngredientsText,
                source: appLanguage == .german ? "Vom Foto erkannt" : "Recognized from photo",
                productCategory: audit.productCategory,
                checkedAt: audit.checkedAt,
                confidence: audit.confidence,
                sourceStatus: .manualEntry,
                reviewStatus: .userSubmitted,
                storeAvailability: originalAudit?.storeAvailability ?? []
            )
            showAudit(contextualAudit)
            await saveMissingSubmission(ProductSubmissionDraft(
                barcode: contextualAudit.barcode,
                productName: contextualAudit.productName,
                brand: contextualAudit.brand,
                category: contextualAudit.productCategory,
                ingredientsText: text,
                sourceStatus: .manualEntry,
                reviewStatus: .userSubmitted,
                note: "Ingredient photo OCR from iOS app.",
                resultStatus: contextualAudit.finalStatus,
                summaryLine: contextualAudit.summaryLine,
                cleanedIngredientsText: contextualAudit.cleanedIngredientsText,
                flaggedIngredientNames: contextualAudit.flaggedIngredients.map(\.name)
            ))
            await saveScanLog(contextualAudit, scanSource: "ingredient_photo_ocr")
            ocrStateText = contextualAudit.finalStatus == .insufficientData
                ? (appLanguage == .german ? "Bitte Zutatenfoto erneut aufnehmen. Zutatenliste nicht vollständig lesbar." : "Please retake the ingredient photo. Ingredient list is not fully readable.")
                : (appLanguage == .german ? "Foto gespeichert. Zutaten wurden erkannt und zur Prüfung vorgemerkt." : "Photo saved. Ingredients were recognized and queued for review.")
        } catch {
            ocrStateText = appLanguage == .german
                ? "Foto gespeichert. Zutatenliste nicht vollständig lesbar und wartet auf Prüfung."
                : "Photo saved. Ingredient list was not fully readable and is waiting for review."
        }
    }

    func storeFrontImageForReview(_ image: UIImage) {
        let currentAudit = activeAudit
        let barcode = currentAudit?.barcode ?? scanBarcode
        Task {
            let draft = ProductSubmissionDraft(
                barcode: barcode,
                productName: currentAudit?.productName ?? (appLanguage == .german ? "Unbekanntes Produkt" : "Unknown product"),
                brand: currentAudit?.brand ?? "",
                category: currentAudit?.productCategory ?? "unknown",
                ingredientsText: currentAudit?.rawIngredientsText ?? "",
                sourceStatus: .userSubmitted,
                reviewStatus: .missingIngredients,
                note: "Front label photo uploaded from iOS app."
            )
            var didStorePhoto = false
            do {
                try await supabaseManager.saveMissingProductSubmission(draft)
                _ = try await supabaseManager.uploadSubmissionImage(image, barcode: barcode, purpose: "front")
                didStorePhoto = true
            } catch {
                print("Supabase front photo upload failed: \(error)")
            }

            if didStorePhoto {
                ocrStateText = appLanguage == .german
                    ? "Vorderseite wurde hochgeladen und wartet auf Prüfung."
                    : "Front image uploaded and waiting for review."
            } else {
                ocrStateText = appLanguage == .german
                    ? "Vorderseite konnte nicht hochgeladen werden. Bitte erneut versuchen."
                    : "Front image could not be uploaded. Please try again."
            }
        }
    }

    func createSavedList(name: String, kind: SavedListKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !savedLists.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        savedLists.append(SavedProductList(name: trimmed, kind: kind))
    }

    func updateSavedList(id: UUID, name: String, kind: SavedListKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = savedLists.firstIndex(where: { $0.id == id }) else { return }
        guard !savedLists.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        savedLists[index].name = trimmed
        savedLists[index].kind = kind
    }

    func deleteSavedList(id: UUID) {
        guard let index = savedLists.firstIndex(where: { $0.id == id }), !savedLists[index].isSystemList else { return }
        savedLists.remove(at: index)
    }

    func saveAuditToList(_ audit: ProductAudit) {
        let kind: SavedListKind = audit.finalStatus == .avoid ? .avoid : .clean
        guard let index = savedLists.firstIndex(where: { $0.kind == kind }) else {
            savedLists.append(SavedProductList(name: kind.title, kind: kind, audits: [audit]))
            return
        }
        if !savedLists[index].audits.contains(where: { existing in
            (!audit.barcode.isEmpty && existing.barcode == audit.barcode)
            || (existing.productName == audit.productName && existing.brand == audit.brand)
        }) {
            savedLists[index].audits.insert(audit, at: 0)
        }
    }

    func saveProductToSupabase(_ audit: ProductAudit) async {
        saveAuditToList(audit)
    }

    func submitIngredientCorrection(_ audit: ProductAudit) async {
        await reportAuditIssue(audit)
    }

    func reportAuditIssue(_ audit: ProductAudit) async {
        await saveMissingSubmission(ProductSubmissionDraft(
            barcode: audit.barcode,
            productName: audit.productName,
            brand: audit.brand,
            category: audit.productCategory,
            ingredientsText: audit.cleanedIngredientsText.isEmpty ? audit.rawIngredientsText : audit.cleanedIngredientsText,
            sourceStatus: .userSubmitted,
            reviewStatus: audit.confidence == .unusableData ? .missingIngredients : .userSubmitted,
            note: "User reported this product result from the iOS app.",
            resultStatus: audit.finalStatus,
            summaryLine: audit.summaryLine,
            cleanedIngredientsText: audit.cleanedIngredientsText,
            flaggedIngredientNames: audit.flaggedIngredients.map(\.name)
        ))
    }

    private func saveScanLog(_ audit: ProductAudit, scanSource: String) async {
        try? await supabaseManager.saveScanLog(audit: audit, scanSource: scanSource)
    }

    private func savePublicProductIfNeeded(_ audit: ProductAudit) async {
        try? await supabaseManager.upsertScannedProductIfNeeded(audit: audit)
    }

    private func saveMissingSubmission(_ draft: ProductSubmissionDraft) async {
        try? await supabaseManager.saveMissingProductSubmission(draft)
    }

    private func showAudit(_ audit: ProductAudit) {
        dismissKeyboard()
        activeAudit = audit
        activeAlternativeState = .none
        if !auditHistory.contains(where: { $0.barcode == audit.barcode && !$0.barcode.isEmpty }) {
            auditHistory.insert(audit, at: 0)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func localized(de: String, en: String) -> String {
        appLanguage == .german ? de : en
    }

    private func missingIngredientAudit(barcode: String, productName: String, brand: String, source: String) -> ProductAudit {
        ProductAudit(
            barcode: barcode,
            productName: productName,
            brand: brand,
            store: nil,
            imageURL: nil,
            finalStatus: .insufficientData,
            summaryLine: appLanguage == .german ? "Zutatenliste nicht eindeutig erkannt." : "Ingredient list unclear.",
            avoidCount: 0,
            watchCount: 0,
            cleanCount: 0,
            displayIngredients: [],
            flaggedIngredients: [],
            rawIngredientsText: "",
            cleanedIngredientsText: "",
            source: source,
            productCategory: "unknown",
            checkedAt: Date(),
            confidence: .productNotFound,
            sourceStatus: .pendingReview,
            reviewStatus: .pending
        )
    }

    private func auditFromBeautyProduct(_ product: BeautyProduct) -> ProductAudit {
        if product.hasTrustedIngriaResult, let result = product.result {
            return ProductAudit(
                barcode: product.barcode,
                productName: product.productName,
                brand: product.brand,
                store: nil,
                imageURL: product.imageURL,
                finalStatus: result,
                summaryLine: product.summaryLine.isEmpty ? beautySummary(for: result) : product.summaryLine,
                avoidCount: result == .avoid ? 1 : 0,
                watchCount: result == .watch ? 1 : 0,
                cleanCount: result == .clean ? 1 : 0,
                displayIngredients: ingredientDisplayItems(from: product.ingredientsText),
                flaggedIngredients: [],
                rawIngredientsText: product.ingredientsText,
                cleanedIngredientsText: product.ingredientsText,
                source: product.source,
                productCategory: "Beauty / personal care",
                checkedAt: Date(),
                confidence: product.hasIngredientText ? .structured : .unusableData,
                sourceStatus: product.sourceStatus,
                reviewStatus: product.reviewStatus
            )
        }

        guard product.hasIngredientText, let auditor else {
            return ProductAudit(
                barcode: product.barcode,
                productName: product.productName,
                brand: product.brand,
                store: nil,
                imageURL: product.imageURL,
                finalStatus: .insufficientData,
                summaryLine: appLanguage == .german ? "INCI/Zutatenliste fehlt. Bitte Foto hochladen." : "INCI/ingredient list missing. Please upload a photo.",
                avoidCount: 0,
                watchCount: 0,
                cleanCount: 0,
                displayIngredients: [],
                flaggedIngredients: [],
                rawIngredientsText: "",
                cleanedIngredientsText: "",
                source: product.source,
                productCategory: "Beauty / personal care",
                checkedAt: Date(),
                confidence: .unusableData,
                sourceStatus: product.sourceStatus,
                reviewStatus: .missingIngredients
            )
        }

        let extraction = IngredientExtractor.extract(product.ingredientsText, source: product.source)
        var audit = auditor.audit(product: RawProduct(
            barcode: product.barcode,
            name: product.productName,
            brand: product.brand,
            imageURL: product.imageURL,
            ingredientsImageURL: nil,
            ingredientsText: product.ingredientsText,
            cleanedIngredientsText: extraction.cleanedText,
            ingredients: extraction.ingredients,
            ingredientTags: [],
            additiveTags: [],
            ingredientsAnalysisTags: [],
            novaGroup: nil,
            category: "beauty",
            confidence: extraction.isValid ? .extractedFromText : .unusableData,
            productExists: true,
            source: product.source
        ))
        audit.sourceStatus = product.sourceStatus
        audit.reviewStatus = product.reviewStatus
        return audit
    }

    private func beautySummary(for result: IngredientStatus) -> String {
        switch result {
        case .avoid:
            return appLanguage == .german
                ? "INGRIA hat nach seinen Prüfkriterien eine deutliche Auffälligkeit gefunden."
                : "INGRIA found a significant concern based on its screening criteria."
        case .watch:
            return appLanguage == .german
                ? "Weitere Prüfung oder bessere Daten können nötig sein."
                : "More information or human review may be needed."
        case .clean:
            return appLanguage == .german
                ? "Keine deutliche Auffälligkeit in den verfügbaren Daten gefunden."
                : "No obvious concern found from the available data."
        case .insufficientData, .neutral:
            return appLanguage == .german
                ? "Zutatenliste nicht eindeutig erkannt."
                : "Ingredient list unclear."
        }
    }

    private func ingredientDisplayItems(from text: String) -> [DisplayIngredient] {
        IngredientExtractor.extract(text, source: "Beauty product")
            .ingredients
            .map { DisplayIngredient(label: $0.originalText, status: .neutral) }
    }

    private func mergeSearchResults(_ first: [ProductSearchItem], _ second: [ProductSearchItem]) -> [ProductSearchItem] {
        var seen = Set<String>()
        return (first + second).filter { item in
            let key = item.barcode.isEmpty ? "\(item.name)-\(item.brand)" : item.barcode
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func applyLocalSearchFilters(_ items: [ProductSearchItem]) -> [ProductSearchItem] {
        items.filter { item in
            let matchesResult = searchFilter.status == nil || item.resultStatus == searchFilter.status
            let matchesStore = selectedStoreFilter == .all || item.storeAvailability.contains {
                $0.storeName.localizedCaseInsensitiveContains(selectedStoreFilter.rawValue)
            }
            let matchesBrand = brandFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.brand.localizedCaseInsensitiveContains(brandFilter)
            let matchesCategory = categoryFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.category.localizedCaseInsensitiveContains(categoryFilter)
            let matchesConcern = ingredientConcernFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.ingredientsText.localizedCaseInsensitiveContains(ingredientConcernFilter)
                || item.ingredientTags.joined(separator: " ").localizedCaseInsensitiveContains(ingredientConcernFilter)
            let matchesOnline = !onlineOnly || item.storeAvailability.contains(where: \.isOnline)
            let matchesNearby = !availableNearbyOnly || !item.storeAvailability.isEmpty
            return matchesResult && matchesStore && matchesBrand && matchesCategory && matchesConcern && matchesOnline && matchesNearby
        }
    }

    private func auditFromSupabaseRecord(_ record: SupabaseProductRecord) -> ProductAudit {
        ProductAudit(
            barcode: record.barcode,
            productName: record.productName,
            brand: record.brand,
            store: record.storeAvailability.first?.storeName,
            imageURL: record.imageURL,
            finalStatus: record.resultStatus,
            summaryLine: record.summaryLine,
            avoidCount: record.resultStatus == .avoid ? 1 : 0,
            watchCount: record.resultStatus == .watch ? 1 : 0,
            cleanCount: record.resultStatus == .clean ? 1 : 0,
            displayIngredients: [],
            flaggedIngredients: [],
            rawIngredientsText: record.ingredientsText,
            cleanedIngredientsText: record.ingredientsText,
            source: record.source,
            productCategory: record.category,
            checkedAt: Date(),
            confidence: record.ingredientsText.isEmpty ? .unusableData : .structured,
            sourceStatus: record.sourceStatus,
            reviewStatus: record.reviewStatus,
            storeAvailability: record.storeAvailability
        )
    }

    private func auditFromReviewedSearchItem(_ item: ProductSearchItem) -> ProductAudit {
        ProductAudit(
            barcode: item.barcode,
            productName: item.name,
            brand: item.brand,
            store: item.storeAvailability.first?.storeName,
            imageURL: item.imageURL,
            finalStatus: item.resultStatus ?? .watch,
            summaryLine: item.resultReason ?? "Based on available data.",
            avoidCount: item.resultStatus == .avoid ? 1 : 0,
            watchCount: item.resultStatus == .watch ? 1 : 0,
            cleanCount: item.resultStatus == .clean ? 1 : 0,
            displayIngredients: [],
            flaggedIngredients: [],
            rawIngredientsText: item.ingredientsText,
            cleanedIngredientsText: item.ingredientsText,
            source: item.sourceStatus.title,
            productCategory: item.category,
            checkedAt: Date(),
            confidence: item.ingredientsText.isEmpty ? .unusableData : .structured,
            sourceStatus: item.sourceStatus,
            reviewStatus: item.reviewStatus,
            storeAvailability: item.storeAvailability
        )
    }
}
