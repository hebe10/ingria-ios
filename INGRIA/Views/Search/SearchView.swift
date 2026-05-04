import SwiftUI
import UIKit

struct SearchView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    @FocusState private var isSearchFocused: Bool

    private let recent = [
        RecentSearchItem(title: "Nutella", type: "food", tone: .safe),
        RecentSearchItem(title: "Haferdrink", type: "food", tone: .safe),
        RecentSearchItem(title: "Vanillin", type: "ingr.", tone: .avoid),
        RecentSearchItem(title: "Palm Oil", type: "ingr.", tone: .avoid),
        RecentSearchItem(title: "Carrageenan", type: "ingr.", tone: .caution)
    ]
    private let trending = [
        "🥣 Haferdrink",
        "🍫 Nutella",
        "🧴 Parfum",
        "🌻 Sonnenblumenöl",
        "🍬 Sucralose",
        "🧪 E407"
    ]
    private let green = Color(hex: "1B4332")
    private let cream = Color(hex: "F4F1EB")
    private let border = Color(hex: "DDD9D2")

    private var hasQuery: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.appLanguage == .german ? "Alles finden." : "Find anything.")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundStyle(green)
                    Text(viewModel.appLanguage == .german ? "Produkte, Zutaten oder Barcodes" : "Products, ingredients, or barcodes")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(IngriaTheme.secondaryText)
                }

                SearchPageField(
                    placeholder: viewModel.appLanguage == .german ? "Produkte oder Zutaten suchen..." : "Search products or ingredients...",
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        dismissSearchKeyboard()
                        Task { await viewModel.runSearch() }
                    }
                )

                if hasQuery {
                    searchFilters
                    resultsSection
                } else {
                    recentSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 156)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.visible)
        .background(cream)
        .task(id: searchTaskID) {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await viewModel.runSearch()
        }
    }

    private var searchTaskID: String {
        [
            viewModel.searchQuery,
            viewModel.searchFilter.rawValue,
            viewModel.selectedStoreFilter.rawValue,
            viewModel.categoryFilter,
            viewModel.brandFilter,
            viewModel.ingredientConcernFilter,
            "\(viewModel.availableNearbyOnly)",
            "\(viewModel.onlineOnly)"
        ].joined(separator: "|")
    }

    private var searchFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchResultFilter.allCases) { filter in
                        Button {
                            viewModel.searchFilter = filter
                        } label: {
                            Text(filter.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(viewModel.searchFilter == filter ? .white : green)
                                .padding(.horizontal, 13)
                                .frame(height: 36)
                                .background(viewModel.searchFilter == filter ? green : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(border, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(RetailerTag.allCases) { store in
                            Button(store.rawValue) {
                                viewModel.selectedStoreFilter = store
                            }
                        }
                    } label: {
                        FilterChip(title: viewModel.selectedStoreFilter.rawValue, systemImage: "storefront")
                    }

                    ToggleChip(title: viewModel.appLanguage == .german ? "Store gelistet" : "Store listed", isOn: $viewModel.availableNearbyOnly)
                    ToggleChip(title: viewModel.appLanguage == .german ? "Online" : "Online option", isOn: $viewModel.onlineOnly)
                }
            }

            HStack(spacing: 8) {
                CompactFilterField(placeholder: viewModel.appLanguage == .german ? "Kategorie" : "Category", text: $viewModel.categoryFilter)
                CompactFilterField(placeholder: viewModel.appLanguage == .german ? "Marke" : "Brand", text: $viewModel.brandFilter)
            }

            CompactFilterField(
                placeholder: viewModel.appLanguage == .german ? "Zutatenbedenken" : "Ingredient concern",
                text: $viewModel.ingredientConcernFilter
            )
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle(viewModel.appLanguage == .german ? "Ergebnisse" : "Results")
                Spacer()
                Text(viewModel.searchStateText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IngriaTheme.green700)
            }

            if viewModel.searchResults.isEmpty {
                Text(emptySearchCopy)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, item in
                        Button {
                            dismissSearchKeyboard()
                            Task { await viewModel.selectProduct(item) }
                        } label: {
                            SearchResultRow(item: item)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.searchResults.count - 1 {
                            Divider()
                                .background(IngriaTheme.border)
                                .padding(.leading, 76)
                        }
                    }
                }
                .background(IngriaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(IngriaTheme.border, lineWidth: 1))
            }
        }
    }

    private var emptySearchCopy: String {
        if viewModel.isSearching {
            return viewModel.appLanguage == .german ? "Suche..." : "Searching..."
        }
        if viewModel.searchFilter == .clean && viewModel.selectedStoreFilter != .all {
            return viewModel.appLanguage == .german
                ? "Noch kein Clean-Match in diesen Stores gefunden. Probiere alle Stores oder Online-Optionen."
                : "No clean match found in these stores yet. Try all stores or online options."
        }
        if viewModel.searchFilter == .clean {
            return viewModel.appLanguage == .german
                ? "Noch kein Clean-Produkt gefunden. INGRIA kann trotzdem Zutaten-Guidance anzeigen, wenn du ein Produkt scannst."
                : "No clean product found yet. Scan a product and INGRIA can still show ingredient-level guidance."
        }
        return viewModel.appLanguage == .german
            ? "Kein Produkt gefunden. Probiere einen Barcode oder scanne die Zutatenliste."
            : "No product found. Try a barcode or scan the label side."
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(viewModel.appLanguage == .german ? "Letzte Suchen" : "Recent searches")

            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.title) { index, item in
                    Button {
                        dismissSearchKeyboard()
                        viewModel.searchQuery = item.title
                        Task { await viewModel.runSearch(query: item.title) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "clock")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(IngriaTheme.secondaryText)
                                .frame(width: 34, height: 34)

                            RecentTypePill(item: item)

                            Text(item.title)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(IngriaTheme.ink)

                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(IngriaTheme.secondaryText.opacity(0.7))
                        }
                        .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)

                    if index < recent.count - 1 {
                        Divider()
                            .background(border)
                            .padding(.leading, 48)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(viewModel.appLanguage == .german ? "Häufig gesucht" : "Trending searches")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(trending, id: \.self) { item in
                        Button {
                            dismissSearchKeyboard()
                            let clean = item.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                            viewModel.searchQuery = clean
                            Task { await viewModel.runSearch(query: clean) }
                        } label: {
                            Text(item)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(green)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "D6EAE0"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(IngriaTheme.ink)
    }

    private func dismissSearchKeyboard() {
        isSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private enum RecentTone {
    case safe
    case caution
    case avoid
}

private struct RecentSearchItem {
    let title: String
    let type: String
    let tone: RecentTone
}

private struct SearchPageField: View {
    let placeholder: String
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(IngriaTheme.secondaryText)
            TextField(placeholder, text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "DDD9D2"), lineWidth: 0.5))
    }
}

