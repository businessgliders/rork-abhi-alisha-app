import PDFKit
import SwiftUI

/// The South Wing / North Wing guide, bundled with the app.
enum WingMapArtwork {
    static let imageName = "resort_wing_map"
    static let pdfURL = URL(string: "https://www.avaresortcancun.com/files/6879/ava-resort-cancun-map.pdf")
}

/// The wing map full screen: pinch, pan, double tap. Fully offline.
struct WingMapViewer: View {
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isShowingPDF = false

    var body: some View {
        ZStack {
            Color(hex: 0xFBF7EE).ignoresSafeArea()

            GeometryReader { proxy in
                Image(WingMapArtwork.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value.magnification, 1), 6)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1.02 { recentre() }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.02 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.calm) {
                            if scale > 1.02 {
                                scale = 1
                                lastScale = 1
                                recentre()
                            } else {
                                scale = 2.6
                                lastScale = 2.6
                            }
                        }
                    }
                    .accessibilityLabel("AVA Resort Cancún map, South Wing and North Wing")
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Text("WING MAP")
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color(hex: 0x2B2622).opacity(0.7))

                Spacer()

                Button {
                    BrandHaptics.tick()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Color(hex: 0x2B2622))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                Text("Pinch to zoom · double tap to enlarge")
                    .font(BrandLabel.font(size: 10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0x6D6459))

                Button {
                    BrandHaptics.soft()
                    isShowingPDF = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 12, weight: .light))
                        Text("Full map (PDF)")
                            .font(BrandLabel.font(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Color(hex: 0xFFFBF1))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(Color(hex: 0xA9873C)))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.bottom, 18)
        }
        .statusBarHidden()
        .fullScreenCover(isPresented: $isShowingPDF) {
            ResortPDFViewer()
        }
    }

    private func recentre() {
        withAnimation(.calm) { offset = .zero }
        lastOffset = .zero
    }
}

// MARK: - PDF

/// The resort's official map PDF, read in-app. Once loaded it is kept on the phone, so
/// later visits open instantly and offline.
struct ResortPDFViewer: View {
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case loading
        case ready(Data)
        case failed
    }

    @State private var stage: Stage = .loading

    var body: some View {
        NavigationStack {
            ZStack {
                BrandPalette.background.ignoresSafeArea()

                switch stage {
                case .loading:
                    VStack(spacing: 14) {
                        Image(WingMapArtwork.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(0.35)
                            .padding(.horizontal, 30)
                        Text("Opening the resort map…")
                            .brandFont(.bodyItalic)
                            .foregroundStyle(BrandPalette.body)
                    }
                case .ready(let data):
                    PDFKitView(data: data)
                        .ignoresSafeArea(edges: .bottom)
                case .failed:
                    VStack(spacing: 16) {
                        Image(WingMapArtwork.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, 16)
                        Text("The full PDF needs a connection the first time. The wing map above works offline.")
                            .brandFont(.bodyItalic)
                            .foregroundStyle(BrandPalette.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button("Try again") {
                            Task { await load() }
                        }
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                        .foregroundStyle(BrandPalette.goldDeep)
                    }
                }
            }
            .navigationTitle("Resort Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(BrandLabel.font(size: 13, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
                if let url = WingMapArtwork.pdfURL, case .ready = stage {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(BrandPalette.goldDeep)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        if let cached = ResortPDFCache.cached() {
            stage = .ready(cached)
            return
        }
        stage = .loading
        if let data = await ResortPDFCache.download() {
            withAnimation(.softFade) { stage = .ready(data) }
        } else {
            withAnimation(.softFade) { stage = .failed }
        }
    }
}

/// Keeps the downloaded PDF in Caches.
nonisolated enum ResortPDFCache {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ava-resort-cancun-map.pdf")
    }

    static func cached() -> Data? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL), PDFDocument(data: data) != nil else { return nil }
        return data
    }

    static func download() async -> Data? {
        guard let url = WingMapArtwork.pdfURL else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, PDFDocument(data: data) != nil else { return nil }
            if let fileURL { try? data.write(to: fileURL, options: .atomic) }
            return data
        } catch {
            return nil
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(BrandPalette.background)
        view.document = PDFDocument(data: data)
        view.maxScaleFactor = 8
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
