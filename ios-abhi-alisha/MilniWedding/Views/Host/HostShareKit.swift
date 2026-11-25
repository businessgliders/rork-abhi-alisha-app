import CoreImage.CIFilterBuiltins
import SwiftUI

/// The wedding Photos and Wedding Week timeline, as guests see it, with the host's
/// add and manage controls.
struct HostPhotosView: View {
    var body: some View {
        ScrollView {
            WeddingWeekSection()
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 40)
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .navigationTitle("Wedding Week photos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Everything a host needs to invite people: the card, a QR code, the code and link.
struct HostShareKit: View {
    @Binding var code: String?

    @Environment(\.dismiss) private var dismiss
    @State private var share: HostSharePayload?
    @State private var confirmNewCode = false
    @State private var isRegenerating = false
    @State private var codeFailed = false
    @State private var isLoadingCode = false
    @State private var error: String?

    private let snapshot = WeddingContext.shared.snapshot
    private var weddingID: String { WeddingContext.shared.weddingID }

    private var link: String? { code.map { "https://milniapp.com/j/\($0)" } }
    private var message: String {
        guard let link else { return "" }
        return "Join \(snapshot.coupleNames)'s wedding on Milni: \(link)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    MilniInvitationCard(
                        partnerOne: snapshot.partnerOne,
                        partnerTwo: snapshot.partnerTwo,
                        detail: snapshot.cityAndDates,
                        preset: snapshot.preset
                    )
                    .frame(width: 260, height: 360)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 12)
                    .padding(.top, 10)
                    .milniEntrance(0)

                    VStack(spacing: 14) {
                        if let link, let qr = Self.qr(link) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 168, height: 168)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
                                .accessibilityLabel("QR code for the wedding link")
                        } else if codeFailed {
                            VStack(spacing: 10) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(HostStyle.muted)
                                Text("Couldn't load the code")
                                    .font(Milni.inter(15, weight: 600))
                                    .foregroundStyle(HostStyle.ink)
                                Button {
                                    BrandHaptics.tick()
                                    Task { await loadCode() }
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .font(Milni.inter(14, weight: 600))
                                }
                                .buttonStyle(.milniTertiary)
                            }
                            .frame(width: 196, height: 196)
                            .accessibilityElement(children: .combine)
                        } else {
                            ProgressView().frame(width: 196, height: 196)
                        }

                        Text(code ?? "······")
                            .font(Milni.inter(24, weight: 600))
                            .tracking(7)
                            .foregroundStyle(HostStyle.ink)
                            .contentTransition(.numericText())
                            .textSelection(.enabled)
                        if let link {
                            Text(link.replacingOccurrences(of: "https://", with: ""))
                                .font(Milni.inter(13))
                                .foregroundStyle(HostStyle.muted)
                                .textSelection(.enabled)
                        }
                    }
                    .milniEntrance(1)

                    HostErrorLine(message: error)

                    VStack(spacing: 10) {
                        Button {
                            BrandHaptics.soft()
                            share = HostSharePayload(items: [message])
                        } label: {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.milniPrimary)

                        Button {
                            BrandHaptics.tick()
                            if let url = printCard() { share = HostSharePayload(items: [url]) }
                        } label: {
                            Label("Print card", systemImage: "printer")
                        }
                        .buttonStyle(.milniSecondary)

                        Button {
                            confirmNewCode = true
                        } label: {
                            if isRegenerating { ProgressView() } else { Text("Make a new code") }
                        }
                        .buttonStyle(.milniTertiary)
                    }
                    .disabled(code == nil)
                    .milniEntrance(2)
                }
                .padding(.horizontal, HostStyle.side)
                .padding(.bottom, 40)
            }
            .background(HostPaper())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Milni.inter(16, weight: 600))
                }
            }
        }
        .tint(HostStyle.ink)
        .environment(\.colorScheme, .light)
        .task {
            if code == nil { await loadCode() }
        }
        .sheet(item: $share) { payload in
            HostShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Make a new code?", isPresented: $confirmNewCode, titleVisibility: .visible) {
            Button("Make a new code", role: .destructive) { Task { await regenerate() } }
        } message: {
            Text("The old code and link stop working. Anyone already in the wedding stays in.")
        }
    }

    /// Reads the join code, offering a retry if it can't be loaded.
    private func loadCode() async {
        guard !isLoadingCode else { return }
        isLoadingCode = true
        defer { isLoadingCode = false }
        withAnimation(.calm) { codeFailed = false }
        do {
            let loadedCode = try await HostAPI.shared.joinCode(weddingID: weddingID)
            withAnimation(.calm) {
                if let loadedCode {
                    code = loadedCode
                } else {
                    codeFailed = true
                }
            }
        } catch {
            withAnimation(.calm) { codeFailed = true }
        }
    }

    private func regenerate() async {
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            let fresh = try await HostAPI.shared.regenerateJoinCode(weddingID: weddingID)
            BrandHaptics.soft()
            withAnimation(.calm) { code = fresh }
            error = nil
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }

    /// A one-page printable card: the invitation, the QR and the code, as a PDF.
    private func printCard() -> URL? {
        guard let link, let code else { return nil }
        let page = HostPrintableCard(snapshot: snapshot, code: code, link: link, qr: Self.qr(link, scale: 20))
        let renderer = ImageRenderer(content: page.frame(width: 612, height: 792))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(snapshot.coupleNames.replacingOccurrences(of: " ", with: "")) Invitation.pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            ok = true
        }
        if !ok { error = "The card couldn't be made. Please try again." }
        return ok ? url : nil
    }

    static func qr(_ text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let colored = output.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0.09, green: 0.075, blue: 0.06),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ])
        guard let cg = CIContext().createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The printed page: a letter-size card guests can scan from a table or a fridge.
private struct HostPrintableCard: View {
    let snapshot: WeddingSnapshot
    let code: String
    let link: String
    let qr: UIImage?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            MilniInvitationCard(
                partnerOne: snapshot.partnerOne,
                partnerTwo: snapshot.partnerTwo,
                detail: snapshot.cityAndDates,
                preset: snapshot.preset,
                drawsRings: false
            )
            .frame(width: 280, height: 380)

            Text("Scan to join our wedding on Milni")
                .font(Milni.cormorant(24, italic: true))
                .foregroundStyle(Milni.ink)

            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 150, height: 150)
            }

            VStack(spacing: 6) {
                Text(code)
                    .font(Milni.inter(22, weight: 600))
                    .tracking(6)
                Text(link.replacingOccurrences(of: "https://", with: ""))
                    .font(Milni.inter(12))
                    .foregroundStyle(Milni.muted)
            }
            .foregroundStyle(Milni.ink)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
