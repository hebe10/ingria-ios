import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    @State private var didSaveToList = false
    @State private var didReportIssue = false
    @State private var imagePickerMode: ResultImagePickerMode?
    let audit: ProductAudit
    let onClose: () -> Void
    let onUploadLabel: () -> Void
    let onScanNext: () -> Void

    private var flaggedForExplanation: [AuditedIngredient] {
        deduplicatedFlaggedIngredients
    }

    private var hasIngredientData: Bool {
        !audit.displayIngredients.isEmpty && (audit.confidence == .structured || audit.confidence == .extractedFromText)
    }

    private var resultDisplayIngredients: [DisplayIngredient] {
        audit.displayIngredients
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                resultHero
                resultCard
                if audit.totalIngredientCount > 0 {
                    coverageCard
                }
                whyFlaggedCard
                if !audit.unknownIngredients.isEmpty {
                    unverifiedCard
                }
            }
            .padding(.bottom, 168)
        }
        .scrollIndicators(.hidden)
        .background(pageBackground.ignoresSafeArea())
        .sheet(item: $imagePickerMode) { mode in
            ImagePickerView(sourceType: mode.sourceType) { image in
                switch mode.purpose {
                case .ingredients:
                    Task {
                        await viewModel.auditIngredientImage(
                            image,
                            productName: audit.productName,
                            brand: audit.brand,
                            category: audit.productCategory.lowercased().contains("beauty") ? "beauty" : "food"
                        )
                    }
                case .front:
                    viewModel.storeFrontImageForReview(image)
                }
            }
        }
    }

    private var resultHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                compactTopButton(system: "chevron.left", action: onClose)
                Spacer()
                Text(viewModel.appLanguage == .german ? "INGRIA ERGEBNIS" : "INGRIA RESULT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(heroForeground)
                Spacer()
                Color.clear
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(productContextLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(heroForeground.opacity(0.82))
                    .lineLimit(1)

                Text(audit.productName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(heroForeground)
                    .lineLimit(2)
            }

            ZStack(alignment: .bottom) {
                largeProductImageCard

                StatusScanLogo(status: audit.finalStatus, size: 68)
                    .overlay(Circle().stroke(Color.white, lineWidth: 5))
                    .offset(y: 34)
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(heroBackground)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(verdictDisplay)
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .italic()
                    .foregroundStyle(statusColor(audit.finalStatus))

                Text(resultDefinition)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IngriaTheme.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                Text(viewModel.appLanguage == .german ? "Zutaten" : "Ingredients")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(statusColor(audit.finalStatus))

                if hasIngredientData {
                    IngredientInlineText(items: resultDisplayIngredients, language: viewModel.appLanguage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(viewModel.appLanguage == .german ? "Für dieses Produkt ist noch keine Zutatenliste verfügbar." : "No ingredient list is available for this product yet.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(IngriaTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(IngriaTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(IngriaTheme.border, lineWidth: 1))
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await viewModel.saveProductToSupabase(audit)
                        withAnimation(.snappy(duration: 0.2)) {
                            didSaveToList = true
                        }
                    }
                } label: {
                    Text(saveButtonTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(hex: "1B4332"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task {
                        await viewModel.reportAuditIssue(audit)
                        withAnimation(.snappy(duration: 0.2)) {
                            didReportIssue = true
                        }
                    }
                } label: {
                    Text(reportButtonTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "1B4332"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "DDD9D2"), lineWidth: 0.8))
                }
            }
            .padding(.top, 2)

            if didReportIssue {
                Text(viewModel.appLanguage == .german ? "Danke. Wir merken diesen Produktbericht für eine spätere Datenprüfung vor." : "Thanks. This product report is marked for later data review.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IngriaTheme.green700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(resultCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(resultCardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var largeProductImageCard: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
            .overlay(
                AsyncImage(url: audit.imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 250)
                        .clipped()
                        .padding(18)
                } placeholder: {
                    VStack(spacing: 9) {
                        ScanAppIcon(size: 72, filled: false)
                        Text(audit.productName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(IngriaTheme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.8), lineWidth: 1))
    }

    private var productImage: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white)
            .frame(width: 42, height: 42)
            .overlay(
                AsyncImage(url: audit.imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: {
                    ScanAppIcon(size: 24, filled: false)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(IngriaTheme.border, lineWidth: 0.8))
    }

    private var whyFlaggedCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            miniProductStrip

            Text(audit.finalStatus == .insufficientData ? (viewModel.appLanguage == .german ? "Zur Prüfung hochladen" : "Upload for review") : (viewModel.appLanguage == .german ? "Warum markiert?" : "Why flagged?"))
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color(hex: "1B4332"))

            if audit.finalStatus == .insufficientData {
                Text(viewModel.appLanguage == .german ? "INGRIA kann dieses Produkt ohne Zutatenliste nicht prüfen. Scanne die Rückseite, damit die Zutaten mit der INGRIA-Datenbank abgeglichen werden können." : "INGRIA cannot screen this product without the back-label ingredients. Upload or scan the ingredient side so the system can match the ingredient list against the INGRIA database.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IngriaTheme.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                missingIngredientActions

                if !viewModel.ocrStateText.isEmpty {
                    Text(viewModel.ocrStateText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IngriaTheme.green700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if flaggedForExplanation.isEmpty {
                Text(viewModel.appLanguage == .german ? "Keine offensichtliche Auffälligkeit in den verfügbaren Zutatendaten gefunden." : "No obvious concern found from the available ingredient data.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(flaggedForExplanation) { ingredient in
                        FlaggedReasonCard(ingredient: ingredient, language: viewModel.appLanguage)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: "DDD9D2"), lineWidth: 0.6)
        )
        .padding(.horizontal, 20)
    }

    private var coverageCard: some View {
        let percent = Int((audit.coverageRatio * 100).rounded())
        let recognized = audit.recognizedIngredientCount
        let total = audit.totalIngredientCount
        let scoreLine: String? = audit.score.map { score in
            viewModel.appLanguage == .german ? "INGRIA Score: \(score)/100" : "INGRIA score: \(score)/100"
        }
        let coverageLine = viewModel.appLanguage == .german
            ? "Geprüft: \(recognized) von \(total) Zutaten (\(percent)%)"
            : "Checked \(recognized) of \(total) ingredients (\(percent)%)"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: audit.isPartialResult ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(audit.isPartialResult ? IngriaTheme.watch : IngriaTheme.green700)
                Text(coverageLine)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(IngriaTheme.ink)
                Spacer(minLength: 0)
            }

            // Coverage bar — visual signal that this is a partial scan.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(IngriaTheme.surface)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(audit.coverageRatio >= 0.80 ? IngriaTheme.green700 : (audit.coverageRatio >= 0.60 ? IngriaTheme.watch : IngriaTheme.avoid))
                        .frame(width: max(6, proxy.size.width * audit.coverageRatio))
                }
            }
            .frame(height: 6)

            if audit.isPartialResult {
                Text(viewModel.appLanguage == .german
                     ? "Teilergebnis. Einige Zutaten wurden nicht erkannt — INGRIA hat dieses Produkt deshalb nicht als sauber bewertet."
                     : "Partial result. Some ingredients were not recognized, so INGRIA did not mark this product as fully clean.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IngriaTheme.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let scoreLine {
                Text(scoreLine)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(IngriaTheme.green700)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "DDD9D2"), lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private var unverifiedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.appLanguage == .german
                 ? "Nicht verifizierte Zutaten (\(audit.unknownIngredientCount))"
                 : "Unverified ingredients (\(audit.unknownIngredientCount))")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color(hex: "1B4332"))

            Text(viewModel.appLanguage == .german
                 ? "Diese Zutaten waren nicht in der INGRIA-Datenbank. Sie wurden nicht als sauber, prüfen oder meiden eingestuft."
                 : "These ingredients were not in the INGRIA database. They have not been classified as clean, review, or avoid.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IngriaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(audit.unknownIngredients.prefix(40).enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IngriaTheme.ink.opacity(0.75))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "F4F1EB"))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(hex: "DDD9D2"), lineWidth: 0.6))
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "DDD9D2"), lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private var missingIngredientActions: some View {
        VStack(spacing: 10) {
            Button {
                imagePickerMode = .cameraIngredients
            } label: {
                Label(viewModel.appLanguage == .german ? ingredientPhotoTitle : ingredientPhotoTitleEN, systemImage: "camera.viewfinder")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(hex: "1B4332"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                Button {
                    imagePickerMode = .cameraFront
                } label: {
                    Text(viewModel.appLanguage == .german ? "Vorderseite fotografieren" : "Photograph front")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "1B4332"))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(IngriaTheme.border, lineWidth: 0.8))
                }

                Button {
                    imagePickerMode = .libraryIngredients
                } label: {
                    Text(viewModel.appLanguage == .german ? "Aus Galerie wählen" : "Choose from gallery")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "1B4332"))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(IngriaTheme.border, lineWidth: 0.8))
                }
            }
        }
    }

    private var ingredientPhotoTitle: String {
        audit.productCategory.lowercased().contains("beauty") ? "INCI fotografieren" : "Zutaten fotografieren"
    }

    private var ingredientPhotoTitleEN: String {
        audit.productCategory.lowercased().contains("beauty") ? "Photograph INCI" : "Photograph ingredients"
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.appLanguage == .german ? "Worauf dieses Ergebnis basiert" : "What this result is based on")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color(hex: "1B4332"))

            VStack(spacing: 10) {
                EvidenceRow(label: viewModel.appLanguage == .german ? "Zutatenliste" : "Ingredient list", value: hasIngredientData ? (viewModel.appLanguage == .german ? "Verfügbar" : "Available") : (viewModel.appLanguage == .german ? "Fehlt oder unvollständig" : "Missing or incomplete"))
                EvidenceRow(label: viewModel.appLanguage == .german ? "Quelle" : "Source database", value: localizedSource)
                EvidenceRow(label: viewModel.appLanguage == .german ? "Quellstatus" : "Source status", value: localizedSourceStatus)
                EvidenceRow(label: viewModel.appLanguage == .german ? "Review-Status" : "Review status", value: localizedReviewStatus)
                EvidenceRow(label: viewModel.appLanguage == .german ? "Kategorie" : "Product category", value: localizedCategory)
                EvidenceRow(label: viewModel.appLanguage == .german ? "Geprüft am" : "Date checked", value: checkedDate)
                EvidenceRow(label: viewModel.appLanguage == .german ? "Grund" : "Reason for result", value: evidenceReason)
            }

            Text(IngriaLegalCopy.result(language: viewModel.appLanguage))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IngriaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(IngriaLegalCopy.publicData(language: viewModel.appLanguage))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IngriaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "DDD9D2"), lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private var alternativesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.appLanguage == .german ? "Clean Alternativen" : "Clean alternatives")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color(hex: "1B4332"))

            Text(alternativeTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IngriaTheme.ink.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            switch viewModel.activeAlternativeState {
            case .productMatches(let matches):
                VStack(spacing: 10) {
                    ForEach(matches.prefix(3)) { alternative in
                        ProductAlternativeRow(alternative: alternative)
                    }
                }
            case .ingredientGuidance(let guidance):
                VStack(spacing: 10) {
                    ForEach(guidance.prefix(3)) { alternative in
                        IngredientAlternativeRow(alternative: alternative)
                    }
                }
            case .none:
                Text(viewModel.appLanguage == .german ? "Du kannst ein Produkt scannen oder melden, damit INGRIA später eine Alternative prüfen kann." : "You can scan or report a product so INGRIA can review an alternative later.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "DDD9D2"), lineWidth: 0.6))
    }

    private var miniProductStrip: some View {
        HStack(spacing: 10) {
            productImage

            VStack(alignment: .leading, spacing: 2) {
                Text(audit.productName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(IngriaTheme.ink)
                    .lineLimit(1)
                Text(audit.brand.isEmpty ? "Unknown brand" : audit.brand)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
            SeverityBadge(status: audit.finalStatus, language: viewModel.appLanguage)
        }
        .padding(10)
        .background(Color(hex: "F4F1EB"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var resultCardBackground: Color {
        switch audit.finalStatus {
        case .avoid: return Color(hex: "FFF4F3")
        case .watch: return Color(hex: "FFFBF0")
        case .clean: return Color(hex: "F3FBF7")
        case .insufficientData, .neutral: return Color.white
        }
    }

    private var resultCardBorder: Color {
        switch audit.finalStatus {
        case .avoid: return Color(hex: "FFD5D0")
        case .watch: return Color(hex: "FFE8A0")
        case .clean: return Color(hex: "C0DDB0")
        case .insufficientData, .neutral: return Color(hex: "DDD9D2")
        }
    }

    private var verdictDisplay: String {
        switch audit.finalStatus {
        case .avoid: return viewModel.appLanguage == .german ? "Meiden" : "Avoid"
        case .watch: return viewModel.appLanguage == .german ? "Prüfen" : "Review"
        case .clean: return viewModel.appLanguage == .german ? "Sauber" : "Clean"
        case .insufficientData, .neutral: return viewModel.appLanguage == .german ? "Zutaten nötig" : "Needs ingredients"
        }
    }

    private var resultDefinition: String {
        switch audit.finalStatus {
        case .clean:
            return viewModel.appLanguage == .german ? "Keine offensichtliche Auffälligkeit in den verfügbaren Zutatendaten gefunden." : "No obvious concern found from the available ingredient data."
        case .watch:
            return viewModel.appLanguage == .german ? "Weitere Informationen oder eine manuelle Prüfung können nötig sein." : "More information or human review may be needed."
        case .avoid:
            return viewModel.appLanguage == .german ? "INGRIA hat nach seinen Prüfkriterien eine deutliche Auffälligkeit gefunden." : "INGRIA found a significant concern based on its screening criteria."
        case .insufficientData, .neutral:
            return viewModel.appLanguage == .german ? "Zutatendaten fehlen oder sind unvollständig." : "Ingredient data is missing or incomplete."
        }
    }

    private var reportButtonTitle: String {
        if didReportIssue {
            return viewModel.appLanguage == .german ? "Gemeldet" : "Reported"
        }
        return viewModel.appLanguage == .german ? "Melden" : "Report"
    }

    private var saveButtonTitle: String {
        if didSaveToList {
            return viewModel.appLanguage == .german ? "Gespeichert" : "Saved"
        }
        return viewModel.appLanguage == .german ? "Speichern" : "Save"
    }

    private var deduplicatedFlaggedIngredients: [AuditedIngredient] {
        var seen = Set<String>()
        return audit.flaggedIngredients.filter { ingredient in
            let key = normalizedIngredientKey(ingredient.name)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return ingredient.status == .avoid || ingredient.status == .watch
        }
    }

    private func normalizedIngredientKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private func displayRank(_ status: IngredientStatus) -> Int {
        switch status {
        case .avoid: return 0
        case .watch: return 1
        case .clean: return 2
        case .neutral, .insufficientData: return 3
        }
    }

    private var evidenceReason: String {
        if audit.finalStatus == .insufficientData {
            return viewModel.appLanguage == .german ? "Zutatenliste fehlt oder ist nicht gut lesbar." : "Ingredient list missing or not readable."
        }
        if let firstFlag = flaggedForExplanation.first {
            let reason = IngredientCopyFormatter.reason(firstFlag, language: viewModel.appLanguage)
            return "\(IngredientCopyFormatter.ingredientLabel(firstFlag, language: viewModel.appLanguage)): \(reason)"
        }
        return viewModel.appLanguage == .german ? "Keine offensichtliche Auffälligkeit in der verfügbaren Zutatenliste gefunden." : "No flagged ingredient concern found in the available list."
    }

    private var localizedSource: String {
        guard viewModel.appLanguage == .german else { return audit.source }
        return audit.source
            .replacingOccurrences(of: "Open product data", with: "Offene Produktdaten")
            .replacingOccurrences(of: "structured", with: "strukturiert")
            .replacingOccurrences(of: "extractedFromText", with: "aus Text erkannt")
            .replacingOccurrences(of: "unusableData", with: "Zutaten unklar")
            .replacingOccurrences(of: "Manual ingredient text", with: "Manuell eingefügte Zutaten")
            .replacingOccurrences(of: "Local German product data", with: "Lokale deutsche Produktdaten")
    }

    private var localizedSourceStatus: String {
        guard viewModel.appLanguage == .german else { return audit.sourceStatus.title }
        switch audit.sourceStatus {
        case .ingriaReviewed: return "INGRIA geprüft"
        case .userSubmitted: return "Nutzerbeitrag"
        case .openFoodFacts: return "Open Food Facts Quelle"
        case .openBeautyFacts: return "Open Beauty Facts Quelle"
        case .manualEntry: return "Manuelle Eingabe"
        case .pendingReview: return "Ausstehende Prüfung"
        case .localSeed: return "Lokale INGRIA Startdaten"
        }
    }

    private var localizedReviewStatus: String {
        guard viewModel.appLanguage == .german else { return audit.reviewStatus.title }
        switch audit.reviewStatus {
        case .approved, .adminReviewed: return "INGRIA geprüft"
        case .pending: return "Prüfung ausstehend"
        case .missingIngredients: return "Zutatendaten nötig"
        case .unverifiedSourceData: return "Quelldaten können unvollständig sein"
        case .userSubmitted: return "Nutzerbeitrag"
        }
    }

    private var alternativeTitle: String {
        switch viewModel.activeAlternativeState {
        case .productMatches:
            return viewModel.appLanguage == .german ? "Cleaner alternative found." : "Cleaner alternative found."
        case .ingredientGuidance:
            return viewModel.appLanguage == .german ? "No exact product match yet. INGRIA found cleaner ingredient guidance." : "No exact product match yet. INGRIA found cleaner ingredient guidance."
        case .none:
            return viewModel.appLanguage == .german ? "No clean alternative found yet. We’ll keep improving the database." : "No clean alternative found yet. We’ll keep improving the database."
        }
    }

    private var localizedCategory: String {
        guard viewModel.appLanguage == .german else { return audit.productCategory }
        if audit.productCategory.lowercased().contains("beauty") { return "Kosmetik / Körperpflege" }
        return "Lebensmittel"
    }

    private var checkedDate: String {
        audit.checkedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var pageBackground: Color {
        audit.finalStatus == .avoid ? Color(hex: "FFF7F6") : IngriaTheme.background
    }

    private var productContextLine: String {
        let category = localizedCategory
        let brand = audit.brand.isEmpty ? (viewModel.appLanguage == .german ? "Unbekannte Marke" : "Unknown brand") : audit.brand
        return viewModel.appLanguage == .german ? "\(category) von \(brand)" : "\(category) by \(brand)"
    }

    private var heroForeground: Color {
        audit.finalStatus == .avoid ? .white : IngriaTheme.green900
    }

    private var heroBackground: LinearGradient {
        let colors: [Color]
        switch audit.finalStatus {
        case .avoid:
            colors = [Color(hex: "D90F16"), IngriaTheme.avoid, Color(hex: "FFD6D8")]
        case .watch:
            colors = [Color(hex: "F2B95B"), Color(hex: "FFE8B3"), IngriaTheme.background]
        case .clean:
            colors = [Color(hex: "DCE8DE"), Color(hex: "EEF6EF"), IngriaTheme.background]
        case .insufficientData, .neutral:
            colors = [Color(hex: "ECE8E2"), Color(hex: "F7F6F2"), IngriaTheme.background]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var whyCardBackground: Color {
        audit.finalStatus == .avoid ? IngriaTheme.avoidSoft.opacity(0.65) : IngriaTheme.surface
    }

    private var verdictTitle: String {
        switch audit.finalStatus {
        case .avoid: return "AVOID"
        case .watch: return "REVIEW"
        case .clean: return "CLEAN"
        case .insufficientData, .neutral: return "INGREDIENTS NEEDED"
        }
    }

    private var primaryActionTitle: String {
        audit.finalStatus == .insufficientData ? "Upload label for review" : "Report data issue"
    }

    private func topButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 20)
                .fill(IngriaTheme.surface)
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: system)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(IngriaTheme.green900)
                )
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(IngriaTheme.border, lineWidth: 1))
        }
    }

    private func compactTopButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(audit.finalStatus == .avoid ? IngriaTheme.avoid : IngriaTheme.green900)
                .frame(width: 42, height: 42)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func scanTopButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image("ScanIconForest")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .frame(width: 58, height: 58)
                .background(IngriaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(IngriaTheme.border, lineWidth: 1))
        }
    }

    private func statusColor(_ status: IngredientStatus) -> Color {
        switch status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return IngriaTheme.clean
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

    private func statusBackground(_ status: IngredientStatus) -> Color {
        switch status {
        case .avoid: return IngriaTheme.avoidSoft
        case .watch: return IngriaTheme.watchSoft
        case .clean: return IngriaTheme.cleanSoft
        case .insufficientData, .neutral: return IngriaTheme.surface
        }
    }
}

private struct StatusScanLogo: View {
    let status: IngredientStatus
    let size: CGFloat

    var body: some View {
        Image("ScanIconWhite")
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.56, height: size * 0.56)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
            .shadow(color: background.opacity(0.18), radius: 10, y: 5)
    }

    private var background: Color {
        switch status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return Color(hex: "1B4332")
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }
}

private struct GradeBadge: View {
    let status: IngredientStatus

    var body: some View {
        Text(grade)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 28, height: 28)
            .background(background)
            .clipShape(Circle())
    }

    private var grade: String {
        switch status {
        case .clean: return "A"
        case .watch: return "B"
        case .insufficientData, .neutral: return "C"
        case .avoid: return "D"
        }
    }

    private var background: Color {
        switch status {
        case .clean: return Color(hex: "D6EAE0")
        case .watch: return Color(hex: "E7F0C6")
        case .insufficientData, .neutral: return Color(hex: "FFF0CC")
        case .avoid: return Color(hex: "FFE0DC")
        }
    }

    private var foreground: Color {
        switch status {
        case .clean: return Color(hex: "1B4332")
        case .watch: return Color(hex: "566B23")
        case .insufficientData, .neutral: return Color(hex: "8A5A18")
        case .avoid: return IngriaTheme.avoid
        }
    }
}

