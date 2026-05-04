import SwiftUI

@main
struct INGRIAApp: App {
    @StateObject private var viewModel = IngriaViewModel()

    var body: some Scene {
        WindowGroup {
            IngriaRootView()
                .environmentObject(viewModel)
                .tint(Color(hex: "1B4332"))
        }
    }
}
