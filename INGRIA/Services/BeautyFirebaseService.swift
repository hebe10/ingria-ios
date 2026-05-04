import Foundation
import UIKit
import FirebaseFirestore
import FirebaseStorage

/// Firebase storage for beauty products.
///
/// Main collections used by this service:
/// - `beauty_products`: INGRIA source of truth for approved/imported beauty products.
/// - `beauty_pending_review`: products that need ingredient data or admin review.
/// - `beauty_scan_logs`: lightweight scan history/debug trail.
/// - `beauty_uploads`: uploaded front-label and ingredient-label image metadata.
/// - `beauty_sources`: source metadata, e.g. Open Beauty Facts import timestamps.
/// - `beauty_results`: optional result snapshots for analytics/admin review.
struct BeautyFirebaseService {
    private let db = Firestore.firestore()

    func lookupBeautyProduct(barcode rawBarcode: String) async throws -> BeautyProduct? {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { return nil }

        let snapshot = try await document(collection: "beauty_products", id: barcode)
        guard let data = snapshot else { return nil }
        return beautyProduct(from: data, fallbackBarcode: barcode)
    }

    @discardableResult
    func importOpenBeautyFactsProduct(_ product: BeautyProduct) async throws -> BeautyProduct {
        let barcode = BarcodeValueNormalizer.normalize(product.barcode)
        let now = FieldValue.serverTimestamp()
        var data: [String: Any] = [
            "barcode": barcode,
            "product_name": product.productName,
            "brands": product.brand,
            "brand": product.brand,
            "categories": product.categories,
            "image_url": product.imageURL?.absoluteString ?? "",
            "ingredients_text": product.ingredientsText,
            "countries": product.countries,
            "labels": product.labels,
            "source": "open_beauty_facts",
            "source_status": ProductSourceStatus.openBeautyFacts.rawValue,
            "review_status": ProductReviewStatus.unverifiedSourceData.rawValue,
            "data_confidence": product.hasIngredientText ? BeautyDataConfidence.openDatabase.rawValue : BeautyDataConfidence.missingIngredients.rawValue,
            "imported_at": now,
            "last_checked_at": now,
            "updated_at": now
        ]

        if !product.hasIngredientText {
            data["result"] = "INGREDIENT_DATA_NEEDED"
        }

        try await setData(collection: "beauty_products", id: barcode, data: data, merge: true)
        try await setData(collection: "beauty_sources", id: "open_beauty_facts_\(barcode)", data: [
            "barcode": barcode,
            "source": "open_beauty_facts",
            "source_url": "https://world.openbeautyfacts.org/api/v2/product/\(barcode).json",
            "imported_at": now,
            "last_checked_at": now,
            "data_confidence": data["data_confidence"] ?? BeautyDataConfidence.openDatabase.rawValue
        ], merge: true)

        if !product.hasIngredientText {
            try await createPendingReview(
                barcode: barcode,
                status: .ingredientsNeeded,
                product: product,
                note: "Open Beauty Facts product imported, but ingredient/INCI text is missing."
            )
        }

        return BeautyProduct(
            barcode: barcode,
            productName: product.productName,
            brand: product.brand,
            categories: product.categories,
            imageURL: product.imageURL,
            ingredientsText: product.ingredientsText,
            countries: product.countries,
            labels: product.labels,
            source: "open_beauty_facts",
            importedAt: Date(),
            lastCheckedAt: Date(),
            dataConfidence: product.hasIngredientText ? .openDatabase : .missingIngredients,
            result: product.result,
            summaryLine: product.summaryLine,
            reviewStatus: .unverifiedSourceData,
            sourceStatus: .openBeautyFacts
        )
    }

    func createPendingReview(
        barcode rawBarcode: String,
        status: BeautyPendingReviewStatus,
        product: BeautyProduct? = nil,
        note: String
    ) async throws {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { return }

        let now = FieldValue.serverTimestamp()
        try await setData(collection: "beauty_pending_review", id: barcode, data: [
            "barcode": barcode,
            "status": status.rawValue,
            "product_name": product?.productName ?? "Unknown beauty product",
            "brands": product?.brand ?? "Unknown brand",
            "brand": product?.brand ?? "Unknown brand",
            "categories": product?.categories ?? "beauty",
            "image_url": product?.imageURL?.absoluteString ?? "",
            "ingredients_text": product?.ingredientsText ?? "",
            "source": product?.source ?? "INGRIA iOS",
            "admin_review_status": "waiting",
            "note": note,
            "created_at": now,
            "updated_at": now
        ], merge: true)
    }

    func saveBeautyScanLog(barcode rawBarcode: String, status: String, source: String) async throws {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { return }

        try await setData(collection: "beauty_scan_logs", id: UUID().uuidString, data: [
            "barcode": barcode,
            "status": status,
            "source": source,
            "created_at": FieldValue.serverTimestamp()
        ])
    }