private struct FlexiblePillRow<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

private struct FlaggedIngredientPill: View {
    let ingredient: AuditedIngredient
    var language: AppLanguage = .englishUK

    var body: some View {
        Text(IngredientCopyFormatter.ingredientLabel(ingredient, language: language))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 0.6))
    }

    private var tint: Color {
        switch ingredient.status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return Color(hex: "1B4332")
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

    private var background: Color {
        switch ingredient.status {
        case .avoid: return Color(hex: "FFF4F3")
        case .watch: return Color(hex: "FFFBF0")
        case .clean: return Color(hex: "F3FBF7")
        case .insufficientData, .neutral: return Color(hex: "F4F1EB")
        }
    }

    private var border: Color {
        switch ingredient.status {
        case .avoid: return Color(hex: "FFD5D0")
        case .watch: return Color(hex: "FFE8A0")
        case .clean: return Color(hex: "C0DDB0")
        case .insufficientData, .neutral: return Color(hex: "DDD9D2")
        }
    }
}

private struct EvidenceRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(IngriaTheme.secondaryText)
                .frame(width: 112, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IngriaTheme.ink.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct ProductAlternativeRow: View {
    let alternative: ProductAlternative

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(alternative.alternativeProductName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(IngriaTheme.ink)
                        .lineLimit(2)
                    Text(alternative.alternativeBrand.isEmpty ? "Unknown brand" : alternative.alternativeBrand)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IngriaTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                SeverityBadge(status: alternative.alternativeResult)
            }

            Text(alternative.reason)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IngriaTheme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Text(storeCopy)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IngriaTheme.green700)
        }
        .padding(12)
        .background(Color(hex: "F3FBF7"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "C0DDB0"), lineWidth: 0.8))
    }

    private var storeCopy: String {
        alternative.store.isEmpty ? "Availability not confirmed" : "May be available at \(alternative.store)"
    }
}

