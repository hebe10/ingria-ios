import SwiftUI

enum IngriaLegalCopy {
    static func firstUse(language: AppLanguage) -> String {
        switch language {
        case .german:
            return "INGRIA bietet Zutaten-Screening nur zu Informationszwecken. Ergebnisse sind keine rechtliche, medizinische oder regulatorische Beratung."
        case .englishUK:
            return "INGRIA provides ingredient screening for informational purposes only. Results are not legal, medical, or regulatory advice."
        }
    }

    static func result(language: AppLanguage) -> String {
        switch language {
        case .german:
            return "Ergebnisse basieren auf verfügbaren Zutaten- und Produktdaten. INGRIA ist ein informatives Screening und keine rechtliche, medizinische oder regulatorische Beratung."
        case .englishUK:
            return "Results are based on available ingredient and product data. INGRIA is informational screening only and not legal, medical, or regulatory advice."
        }
    }

    static func publicData(language: AppLanguage) -> String {
        switch language {
        case .german:
            return "Produktdaten können unvollständig, veraltet oder nutzerbasiert sein. Prüfe immer das physische Produktetikett."
        case .englishUK:
            return "Product data may be incomplete, outdated, or user-submitted. Always check the product label."
        }
    }
}

enum IngredientCopyFormatter {
    static func ingredientLabel(_ ingredient: AuditedIngredient, language: AppLanguage) -> String {
        switch language {
        case .german:
            return ingredient.nameDE.map { ingredientLabel($0, language: language) }
                ?? ingredientLabel(ingredient.name, language: language)
        case .englishUK:
            return ingredient.nameEN.map { ingredientLabel($0, language: language) }
                ?? ingredientLabel(ingredient.name, language: language)
        }
    }

