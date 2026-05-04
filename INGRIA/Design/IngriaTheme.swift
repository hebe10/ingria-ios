import SwiftUI

enum IngriaTheme {
    static let background = Color(hex: "F7F6F2")
    static let surface = Color.white.opacity(0.94)
    static let border = Color(hex: "E8E6E1")
    static let ink = Color(hex: "111111")
    static let secondaryText = Color(hex: "6B7280")
    static let green900 = Color(hex: "143D2E")
    static let green700 = Color(hex: "2F6B52")
    static let green200 = Color(hex: "DCE8DE")
    static let avoid = Color(hex: "E75B5B")
    static let avoidSoft = Color(hex: "FFF0EF")
    static let watch = Color(hex: "E5A44B")
    static let watchSoft = Color(hex: "FFF6E8")
    static let clean = Color(hex: "5DAA72")
    static let cleanSoft = Color(hex: "EFF8F1")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