private struct IngredientAlternativeRow: View {
    let alternative: IngredientAlternative

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(alternative.flaggedIngredient.isEmpty ? alternative.issueType : alternative.flaggedIngredient)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(IngriaTheme.avoid)
                    .lineLimit(1)
                Spacer()
                Text(alternative.evidenceLevel.isEmpty ? "Guidance" : alternative.evidenceLevel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IngriaTheme.green700)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "D6EAE0"))
                    .clipShape(Capsule())
            }

            Text(alternative.cleanerAlternative)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(IngriaTheme.ink)

            if !alternative.explanation.isEmpty {
                Text(alternative.explanation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IngriaTheme.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !alternative.recommendedSearchTerms.isEmpty {
                Text("Search: \(alternative.recommendedSearchTerms.prefix(4).joined(separator: ", "))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IngriaTheme.green700)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(hex: "FFFBF0"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "FFE8A0"), lineWidth: 0.8))
    }
}

private struct FlaggedReasonCard: View {
    let ingredient: AuditedIngredient
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)

                Text(IngredientCopyFormatter.ingredientLabel(ingredient, language: language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)

                Spacer()

                SeverityBadge(status: ingredient.status, language: language)
            }

            Text(IngredientCopyFormatter.reason(ingredient, language: language))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(IngriaTheme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 0.8))
    }

    private var tint: Color {
        switch ingredient.status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return IngriaTheme.clean
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

    private var nameColor: Color {
        ingredient.status == .avoid ? IngriaTheme.avoid : IngriaTheme.ink
    }

    private var background: Color {
        switch ingredient.status {
        case .avoid: return Color(hex: "FFF4F3")
        case .watch: return Color(hex: "FFFBF0")
        case .clean: return Color(hex: "F3FBF7")
        case .insufficientData, .neutral: return Color(hex: "F4F1EB")
        }
    }

    private var border: Color {
        switch ingredient.status {
        case .avoid: return Color(hex: "FFD5D0")
        case .watch: return Color(hex: "FFE8A0")
        case .clean: return Color(hex: "C0DDB0")
        case .insufficientData, .neutral: return Color(hex: "DDD9D2")
        }
    }
}

