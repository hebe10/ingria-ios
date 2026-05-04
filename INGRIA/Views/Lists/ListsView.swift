import SwiftUI

struct ListsView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    @State private var isCreateSheetVisible = false
    @State private var isManageSheetVisible = false
    @State private var isAdminSheetVisible = false
    @State private var selectedList: SavedListPreview?
    @State private var newListName = ""
    @State private var editListName = ""
    @State private var selectedKind: SavedListKind = .clean
    private let green = Color(hex: "1B4332")
    private let cream = Color(hex: "F4F1EB")
    private let border = Color(hex: "DDD9D2")

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    emptyState
                    defaultListsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 156)
            }
            .scrollIndicators(.visible)
            .background(cream)

            if isCreateSheetVisible {
                createListOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(5)
            }

            if isManageSheetVisible, let selectedList {
                manageListOverlay(selectedList)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(6)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isCreateSheetVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isManageSheetVisible)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.appLanguage == .german ? "Meine Listen." : "My Lists.")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(green)
                Text(viewModel.appLanguage == .german ? "Produkte nach dem Scan speichern." : "Save products after a scan.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    isAdminSheetVisible = true
                } label: {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(green)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(border, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Admin review")

                Button {
                    print("+ pressed")
                    showCreateSheet()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create list")
            }
        }
        .sheet(isPresented: $isAdminSheetVisible) {
            AdminApprovalView()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanAppIcon(size: 48, filled: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.appLanguage == .german ? "Noch keine Produkte gespeichert" : "No saved products yet")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(IngriaTheme.ink)

                Text(viewModel.appLanguage == .german ? "Nach einem Scan kannst du Produkte in einer Gut- oder Meiden-Liste speichern." : "When you scan a product, you’ll be able to save it to a clean list or avoid list.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                print("Create a list pressed")
                showCreateSheet()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                    Text(viewModel.appLanguage == .german ? "Liste erstellen" : "Create a list")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(green)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(border, lineWidth: 0.5))
    }

    private var defaultListsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.appLanguage == .german ? "Standardlisten" : "Default lists")
                .font(.system(size: 15, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(IngriaTheme.ink)

            VStack(spacing: 0) {
                ForEach(Array(listPreviews.enumerated()), id: \.element.id) { index, item in
                    Button {
                        showManageSheet(item)
                    } label: {
                        SavedListRow(item: item)
                    }
                    .buttonStyle(.plain)

                    if index < listPreviews.count - 1 {
                        Divider()
                            .background(border)
                            .padding(.leading, 58)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 0.5))
        }
    }

    private var createListOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { hideCreateSheet() }

            GeometryReader { proxy in
                let maxHeight = proxy.size.height * 0.72
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(viewModel.appLanguage == .german ? "Liste erstellen" : "Create a list")
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(green)

                        TextField(viewModel.appLanguage == .german ? "Listenname" : "List name", text: $newListName)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 0.8))

                        HStack(spacing: 10) {
                            kindButton(.clean)
                            kindButton(.avoid)
                        }

                        Button {
                            let fallback = selectedKind.title
                            viewModel.createSavedList(name: newListName.isEmpty ? fallback : newListName, kind: selectedKind)
                            hideCreateSheet()
                        } label: {
                            Text(viewModel.appLanguage == .german ? "Erstellen" : "Create")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(green)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button(viewModel.appLanguage == .german ? "Abbrechen" : "Cancel") {
                            hideCreateSheet()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IngriaTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: maxHeight)
            }
            .background(cream)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(border, lineWidth: 0.8))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func manageListOverlay(_ item: SavedListPreview) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { hideManageSheet() }

            GeometryReader { proxy in
                let maxHeight = proxy.size.height * 0.78
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(item.foreground)
                                .frame(width: 40, height: 40)
                                .background(item.background)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(viewModel.appLanguage == .german ? "Liste bearbeiten" : "Edit list")
                                    .font(.system(size: 24, weight: .semibold, design: .serif))
                                    .italic()
                                    .foregroundStyle(green)
                                Text(item.isSystemList
                                     ? (viewModel.appLanguage == .german ? "Standardliste" : "Default list")
                                     : (viewModel.appLanguage == .german ? "Eigene Liste" : "Custom list"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(IngriaTheme.secondaryText)
                            }
                        }

                        TextField(viewModel.appLanguage == .german ? "Listenname" : "List name", text: $editListName)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 0.8))

                        HStack(spacing: 10) {
                            kindButton(.clean)
                            kindButton(.avoid)
                        }

                        Button {
                            viewModel.updateSavedList(id: item.id, name: editListName, kind: selectedKind)
                            hideManageSheet()
                        } label: {
                            Text(viewModel.appLanguage == .german ? "Speichern" : "Save changes")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(green)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        if !item.isSystemList {
                            Button(role: .destructive) {
                                viewModel.deleteSavedList(id: item.id)
                                hideManageSheet()
                            } label: {
                                Text(viewModel.appLanguage == .german ? "Liste löschen" : "Delete list")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(IngriaTheme.avoid)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(IngriaTheme.avoidSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(viewModel.appLanguage == .german ? "Abbrechen" : "Cancel") {
                            hideManageSheet()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IngriaTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: maxHeight)
            }
            .background(cream)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(border, lineWidth: 0.8))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func kindButton(_ kind: SavedListKind) -> some View {
        Button {
            selectedKind = kind
        } label: {
            Text(kind.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(green)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(selectedKind == kind ? Color(hex: "D6EAE0") : cream)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(border, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var listPreviews: [SavedListPreview] {
        viewModel.savedLists.map { list in
            SavedListPreview(
                id: list.id,
                title: list.name,
                subtitle: list.kind == .clean
                    ? (viewModel.appLanguage == .german ? "Produkte, die du wieder kaufen würdest." : "Products you would buy again.")
                    : (viewModel.appLanguage == .german ? "Produkte oder Zutaten zum Meiden." : "Products or ingredients to skip."),
                systemName: list.kind == .clean ? "checkmark" : "xmark",
                foreground: list.kind == .clean ? Color(hex: "1B4332") : IngriaTheme.avoid,
                background: list.kind == .clean ? Color(hex: "D6EAE0") : Color(hex: "FFE0DC"),
                count: list.audits.count,
                kind: list.kind,
                isSystemList: list.isSystemList
            )
        }
    }

    private func showCreateSheet() {
        newListName = ""
        selectedKind = .clean
        isCreateSheetVisible = true
    }

    private func hideCreateSheet() {
        isCreateSheetVisible = false
        newListName = ""
    }

    private func showManageSheet(_ item: SavedListPreview) {
        selectedList = item
        editListName = item.title
        selectedKind = item.kind
        isManageSheetVisible = true
    }

    private func hideManageSheet() {
        isManageSheetVisible = false
        selectedList = nil
        editListName = ""
    }
}

private struct SavedListPreview: Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let systemName: String
    let foreground: Color
    let background: Color
    let count: Int
    let kind: SavedListKind
    let isSystemList: Bool
}

private struct SavedListRow: View {
    let item: SavedListPreview

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(item.foreground)
                .frame(width: 44, height: 44)
                .background(item.background)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(IngriaTheme.ink)

                Text(item.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(item.count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "1B4332"))
                .frame(minWidth: 28, minHeight: 24)
                .background(Color(hex: "F4F1EB"))
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "B0ADA6"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
