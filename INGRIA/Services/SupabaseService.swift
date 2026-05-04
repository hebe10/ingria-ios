import Foundation

enum SupabaseServiceError: LocalizedError {
    case badURL
    case badResponse(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Could not build Supabase REST URL."
        case let .badResponse(status, body):
            return "Supabase returned \(status): \(body)"
        }
    }
}

struct ScanHistoryInsert: Encodable {
    let barcode: String
    let productName: String
    let brand: String
    let verdict: String
    let score: Int?
    let totalIngredients: Int
    let recognizedIngredients: Int
    let unknownIngredients: Int
    let coverageRatio: Double
    let unknownIngredientList: [String]
    let rawIngredients: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case verdict
        case score
        case totalIngredients = "total_ingredients"
        case recognizedIngredients = "recognized_ingredients"
        case unknownIngredients = "unknown_ingredients"
        case coverageRatio = "coverage_ratio"
        case unknownIngredientList = "unknown_ingredient_list"
        case rawIngredients = "raw_ingredients"
        case source
    }
}

struct SavedProductInsert: Encodable {
    let barcode: String
    let productName: String
    let brand: String
    let verdict: String
    let score: Int?
    let rawIngredients: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case verdict
        case score
        case rawIngredients = "raw_ingredients"
        case source
    }
}

struct IngredientCorrectionInsert: Encodable {
    let barcode: String
    let productName: String
    let brand: String
    let rawIngredients: String
    let unknownIngredientList: [String]
    let issueType: String
    let note: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case rawIngredients = "raw_ingredients"
        case unknownIngredientList = "unknown_ingredient_list"
        case issueType = "issue_type"
        case note
        case source
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    private let session: URLSession
    private let encoder: JSONEncoder

    private init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
    }

    func insertScanHistory(data: ScanHistoryInsert) async {
        await post(table: "scan_history", payload: data, label: "scan_history")
    }

    func saveProduct(data: SavedProductInsert) async {
        await post(table: "saved_products", payload: data, label: "saved_products")
    }

    func submitIngredientCorrection(data: IngredientCorrectionInsert) async {
        await post(table: "ingredient_corrections", payload: data, label: "ingredient_corrections")
    }

    private func post<T: Encodable>(table: String, payload: T, label: String) async {
        do {
            let body = try encoder.encode(payload)
            let request = try makeRequest(table: table, body: body)
            logRequest(request, body: body, label: label)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("Supabase \(label) failure: missing HTTP response")
                return
            }

            let responseBody = String(data: data, encoding: .utf8) ?? ""
            if (200..<300).contains(http.statusCode) {
                print("Supabase \(label) insert succeeded: HTTP \(http.statusCode)")
            } else {
                print("Supabase \(label) insert failed: HTTP \(http.statusCode)")
                print("Supabase \(label) response body: \(responseBody)")
                print("Supabase \(label) error: \(SupabaseServiceError.badResponse(status: http.statusCode, body: responseBody).localizedDescription)")
            }
        } catch {
            print("Supabase \(label) insert failed before response: \(error.localizedDescription)")
        }
    }

    private func makeRequest(table: String, body: Data) throws -> URLRequest {
        var url = SupabaseConfig.url
        url.append(path: "rest")
        url.append(path: "v1")
        url.append(path: table)

        guard URLComponents(url: url, resolvingAgainstBaseURL: false)?.url != nil else {
            throw SupabaseServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return request
    }

    private func logRequest(_ request: URLRequest, body: Data, label: String) {
        print("Supabase \(label) request: \(request.httpMethod ?? "POST") \(request.url?.absoluteString ?? "")")
        print("Supabase \(label) headers: apikey=<anon>, Authorization=Bearer <anon>, Content-Type=application/json")
        print("Supabase \(label) payload: \(String(data: body, encoding: .utf8) ?? "")")
    }
}

extension ScanHistoryInsert {
    init(audit: ProductAudit) {
        self.init(
            barcode: audit.barcode,
            productName: audit.productName,
            brand: audit.brand,
            verdict: audit.ingriaSupabaseVerdict,
            score: audit.score,
            totalIngredients: audit.totalIngredientCount,
            recognizedIngredients: audit.recognizedIngredientCount,
            unknownIngredients: audit.unknownIngredientCount,
            coverageRatio: audit.coverageRatio,
            unknownIngredientList: audit.unknownIngredients,
            rawIngredients: audit.cleanedIngredientsText.isEmpty ? audit.rawIngredientsText : audit.cleanedIngredientsText,
            source: "ios_app"
        )
    }
}

extension SavedProductInsert {
    init(audit: ProductAudit) {
        self.init(
            barcode: audit.barcode,
            productName: audit.productName,
            brand: audit.brand,
            verdict: audit.ingriaSupabaseVerdict,
            score: audit.score,
            rawIngredients: audit.cleanedIngredientsText.isEmpty ? audit.rawIngredientsText : audit.cleanedIngredientsText,
            source: "ios_app"
        )
    }
}

extension IngredientCorrectionInsert {
    init(audit: ProductAudit) {
        let ingredientsText = audit.cleanedIngredientsText.isEmpty ? audit.rawIngredientsText : audit.cleanedIngredientsText
        self.init(
            barcode: audit.barcode,
            productName: audit.productName,
            brand: audit.brand,
            rawIngredients: ingredientsText,
            unknownIngredientList: audit.unknownIngredients,
            issueType: "ingredient_issue",
            note: "User reported an ingredient issue from the iOS app.",
            source: "ios_app"
        )
    }
}

private extension ProductAudit {
    var ingriaSupabaseVerdict: String {
        switch finalStatus {
        case .clean:
            return "Clean"
        case .avoid:
            return "Avoid"
        case .watch, .neutral, .insufficientData:
            return "Review"
        }
    }
}
