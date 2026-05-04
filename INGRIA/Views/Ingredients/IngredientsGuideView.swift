import SwiftUI

struct IngredientsGuideView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    @State private var expandedID: String?
    @State private var statusFilter: IngredientStatusFilter = .all
    private let cream = Color(hex: "F4F1EB")
    private let green = Color(hex: "1B4332")
    private let border = Color(hex: "DDD9D2")
    private let headerSage = Color(hex: "EEF4EC")

    var body: some View {
        let entries = statusFilter.apply(to: viewModel.ingredientEntries())

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                guideHeader

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.appLanguage == .german ? "Zutaten" : "Ingredient guide")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundStyle(green)

                    HStack(spacing: 8) {
                        ForEach(IngredientStatusFilter.allCases) { filter in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    statusFilter = filter
                                }
                            } label: {
                                Text(filter.title(language: viewModel.appLanguage))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(statusFilter == filter ? .white : green)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(statusFilter == filter ? green : Color.white)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(border, lineWidth: statusFilter == filter ? 0 : 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            IngredientGuideRow(
                                entry: entry,
                                language: viewModel.appLanguage,
                                isExpanded: expandedID == entry.id,
                                onTap: {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        expandedID = expandedID == entry.id ? nil : entry.id
                                    }
                                }
                            )

                            if index < entries.count - 1 {
                                Divider()
                                    .background(border)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 0.5))
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 156)
        }
        .scrollIndicators(.visible)
        .background(cream)
        .onAppear {
            viewModel.ingredientFilter = "all"
        }
    }

    private var guideHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    viewModel.selectedTab = .home
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(green)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(green.opacity(0.62))
                    TextField(viewModel.appLanguage == .german ? "Zutaten suchen..." : "Search for ingredients...", text: $viewModel.ingredientQuery)
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(IngriaTheme.ink)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 0.6))
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 48)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [cream, headerSage],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
        .overlay(
            Rectangle()
                .fill(border.opacity(0.7))
                .frame(height: 0.6),
            alignment: .bottom
        )
    }
}

private enum IngredientStatusFilter: String, CaseIterable, Identifiable {
    case all
    case safe
    case caution
    case avoid

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all: return language == .german ? "Alle" : "All"
        case .safe: return language == .german ? "Gut" : "Clean"
        case .caution: return language == .german ? "Prüfen" : "Review"
        case .avoid: return language == .german ? "Meiden" : "Avoid"
        }
    }

    func apply(to entries: [IngredientGuideEntry]) -> [IngredientGuideEntry] {
        switch self {
        case .all:
            return entries
        case .safe:
            return entries.filter { $0.status == .clean }
        case .caution:
            return entries.filter { $0.status == .watch || $0.status == .insufficientData || $0.status == .neutral }
        case .avoid:
            return entries.filter { $0.status == .avoid }
        }
    }
}

private struct IngredientGuideRow: View {
    let entry: IngredientGuideEntry
    let language: AppLanguage
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(IngriaTheme.ink)
                            .multilineTextAlignment(.leading)

                        StatusMark(status: entry.status)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "B0ADA6"))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 2)
                }

                if isExpanded {
                    expandedDetails
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .buttonStyle(.plain)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailSection(language == .german ? "Kategorie" : "Category", value: categoryLabel)
            detailSection(language == .german ? "Ergebnis" : "Result", value: summary)
            detailSection(language == .german ? "Grund" : "Reason", values: reasonValues)
        }
        .padding(10)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        )
        .padding(.top, 2)
    }

    @ViewBuilder
    private func detailSection(_ title: String, value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                detailLabel(title)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IngriaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func detailSection(_ title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                detailLabel(title)
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IngriaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1)
            .foregroundStyle(statusColor)
    }

    private var summary: String {
        let localized = language == .german ? entry.verdict_de : entry.verdict_en
        return sanitize(localized ?? entry.verdict ?? fallbackReason)
    }

    private var categoryLabel: String {
        if language == .german, let category = entry.category_de, !category.isEmpty { return category }
        if language == .englishUK, let category = entry.category_en, !category.isEmpty { return category }
        switch entry.category {
        case "beauty":
            return language == .german ? "Kosmetik / Körperpflege" : "Beauty / Personal care"
        case "both":
            return language == .german ? "Lebensmittel / Körperpflege" : "Food / Personal care"
        default:
            return language == .german ? "Lebensmittel" : "Food"
        }
    }

    private var reasonValues: [String] {
        let localized = language == .german ? entry.reason_de : entry.reason_en
        if let localized, !localized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [sanitize(localized)]
        }
        return [sanitize(fallbackReason)]
    }

    private var displayName: String {
        if language == .german, let name = entry.name_de, !name.isEmpty { return name }
        if language == .englishUK, let name = entry.name_en, !name.isEmpty { return name }
        return entry.name
    }

    private var fallbackReason: String {
        entry.why_bad?.first
            ?? entry.why_moderate?.first
            ?? entry.why_good?.first
            ?? "No short explanation added yet."
    }

    private func sanitize(_ value: String) -> String {
        var cleaned = IngredientCopyFormatter.clean(value)
            .replacingOccurrences(of: #"(?i)^INGRIA flags\s+.+?\s+because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA marks\s+.+?\s+as questionable because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA treats\s+.+?\s+as clean because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is flagged as an avoid ingredient because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is flagged as avoid\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is considered clean when\s+"#, with: "Clean when ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is a questionable ingredient\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bquestionable ingredient\b"#, with: "review trigger", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bbad ingredient\b"#, with: "flagged ingredient", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstrict clean-label standards\b"#, with: "INGRIA screening criteria", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstrict clean-label rules\b"#, with: "INGRIA screening criteria", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bsafety concerns\b"#, with: "ingredient concerns", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bsafe\b"#, with: "low concern", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bEU banned it in food\b"#, with: "restricted for this use in some EU contexts", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.range(of: #"^[a-z]"#, options: .regularExpression) != nil {
            cleaned.replaceSubrange(cleaned.startIndex...cleaned.startIndex, with: String(cleaned[cleaned.startIndex]).uppercased())
        }
        return IngredientCopyFormatter.display(cleaned, ingredientName: displayName, status: entry.status, language: language)
    }

    private var statusColor: Color {
        switch entry.status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return IngriaTheme.clean
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

}

private struct StatusMark: View {
    let status: IngredientStatus

    var body: some View {
        Circle()
            .fill(background)
            .frame(width: 18, height: 18)
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(foreground)
            )
            .accessibilityLabel(status.title)
    }

    private var background: Color {
        switch status {
        case .avoid: return Color(hex: "FFE0DC")
        case .watch: return Color(hex: "FFF0CC")
        case .clean: return Color(hex: "D6EAE0")
        case .insufficientData, .neutral: return Color(hex: "ECE8E2")
        }
    }

    private var foreground: Color {
        switch status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return Color(hex: "1B4332")
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

    private var iconName: String {
        switch status {
        case .avoid: return "xmark"
        case .watch: return "exclamationmark"
        case .clean: return "checkmark"
        case .insufficientData, .neutral: return "questionmark"
        }
    }
}
