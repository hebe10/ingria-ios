import Foundation

/// Beauty-specific product model.
///
/// This is intentionally separate from the food product model so beauty,
/// oral-care, and personal-care logic can grow without breaking food scans.
struct BeautyProduct: Identifiable, Hashable {
    var id: String { barcode }

    let barcode: String
    var productName: String
    var brand: String
    var categories: String
    var imageURL: URL?
    var ingredientsText: String
    var countries: String
    var labels: String
    var source: String
    var importedAt: Date?
    var lastCheckedAt: Date?
    var dataConfidence: BeautyDataConfidence
    var result: IngredientStatus?
    var summaryLine: String
    var reviewStatus: ProductReviewStatus
    var sourceStatus: ProductSourceStatus

    var hasIngredientText: Bool {
        !ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasTrustedIngriaResult: Bool {
        guard result != nil else { return false }
        return reviewStatus == .approved || reviewStatus == .adminReviewed || sourceStatus == .ingriaReviewed
    }
}

enum BeautyDataConfidence: String, Codable, Hashable {
    case ingriaReviewed = "ingria_reviewed"
    case openDatabase = "open_database"
    case missingIngredients = "missing_ingredients"
    case missingProduct = "missing_product"
    case apiFailed = "api_failed"
}

enum BeautyPendingReviewStatus: String, Codable, Hashable {
    case ingredientsNeeded = "ingredients_needed"
    case missingProduct = "missing_product"
    case apiFailed = "api_failed"
}

enum BeautyLookupResult: Hashable {
    case firebaseProduct(BeautyProduct)
    case importedOpenBeautyFactsProduct(BeautyProduct)
    case pendingReview(status: BeautyPendingReviewStatus, product: BeautyProduct?)
}