private struct RecentTypePill: View {
    let item: RecentSearchItem

    var body: some View {
        Text(item.type)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch item.tone {
        case .safe: return Color(hex: "D6EAE0")
        case .caution: return Color(hex: "FFF0CC")
        case .avoid: return Color(hex: "FFE0DC")
        }
    }

    private var foreground: Color {
        switch item.tone {
        case .safe: return Color(hex: "1B4332")
        case .caution: return Color(hex: "8A5A18")
        case .avoid: return IngriaTheme.avoid
        }
    }
}

private struct SearchResultRow: View {
    let item: ProductSearchItem

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: item.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14)
                    .fill(IngriaTheme.green200.opacity(0.45))
                    .overlay(
                        Image(systemName: "shippingbox")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(IngriaTheme.green700.opacity(0.7))
                    )
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IngriaTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(item.brand)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .lineLimit(1)

                if let resultStatus = item.resultStatus {
                    HStack(spacing: 7) {
                        ResultMiniBadge(status: resultStatus)
                        if let store = item.storeAvailability.first {
                            Text(store.displayText)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(IngriaTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                if let reason = item.resultReason, item.resultStatus == .clean {
                    Text(reason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IngriaTheme.green700)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(IngriaTheme.secondaryText.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(hex: "1B4332"))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(IngriaTheme.border, lineWidth: 0.8))
    }
}

private struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isOn ? .white : Color(hex: "1B4332"))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isOn ? Color(hex: "1B4332") : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(IngriaTheme.border, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct CompactFilterField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 13, weight: .semibold))
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(IngriaTheme.border, lineWidth: 0.8))
    }
}

private struct ResultMiniBadge: View {
    let status: IngredientStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch status {
        case .clean: return Color(hex: "1B4332")
        case .watch: return Color(hex: "8A5A18")
        case .avoid: return IngriaTheme.avoid
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

    private var background: Color {
        switch status {
        case .clean: return Color(hex: "D6EAE0")
        case .watch: return Color(hex: "FFF0CC")
        case .avoid: return Color(hex: "FFE0DC")
        case .insufficientData, .neutral: return Color(hex: "F4F1EB")
        }
    }
}
