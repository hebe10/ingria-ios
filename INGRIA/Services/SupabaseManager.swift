import Foundation
import UIKit
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://zzneaciygbazcybbsxdy.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp6bmVhY2l5Z2JhemN5YmJzeGR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc4ODM3MjksImV4cCI6MjA5MzQ1OTcyOX0.z3iAIhBMtd4DcjAaAtN_fgOJC1PoPFMK1G2wmALfN7I"

    static var isConfigured: Bool {
        let trimmed = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("PASTE_MY_ANON_PUBLIC_KEY_HERE")
    }
}

enum SupabaseManagerError: LocalizedError {
    case notConfigured
    case imageEncodingFailed
    case missingBarcode
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase anon key is not configured yet."
        case .imageEncodingFailed:
            return "Image could not be encoded."
        case .missingBarcode:
            return "Barcode is missing."
        case let .badResponse(status, body):
            return "Supabase returned \(status): \(body)"
        }
    }
}

struct SupabaseProductRecord: Hashable {
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

@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()

    // Keep the official Supabase Swift client initialized with the base project URL.
    // Do not append /rest/v1 here.
    lazy var client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let isoFormatter: ISO8601DateFormatter

    private init() {
        session = URLSession(configuration: .default)
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func fetchProduct(barcode rawBarcode: String) async throws -> SupabaseProductRecord? {
        try ensureConfigured()
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { return nil }

        let rows: [ProductRow] = try await restJSON(
            table: "products",
            queryItems: [
                URLQueryItem(name: "barcode", value: "eq.\(barcode)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        guard let row = rows.first, row.isTrusted else { return nil }
        let stores = try await storeAvailability(barcode: barcode)
        return productRecord(from: row, storeAvailability: stores)
    }

    func searchProducts(query: String, filters: FirebaseProductFilters) async throws -> [ProductSearchItem] {
        try ensureConfigured()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "review_status", value: "in.(approved,adminReviewed)"),
            URLQueryItem(name: "limit", value: "60")
        ]

        if let result = filters.result {
            queryItems.append(URLQueryItem(name: "result", value: "eq.\(result.supabaseValue)"))
        }
        if !filters.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "brand_key", value: "eq.\(normalizedSupabaseKey(filters.brand))"))
        }
        if !filters.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "category_key", value: "eq.\(normalizedSupabaseKey(filters.category))"))
        }

        let safeQuery = trimmed.replacingOccurrences(of: ",", with: " ")
        queryItems.append(URLQueryItem(
            name: "or",
            value: "(product_name.ilike.*\(safeQuery)*,brand.ilike.*\(safeQuery)*,ingredients_text.ilike.*\(safeQuery)*)"
        ))

        let rows: [ProductRow] = try await restJSON(table: "products", queryItems: queryItems)
        let concernKey = normalizedSupabaseKey(filters.ingredientConcern)
        let items = rows.compactMap { row -> ProductSearchItem? in
            guard row.isTrusted else { return nil }
            let haystack = normalizedSupabaseKey([
                row.productName ?? "",
                row.brand ?? "",
                row.category ?? "",
                row.ingredientsText ?? ""
            ].joined(separator: " "))
            guard concernKey.isEmpty || haystack.contains(concernKey) else { return nil }
            let record = productRecord(from: row, storeAvailability: row.storeAvailability ?? [])
            return ProductSearchItem(
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

        return items.filter { item in
            let matchesStore = filters.store == .all || item.storeAvailability.contains {
                normalizedSupabaseKey($0.storeName) == normalizedSupabaseKey(filters.store.rawValue)
            }
            let matchesOnline = !filters.onlineOnly || item.storeAvailability.contains(where: \.isOnline)
            let matchesNearby = !filters.availableNearby || !item.storeAvailability.isEmpty
            return matchesStore && matchesOnline && matchesNearby
        }
    }

    func saveScanLog(audit: ProductAudit, scanSource: String) async throws {
        try ensureConfigured()
        let payload = ScanLogInsert(
            barcode: audit.barcode,
            productName: audit.productName,
            brand: audit.brand,
            result: audit.finalStatus.supabaseValue,
            reviewStatus: audit.reviewStatus.rawValue,
            sourceStatus: audit.sourceStatus.rawValue,
            scanSource: scanSource,
            summaryLine: audit.summaryLine,
            ingredientCount: audit.displayIngredients.count,
            avoidCount: audit.avoidCount,
            reviewCount: audit.watchCount,
            cleanCount: audit.cleanCount,
            category: audit.productCategory,
            createdAt: nowString()
        )
        _ = try await restWrite(table: "scan_logs", method: "POST", body: payload)
    }

    func upsertScannedProductIfNeeded(audit: ProductAudit) async throws {
        try ensureConfigured()
        guard !audit.barcode.isEmpty, audit.confidence != .productNotFound else { return }
        let reviewStatus: ProductReviewStatus = audit.confidence == .unusableData ? .missingIngredients : .unverifiedSourceData
        let payload = ProductUpsert(
            barcode: audit.barcode,
            productName: audit.productName,
            brand: audit.brand,
            brandKey: normalizedSupabaseKey(audit.brand),
            category: audit.productCategory,
            categoryKey: normalizedSupabaseKey(audit.productCategory),
            imageURL: audit.imageURL?.absoluteString,
            ingredientsText: audit.rawIngredientsText,
            cleanedIngredientsText: audit.cleanedIngredientsText,
            result: audit.finalStatus.supabaseValue,
            summaryLine: audit.summaryLine,
            source: audit.source,
            sourceStatus: audit.sourceStatus.rawValue,
            reviewStatus: reviewStatus.rawValue,
            adminReviewStatus: "waiting",
            flaggedIngredients: audit.flaggedIngredients.map(\.name),
            createdFromIosScan: true,
            updatedAt: nowString()
        )
        _ = try await restWrite(
            table: "products",
            queryItems: [URLQueryItem(name: "on_conflict", value: "barcode")],
            method: "POST",
            body: payload,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func saveMissingProductSubmission(_ draft: FirebaseSubmissionDraft) async throws {
        try ensureConfigured()
        let barcode = draft.barcode.isEmpty ? UUID().uuidString : BarcodeValueNormalizer.normalize(draft.barcode)
        let result = draft.resultStatus?.supabaseValue ?? IngredientStatus.insufficientData.supabaseValue
        let payload = MissingSubmissionUpsert(
            barcode: barcode,
            productName: draft.productName,
            brand: draft.brand,
            category: draft.category,
            ingredientsText: draft.ingredientsText,
            cleanedIngredientsText: draft.cleanedIngredientsText,
            result: result,
            summaryLine: draft.summaryLine.isEmpty ? defaultSummary(for: draft.resultStatus ?? .insufficientData) : draft.summaryLine,
            sourceStatus: draft.sourceStatus.rawValue,
            reviewStatus: draft.reviewStatus.rawValue,
            adminReviewStatus: "waiting",
            note: draft.note,
            flaggedIngredients: draft.flaggedIngredientNames,
            createdAt: nowString(),
            updatedAt: nowString()
        )
        _ = try await restWrite(
            table: "missing_product_submissions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "barcode")],
            method: "POST",
            body: payload,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    @discardableResult
    func uploadSubmissionImage(_ image: UIImage, barcode rawBarcode: String, purpose: String) async throws -> URL {
        try ensureConfigured()
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { throw SupabaseManagerError.missingBarcode }
        guard let data = image.jpegData(compressionQuality: 0.78) else {
            throw SupabaseManagerError.imageEncodingFailed
        }

        let safePurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "image" : purpose
        let filename = "\(safePurpose)_\(Int(Date().timeIntervalSince1970)).jpg"
        let objectPath = "\(barcode)/\(filename)"

        var uploadURL = SupabaseConfig.url
        uploadURL.append(path: "storage")
        uploadURL.append(path: "v1")
        uploadURL.append(path: "object")
        uploadURL.append(path: "product-submissions")
        uploadURL.append(path: barcode)
        uploadURL.append(path: filename)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")

        let (responseData, response) = try await session.data(for: request)
        try validate(response: response, data: responseData)

        var publicURL = SupabaseConfig.url
        publicURL.append(path: "storage")
        publicURL.append(path: "v1")
        publicURL.append(path: "object")
        publicURL.append(path: "public")
        publicURL.append(path: "product-submissions")
        publicURL.append(path: barcode)
        publicURL.append(path: filename)

        try await updateSubmissionImage(
            barcode: barcode,
            purpose: safePurpose,
            imageURL: publicURL.absoluteString,
            storagePath: objectPath,
            sizeBytes: data.count
        )
        return publicURL
    }

    private func updateSubmissionImage(
        barcode: String,
        purpose: String,
        imageURL: String,
        storagePath: String,
        sizeBytes: Int
    ) async throws {
        let payload = SubmissionImagePatch(
            barcode: barcode,
            adminReviewStatus: "waiting",
            reviewStatus: ProductReviewStatus.missingIngredients.rawValue,
            imageURL: imageURL,
            storagePath: storagePath,
            imagePendingUpload: false,
            imageContentType: "image/jpeg",
            imageSizeBytes: sizeBytes,
            imageUploadedAt: nowString(),
            updatedAt: nowString()
        )
        let data = try encoder.encode(payload.dictionary(prefix: purpose))
        _ = try await restData(
            table: "missing_product_submissions",
            queryItems: [URLQueryItem(name: "barcode", value: "eq.\(barcode)")],
            method: "PATCH",
            body: data,
            prefer: "return=minimal"
        )
    }

    private func storeAvailability(barcode: String) async throws -> [ProductStoreAvailability] {
        let rows: [StoreAvailabilityRow] = try await restJSON(
            table: "product_store_availability",
            queryItems: [
                URLQueryItem(name: "barcode", value: "eq.\(barcode)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "20")
            ]
        )
        return rows.map {
            ProductStoreAvailability(
                storeName: $0.storeName,
                availabilityStatus: $0.availabilityStatus,
                sourceLabel: $0.sourceLabel,
                isOnline: $0.isOnline ?? normalizedSupabaseKey($0.storeName).contains("online")
            )
        }
    }
}

private extension SupabaseManager {
    func ensureConfigured() throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseManagerError.notConfigured }
    }

    func productRecord(from row: ProductRow, storeAvailability: [ProductStoreAvailability]) -> SupabaseProductRecord {
        SupabaseProductRecord(
            barcode: row.barcode,
            productName: nonEmpty(row.productName) ?? "Unknown product",
            brand: nonEmpty(row.brand) ?? "Unknown brand",
            category: nonEmpty(row.category) ?? "unknown",
            imageURL: URL(string: row.imageURL ?? ""),
            ingredientsText: row.ingredientsText ?? "",
            resultStatus: IngredientStatus(supabaseValue: row.result ?? "REVIEW"),
            summaryLine: nonEmpty(row.summaryLine) ?? "Based on available data.",
            sourceStatus: ProductSourceStatus(rawValue: row.sourceStatus ?? "") ?? sourceStatus(from: row.source),
            reviewStatus: ProductReviewStatus(supabaseValue: row.reviewStatus),
            source: nonEmpty(row.source) ?? "Supabase",
            storeAvailability: storeAvailability
        )
    }

    func sourceStatus(from source: String?) -> ProductSourceStatus {
        let key = normalizedSupabaseKey(source ?? "")
        if key.contains("open beauty") || key.contains("openbeauty") { return .openBeautyFacts }
        if key.contains("open food") || key.contains("openfood") { return .openFoodFacts }
        if key.contains("manual") { return .manualEntry }
        return .ingriaReviewed
    }

    func defaultSummary(for status: IngredientStatus) -> String {
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

    func nowString() -> String {
        isoFormatter.string(from: Date())
    }

    func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func restJSON<T: Decodable>(
        table: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> T {
        let data = try await restData(table: table, queryItems: queryItems, method: method, body: body, prefer: prefer)
        return try decoder.decode(T.self, from: data)
    }

    @discardableResult
    func restWrite<T: Encodable>(
        table: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: T,
        prefer: String = "return=minimal"
    ) async throws -> Data {
        try await restData(
            table: table,
            queryItems: queryItems,
            method: method,
            body: try encoder.encode(body),
            prefer: prefer
        )
    }

    func restData(
        table: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        var url = SupabaseConfig.url
        url.append(path: "rest")
        url.append(path: "v1")
        url.append(path: table)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let finalURL = components?.url else { throw SupabaseManagerError.badResponse(-1, "Bad Supabase URL") }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseManagerError.badResponse(http.statusCode, body)
        }
    }
}

private struct ProductRow: Codable {
    let barcode: String
    let productName: String?
    let brand: String?
    let category: String?
    let imageURL: String?
    let ingredientsText: String?
    let cleanedIngredientsText: String?
    let result: String?
    let summaryLine: String?
    let source: String?
    let sourceStatus: String?
    let reviewStatus: String?
    let adminReviewStatus: String?
    let flaggedIngredients: [String]?
    let storeAvailability: [ProductStoreAvailability]?

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case category
        case imageURL = "image_url"
        case ingredientsText = "ingredients_text"
        case cleanedIngredientsText = "cleaned_ingredients_text"
        case result
        case summaryLine = "summary_line"
        case source
        case sourceStatus = "source_status"
        case reviewStatus = "review_status"
        case adminReviewStatus = "admin_review_status"
        case flaggedIngredients = "flagged_ingredients"
        case storeAvailability = "store_availability"
    }

    var isTrusted: Bool {
        let review = ProductReviewStatus(supabaseValue: reviewStatus)
        return review == .approved || review == .adminReviewed || adminReviewStatus == "approved"
    }
}

private struct StoreAvailabilityRow: Codable {
    let barcode: String
    let storeName: String
    let availabilityStatus: String
    let sourceLabel: String
    let isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case barcode
        case storeName = "store_name"
        case availabilityStatus = "availability_status"
        case sourceLabel = "source_label"
        case isOnline = "is_online"
    }
}

private struct ProductUpsert: Codable {
    let barcode: String
    let productName: String
    let brand: String
    let brandKey: String
    let category: String
    let categoryKey: String
    let imageURL: String?
    let ingredientsText: String
    let cleanedIngredientsText: String
    let result: String
    let summaryLine: String
    let source: String
    let sourceStatus: String
    let reviewStatus: String
    let adminReviewStatus: String
    let flaggedIngredients: [String]
    let createdFromIosScan: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case brandKey = "brand_key"
        case category
        case categoryKey = "category_key"
        case imageURL = "image_url"
        case ingredientsText = "ingredients_text"
        case cleanedIngredientsText = "cleaned_ingredients_text"
        case result
        case summaryLine = "summary_line"
        case source
        case sourceStatus = "source_status"
        case reviewStatus = "review_status"
        case adminReviewStatus = "admin_review_status"
        case flaggedIngredients = "flagged_ingredients"
        case createdFromIosScan = "created_from_ios_scan"
        case updatedAt = "updated_at"
    }
}

private struct ScanLogInsert: Codable {
    let barcode: String
    let productName: String
    let brand: String
    let result: String
    let reviewStatus: String
    let sourceStatus: String
    let scanSource: String
    let summaryLine: String
    let ingredientCount: Int
    let avoidCount: Int
    let reviewCount: Int
    let cleanCount: Int
    let category: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case result
        case reviewStatus = "review_status"
        case sourceStatus = "source_status"
        case scanSource = "scan_source"
        case summaryLine = "summary_line"
        case ingredientCount = "ingredient_count"
        case avoidCount = "avoid_count"
        case reviewCount = "review_count"
        case cleanCount = "clean_count"
        case category
        case createdAt = "created_at"
    }
}

