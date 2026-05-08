import SwiftUI

struct AdminApprovalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AdminReviewItem] = []
    @State private var selectedItem: AdminReviewItem?
    @State private var isLoading = false
    @State private var errorMessage = ""

    private let repository = SupabaseManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                IngriaTheme.background.ignoresSafeArea()

                if isLoading && items.isEmpty {
                    ProgressView("Loading review queue…")
                } else if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(items) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    AdminReviewRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                    .refreshable {
                        await loadItems()
                    }
                }
            }
            .navigationTitle("Admin Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadItems() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IngriaTheme.avoid)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                }
            }
            .task {
                await loadItems()
            }
            .sheet(item: $selectedItem) { item in
                AdminReviewEditorView(item: item) {
                    selectedItem = nil
                    await loadItems()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ScanAppIcon(size: 54, filled: true)
            Text("No pending products")
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color(hex: "1B4332"))
            Text("New missing or incomplete scans will appear here from Supabase missing submissions.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IngriaTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
    }

    @MainActor
    private func loadItems() async {
        isLoading = true
        errorMessage = ""
        do {
            items = try await repository.pendingAdminReviewItems()
        } catch {
            errorMessage = "Could not load review queue: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

private struct AdminReviewRow: View {
    let item: AdminReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if item.frontImageURL != nil || item.ingredientsImageURL != nil {
                    AdminImageThumbnail(url: item.frontImageURL ?? item.ingredientsImageURL)
                } else {
                    StatusScanLogoSmall(status: item.resultStatus)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(IngriaTheme.ink)
                        .lineLimit(2)

                    Text(item.brand)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IngriaTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.resultStatus.firestoreAdminTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(statusBackground)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                AdminMetaPill(text: item.barcode.isEmpty ? "No barcode" : item.barcode)
                AdminMetaPill(text: item.category)
                AdminMetaPill(text: item.adminReviewStatus)
                if item.frontImageURL != nil || item.ingredientsImageURL != nil {
                    AdminMetaPill(text: "photo")
                }
            }

            if !item.ingredientsText.isEmpty {
                Text(item.ingredientsText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(IngriaTheme.border, lineWidth: 0.7))
    }

    private var statusColor: Color {
        switch item.resultStatus {
        case .avoid: return IngriaTheme.avoid
        case .watch, .neutral, .insufficientData: return IngriaTheme.watch
        case .clean: return IngriaTheme.clean
        }
    }

    private var statusBackground: Color {
        switch item.resultStatus {
        case .avoid: return IngriaTheme.avoidSoft
        case .watch, .neutral, .insufficientData: return IngriaTheme.watchSoft
        case .clean: return IngriaTheme.cleanSoft
        }
    }
}

private struct AdminReviewEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AdminReviewItem
    @State private var isSaving = false
    @State private var message = ""

    let onFinished: () async -> Void
    private let repository = SupabaseManager.shared

    init(item: AdminReviewItem, onFinished: @escaping () async -> Void) {
        _draft = State(initialValue: item)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if draft.frontImageURL != nil || draft.ingredientsImageURL != nil {
                        HStack(spacing: 12) {
                            AdminReviewImagePreview(title: "Front", url: draft.frontImageURL)
                            AdminReviewImagePreview(title: "Ingredients", url: draft.ingredientsImageURL)
                        }
                    }

                    adminTextField("Barcode", text: $draft.barcode)
                        .keyboardType(.numberPad)
                    adminTextField("Product name", text: $draft.productName)
                    adminTextField("Brand", text: $draft.brand)
                    adminTextField("Category", text: $draft.category)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Result")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(IngriaTheme.secondaryText)
                        Picker("Result", selection: $draft.resultStatus) {
                            Text("CLEAN").tag(IngredientStatus.clean)
                            Text("REVIEW").tag(IngredientStatus.watch)
                            Text("AVOID").tag(IngredientStatus.avoid)
                            Text("INGREDIENT DATA NEEDED").tag(IngredientStatus.insufficientData)
                        }
                        .pickerStyle(.segmented)
                    }

                    adminEditor("Ingredient text", text: $draft.ingredientsText, minHeight: 145)
                    if !draft.cleanedIngredientsText.isEmpty {
                        adminEditor("Cleaned ingredient text", text: $draft.cleanedIngredientsText, minHeight: 100)
                    }
                    if !draft.flaggedIngredientNames.isEmpty {
                        Text("Auto flagged: \(draft.flaggedIngredientNames.joined(separator: ", "))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(IngriaTheme.avoid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    adminEditor("Summary", text: $draft.summaryLine, minHeight: 84)
                    adminEditor("Notes", text: $draft.notes, minHeight: 84)

                    VStack(spacing: 10) {
                        Button {
                            Task { await save(.approve) }
                        } label: {
                            adminActionLabel("Approve", color: Color(hex: "1B4332"), foreground: .white)
                        }
                        .disabled(isSaving || draft.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        HStack(spacing: 10) {
                            Button {
                                Task { await save(.needsIngredients) }
                            } label: {
                                adminActionLabel("Needs Ingredient Data", color: IngriaTheme.watchSoft, foreground: IngriaTheme.watch)
                            }
                            .disabled(isSaving)

                            Button {
                                Task { await save(.reject) }
                            } label: {
                                adminActionLabel("Reject", color: IngriaTheme.avoidSoft, foreground: IngriaTheme.avoid)
                            }
                            .disabled(isSaving)
                        }
                    }
                    .padding(.top, 4)

                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(message.contains("Failed") ? IngriaTheme.avoid : IngriaTheme.green700)
                    }
                }
                .padding(20)
                .padding(.bottom, 34)
            }
            .background(IngriaTheme.background.ignoresSafeArea())
            .navigationTitle("Review product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private enum Action {
        case approve
        case reject
        case needsIngredients
    }

    @MainActor
    private func save(_ action: Action) async {
        isSaving = true
        message = ""
        do {
            switch action {
            case .approve:
                try await repository.approveAdminReviewItem(draft)
                message = "Approved and saved to products/\(draft.barcode)."
            case .reject:
                try await repository.rejectAdminReviewItem(draft)
                message = "Rejected."
            case .needsIngredients:
                try await repository.markAdminReviewNeedsIngredientData(draft)
                message = "Marked as needing ingredient data."
            }
            await onFinished()
            dismiss()
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
        isSaving = false
    }

    private func adminTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(IngriaTheme.secondaryText)
            TextField(title, text: text)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(IngriaTheme.border, lineWidth: 0.8))
        }
    }

    private func adminEditor(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(IngriaTheme.secondaryText)
            TextEditor(text: text)
                .font(.system(size: 14, weight: .medium))
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(IngriaTheme.border, lineWidth: 0.8))
        }
    }

    private func adminActionLabel(_ title: String, color: Color, foreground: Color) -> some View {
        Text(isSaving ? "Saving…" : title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AdminMetaPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "1B4332"))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: "D6EAE0"))
            .clipShape(Capsule())
    }
}

private struct AdminImageThumbnail: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(IngriaTheme.surface)
            .frame(width: 46, height: 46)
            .overlay(
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(IngriaTheme.secondaryText)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(IngriaTheme.border, lineWidth: 0.8))
    }
}

private struct AdminReviewImagePreview: View {
    let title: String
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(IngriaTheme.secondaryText)

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .frame(height: 150)
                .overlay(
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } placeholder: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                            Text("No image")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(IngriaTheme.secondaryText)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(IngriaTheme.border, lineWidth: 0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatusScanLogoSmall: View {
    let status: IngredientStatus

    var body: some View {
        Image("ScanIconWhite")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .frame(width: 38, height: 38)
            .background(background)
            .clipShape(Circle())
    }

    private var background: Color {
        switch status {
        case .avoid: return IngriaTheme.avoid
        case .watch, .neutral, .insufficientData: return IngriaTheme.watch
        case .clean: return Color(hex: "1B4332")
        }
    }
}

private extension IngredientStatus {
    var firestoreAdminTitle: String {
        switch self {
        case .avoid: return "AVOID"
        case .watch, .neutral: return "REVIEW"
        case .clean: return "CLEAN"
        case .insufficientData: return "DATA NEEDED"
        }
    }
}
