import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    private let homeGreen = Color(hex: "1B4332")
    private let homeCream = Color(hex: "F4F1EB")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center) {
                    IngriaBrandLockup()
                    Spacer()
                    LanguageToggle(selection: $viewModel.appLanguage)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(copy.eyebrow)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(homeGreen.opacity(0.66))

                    Text(copy.headline)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .italic()
                        .tracking(-0.5)
                        .foregroundStyle(homeGreen)

                    Text(copy.subtitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(IngriaTheme.secondaryText)
                        .lineSpacing(5)

                    HStack(spacing: 8) {
                        ForEach(copy.tags, id: \.self) { tag in
                            HomePillTag(title: tag)
                        }
                    }
                    .padding(.top, 2)
                }

                Button {
                    viewModel.selectedTab = .scan
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "barcode.viewfinder")
                        Text(copy.scanButton)
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(homeGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        IngriaSearchField(
                            placeholder: "Search by name or barcode...",
                            text: $viewModel.homeQuery
                        )

                        Button(copy.searchButton) {
                            dismissKeyboard()
                            Task { await viewModel.searchFromHome() }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(homeGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    if !viewModel.homeSuggestions.isEmpty {
                        IngriaCard {
                            VStack(spacing: 10) {
                                ForEach(viewModel.homeSuggestions) { item in
                                    Button {
                                        dismissKeyboard()
                                        Task { await viewModel.selectProduct(item) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            AsyncImage(url: item.imageURL) { image in
                                                image.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.gray.opacity(0.12)
                                            }
                                            .frame(width: 54, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name)
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundStyle(IngriaTheme.ink)
                                                    .multilineTextAlignment(.leading)
                                                Text(item.brand)
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(IngriaTheme.secondaryText)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                RecentScansCard(audits: Array(viewModel.auditHistory.prefix(3)), language: viewModel.appLanguage)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 156)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.visible)
        .background(homeCream)
        .task(id: viewModel.homeQuery) {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await viewModel.updateHomeSuggestions()
        }
    }

    private var copy: HomeCopy {
        HomeCopy(language: viewModel.appLanguage)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct HomeCopy {
    let language: AppLanguage

    var eyebrow: String {
        language == .german ? "EU-fokussierte Zutatenprüfung" : "EU-focused ingredient review"
    }

    var headline: String {
        language == .german ? "Kein Kompromiss." : "No Compromise."
    }

    var subtitle: String {
        language == .german
            ? "Strenge Zutatenprüfung\nfür Lebensmittel und\nKörperpflege."
            : "No compromise ingredient\nscanning for food and\npersonal care."
    }

    var tags: [String] {
        language == .german
            ? ["EU-fokussiert", "Datenbasiert", "Keine Werbung"]
            : ["EU-focused", "Evidence-aware", "No ads"]
    }

    var scanButton: String {
        language == .german ? "PRODUKT SCANNEN" : "SCAN PRODUCT"
    }

    var searchButton: String {
        language == .german ? "Suchen" : "Search"
    }
}

private struct LanguageToggle: View {
    @Binding var selection: AppLanguage
    private let green = Color(hex: "1B4332")

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = language
                    }
                } label: {
                    Text(language.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(selection == language ? .white : green)
                        .frame(width: 34, height: 30)
                        .background(selection == language ? green : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.title)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.78))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(IngriaTheme.border, lineWidth: 1))
    }
}

private struct HomePillTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: "1B4332"))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "D6EAE0"))
            .clipShape(Capsule())
    }
}

private struct RecentScansCard: View {
    let audits: [ProductAudit]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(language == .german ? "Zuletzt gescannt" : "Recently scanned")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(IngriaTheme.ink)
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
            }

            if audits.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    Text("⌁")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(hex: "1B4332"))
                        .frame(width: 44, height: 44)
                        .background(Color(hex: "D6EAE0"))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language == .german ? "Noch keine Scans" : "No scans yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(IngriaTheme.ink)
                        Text(language == .german ? "Scanne dein erstes Produkt, um die Liste zu starten." : "Scan your first product to build a clean history.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(IngriaTheme.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(audits) { audit in
                        RecentScanRow(audit: audit)

                        if audit.id != audits.last?.id {
                            Divider()
                                .background(IngriaTheme.border)
                                .padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(IngriaTheme.border, lineWidth: 1)
        )
    }
}

private struct RecentScanRow: View {
    let audit: ProductAudit

    var body: some View {
        HStack(spacing: 12) {
            RecentScanThumbnail(audit: audit)

            VStack(alignment: .leading, spacing: 3) {
                Text(audit.productName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IngriaTheme.ink)
                    .lineLimit(1)
                Text(audit.brand.isEmpty ? "Unknown brand" : audit.brand)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(grade.letter)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(grade.foreground)
                .frame(width: 34, height: 28)
                .background(grade.background)
                .clipShape(Capsule())
        }
        .padding(.vertical, 10)
    }

    private var grade: (letter: String, foreground: Color, background: Color) {
        switch audit.finalStatus {
        case .clean:
            return ("A", Color(hex: "1B4332"), Color(hex: "D6EAE0"))
        case .watch:
            return ("B", Color(hex: "566B23"), Color(hex: "E7F0C6"))
        case .insufficientData:
            return ("C", Color(hex: "8A5A18"), Color(hex: "F7E1B4"))
        case .avoid:
            return ("D", IngriaTheme.avoid, IngriaTheme.avoidSoft)
        case .neutral:
            return ("C", Color(hex: "8A5A18"), Color(hex: "F7E1B4"))
        }
    }
}

private struct RecentScanThumbnail: View {
    let audit: ProductAudit

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "F4F1EB"))

            if let imageURL = audit.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    case .empty:
                        ProgressView()
                            .tint(Color(hex: "1B4332"))
                            .scaleEffect(0.7)
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(IngriaTheme.border, lineWidth: 0.8)
        )
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: audit.source.localizedCaseInsensitiveContains("beauty") ? "sparkles" : "barcode.viewfinder")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color(hex: "1B4332"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "D6EAE0").opacity(0.72))
    }
}