private struct MissingSubmissionUpsert: Codable {
    let barcode: String
    let productName: String
    let brand: String
    let category: String
    let ingredientsText: String
    let cleanedIngredientsText: String
    let result: String
    let summaryLine: String
    let sourceStatus: String
    let reviewStatus: String
    let adminReviewStatus: String
    let note: String
    let flaggedIngredients: [String]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case category
        case ingredientsText = "ingredients_text"
        case cleanedIngredientsText = "cleaned_ingredients_text"
        case result
        case summaryLine = "summary_line"
        case sourceStatus = "source_status"
        case reviewStatus = "review_status"
        case adminReviewStatus = "admin_review_status"
        case note
        case flaggedIngredients = "flagged_ingredients"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct SubmissionImagePatch: Encodable {
    let barcode: String
    let adminReviewStatus: String
    let reviewStatus: String
    let imageURL: String
    let storagePath: String
    let imagePendingUpload: Bool
    let imageContentType: String
    let imageSizeBytes: Int
    let imageUploadedAt: String
    let updatedAt: String

    func dictionary(prefix: String) -> [String: StringEncodableValue] {
        [
            "barcode": .string(barcode),
            "admin_review_status": .string(adminReviewStatus),
            "review_status": .string(reviewStatus),
            "\(prefix)_image_url": .string(imageURL),
            "\(prefix)_image_storage_path": .string(storagePath),
            "\(prefix)_image_pending_upload": .bool(imagePendingUpload),
            "\(prefix)_image_content_type": .string(imageContentType),
            "\(prefix)_image_size_bytes": .int(imageSizeBytes),
            "\(prefix)_image_uploaded_at": .string(imageUploadedAt),
            "updated_at": .string(updatedAt)
        ]
    }
}

private enum StringEncodableValue: Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }
}

private extension IngredientStatus {
    var supabaseValue: String {
        switch self {
        case .avoid: return "AVOID"
        case .watch, .neutral: return "REVIEW"
        case .clean: return "CLEAN"
        case .insufficientData: return "INGREDIENT_DATA_NEEDED"
        }
    }

    init(supabaseValue: String) {
        switch supabaseValue.uppercased() {
        case "AVOID": self = .avoid
        case "CLEAN": self = .clean
        case "INGREDIENT_DATA_NEEDED", "INSUFFICIENT_DATA": self = .insufficientData
        default: self = .watch
        }
    }
}

private extension ProductReviewStatus {
    init(supabaseValue: String?) {
        switch supabaseValue {
        case "approved": self = .approved
        case "adminReviewed", "admin_reviewed": self = .adminReviewed
        case "missingIngredients", "missing_ingredients": self = .missingIngredients
        case "unverifiedSourceData", "unverified_source_data": self = .unverifiedSourceData
        case "userSubmitted", "user_submitted": self = .userSubmitted
        default: self = .pending
        }
    }
}

private func normalizedSupabaseKey(_ value: String) -> String {
    value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