    static func reason(_ ingredient: AuditedIngredient, language: AppLanguage) -> String {
        switch language {
        case .german:
            if let reason = ingredient.reasonDE, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanGerman(reason)
            }
            return germanReason(for: ingredient.reason, ingredientName: ingredient.nameDE ?? ingredient.name, status: ingredient.status)
        case .englishUK:
            if let reason = ingredient.reasonEN, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanEnglish(reason)
            }
            return cleanEnglish(ingredient.reason)
        }
    }

    static func ingredientLabel(_ value: String, language: AppLanguage) -> String {
        let cleaned = cleanInlineIngredient(value)
        guard language == .german else { return cleaned }

        let key = normalized(cleaned)
        let replacements: [(String, String)] = [
            ("skimmed milk powder", "Magermilchpulver"),
            ("skim milk powder", "Magermilchpulver"),
            ("milk powder", "Milchpulver"),
            ("palm kernel oil", "Palmkernöl"),
            ("palm oil", "Palmöl"),
            ("cane sugar", "Rohrzucker"),
            ("glucose syrup", "Glukosesirup"),
            ("glucose fructose syrup", "Glukose-Fruktose-Sirup"),
            ("high fructose corn syrup", "Glukose-Fruktose-Sirup"),
            ("invert sugar syrup", "Invertzuckersirup"),
            ("maltodextrin", "Maltodextrin"),
            ("dextrose", "Dextrose"),
            ("sugar", "Zucker"),
            ("hazelnuts", "Haselnüsse"),
            ("hazelnut", "Haselnuss"),
            ("cocoa butter", "Kakaobutter"),
            ("cocoa mass", "Kakaomasse"),
            ("lean cocoa", "Magerkakao"),
            ("cocoa", "Kakao"),
            ("whey products", "Molkenerzeugnisse"),
            ("whey powder", "Molkenpulver"),
            ("milk fat", "Milchfett"),
            ("emulsifiers", "Emulgatoren"),
            ("emulsifier", "Emulgator"),
            ("lecithins", "Lecithine"),
            ("lecithin", "Lecithin"),
            ("soy lecithin", "Sojalecithin"),
            ("soya lecithin", "Sojalecithin"),
            ("sunflower lecithin", "Sonnenblumenlecithin"),
            ("flavourings", "Aromen"),
            ("flavorings", "Aromen"),
            ("flavouring", "Aroma"),
            ("flavoring", "Aroma"),
            ("natural flavour", "Natürliches Aroma"),
            ("natural flavor", "Natürliches Aroma"),
            ("artificial flavor", "Künstliches Aroma"),
            ("vanillin", "Vanillin"),
            ("salt", "Salz"),
            ("almond", "Mandel"),
            ("almonds", "Mandeln"),
            ("wheat", "Weizen")
        ]

        if let exact = replacements.first(where: { key == normalized($0.0) }) {
            return exact.1
        }
        if let contained = replacements.first(where: { key.contains(normalized($0.0)) }) {
            return contained.1
        }
        return cleaned
    }

    static func display(_ value: String, ingredientName: String = "", status: IngredientStatus? = nil, language: AppLanguage) -> String {
        let cleaned = clean(value)
        guard language == .german else { return cleaned }
        return germanReason(for: cleaned, ingredientName: ingredientName, status: status)
    }

    private static func cleanGerman(_ value: String) -> String {
        let cleaned = clean(value)
            .replacingOccurrences(of: #"(?i)\bflag\b"#, with: "markieren", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bavoid\b"#, with: "meiden", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bclean-label\b"#, with: "Clean-Label", options: .regularExpression)
        if containsMostlyEnglish(cleaned) {
            return germanReason(for: cleaned, ingredientName: "", status: nil)
        }
        return cleaned
    }

    private static func cleanEnglish(_ value: String) -> String {
        var cleaned = clean(value)
            .replacingOccurrences(of: #"(?i)\bMeiden\b"#, with: "Avoid", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bSauber\b"#, with: "Clean", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bVorsicht\b"#, with: "Review", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bPrüfen\b"#, with: "Review", options: .regularExpression)
        if containsMostlyGerman(cleaned) {
            cleaned = "Ingredient concern based on INGRIA screening criteria."
        }
        return cleaned
    }

    static func clean(_ value: String) -> String {
        var cleaned = value
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? value

        cleaned = cleaned
            .replacingOccurrences(of: #"(?i)\bB[o]bby(?:’s|'s)?(?:-style)?\b"#, with: "INGRIA", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bINGRIA framework\b"#, with: "INGRIA screening criteria", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bofficial INGRIA rules?\b"#, with: "INGRIA screening criteria", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA flags\s+.+?\s+because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA marks\s+.+?\s+as questionable because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^INGRIA treats\s+.+?\s+as clean because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is flagged as an avoid ingredient because\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is flagged as avoid\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^.+?\s+is a questionable ingredient\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bquestionable ingredient\b"#, with: "review trigger", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bbad ingredient\b"#, with: "flagged ingredient", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstrict clean-label standards\b"#, with: "INGRIA screening criteria", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstrict clean-label rules\b"#, with: "INGRIA screening criteria", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bsafety concerns\b"#, with: "ingredient concerns", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\btoxic\b"#, with: "flagged", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bdangerous\b"#, with: "flagged", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bEU banned it in food\b"#, with: "restricted for this use in some EU contexts", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.range(of: #"^[a-z]"#, options: .regularExpression) != nil {
            cleaned.replaceSubrange(cleaned.startIndex...cleaned.startIndex, with: String(cleaned[cleaned.startIndex]).uppercased())
        }
        if !cleaned.isEmpty, !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") && !cleaned.hasSuffix("?") {
            cleaned += "."
        }
        return cleaned
    }

    private static func germanReason(for reason: String, ingredientName: String, status: IngredientStatus?) -> String {
        let name = normalized(ingredientName)
        let text = normalized(reason)

        if text.contains("missing") || text.contains("not readable") || text.contains("unvollstandig") {
            return "Die Zutatenliste fehlt oder ist nicht gut lesbar."
        }
        if name.contains("sugar") || name.contains("zucker") || name.contains("sirup") || name.contains("dextrose") || text.contains("sweetener") || text.contains("sweetness") {
            return "Raffinierter oder konzentrierter Süßungsstoff; vor allem ein Marker für stärker verarbeitete Produkte."
        }
        if name.contains("palm") {
            return "Palmöl oder palm-basiertes Fett; häufig verarbeitet und für Textur, Kosten oder Haltbarkeit eingesetzt."
        }
        if name.contains("rapsol") || name.contains("canola") || name.contains("sunflower oil") || name.contains("sonnenblumenol") || name.contains("soybean oil") || name.contains("corn oil") || text.contains("seed oil") {
            return "Raffiniertes Pflanzen- oder Saatöl; INGRIA markiert es als Hinweis auf eine stärker verarbeitete Rezeptur."
        }
        if name.contains("aroma") || name.contains("flavor") || name.contains("flavour") || name.contains("vanillin") || text.contains("flavor") || text.contains("flavour") {
            return "Aromaangabe mit begrenzter Transparenz; die genaue Zusammensetzung ist für Verbraucher nicht klar erkennbar."
        }
        if name.contains("milchpulver") || name.contains("milk powder") || name.contains("whey") || name.contains("molken") {
            return "Verarbeitetes Milchpulver oder Molkenbestandteil; meist für Textur, Süße oder Volumen eingesetzt."
        }
        if name.contains("lecithin") || name.contains("lecithine") || name.contains("emulsifier") || name.contains("emulgator") || text.contains("emulsifier") {
            return "Emulgator zur Stabilisierung der Textur; ein Hinweis auf eine stärker formulierte Rezeptur."
        }
        if name.contains("gum") || name.contains("gummi") || name.contains("carrageenan") || name.contains("carrageen") || name.contains("guar") || name.contains("xanthan") || text.contains("thickener") || text.contains("stabilizer") {
            return "Verdickungs- oder Stabilisierungsmittel; INGRIA markiert es, wenn die Rezeptur unnötig technisch wirkt."
        }
        if text.contains("artificial sweetener") || name.contains("acesulfame") || name.contains("aspartame") || name.contains("sucralose") || name.contains("saccharin") {
            return "Künstlicher Süßstoff; häufig in stark formulierten Light- oder Zero-Produkten eingesetzt."
        }
        if text.contains("synthetic color") || text.contains("color added") || text.contains("colour") || name.contains("red ") || name.contains("yellow ") || name.contains("blue ") || name.contains("violet") {
            return "Synthetischer Farbstoff; dient der Optik und verbessert die Zutatenqualität nicht."
        }
        if text.contains("preservative") || name.contains("nitrite") || name.contains("bha") || name.contains("bht") || name.contains("tbhq") {
            return "Konservierungsstoff oder Verarbeitungshilfe; von INGRIA als Prüfpunkt für stärker formulierte Produkte markiert."
        }
        if text.contains("no obvious concern") {
            return "Keine offensichtliche Auffälligkeit in den verfügbaren Zutatendaten gefunden."
        }

        switch status {
        case .avoid:
            return "Nach INGRIA-Kriterien ein deutlicher Prüfpunkt in der Zutatenliste."
        case .watch:
            return "Kontextabhängige Zutat; Quelle, Menge und Produktart sollten geprüft werden."
        case .clean:
            return "In normaler Verwendung kein offensichtlicher Prüfpunkt nach INGRIA-Kriterien."
        case .insufficientData, .neutral:
            return "Für diese Zutat liegen nicht genug klare Informationen vor."
        case .none:
            return reason
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func containsMostlyEnglish(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let hits = ["because", "sweetness", "flavor", "colour", "color", "processed", "used for", "without real sugar", "ingredient"].filter { lowered.contains($0) }.count
        return hits >= 2
    }

    private static func containsMostlyGerman(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let hits = ["weil", "zutat", "süß", "für", "häufig", "verarbeitet", "meiden", "sauber", "prüfen"].filter { lowered.contains($0) }.count
        return hits >= 2
    }

    private static func cleanInlineIngredient(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)\bingredients?\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bzutaten\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bmay contain\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bkann enthalten\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bcontains?\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bmilk chocolate contains\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"&quot;|\""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[_]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,;:.])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,;:.])\s*"#, with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;")))
    }
}

