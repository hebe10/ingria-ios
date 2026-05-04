import Foundation

enum IngriaTab: String, CaseIterable, Identifiable {
    case home
    case search
    case scan
    case ingredients
    case lists

    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case englishUK = "EN"
    case german = "DE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .englishUK: return "English UK"
        case .german: return "Deutsch"
        }
    }
}

enum IngredientStatus: String, Codable {
    case avoid = "AVOID"
    case watch = "MODERATE"
    case clean = "CLEAN"
    case insufficientData = "INSUFFICIENT_DATA"
    case neutral = "NEUTRAL"

    var title: String {
        switch self {
        case .avoid: return "Avoid"
        case .watch: return "Review"
        case .clean: return "Clean"
        case .insufficientData: return "Unknown"
        case .neutral: return "Neutral"
        }
    }
}

enum ProductDataConfidence: String, Codable, Hashable {
    case structured
    case extractedFromText
    case unusableData
    case productNotFound
}

enum ProductReviewStatus: String, Codable, Hashable {
    case approved
    case pending
    case missingIngredients
    case unverifiedSourceData
    case adminReviewed
    case userSubmitted

    var title: String {
        switch self {
        case .approved: return "INGRIA reviewed"
        case .pending: return "Pending review"
        case .missingIngredients: return "Ingredient data needed"
        case .unverifiedSourceData: return "Source data may be incomplete"
        case .adminReviewed: return "INGRIA reviewed"
        case .userSubmitted: return "User submitted"
        }
    }
}

enum ProductSourceStatus: String, Codable, Hashable {
    case ingriaReviewed
    case userSubmitted
    case openFoodFacts
    case openBeautyFacts
    case manualEntry
    case pendingReview
    case localSeed

    var title: String {
        switch self {
        case .ingriaReviewed: return "INGRIA reviewed"
        case .userSubmitted: return "User submitted"
        case .openFoodFacts: return "Open Food Facts source"
        case .openBeautyFacts: return "Open Beauty Facts source"
        case .manualEntry: return "Manual entry"
        case .pendingReview: return "Pending review"
        case .localSeed: return "Local INGRIA seed data"
        }
    }
}

enum SearchResultFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case clean
    case review
    case avoid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .clean: return "Clean"
        case .review: return "Review"
        case .avoid: return "Avoid"
        }
    }

    var status: IngredientStatus? {
        switch self {
        case .all: return nil
        case .clean: return .clean
        case .review: return .watch
        case .avoid: return .avoid
        }
    }
}

enum RetailerTag: String, CaseIterable, Identifiable, Codable, Hashable {
    case all = "All stores"
    case lidl = "Lidl"
    case aldi = "Aldi"
    case edeka = "Edeka"
    case rewe = "Rewe"
    case dm = "DM"
    case rossmann = "Rossmann"
    case mueller = "Müller"
    case kaufland = "Kaufland"
    case online = "Online"

    var id: String { rawValue }
}

enum ProductCategoryKind: String, Codable, Hashable {
    case food
    case drink
    case beauty
    case oralCare
    case supplement
    case unknown
}

struct IngredientGuideEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let name_de: String?
    let name_en: String?
    let aliases: [String]
    let category: String
    let category_de: String?
    let category_en: String?
    let status: IngredientStatus
    let verdict: String?
    let verdict_de: String?
    let verdict_en: String?
    let reason_de: String?
    let reason_en: String?
    let why_bad: [String]?
    let why_moderate: [String]?
    let why_good: [String]?
    let mechanism: String?
    let common_uses: [String]?
    let regulatory: IngredientRegulatory?
    let tags: [String]?
}

struct IngredientRegulatory: Codable, Hashable {
    let eu: String?
    let us: String?
}

struct ProductSearchItem: Identifiable, Hashable {
    let id: String
    let barcode: String
    let name: String
    let brand: String
    let imageURL: URL?
    let category: String
    var ingredientsText: String = ""
    var ingredientTags: [String] = []
    var additiveTags: [String] = []
    var resultStatus: IngredientStatus? = nil
    var resultReason: String? = nil
    var sourceStatus: ProductSourceStatus = .openFoodFacts
    var reviewStatus: ProductReviewStatus = .unverifiedSourceData
    var storeAvailability: [ProductStoreAvailability] = []
}

