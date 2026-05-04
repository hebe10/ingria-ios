import Foundation

/// Small Open Beauty Facts client.
///
/// Supabase remains INGRIA's source of truth. This service is only used as a
/// public fallback when INGRIA does not have a reviewed product yet.
struct OpenBeautyFactsService {
    private let decoder = JSONDecoder()

    func fetchProduct(barcode rawBarcode: String) async throws -> BeautyProduct? {
        let barcode = BarcodeValueNormalizer.normalize(rawBarcode)
        guard !barcode.isEmpty else { return nil }

        let fields = [
            "code",
            "product_name",
            "product_name_en",
            "product_name_de",
            "brands",
            "categories",
            "categories_tags",
            "image_url",
            "image_front_url",
            "ingredients_text",
            "ingredients_text_en",
            "ingredients_text_de",
            "ingredients_text_fr",
            "countries",
            "countries_tags",
            "labels",
            "labels_tags"
        ].joined(separator: ",")

        guard var components = URLComponents(string: "https://world.openbeautyfacts.org/api/v2/product/\(barcode).json") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "fields", value: fields)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("INGRIA/1.0 contact@email.com", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await Self.session.data(for: request)
        let response = try decoder.decode(OpenBeautyFactsProductResponse.self, from: data)
        guard response.status == 1, let payload = response.product else { return nil }

        let ingredientText = firstNonEmpty([
            payload.ingredients_text_de,
            payload.ingredients_text,
            payload.ingredients_text_en,
            payload.ingredients_text_fr
        ])

        return BeautyProduct(
            barcode: payload.code ?? barcode,
            productName: firstNonEmpty([payload.product_name_de, payload.product_name, payload.product_name_en]) ?? "Unknown beauty product",
            brand: payload.brands ?? "Unknown brand",
            categories: payload.categories ?? payload.categories_tags?.joined(separator: ", ") ?? "beauty",
            imageURL: URL(string: firstNonEmpty([payload.image_front_url, payload.image_url]) ?? ""),
            ingredientsText: ingredientText ?? "",
            countries: payload.countries ?? payload.countries_tags?.joined(separator: ", ") ?? "",
            labels: payload.labels ?? payload.labels_tags?.joined(separator: ", ") ?? "",
            source: "open_beauty_facts",
            importedAt: nil,
            lastCheckedAt: Date(),
            dataConfidence: ingredientText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? .openDatabase : .missingIngredients,
            result: nil,
            summaryLine: "",
            reviewStatus: .unverifiedSourceData,
            sourceStatus: .openBeautyFacts
        )
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 12 * 1024 * 1024,
            diskCapacity: 48 * 1024 * 1024,
            diskPath: "ingria-open-beauty-facts"
        )
        return URLSession(configuration: configuration)
    }()
}

private struct OpenBeautyFactsProductResponse: Decodable {
    let status: Int
    let product: OpenBeautyFactsProductPayload?
}

private struct OpenBeautyFactsProductPayload: Decodable {
    let code: String?
    let product_name: String?
    let product_name_en: String?
    let product_name_de: String?
    let brands: String?
    let categories: String?
    let categories_tags: [String]?
    let image_url: String?
    let image_front_url: String?
    let ingredients_text: String?
    let ingredients_text_en: String?
    let ingredients_text_de: String?
    let ingredients_text_fr: String?
    let countries: String?
    let countries_tags: [String]?
    let labels: String?
    let labels_tags: [String]?
}
