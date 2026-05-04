import Foundation
import UIKit
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage

enum FirebaseService {
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    static func writeDebugSmokeTestIfNeeded() {
        #if DEBUG
        configure()
        guard FirebaseApp.app() != nil else { return }

        let key = "didWriteFirebaseSmokeTest"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        Firestore.firestore()
            .collection("test")
            .addDocument(data: [
                "ok": true,
                "source": "INGRIA iOS debug",
                "createdAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error {
                    print("Firebase smoke test failed: \(error.localizedDescription)")
                    return
                }

                UserDefaults.standard.set(true, forKey: key)
                print("Firebase smoke test wrote to test collection.")
            }
        #endif
    }
}

struct FirebaseProductRecord: Hashable {
    let barcode: String
    let productName: String
    let brand: String
    let category: String
    let imageURL: URL?
    let ingredientsText: String
    let resultStatus: IngredientStatus
    let summaryLine: String
    let sourceStatus: ProductSourceStatus
    let reviewStatus: ProductReviewStatus
    let source: String
    let storeAvailability: [ProductStoreAvailability]
}

struct FirebaseSubmissionDraft {
    let barcode: String
    let productName: String
    let brand: String
    let category: String
    let ingredientsText: String
    let sourceStatus: ProductSourceStatus
    let reviewStatus: ProductReviewStatus
    let note: String
    let resultStatus: IngredientStatus?
    let summaryLine: String
    let cleanedIngredientsText: String
    let flaggedIngredientNames: [String]

    init(
        barcode: String,
        productName: String,
        brand: String,
        category: String,
        ingredientsText: String,
        sourceStatus: ProductSourceStatus,
        reviewStatus: ProductReviewStatus,
        note: String,
        resultStatus: IngredientStatus? = nil,
        summaryLine: String = "",
        cleanedIngredientsText: String = "",
        flaggedIngredientNames: [String] = []
    ) {
        self.barcode = barcode
        self.productName = productName
        self.brand = brand
        self.category = category
        self.ingredientsText = ingredientsText
        self.sourceStatus = sourceStatus
        self.reviewStatus = reviewStatus
        self.note = note
        self.resultStatus = resultStatus
        self.summaryLine = summaryLine
        self.cleanedIngredientsText = cleanedIngredientsText
        self.flaggedIngredientNames = flaggedIngredientNames
    }
}

struct FirebaseProductFilters {
    var result: IngredientStatus?
    var store: RetailerTag = .all
    var category = ""
    var brand = ""
    var ingredientConcern = ""
    var onlineOnly = false
    var availableNearby = false
}

struct AdminReviewItem: Identifiable, Hashable {
    let id: String
    let submissionID: String
    let queueID: String
    var barcode: String
    var productName: String
    var brand: String
    var category: String
    var ingredientsText: String
    var resultStatus: IngredientStatus
    var summaryLine: String
    var notes: String
    var adminReviewStatus: String
    var sourceStatus: ProductSourceStatus
    var reviewStatus: ProductReviewStatus
    var createdAt: Date?
    var frontImageURL: URL?
    var ingredientsImageURL: URL?
    var cleanedIngredientsText: String
    var flaggedIngredientNames: [String]
}

struct FirebaseProductRepository {
    private let db = Firestore.firestore()

    func lookupApprovedProduct(barcode: String) async throws -> FirebaseProductRecord? {
        let normalized = BarcodeValueNormalizer.normalize(barcode)
        guard !normalized.isEmpty else { return nil }

        if let byID = try await document(collection: "products", id: normalized),
           let record = productRecord(from: byID, fallbackBarcode: normalized) {
            return record
        }

        let snapshot = try await runQuery(
            db.collection("products")
                .whereField("barcode", isEqualTo: normalized)
                .whereField("review_status", in: ["approved", "adminReviewed"])
                .limit(to: 1)
        )
        guard let document = snapshot.documents.first else { return nil }
        return productRecord(from: document.data(), fallbackBarcode: normalized)
    }

