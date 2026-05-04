import SwiftUI

struct ScanView: View {
    @EnvironmentObject private var viewModel: IngriaViewModel
    @State private var lastScannedBarcode: String?
    @State private var showsIngredientPaste = false
    @State private var torchOn = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            BarcodeScannerCameraView(
                torchOn: $torchOn,
                onCodeScanned: handleScannedBarcode,
                onStateChange: { state in
                    DispatchQueue.main.async {
                        viewModel.scanStateText = state
                    }
                }
            )
            .ignoresSafeArea()

            // Keep one consistent camera exposure. The scanner reads the full camera
            // feed for reliability, so we avoid a fake bright cutout that can drift
            // away from the visible barcode frame on different iPhone sizes.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                scannerHeader
                Spacer()
                scannerFrame
                Spacer()
                manualBarcodeFallback
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 150)
        }
        .background(Color(hex: "0A0A0A"))
        .onAppear {
            Task { @MainActor in
                viewModel.scanStateText = viewModel.appLanguage == .german ? "Kamera startet..." : "Starting camera..."
            }
        }
        .sheet(isPresented: $showsIngredientPaste) {
            ingredientPasteSheet
        }
    }

    private var scannerHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Scan.")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                Text(viewModel.appLanguage == .german ? "Barcode in den Rahmen halten" : "Point at any barcode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "5DCB99"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                torchOn.toggle()
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "1B4332"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var scannerFrame: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 390)
            let height: CGFloat = 224
            let bracketWidth = min(width - 92, 286)

            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.white.opacity(0.42), lineWidth: 1)
                    )

                ScannerCorners()
                    .stroke(.white.opacity(0.96), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: bracketWidth, height: 136)

                Rectangle()
                    .fill(Color(hex: "5DCB99").opacity(0.86))
                    .frame(width: bracketWidth - 26, height: 2)
                    .shadow(color: Color(hex: "5DCB99").opacity(0.45), radius: 6, x: 0, y: 0)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 224)
    }

    private var manualBarcodeFallback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.appLanguage == .german ? "Keine Kamera? Manuell eingeben" : "No camera? Enter manually")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.7)
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: "5DCB99").opacity(0.86))

            HStack(spacing: 10) {
                TextField(viewModel.appLanguage == .german ? "Barcode eingeben" : "Enter barcode", text: $viewModel.scanBarcode)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
                    .tint(Color(hex: "5DCB99"))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color(hex: "1A1A1A"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "333333"), lineWidth: 1))

                Button {
                    Task { await viewModel.submitBarcode() }
                } label: {
                    Text(viewModel.appLanguage == .german ? "Suchen" : "Find")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 78, height: 52)
                        .background(Color(hex: "1B4332"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button {
                showsIngredientPaste = true
            } label: {
                Text(viewModel.appLanguage == .german ? "Zutaten einfügen" : "Paste ingredients")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "5DCB99"))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "333333"), lineWidth: 1))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.44))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "333333"), lineWidth: 1))
    }

    private var ingredientPasteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.appLanguage == .german ? "Zutaten einfügen" : "Paste ingredients")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(Color(hex: "1B4332"))

                Text(viewModel.appLanguage == .german ? "Füge nur die Zutatenliste ein. Lagerung, Zubereitung und Nährwerte werden konservativ herausgefiltert." : "Paste only the ingredient list. Storage, preparation, and nutrition text will be filtered conservatively.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IngriaTheme.secondaryText)

                TextEditor(text: $viewModel.scannedLabelText)
                    .font(.system(size: 16, weight: .medium))
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(IngriaTheme.border, lineWidth: 0.8))

                Button {
                    viewModel.auditLabelText()
                    showsIngredientPaste = false
                } label: {
                    Text(viewModel.appLanguage == .german ? "Zutaten prüfen" : "Screen ingredients")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(hex: "1B4332"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(IngriaTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.appLanguage == .german ? "Schließen" : "Close") {
                        showsIngredientPaste = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func handleScannedBarcode(_ code: String) {
        let normalized = BarcodeValueNormalizer.normalize(code)
        guard normalized != lastScannedBarcode, normalized.count >= 8 else { return }
        lastScannedBarcode = normalized
        viewModel.scanBarcode = normalized
        Task { await viewModel.submitBarcode() }
    }
}

private struct ScannerDimOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let cutoutWidth = min(max(width - 40, 260), width - 32)
            let cutoutHeight: CGFloat = 260
            let cutout = CGRect(
                x: (width - cutoutWidth) / 2,
                y: height * 0.29,
                width: cutoutWidth,
                height: cutoutHeight
            )

            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 32, height: 32))
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
        }
    }
}

private struct ScannerCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 42
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}
