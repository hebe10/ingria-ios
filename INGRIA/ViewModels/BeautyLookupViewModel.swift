import Foundation
import Combine
import UIKit

/// Beauty lookup coordinator.
///
/// Beginner version of the flow:
/// 1. Check Firebase `beauty_products/{barcode}` first.
/// 2. If missing, try Open Beauty Facts.
/// 3. Import any Open Beauty Facts product into Firebase.
/// 4. If data is incomplete or the API fails, create `beauty_pending_review/{barcode}`.
@MainActor
final class BeautyLookupViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var lastResult: BeautyLookupResult?
    @Published private(set) var statusText = ""

    private let firebase: BeautyFirebaseService
    private let openBeautyFacts: OpenBeautyFactsService

    init(
        firebase: BeautyFirebaseService? = nil,
        openBeautyFacts: OpenBeautyFactsService? = nil
    ) {
        self.firebase = firebase ?? BeautyFirebaseService()
        self.openBeautyFacts = openBeautyFacts ?? OpenBeautyFactsService()
    }

    func lookup(barcode rawBarcode: String) async -> BeautyLookupResult {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        isLoading = true
        defer { isLoading = false }

        guard !barcode.isEmpty else {
            let result: BeautyLookupResult = .pendingReview(status: .missingProduct, product: nil)
            lastResult = result
            statusText = "Missing barcode."
            return result
        }

        do {
            try await firebase.saveBeautyScanLog(barcode: barcode, status: "started", source: "iOS")

            if let firebaseProduct = try await firebase.lookupBeautyProduct(barcode: barcode) {
                let result: BeautyLookupResult = .firebaseProduct(firebaseProduct)
                lastResult = result
                statusText = "Loaded beauty product from Firebase."
                try? await firebase.saveBeautyScanLog(barcode: barcode, status: "firebase_found", source: "beauty_products")
                return result
            }

            if let openProduct = try await openBeautyFacts.fetchProduct(barcode: barcode) {
                let imported = try await firebase.importOpenBeautyFactsProduct(openProduct)
                if !imported.hasIngredientText {
                    try await firebase.createPendingReview(
                        barcode: barcode,
                        status: .ingredientsNeeded,
                        product: imported,
                        note: "Beauty product found in Open Beauty Facts, but INCI/ingredient text is missing."
                    )
                    let result: BeautyLookupResult = .pendingReview(status: .ingredientsNeeded, product: imported)
                    lastResult = result
                    statusText = "Ingredient photo needed."
                    try? await firebase.saveBeautyScanLog(barcode: barcode, status: "ingredients_needed", source: "open_beauty_facts")
                    return result
                }

                let result: BeautyLookupResult = .importedOpenBeautyFactsProduct(imported)
                lastResult = result
                statusText = "Imported beauty product from Open Beauty Facts."
                try? await firebase.saveBeautyScanLog(barcode: barcode, status: "open_beauty_facts_imported", source: "open_beauty_facts")
                return result
            }

            try await firebase.createPendingReview(
                barcode: barcode,
                status: .missingProduct,
                note: "Beauty product was not found in Firebase or Open Beauty Facts."
            )
            let result: BeautyLookupResult = .pendingReview(status: .missingProduct, product: nil)
            lastResult = result
            statusText = "Beauty product not found. Front and ingredient photos needed."
            try? await firebase.saveBeautyScanLog(barcode: barcode, status: "missing_product", source: "open_beauty_facts")
            return result
        } catch {
            try? await firebase.createPendingReview(
                barcode: barcode,
                status: .apiFailed,
                note: "Open Beauty Facts lookup failed. Error: \(error.localizedDescription)"
            )
            let result: BeautyLookupResult = .pendingReview(status: .apiFailed, product: nil)
            lastResult = result
            statusText = "Beauty lookup failed. Ingredient photo needed."
            try? await firebase.saveBeautyScanLog(barcode: barcode, status: "api_failed", source: "open_beauty_facts")
            return result
        }
    }

    func lookupFirebaseOnly(barcode rawBarcode: String) async -> BeautyProduct? {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { return nil }
        do {
            return try await firebase.lookupBeautyProduct(barcode: barcode)
        } catch {
            statusText = "Beauty Firebase lookup unavailable."
            return nil
        }
    }

    @discardableResult
    func uploadBeautyIngredientPhoto(_ image: UIImage, barcode: String) async -> URL? {
        do {
            let url = try await firebase.uploadBeautyImage(image, barcode: barcode, purpose: .ingredientLabel)
            statusText = "Ingredient photo uploaded for beauty review."
            return url
        } catch {
            statusText = "Could not upload ingredient photo."
            return nil
        }
    }

    @discardableResult
    func uploadBeautyFrontLabel(_ image: UIImage, barcode: String) async -> URL? {
        do {
            let url = try await firebase.uploadBeautyImage(image, barcode: barcode, purpose: .frontLabel)
            statusText = "Front label uploaded for beauty review."
            return url
        } catch {
            statusText = "Could not upload front label."
            return nil
        }
    }
}
