import SwiftUI

struct IngriaRootView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    @AppStorage("hasAcceptedIngriaDisclaimer") private var hasAcceptedDisclaimer = false

    var body: some View {
        ZStack {
            TabView(selection: $viewModel.selectedTab) {
                HomeView()
                    .tag(IngriaTab.home)

                SearchView()
                    .tag(IngriaTab.search)

                ScanView()
                    .tag(IngriaTab.scan)

                IngredientsGuideView()
                    .tag(IngriaTab.ingredients)

                ListsView()
                    .tag(IngriaTab.lists)
            }
            .toolbar(.hidden, for: .tabBar)

            if let audit = viewModel.activeAudit {
                ResultsView(
                    audit: audit,
                    onClose: { viewModel.activeAudit = nil },
                    onUploadLabel: {
                        viewModel.activeAudit = nil
                        viewModel.selectedTab = .scan
                        viewModel.scanStateText = "Ingredient list missing. Scan the label side so INGRIA can screen it."
                    },
                    onScanNext: {
                        viewModel.activeAudit = nil
                        viewModel.selectedTab = .scan
                        viewModel.scanStateText = "Ready to scan the next product."
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(10)
            }
        }
        .background(IngriaTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IngriaTabBar()
        }
        .task {
            await viewModel.bootstrap()
        }
        .sheet(isPresented: Binding(
            get: { !hasAcceptedDisclaimer },
            set: { if !$0 { hasAcceptedDisclaimer = true } }
        )) {
            FirstUseDisclaimerSheet {
                hasAcceptedDisclaimer = true
            }
            .interactiveDismissDisabled()
        }
    }
}

#Preview("INGRIA App") {
    IngriaRootView()
        .environmentObject(IngriaViewModel())
}