    func saveBeautyResult(product: BeautyProduct, result: IngredientStatus, summary: String) async throws {
        let barcode = BarcodeValueNormalizer.normalize(product.barcode)
        guard !barcode.isEmpty else { return }

        try await setData(collection: "beauty_results", id: barcode, data: [
            "barcode": barcode,
            "product_name": product.productName,
            "brands": product.brand,
            "category": product.categories,
            "ingredients_text": product.ingredientsText,
            "result": firestoreValue(for: result),
            "summary_line": summary,
            "source": product.source,
            "source_status": product.sourceStatus.rawValue,
            "review_status": product.reviewStatus.rawValue,
            "updated_at": FieldValue.serverTimestamp()
        ], merge: true)
    }

    @discardableResult
    func uploadBeautyImage(_ image: UIImage, barcode rawBarcode: String, purpose: BeautyUploadPurpose) async throws -> URL {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { throw BeautyFirebaseError.missingBarcode }
        guard let data = image.jpegData(compressionQuality: 0.82) else { throw BeautyFirebaseError.imageEncodingFailed }

        let path = "beauty_uploads/\(barcode)/\(purpose.rawValue)_\(Int(Date().timeIntervalSince1970)).jpg"
        let reference = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await putData(data, reference: reference, metadata: metadata)
        let url = try await downloadURL(for: reference)

        let fieldPrefix = purpose.rawValue
        let uploadData: [String: Any] = [
            "barcode": barcode,
            "purpose": purpose.rawValue,
            "image_url": url.absoluteString,
            "storage_path": path,
            "content_type": "image/jpeg",
            "size_bytes": data.count,
            "created_at": FieldValue.serverTimestamp()
        ]
        try await setData(collection: "beauty_uploads", id: "\(barcode)_\(purpose.rawValue)_\(UUID().uuidString)", data: uploadData)
        try await setData(collection: "beauty_pending_review", id: barcode, data: [
            "barcode": barcode,
            "status": BeautyPendingReviewStatus.ingredientsNeeded.rawValue,
            "\(fieldPrefix)_image_url": url.absoluteString,
            "\(fieldPrefix)_image_storage_path": path,
            "admin_review_status": "waiting",
            "updated_at": FieldValue.serverTimestamp()
        ], merge: true)
        return url
    }
}

enum BeautyUploadPurpose: String {
    case frontLabel = "front_label"
    case ingredientLabel = "ingredient_label"
}

private enum BeautyFirebaseError: Error {
    case missingBarcode
    case imageEncodingFailed
}

private extension BeautyFirebaseService {
    func document(collection: String, id: String) async throws -> [String: Any]? {
        try await withCheckedThrowingContinuation { continuation in
            db.collection(collection).document(id).getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: snapshot?.data())
                }
            }
        }
    }

    func setData(collection: String, id: String, data: [String: Any], merge: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection(collection).document(id).setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func putData(_ data: Data, reference: StorageReference, metadata: StorageMetadata) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            reference.putData(data, metadata: metadata) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: BeautyFirebaseError.imageEncodingFailed)
                }
            }
        }
    }

    func downloadURL(for reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: BeautyFirebaseError.imageEncodingFailed)
                }
            }
        }
    }

    func beautyProduct(from data: [String: Any], fallbackBarcode: String) -> BeautyProduct {
        let resultValue = string(data["result"])
        let reviewStatus = ProductReviewStatus(rawValue: string(data["review_status"]) ?? "") ?? .unverifiedSourceData
        let sourceStatus = ProductSourceStatus(rawValue: string(data["source_status"]) ?? "") ?? .openBeautyFacts
        return BeautyProduct(
            barcode: string(data["barcode"]) ?? fallbackBarcode,
            productName: string(data["product_name"]) ?? string(data["name"]) ?? "Unknown beauty product",
            brand: string(data["brands"]) ?? string(data["brand"]) ?? "Unknown brand",
            categories: string(data["categories"]) ?? string(data["category"]) ?? "beauty",
            imageURL: URL(string: string(data["image_url"]) ?? ""),
            ingredientsText: string(data["ingredients_text"]) ?? string(data["inci_text"]) ?? "",
            countries: string(data["countries"]) ?? "",
            labels: string(data["labels"]) ?? "",
            source: string(data["source"]) ?? "Firebase",
            importedAt: date(data["imported_at"]),
            lastCheckedAt: date(data["last_checked_at"]),
            dataConfidence: BeautyDataConfidence(rawValue: string(data["data_confidence"]) ?? "") ?? .openDatabase,
            result: resultValue.map(ingredientStatus(from:)),
            summaryLine: string(data["summary_line"]) ?? "",
            reviewStatus: reviewStatus,
            sourceStatus: sourceStatus
        )
    }

    func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let convertible = value as? CustomStringConvertible { return convertible.description }
        return nil
    }

    func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    func firestoreValue(for status: IngredientStatus) -> String {
        switch status {
        case .avoid: return "AVOID"
        case .watch: return "REVIEW"
        case .clean: return "CLEAN"
        case .insufficientData: return "INGREDIENT_DATA_NEEDED"
        case .neutral: return "REVIEW"
        }
    }

    func ingredientStatus(from value: String) -> IngredientStatus {
        switch value.uppercased() {
        case "AVOID": return .avoid
        case "CLEAN": return .clean
        case "INGREDIENT_DATA_NEEDED", "INSUFFICIENT_DATA": return .insufficientData
        default: return .watch
        }
    }
}