struct ProductStoreAvailability: Identifiable, Codable, Hashable {
    var id: String { "\(storeName)-\(sourceLabel)-\(availabilityStatus)" }
    let storeName: String
    let availabilityStatus: String
    let sourceLabel: String
    let isOnline: Bool

    var displayText: String {
        if availabilityStatus.lowercased().contains("confirmed") {
            return "\(sourceLabel): \(storeName)"
        }
        return "May be available at \(storeName)"
    }
}

struct ProductAlternative: Identifiable, Codable, Hashable {
    let id: String
    let originalBarcode: String
    let alternativeBarcode: String
    let alternativeProductName: String
    let alternativeBrand: String
    let alternativeResult: IngredientStatus
    let store: String
    let country: String
    let reason: String
    let source: String
    let reviewStatus: ProductReviewStatus
    let lastReviewed: Date?
}

struct IngredientAlternative: Identifiable, Codable, Hashable {
    let id: String
    let flaggedIngredient: String
    let issueType: String
    let cleanerAlternative: String
    let explanation: String
    let productCategories: [String]
    let recommendedSearchTerms: [String]
    let evidenceLevel: String
    let source: String
    let reviewStatus: ProductReviewStatus
    let lastReviewed: Date?
}

enum CleanAlternativeState: Hashable {
    case productMatches([ProductAlternative])
    case ingredientGuidance([IngredientAlternative])
    case none

    var title: String {
        switch self {
        case .productMatches: return "Cleaner alternative found."
        case .ingredientGuidance: return "No exact product match yet. INGRIA found cleaner ingredient guidance."
        case .none: return "No clean alternative found yet. We’ll keep improving the database."
        }
    }
}

struct ProductIngredient: Hashable {
    let originalText: String
    let normalizedKey: String
    let displayNameDE: String
    let displayNameEN: String?
    let percent: String?
    let source: String
}

struct RawProduct {
    let barcode: String
    let name: String
    let brand: String
    let imageURL: URL?
    let ingredientsImageURL: URL?
    let ingredientsText: String
    let cleanedIngredientsText: String
    let ingredients: [ProductIngredient]
    let ingredientTags: [String]
    let additiveTags: [String]
    let ingredientsAnalysisTags: [String]
    let novaGroup: Int?
    let category: String
    let confidence: ProductDataConfidence
    let productExists: Bool
    let source: String
}

struct AuditedIngredient: Identifiable, Hashable {
    let id: String
    let name: String
    let nameDE: String?
    let nameEN: String?
    let status: IngredientStatus
    let reason: String
    let reasonDE: String?
    let reasonEN: String?
    let euStatus: String
    let processingLevel: Int
    let alternatives: [String]
}

struct DisplayIngredient: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let status: IngredientStatus
}

struct ProductAudit: Identifiable, Hashable {
    let id = UUID()
    let barcode: String
    let productName: String
    let brand: String
    let store: String?
    let imageURL: URL?
    let finalStatus: IngredientStatus
    let summaryLine: String
    let avoidCount: Int
    let watchCount: Int
    let cleanCount: Int
    let displayIngredients: [DisplayIngredient]
    let flaggedIngredients: [AuditedIngredient]
    let rawIngredientsText: String
    let cleanedIngredientsText: String
    let source: String
    let productCategory: String
    let checkedAt: Date
    let confidence: ProductDataConfidence
    var sourceStatus: ProductSourceStatus = .openFoodFacts
    var reviewStatus: ProductReviewStatus = .unverifiedSourceData
    var storeAvailability: [ProductStoreAvailability] = []
    // Coverage + scoring. `recognizedIngredientCount` counts every parsed
    // token that resolved to either a guide entry, a direct rule, or a
    // neutral display match. `unknownIngredients` are tokens we parsed but
    // could not classify, so they are surfaced in the UI rather than
    // silently passing as clean. `coverageRatio` is recognized / total.
    var totalIngredientCount: Int = 0
    var recognizedIngredientCount: Int = 0
    var unknownIngredientCount: Int = 0
    var coverageRatio: Double = 0
    var unknownIngredients: [String] = []
    var isPartialResult: Bool = false
    var score: Int? = nil
}

enum SavedListKind: String, CaseIterable, Identifiable, Hashable {
    case clean
    case avoid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean picks"
        case .avoid: return "Avoid list"
        }
    }
}

struct SavedProductList: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var kind: SavedListKind
    var isSystemList = false
    var audits: [ProductAudit] = []
}