    func searchProducts(query: String, filters: FirebaseProductFilters) async throws -> [ProductSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var firestoreQuery: Query = db.collection("products").limit(to: 60)

        if let result = filters.result {
            firestoreQuery = firestoreQuery.whereField("result", isEqualTo: result.firestoreValue)
        }
        if !filters.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            firestoreQuery = firestoreQuery.whereField("brand_key", isEqualTo: normalizedKey(filters.brand))
        }
        if !filters.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            firestoreQuery = firestoreQuery.whereField("category_key", isEqualTo: normalizedKey(filters.category))
        }

        let snapshot = try await runQuery(firestoreQuery)
        let queryKey = normalizedKey(trimmed)
        let concernKey = normalizedKey(filters.ingredientConcern)

        let records = snapshot.documents.compactMap { productRecord(from: $0.data(), fallbackBarcode: $0.documentID) }
            .filter { record in
                let haystack = normalizedKey([
                    record.productName,
                    record.brand,
                    record.category,
                    record.ingredientsText
                ].joined(separator: " "))
                let matchesText = queryKey.isEmpty || haystack.contains(queryKey)
                let matchesConcern = concernKey.isEmpty || haystack.contains(concernKey)
                let matchesStore = filters.store == .all || record.storeAvailability.contains {
                    normalizedKey($0.storeName) == normalizedKey(filters.store.rawValue)
                }
                let matchesOnline = !filters.onlineOnly || record.storeAvailability.contains(where: \.isOnline)
                let matchesNearby = !filters.availableNearby || !record.storeAvailability.isEmpty
                return matchesText && matchesConcern && matchesStore && matchesOnline && matchesNearby
            }

        return records.map { record in
            ProductSearchItem(
                id: record.barcode,
                barcode: record.barcode,
                name: record.productName,
                brand: record.brand,
                imageURL: record.imageURL,
                category: record.category,
                ingredientsText: record.ingredientsText,
                resultStatus: record.resultStatus,
                resultReason: record.summaryLine,
                sourceStatus: record.sourceStatus,
                reviewStatus: record.reviewStatus,
                storeAvailability: record.storeAvailability
            )
        }
    }

    func saveScanResult(audit: ProductAudit, scanSource: String) async throws {
        let id = UUID().uuidString
        try await setData(
            collection: "scan_results",
            id: id,
            data: scanResultData(audit: audit, scanSource: scanSource)
        )
    }

    func saveApprovedProductResultIfNeeded(audit: ProductAudit) async throws {
        guard !audit.barcode.isEmpty, audit.confidence != .productNotFound else { return }
        let status: ProductReviewStatus = audit.confidence == .unusableData ? .missingIngredients : .unverifiedSourceData
        try await setData(
            collection: "products",
            id: audit.barcode,
            data: productData(
                audit: audit,
                sourceStatus: audit.sourceStatus,
                reviewStatus: status,
                mergeOnly: true
            ),
            merge: true
        )
    }

    func createSubmission(_ draft: FirebaseSubmissionDraft) async throws {
        let id = draft.barcode.isEmpty ? UUID().uuidString : draft.barcode
        let now = FieldValue.serverTimestamp()
        var data: [String: Any] = [
            "barcode": draft.barcode,
            "product_name": draft.productName,
            "brand": draft.brand,
            "category": draft.category,
            "ingredients_text": draft.ingredientsText,
            "cleaned_ingredients_text": draft.cleanedIngredientsText,
            "source_status": draft.sourceStatus.rawValue,
            "review_status": draft.reviewStatus.rawValue,
            "admin_review_status": "waiting",
            "note": draft.note,
            "created_at": now,
            "updated_at": now
        ]
        if let resultStatus = draft.resultStatus {
            data["result"] = resultStatus.firestoreValue
        } else if draft.ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["result"] = IngredientStatus.insufficientData.firestoreValue
        }
        if !draft.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["summary_line"] = draft.summaryLine
        }
        if !draft.flaggedIngredientNames.isEmpty {
            data["flagged_ingredients"] = draft.flaggedIngredientNames
        }
        try await setData(collection: "product_submissions", id: id, data: data, merge: true)
        try await setData(collection: "review_queue", id: "submission_\(id)", data: [
            "item_type": "product_submission",
            "item_id": id,
            "barcode": draft.barcode,
            "product_name": draft.productName,
            "brand": draft.brand,
            "category": draft.category,
            "ingredients_text": draft.ingredientsText,
            "cleaned_ingredients_text": draft.cleanedIngredientsText,
            "result": data["result"] ?? IngredientStatus.insufficientData.firestoreValue,
            "summary_line": data["summary_line"] ?? defaultAdminSummary(for: draft.resultStatus ?? .insufficientData),
            "flagged_ingredients": draft.flaggedIngredientNames,
            "review_status": draft.reviewStatus.rawValue,
            "admin_review_status": "waiting",
            "note": draft.note,
            "created_at": now,
            "updated_at": now,
            "priority": draft.reviewStatus == .missingIngredients ? "ingredient_data_needed" : "normal"
        ], merge: true)
    }

    @discardableResult
    func uploadSubmissionImage(_ image: UIImage, barcode: String, purpose: String) async throws -> URL {
        let id = barcode.isEmpty ? UUID().uuidString : barcode
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw FirebaseRepositoryError.imageEncodingFailed
        }

        let safePurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "image" : purpose
        let storagePath = "product_submissions/\(id)/\(safePurpose)_\(Int(Date().timeIntervalSince1970)).jpg"
        let reference = Storage.storage().reference(withPath: storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await putData(data, reference: reference, metadata: metadata)
        let downloadURL = try await downloadURL(for: reference)
        let update: [String: Any] = [
            "barcode": barcode,
            "admin_review_status": "waiting",
            "review_status": ProductReviewStatus.missingIngredients.rawValue,
            "\(safePurpose)_image_url": downloadURL.absoluteString,
            "\(safePurpose)_image_storage_path": storagePath,
            "\(safePurpose)_image_pending_upload": false,
            "\(safePurpose)_image_content_type": "image/jpeg",
            "\(safePurpose)_image_size_bytes": data.count,
            "\(safePurpose)_image_uploaded_at": FieldValue.serverTimestamp(),
            "updated_at": FieldValue.serverTimestamp()
        ]
        try await setData(collection: "product_submissions", id: id, data: update, merge: true)
        try await setData(collection: "review_queue", id: "submission_\(id)", data: update.merging([
            "item_type": "product_submission",
            "item_id": id,
            "priority": "ingredient_data_needed"
        ]) { current, _ in current }, merge: true)
        return downloadURL
    }

    func pendingAdminReviewItems() async throws -> [AdminReviewItem] {
        let submissions = try await runQuery(db.collection("product_submissions").limit(to: 80))
        let queue = try await runQuery(db.collection("review_queue").limit(to: 80))
        return pendingAdminReviewItems(from: submissions, queue: queue)
    }

    func listenPendingAdminReviewItems(
        onUpdate: @escaping ([AdminReviewItem]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> () -> Void {
        var latestSubmissions: QuerySnapshot?
        var latestQueue: QuerySnapshot?
        let syncQueue = DispatchQueue(label: "ingria.firebase.admin-review-listener")

        func publishIfReady() {
            guard let latestSubmissions, let latestQueue else { return }
            let items = pendingAdminReviewItems(from: latestSubmissions, queue: latestQueue)
            DispatchQueue.main.async {
                onUpdate(items)
            }
        }

        let submissionsListener = db.collection("product_submissions")
            .limit(to: 80)
            .addSnapshotListener { snapshot, error in
                if let error {
                    DispatchQueue.main.async { onError(error) }
                    return
                }
                guard let snapshot else { return }
                syncQueue.async {
                    latestSubmissions = snapshot
                    publishIfReady()
                }
            }

        let queueListener = db.collection("review_queue")
            .limit(to: 80)
            .addSnapshotListener { snapshot, error in
                if let error {
                    DispatchQueue.main.async { onError(error) }
                    return
                }
                guard let snapshot else { return }
                syncQueue.async {
                    latestQueue = snapshot
                    publishIfReady()
                }
            }

        return {
            submissionsListener.remove()
            queueListener.remove()
        }
    }

    private func pendingAdminReviewItems(from submissions: QuerySnapshot, queue: QuerySnapshot) -> [AdminReviewItem] {
        var queueBySubmissionID: [String: (id: String, data: [String: Any])] = [:]
        for document in queue.documents {
            let data = document.data()
            let itemID = string(data["item_id"]) ?? string(data["barcode"]) ?? document.documentID.replacingOccurrences(of: "submission_", with: "")
            queueBySubmissionID[itemID] = (document.documentID, data)
        }

        var items: [AdminReviewItem] = []
        var seen = Set<String>()

        for document in submissions.documents {
            let data = document.data()
            guard shouldShowInAdminReview(data) else { continue }
            let queueRecord = queueBySubmissionID[document.documentID] ?? queueBySubmissionID[string(data["barcode"]) ?? ""]
            items.append(adminReviewItem(
                submissionID: document.documentID,
                submissionData: data,
                queueID: queueRecord?.id,
                queueData: queueRecord?.data
            ))
            seen.insert(document.documentID)
            if let barcode = string(data["barcode"]) { seen.insert(barcode) }
        }

        for document in queue.documents {
            let data = document.data()
            guard shouldShowInAdminReview(data) else { continue }
            let itemID = string(data["item_id"]) ?? string(data["barcode"]) ?? document.documentID.replacingOccurrences(of: "submission_", with: "")
            guard !seen.contains(itemID) else { continue }
            items.append(adminReviewItem(
                submissionID: itemID,
                submissionData: data,
                queueID: document.documentID,
                queueData: data
            ))
        }

        return items.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }

    func approveAdminReviewItem(_ item: AdminReviewItem) async throws {
        let barcode = BarcodeValueNormalizer.normalize(item.barcode)
        guard !barcode.isEmpty else { throw FirebaseRepositoryError.missingBarcode }

        let now = FieldValue.serverTimestamp()
        let productData: [String: Any] = [
            "barcode": barcode,
            "product_name": item.productName,
            "brand": item.brand,
            "brand_key": normalizedKey(item.brand),
            "category": item.category,
            "category_key": normalizedKey(item.category),
            "ingredients_text": item.ingredientsText,
            "result": item.resultStatus.firestoreValue,
            "summary_line": item.summaryLine,
            "source": "INGRIA admin",
            "source_status": ProductSourceStatus.ingriaReviewed.rawValue,
            "review_status": ProductReviewStatus.adminReviewed.rawValue,
            "admin_review_status": "approved",
            "image_url": item.frontImageURL?.absoluteString ?? "",
            "ingredients_image_url": item.ingredientsImageURL?.absoluteString ?? "",
            "cleaned_ingredients_text": item.cleanedIngredientsText,
            "flagged_ingredients": item.flaggedIngredientNames,
            "approved_at": now,
            "updated_at": now
        ]

        try await setData(collection: "products", id: barcode, data: productData, merge: true)
        try await updateAdminReviewRecords(
            item: item,
            adminStatus: "approved",
            reviewStatus: .adminReviewed,
            extra: [
                "approved_product_id": barcode,
                "approved_at": now
            ]
        )
    }

    func rejectAdminReviewItem(_ item: AdminReviewItem) async throws {
        try await updateAdminReviewRecords(item: item, adminStatus: "rejected", reviewStatus: .pending)
    }

    func markAdminReviewNeedsIngredientData(_ item: AdminReviewItem) async throws {
        try await updateAdminReviewRecords(item: item, adminStatus: "needs_more_info", reviewStatus: .missingIngredients)
    }

    func alternatives(for audit: ProductAudit) async throws -> CleanAlternativeState {
        if !audit.barcode.isEmpty {
            let productMatches = try await productAlternatives(barcode: audit.barcode, category: audit.productCategory)
            if !productMatches.isEmpty {
                return .productMatches(productMatches)
            }
        }

        let ingredientMatches = try await ingredientAlternatives(for: audit)
        if !ingredientMatches.isEmpty {
            return .ingredientGuidance(ingredientMatches)
        }
        return .none
    }

    private func productAlternatives(barcode: String, category: String) async throws -> [ProductAlternative] {
        let exact = try await runQuery(
            db.collection("product_alternatives")
                .whereField("original_barcode", isEqualTo: barcode)
                .whereField("review_status", in: ["approved", "adminReviewed"])
                .limit(to: 8)
        )
        let exactMatches = exact.documents.compactMap { productAlternative(from: $0.data(), id: $0.documentID) }
        if !exactMatches.isEmpty { return exactMatches }

        let categoryKey = normalizedKey(category)
        guard !categoryKey.isEmpty else { return [] }
        let sameCategory = try await runQuery(
            db.collection("product_alternatives")
                .whereField("category_key", isEqualTo: categoryKey)
                .whereField("review_status", in: ["approved", "adminReviewed"])
                .limit(to: 8)
        )
        return sameCategory.documents.compactMap { productAlternative(from: $0.data(), id: $0.documentID) }
    }

    private func ingredientAlternatives(for audit: ProductAudit) async throws -> [IngredientAlternative] {
        let keys = Array(Set(audit.flaggedIngredients.map { normalizedKey($0.name) })).prefix(10)
        guard !keys.isEmpty else { return [] }
        let snapshot = try await runQuery(
            db.collection("ingredient_alternatives")
                .whereField("flagged_ingredient_key", in: Array(keys))
                .whereField("review_status", in: ["approved", "adminReviewed"])
                .limit(to: 12)
        )
        return snapshot.documents.compactMap { ingredientAlternative(from: $0.data(), id: $0.documentID) }
    }
}

private enum FirebaseRepositoryError: Error {
    case imageEncodingFailed
    case missingBarcode
}

private extension FirebaseProductRepository {
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

    func runQuery(_ query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseRepositoryError.imageEncodingFailed)
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
                    continuation.resume(throwing: FirebaseRepositoryError.imageEncodingFailed)
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
                    continuation.resume(throwing: FirebaseRepositoryError.imageEncodingFailed)
                }
            }
        }
    }

    func productRecord(from data: [String: Any], fallbackBarcode: String) -> FirebaseProductRecord? {
        let review = reviewStatus(data["review_status"] as? String)
        guard review == .approved || review == .adminReviewed else { return nil }
        let barcode = string(data["barcode"]) ?? fallbackBarcode
        let stores = storeAvailability(from: data["store_availability"])
        return FirebaseProductRecord(
            barcode: barcode,
            productName: string(data["product_name"]) ?? string(data["name"]) ?? "Unknown product",
            brand: string(data["brand"]) ?? "Unknown brand",
            category: string(data["category"]) ?? "unknown",
            imageURL: URL(string: string(data["image_url"]) ?? ""),
            ingredientsText: string(data["ingredients_text"]) ?? "",
            resultStatus: IngredientStatus(firestoreValue: string(data["result"]) ?? "REVIEW"),
            summaryLine: string(data["summary_line"]) ?? string(data["reason"]) ?? "Based on available data.",
            sourceStatus: sourceStatus(data["source_status"] as? String, source: data["source"] as? String),
            reviewStatus: review,
            source: string(data["source"]) ?? "Firebase",
            storeAvailability: stores
        )
    }

    func shouldShowInAdminReview(_ data: [String: Any]) -> Bool {
        let adminStatus = normalizedKey(string(data["admin_review_status"]) ?? "waiting")
        return !["approved", "rejected"].contains(adminStatus)
    }

    func adminReviewItem(
        submissionID: String,
        submissionData: [String: Any],
        queueID: String?,
        queueData: [String: Any]?
    ) -> AdminReviewItem {
        let barcode = string(submissionData["barcode"]) ?? string(queueData?["barcode"]) ?? submissionID
        let ingredientsText = string(submissionData["ingredients_text"]) ?? string(queueData?["ingredients_text"]) ?? ""
        let rawResult = string(submissionData["result"]) ?? string(queueData?["result"]) ?? (ingredientsText.isEmpty ? "INGREDIENT_DATA_NEEDED" : "REVIEW")
        let source = sourceStatus(string(submissionData["source_status"]) ?? string(queueData?["source_status"]), source: string(submissionData["source"]))
        let review = reviewStatus(string(submissionData["review_status"]) ?? string(queueData?["review_status"]))

        return AdminReviewItem(
            id: submissionID,
            submissionID: submissionID,
            queueID: queueID ?? "submission_\(submissionID)",
            barcode: barcode,
            productName: string(submissionData["product_name"]) ?? string(submissionData["name"]) ?? string(queueData?["product_name"]) ?? "Unknown product",
            brand: string(submissionData["brand"]) ?? string(queueData?["brand"]) ?? "Unknown brand",
            category: string(submissionData["category"]) ?? string(queueData?["category"]) ?? "Food",
            ingredientsText: ingredientsText,
            resultStatus: IngredientStatus(firestoreValue: rawResult),
            summaryLine: string(submissionData["summary_line"]) ?? string(queueData?["summary_line"]) ?? defaultAdminSummary(for: IngredientStatus(firestoreValue: rawResult)),
            notes: string(submissionData["note"]) ?? string(queueData?["note"]) ?? "",
            adminReviewStatus: string(submissionData["admin_review_status"]) ?? string(queueData?["admin_review_status"]) ?? "waiting",
            sourceStatus: source,
            reviewStatus: review,
            createdAt: timestampDate(submissionData["created_at"]) ?? timestampDate(queueData?["created_at"]),
            frontImageURL: url(submissionData["front_image_url"]) ?? url(queueData?["front_image_url"]),
            ingredientsImageURL: url(submissionData["ingredients_image_url"]) ?? url(queueData?["ingredients_image_url"]),
            cleanedIngredientsText: string(submissionData["cleaned_ingredients_text"]) ?? string(queueData?["cleaned_ingredients_text"]) ?? "",
            flaggedIngredientNames: mergedStringArray(
                primary: submissionData["flagged_ingredients"],
                fallback: queueData?["flagged_ingredients"]
            )
        )
    }

    func updateAdminReviewRecords(
        item: AdminReviewItem,
        adminStatus: String,
        reviewStatus: ProductReviewStatus,
        extra: [String: Any] = [:]
    ) async throws {
        var data: [String: Any] = [
            "admin_review_status": adminStatus,
            "review_status": reviewStatus.rawValue,
            "product_name": item.productName,
            "brand": item.brand,
            "category": item.category,
            "ingredients_text": item.ingredientsText,
            "cleaned_ingredients_text": item.cleanedIngredientsText,
            "result": item.resultStatus.firestoreValue,
            "summary_line": item.summaryLine,
            "flagged_ingredients": item.flaggedIngredientNames,
            "front_image_url": item.frontImageURL?.absoluteString ?? "",
            "ingredients_image_url": item.ingredientsImageURL?.absoluteString ?? "",
            "admin_notes": item.notes,
            "updated_at": FieldValue.serverTimestamp()
        ]
        extra.forEach { data[$0.key] = $0.value }

        try await setData(collection: "product_submissions", id: item.submissionID, data: data, merge: true)
        try await setData(collection: "review_queue", id: item.queueID, data: data.merging([
            "item_type": "product_submission",
            "item_id": item.submissionID,
            "barcode": item.barcode
        ]) { current, _ in current }, merge: true)
    }

    func defaultAdminSummary(for status: IngredientStatus) -> String {
        switch status {
        case .clean:
            return "No obvious concern found from the available ingredient data."
        case .avoid:
            return "Significant concern found from INGRIA ingredient screening."
        case .watch, .neutral:
            return "More information or human review may be needed."
        case .insufficientData:
            return "Ingredient data needed before INGRIA can screen this product."
        }
    }

    func productAlternative(from data: [String: Any], id: String) -> ProductAlternative? {
        let alternativeName = string(data["alternative_product_name"]) ?? ""
        guard !alternativeName.isEmpty else { return nil }
        return ProductAlternative(
            id: id,
            originalBarcode: string(data["original_barcode"]) ?? "",
            alternativeBarcode: string(data["alternative_barcode"]) ?? "",
            alternativeProductName: alternativeName,
            alternativeBrand: string(data["alternative_brand"]) ?? "",
            alternativeResult: IngredientStatus(firestoreValue: string(data["alternative_result"]) ?? "CLEAN"),
            store: string(data["alternative_store"]) ?? "Availability not confirmed",
            country: string(data["alternative_country"]) ?? "",
            reason: string(data["alternative_reason"]) ?? "Cleaner ingredient profile.",
            source: string(data["source"]) ?? "INGRIA",
            reviewStatus: reviewStatus(data["review_status"] as? String),
            lastReviewed: timestampDate(data["last_reviewed"])
        )
    }

    func ingredientAlternative(from data: [String: Any], id: String) -> IngredientAlternative? {
        let cleaner = string(data["cleaner_alternative"]) ?? ""
        guard !cleaner.isEmpty else { return nil }
        return IngredientAlternative(
            id: id,
            flaggedIngredient: string(data["flagged_ingredient"]) ?? "",
            issueType: string(data["issue_type"]) ?? "",
            cleanerAlternative: cleaner,
            explanation: string(data["explanation"]) ?? "",
            productCategories: stringArray(data["product_categories"]),
            recommendedSearchTerms: stringArray(data["recommended_search_terms"]),
            evidenceLevel: string(data["evidence_level"]) ?? "",
            source: string(data["source"]) ?? "INGRIA",
            reviewStatus: reviewStatus(data["review_status"] as? String),
            lastReviewed: timestampDate(data["last_reviewed"])
        )
    }

    func productData(audit: ProductAudit, sourceStatus: ProductSourceStatus, reviewStatus: ProductReviewStatus, mergeOnly: Bool) -> [String: Any] {
        [
            "barcode": audit.barcode,
            "product_name": audit.productName,
            "brand": audit.brand,
            "brand_key": normalizedKey(audit.brand),
            "category": audit.productCategory,
            "category_key": normalizedKey(audit.productCategory),
            "image_url": audit.imageURL?.absoluteString ?? "",
            "ingredients_text": audit.rawIngredientsText,
            "cleaned_ingredients_text": audit.cleanedIngredientsText,
            "result": audit.finalStatus.firestoreValue,
            "summary_line": audit.summaryLine,
            "source": audit.source,
            "source_status": sourceStatus.rawValue,
            "review_status": reviewStatus.rawValue,
            "updated_at": FieldValue.serverTimestamp(),
            "created_from_ios_scan": mergeOnly
        ]
    }

    func scanResultData(audit: ProductAudit, scanSource: String) -> [String: Any] {
        [
            "barcode": audit.barcode,
            "product_name": audit.productName,
            "brand": audit.brand,
            "result": audit.finalStatus.firestoreValue,
            "review_status": audit.reviewStatus.rawValue,
            "source_status": audit.sourceStatus.rawValue,
            "scan_source": scanSource,
            "summary_line": audit.summaryLine,
            "ingredient_count": audit.displayIngredients.count,
            "avoid_count": audit.avoidCount,
            "review_count": audit.watchCount,
            "clean_count": audit.cleanCount,
            "category": audit.productCategory,
            "created_at": FieldValue.serverTimestamp()
        ]
    }

    func storeAvailability(from raw: Any?) -> [ProductStoreAvailability] {
        guard let values = raw as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            guard let store = string(value["store_name"] ?? value["store"]) else { return nil }
            let source = string(value["source_label"] ?? value["source"]) ?? "Availability not confirmed"
            return ProductStoreAvailability(
                storeName: store,
                availabilityStatus: string(value["availability_status"]) ?? "availability_not_confirmed",
                sourceLabel: source,
                isOnline: (value["is_online"] as? Bool) ?? normalizedKey(store).contains("online")
            )
        }
    }

    func sourceStatus(_ raw: String?, source: String?) -> ProductSourceStatus {
        if let raw, let value = ProductSourceStatus(rawValue: raw) { return value }
        let sourceKey = normalizedKey(source ?? "")
        if sourceKey.contains("openbeauty") { return .openBeautyFacts }
        if sourceKey.contains("openfood") { return .openFoodFacts }
        if sourceKey.contains("manual") { return .manualEntry }
        return .ingriaReviewed
    }

    func reviewStatus(_ raw: String?) -> ProductReviewStatus {
        switch raw {
        case "approved": return .approved
        case "adminReviewed", "admin_reviewed": return .adminReviewed
        case "missingIngredients", "missing_ingredients": return .missingIngredients
        case "unverifiedSourceData", "unverified_source_data": return .unverifiedSourceData
        case "userSubmitted", "user_submitted": return .userSubmitted
        default: return .pending
        }
    }

    func string(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value { return "\(value)" }
        return nil
    }

    func stringArray(_ value: Any?) -> [String] {
        if let value = value as? [String] { return value }
        if let value = value as? String {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return []
    }

    func mergedStringArray(primary: Any?, fallback: Any?) -> [String] {
        let primaryValues = stringArray(primary)
        return primaryValues.isEmpty ? stringArray(fallback) : primaryValues
    }

    func url(_ value: Any?) -> URL? {
        guard let raw = string(value) else { return nil }
        return URL(string: raw)
    }

    func timestampDate(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}

private extension IngredientStatus {
    var firestoreValue: String {
        switch self {
        case .avoid: return "AVOID"
        case .watch: return "REVIEW"
        case .clean: return "CLEAN"
        case .insufficientData: return "INGREDIENT_DATA_NEEDED"
        case .neutral: return "REVIEW"
        }
    }

    init(firestoreValue: String) {
        switch firestoreValue.uppercased() {
        case "AVOID": self = .avoid
        case "CLEAN": self = .clean
        case "INGREDIENT_DATA_NEEDED", "INSUFFICIENT_DATA": self = .insufficientData
        default: self = .watch
        }
    }
}

private func normalizedKey(_ value: String) -> String {
    value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