private struct SeverityBadge: View {
    let status: IngredientStatus
    var language: AppLanguage = .englishUK

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }

    private var title: String {
        switch status {
        case .avoid: return language == .german ? "MEIDEN" : "AVOID"
        case .watch: return language == .german ? "PRÜFEN" : "REVIEW"
        case .clean: return language == .german ? "SAUBER" : "CLEAN"
        case .insufficientData, .neutral: return language == .german ? "UNKLAR" : "UNKNOWN"
        }
    }

    private var tint: Color {
        switch status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return Color(hex: "1B4332")
        case .insufficientData, .neutral: return IngriaTheme.secondaryText
        }
    }

    private var background: Color {
        switch status {
        case .avoid: return Color(hex: "FFE0DC")
        case .watch: return Color(hex: "FFF0CC")
        case .clean: return Color(hex: "D6EAE0")
        case .insufficientData, .neutral: return Color(hex: "ECE8E2")
        }
    }
}

private struct IngredientInlineText: View {
    let items: [DisplayIngredient]
    let language: AppLanguage

    var body: some View {
        Text(attributedIngredients)
            .font(.system(size: fontSize, weight: .medium))
            .lineSpacing(items.count > 14 ? 2 : 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedIngredients: AttributedString {
        var output = AttributedString()

        for (index, item) in items.enumerated() {
            let label = IngredientCopyFormatter.ingredientLabel(item.label, language: language)
            guard !label.isEmpty else { continue }

            var ingredient = AttributedString(label)
            ingredient.foregroundColor = foreground(for: item.status)
            ingredient.backgroundColor = background(for: item.status)
            ingredient.font = .system(size: fontSize, weight: fontWeight(for: item.status))
            output += ingredient

            if index < items.count - 1 {
                var separator = AttributedString(", ")
                separator.foregroundColor = IngriaTheme.secondaryText.opacity(0.65)
                separator.font = .system(size: fontSize, weight: .medium)
                output += separator
            }
        }

        return output
    }

    private var fontSize: CGFloat {
        items.count > 18 ? 13 : (items.count > 10 ? 14 : 16)
    }

    private func foreground(for status: IngredientStatus) -> Color {
        switch status {
        case .avoid: return IngriaTheme.avoid
        case .watch: return IngriaTheme.watch
        case .clean: return Color(hex: "1B4332").opacity(0.92)
        case .neutral, .insufficientData: return IngriaTheme.ink.opacity(0.78)
        }
    }

    private func background(for status: IngredientStatus) -> Color? {
        switch status {
        case .avoid: return Color(hex: "FFE0DC").opacity(0.72)
        case .watch: return Color(hex: "FFF0CC").opacity(0.8)
        default: return nil
        }
    }

    private func fontWeight(for status: IngredientStatus) -> Font.Weight {
        switch status {
        case .avoid, .watch: return .semibold
        default: return .medium
        }
    }
}

private enum ResultImagePurpose {
    case ingredients
    case front
}

private enum ResultImagePickerMode: String, Identifiable {
    case cameraIngredients
    case cameraFront
    case libraryIngredients

    var id: String { rawValue }

    var sourceType: UIImagePickerController.SourceType {
        switch self {
        case .cameraIngredients, .cameraFront:
            return .camera
        case .libraryIngredients:
            return .photoLibrary
        }
    }

    var purpose: ResultImagePurpose {
        switch self {
        case .cameraIngredients, .libraryIngredients:
            return .ingredients
        case .cameraFront:
            return .front
        }
    }
}