struct IngriaBrandLockup: View {
    var body: some View {
        HStack(spacing: 12) {
            ScanAppIcon(size: 52, filled: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("INGRIA")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .tracking(2.8)
                    .foregroundStyle(IngriaTheme.green900)
                Text("STANDARD")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.6)
                    .foregroundStyle(IngriaTheme.green700)
            }
        }
    }
}

struct FirstUseDisclaimerSheet: View {
    var language: AppLanguage = .german
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScanAppIcon(size: 58, filled: true)

            VStack(alignment: .leading, spacing: 10) {
                Text(language == .german ? "Kein Kompromiss. Nur Klarheit." : "No compromise. Just clarity.")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(IngriaTheme.green900)

                Text(language == .german ? "Strenge Zutatenprüfung für Lebensmittel und Körperpflege, damit du Etiketten schneller einschätzen kannst." : "Strict ingredient screening for food and personal care, with results designed to help you review labels faster.")
                    .font(.system(size: 16, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(IngriaTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 12) {
                disclaimerRow(title: language == .german ? "Informations-Screening" : "Informational screening", text: IngriaLegalCopy.firstUse(language: language))
                disclaimerRow(title: language == .german ? "Verfügbare Daten" : "Available data", text: IngriaLegalCopy.publicData(language: language))
                resultLanguageRow()
            }

            Spacer(minLength: 8)

            Button(action: onContinue) {
                Text(language == .german ? "Weiter" : "Continue")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(IngriaTheme.green900)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IngriaTheme.background)
    }

    private func disclaimerRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(IngriaTheme.green700)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IngriaTheme.ink.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IngriaTheme.border, lineWidth: 0.6))
    }

    private func resultLanguageRow() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language == .german ? "ERGEBNIS-SPRACHE" : "RESULT LANGUAGE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(IngriaTheme.green700)

            HStack(spacing: 8) {
                verdictWord(language == .german ? "Sauber" : "Clean", color: IngriaTheme.clean, background: IngriaTheme.cleanSoft)
                verdictWord(language == .german ? "Prüfen" : "Review", color: IngriaTheme.watch, background: IngriaTheme.watchSoft)
                verdictWord(language == .german ? "Meiden" : "Avoid", color: IngriaTheme.avoid, background: IngriaTheme.avoidSoft)
            }

            Text(language == .german ? "basieren auf INGRIA-Prüfkriterien, nicht auf einer Zertifizierung." : "reflect INGRIA screening criteria, not a certification.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IngriaTheme.ink.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IngriaTheme.border, lineWidth: 0.6))
    }

    private func verdictWord(_ text: String, color: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(Capsule())
    }
}

