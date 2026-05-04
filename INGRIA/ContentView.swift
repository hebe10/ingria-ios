import SwiftUI

struct Product: Codable, CustomStringConvertible {
    let barcode: String
    let product_name: AnyCodable
    let ingredients_text: AnyCodable?

    var description: String {
        """
        Product(
          barcode: \(barcode),
          product_name: \(product_name),
          ingredients_text: \(ingredients_text?.description ?? "nil")
        )
        """
    }
}

struct AnyCodable: Codable, CustomStringConvertible {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            var unkeyed = encoder.unkeyedContainer()
            for element in array {
                let wrapped = AnyCodable(element)
                try unkeyed.encode(wrapped)
            }
        case let dictionary as [String: Any]:
            var keyed = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (key, element) in dictionary {
                let codingKey = DynamicCodingKeys(stringValue: key)!
                try keyed.encode(AnyCodable(element), forKey: codingKey)
            }
        default:
            try container.encode(String(describing: value))
        }
    }

    var description: String {
        if let data = try? JSONSerialization.data(withJSONObject: jsonObject(value), options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func jsonObject(_ value: Any) -> Any {
        switch value {
        case is NSNull, is String, is Bool, is Int, is Double:
            return value
        case let array as [Any]:
            return array.map(jsonObject)
        case let dictionary as [String: Any]:
            return dictionary.mapValues(jsonObject)
        default:
            return String(describing: value)
        }
    }
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

func loadProducts(file: String) -> [Product] {
    guard let url = Bundle.main.url(forResource: file, withExtension: "json"),
          let data = try? Data(contentsOf: url)
    else {
        print("FAILED loading \(file)")
        return []
    }

    let decoder = JSONDecoder()

    if let products = try? decoder.decode([Product].self, from: data) {
        return products
    }

    guard let text = String(data: data, encoding: .utf8) else {
        print("FAILED reading \(file) as text")
        return []
    }

    return text
        .split(whereSeparator: \.isNewline)
        .compactMap { line in
            try? decoder.decode(Product.self, from: Data(line.utf8))
        }
}

func findProduct(barcode: String, file: String) -> Product? {
    guard let url = Bundle.main.url(forResource: file, withExtension: "json") else {
        print("FAILED loading \(file)")
        return nil
    }

    let decoder = JSONDecoder()

    if let data = try? Data(contentsOf: url),
       let products = try? decoder.decode([Product].self, from: data) {
        return products.first { $0.barcode == barcode }
    }

    guard let handle = try? FileHandle(forReadingFrom: url) else {
        print("FAILED opening \(file)")
        return nil
    }
    defer { try? handle.close() }

    var buffer = Data()

    while true {
        let chunk = handle.readData(ofLength: 1024 * 1024)
        if chunk.isEmpty { break }

        buffer.append(chunk)

        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)

            guard !line.isEmpty,
                  let product = try? decoder.decode(Product.self, from: line)
            else { continue }

            if product.barcode == barcode {
                return product
            }
        }
    }

    if !buffer.isEmpty,
       let product = try? decoder.decode(Product.self, from: buffer),
       product.barcode == barcode {
        return product
    }

    return nil
}

struct ContentView: View {
    @State private var barcode = "3017620422003"
    @State private var resultText = "Check console"

    var body: some View {
        VStack(spacing: 16) {
            Text("OpenFacts bundle test")
                .font(.title2.bold())

            TextField("Barcode", text: $barcode)
                .textInputAutocapitalization(.never)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button("Find product") {
                test()
            }
            .buttonStyle(.borderedProminent)

            Text(resultText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .onAppear {
            test()
        }
    }

    func test() {
        if let product = findProduct(barcode: barcode, file: "food") {
            print("FOUND FOOD:", product)
            resultText = "FOUND FOOD: \(barcode)"
        } else if let product = findProduct(barcode: barcode, file: "beauty") {
            print("FOUND BEAUTY:", product)
            resultText = "FOUND BEAUTY: \(barcode)"
        } else {
            print("NOT FOUND")
            resultText = "NOT FOUND: \(barcode)"
        }
    }
}
