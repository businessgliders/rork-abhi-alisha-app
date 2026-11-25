import SwiftUI

/// A map image the couple uploaded, opened full screen.
struct RemoteMapItem: Identifiable, Hashable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

/// Full-screen viewer for an uploaded map: pinch, pan, double tap.
struct RemoteMapViewer: View {
    let item: RemoteMapItem
    var pdfURL: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isShowingPDF = false

    var body: some View {
        ZStack {
            BrandPalette.background.ignoresSafeArea()

            GeometryReader { proxy in
                RemoteImage(url: item.url, contentMode: .fit)
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
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .calm) {
                            if scale > 1.02 {
                                scale = 1
                                lastScale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.6
                                lastScale = 2.6
                            }
                        }
                    }
                    .accessibilityLabel(item.title)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Text(item.title.uppercased())
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(BrandPalette.ink.opacity(0.7))

                Spacer()

                Button {
                    BrandHaptics.tick()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(BrandPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(BrandPalette.ink.opacity(0.07)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .overlay(alignment: .bottom) {
            if pdfURL != nil {
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
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(BrandPalette.card))
                    .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .padding(.bottom, 18)
            }
        }
        .fullScreenCover(isPresented: $isShowingPDF) {
            ResortPDFViewer(pdfURL: pdfURL)
        }
    }

    private func recentre() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .calm) { offset = .zero }
        lastOffset = .zero
    }
}