struct ScanAppIcon: View {
    let size: CGFloat
    var filled = false

    var body: some View {
        Image(filled ? "ScanButtonForest" : "ScanIconForest")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(filled ? 0.08 : 0.04), radius: 10, y: 5)
    }
}

struct IngriaSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(IngriaTheme.secondaryText)
            TextField(placeholder, text: $text)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(IngriaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(IngriaTheme.border, lineWidth: 1)
        )
    }
}

struct IngriaCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(IngriaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(IngriaTheme.border, lineWidth: 1)
            )
    }
}

struct IngriaTabBar: View {
    @EnvironmentObject private var viewModel: IngriaViewModel

    var body: some View {
        HStack {
            tabButton(.home, title: tabTitle(.home), systemName: "house")
            Spacer()
            tabButton(.search, title: tabTitle(.search), systemName: "magnifyingglass")
            Spacer()
            Button {
                viewModel.activeAudit = nil
                viewModel.selectedTab = .scan
                viewModel.scanStateText = "Ready to scan the next product."
            } label: {
                Image("ScanButtonForest")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .shadow(color: IngriaTheme.green900.opacity(0.14), radius: 12, y: 6)
            }
            .offset(y: -12)
            Spacer()
            tabButton(.ingredients, title: tabTitle(.ingredients), systemName: "sparkles")
            Spacer()
            tabButton(.lists, title: tabTitle(.lists), systemName: "list.bullet")
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
        .padding(.bottom, -2)
        .frame(maxWidth: .infinity)
        .background(
            tabBarBackground
                .shadow(color: Color.black.opacity(viewModel.selectedTab == .scan ? 0 : 0.08), radius: 22, y: -8)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func tabButton(_ tab: IngriaTab, title: String, systemName: String) -> some View {
        Button {
            viewModel.activeAudit = nil
            viewModel.selectedTab = tab
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tabForeground(tab))
        }
    }

    private var tabBarBackground: Color {
        viewModel.selectedTab == .scan ? Color(hex: "0A0A0A") : IngriaTheme.surface
    }

    private func tabForeground(_ tab: IngriaTab) -> Color {
        if viewModel.selectedTab == .scan {
            return tab == .scan ? Color(hex: "5DCB99") : Color(hex: "555555")
        }
        return viewModel.selectedTab == tab ? IngriaTheme.green900 : IngriaTheme.secondaryText
    }

    private func tabTitle(_ tab: IngriaTab) -> String {
        guard viewModel.appLanguage == .german else {
            switch tab {
            case .home: return "Home"
            case .search: return "Search"
            case .scan: return "Scan"
            case .ingredients: return "Ingredients"
            case .lists: return "Lists"
            }
        }

        switch tab {
        case .home: return "Home"
        case .search: return "Suche"
        case .scan: return "Scan"
        case .ingredients: return "Zutaten"
        case .lists: return "Listen"
        }
    }
}
