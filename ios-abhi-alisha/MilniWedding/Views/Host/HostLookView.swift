import PhotosUI
import Supabase
import SwiftUI

/// How the wedding looks: palette, light or dark, crest, countdown, RSVP link and the
/// cover photos. Everything previews live and only reaches guests on Save.
struct HostLookView: View {
    private let context = WeddingContext.shared

    @State private var theme: WeddingTheme = WeddingContext.shared.snapshot.resolvedTheme
    @State private var original: WeddingTheme = WeddingContext.shared.snapshot.resolvedTheme
    @State private var mainEventRef: String = WeddingContext.shared.snapshot.mainEventRef ?? ""
    @State private var rsvpURL: String = WeddingContext.shared.snapshot.rsvpURL ?? ""
    @State private var covers: [String] = []
    @State private var originalCovers: [String] = []
    @State private var events: [HostEvent] = []
    @State private var previewDark = false
    @State private var isSaving = false
    @State private var saved = false
    @State private var error: String?
    @State private var crestPick: PhotosPickerItem?
    @State private var coverPicks: [PhotosPickerItem] = []
    @State private var uploading = 0

    private var weddingID: String { context.weddingID }
    private var snapshot: WeddingSnapshot { context.snapshot }

    private var presets: [String] {
        original.preset.lowercased() == "custom" ? ["custom"] + WeddingTheme.presetIDs : WeddingTheme.presetIDs
    }

    private var hasChanges: Bool {
        theme != original
            || mainEventRef != (snapshot.mainEventRef ?? "")
            || rsvpURL.hostTrimmed != (snapshot.rsvpURL ?? "")
            || covers != originalCovers
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                preview
                    .padding(.top, 8)

                presetPicker
                appearancePicker
                crestSection
                countdownSection
                HostField(label: "RSVP link", text: $rsvpURL, placeholder: "https://", keyboard: .URL)
                coverSection

                HostErrorLine(message: error)

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(HostStyle.paper)
                    } else {
                        Text(saved && !hasChanges ? "Saved" : "Save changes")
                    }
                }
                .buttonStyle(.milniPrimary)
                .disabled(!hasChanges || isSaving || uploading > 0)
            }
            .padding(.horizontal, HostStyle.side)
            .padding(.bottom, 50)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(HostPaper())
        .navigationTitle("Look & cover photos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: crestPick) { _, item in
            guard let item else { return }
            crestPick = nil
            Task { await uploadCrest(item) }
        }
        .onChange(of: coverPicks) { _, picks in
            guard !picks.isEmpty else { return }
            coverPicks = []
            Task { await uploadCovers(picks) }
        }
    }

    // MARK: Preview

    private var preview: some View {
        let tokens = theme.tokens(dark: previewDark)
        let bg = Color(hex: tokens.bg), card = Color(hex: tokens.card), ink = Color(hex: tokens.ink)
        let accent = Color(hex: tokens.accent), accentText = Color(hex: tokens.accentText), muted = Color(hex: tokens.muted)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HostCaps("Live preview", color: HostStyle.muted)
                Spacer()
                if theme.forcedDark == nil {
                    Picker("Preview", selection: $previewDark.animation(.calm)) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }

            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let first = covers.first {
                        RemoteImage(url: URL(string: first), contentMode: .fill) { accent.opacity(0.2) }
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    } else {
                        LinearGradient(colors: [accent.opacity(0.35), bg], startPoint: .top, endPoint: .bottom)
                    }
                    Text(snapshot.coupleNames)
                        .font(Milni.cormorant(30, weight: 500, italic: theme.displayIsItalic))
                        .foregroundStyle(covers.isEmpty ? ink : .white)
                        .padding(16)
                }
                .frame(height: 150)
                .clipped()

                VStack(alignment: .leading, spacing: 10) {
                    Text("NEXT UP")
                        .font(Milni.inter(10, weight: 600))
                        .tracking(1.8)
                        .foregroundStyle(accentText)
                    Text(countdownTitle)
                        .font(Milni.cormorant(22, weight: 500, italic: theme.displayIsItalic))
                        .foregroundStyle(ink)
                    Rectangle().fill(accent).frame(width: 36, height: 1)
                    HStack {
                        Text(snapshot.cityAndDates)
                            .font(Milni.inter(12))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                        Spacer()
                        Text("RSVP")
                            .font(Milni.inter(12, weight: 600))
                            .foregroundStyle(bg)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(accent))
                            .opacity(rsvpURL.hostTrimmed.isEmpty ? 0.3 : 1)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(card))
                .padding(12)
            }
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
            .animation(.calm, value: theme)
        }
    }

    private var countdownTitle: String {
        events.first { ($0.ref ?? $0.id) == mainEventRef }?.title ?? "Your celebration"
    }

    // MARK: Pickers

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HostCaps("Palette", color: HostStyle.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(presets, id: \.self) { id in
                    let selected = theme.preset.lowercased() == id
                    let tokens = id == "custom" ? original.tokens(dark: false) : WeddingTheme.builtIn(id).light
                    Button {
                        BrandHaptics.tick()
                        choosePreset(id)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: tokens.bg))
                                VStack(spacing: 4) {
                                    Circle().fill(Color(hex: tokens.accent)).frame(width: 18, height: 18)
                                    Capsule().fill(Color(hex: tokens.ink)).frame(width: 26, height: 3)
                                }
                            }
                            .frame(height: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selected ? HostStyle.ink : HostStyle.hairline, lineWidth: selected ? 2 : 1)
                            )
                            Text(id == "custom" ? "Yours" : id.capitalized)
                                .font(Milni.inter(12, weight: selected ? 600 : 400))
                                .foregroundStyle(HostStyle.ink)
                        }
                    }
                    .buttonStyle(MilniPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HostCaps("Light and dark", color: HostStyle.muted)
            if theme.isMidnight {
                Text("Midnight is always dark.")
                    .font(Milni.inter(14))
                    .foregroundStyle(HostStyle.muted)
            } else {
                Picker("Appearance", selection: $theme.appearance.animation(.calm)) {
                    Text("Follow the phone").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var crestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HostCaps("Crest", color: HostStyle.muted)
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HostStyle.card)
                    if let url = theme.crestURL {
                        RemoteImage(url: url, contentMode: .fit) { Color.clear }.padding(10)
                    } else if theme.hasBundledCrest {
                        Image(systemName: "seal").font(.system(size: 28)).foregroundStyle(HostStyle.goldText)
                    } else {
                        MilniMonogram(initials: snapshot.initials, size: 54, ring: HostStyle.gold, textColor: HostStyle.goldText)
                    }
                }
                .frame(width: 84, height: 84)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    Text(theme.crest == nil ? "Your initials, as a monogram" : (theme.hasBundledCrest ? "Your designed crest" : "Your uploaded crest"))
                        .font(Milni.inter(14))
                        .foregroundStyle(HostStyle.ink)
                    PhotosPicker(selection: $crestPick, matching: .images) {
                        Text("Upload a crest")
                            .font(Milni.inter(15, weight: 600))
                            .foregroundStyle(HostStyle.goldText)
                    }
                    if theme.crest != nil, !theme.hasBundledCrest {
                        Button("Use the monogram") { withAnimation(.calm) { theme.crest = original.hasBundledCrest ? original.crest : nil } }
                            .font(Milni.inter(14))
                            .foregroundStyle(HostStyle.muted)
                    }
                }
            }
            Text("A PNG with a clear background looks best.")
                .font(Milni.inter(12))
                .foregroundStyle(HostStyle.muted)
        }
    }

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HostCaps("The countdown runs to", color: HostStyle.muted)
            Menu {
                Button("The first day") { mainEventRef = "" }
                ForEach(events) { event in
                    Button(event.title.isEmpty ? "Untitled" : event.title) { mainEventRef = event.ref ?? event.id }
                }
            } label: {
                HStack {
                    Text(mainEventRef.isEmpty ? "The first day" : countdownTitle)
                        .font(Milni.inter(16))
                        .foregroundStyle(HostStyle.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HostStyle.gold)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HostStyle.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
            }
        }
    }

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HostCaps("Cover photos", color: HostStyle.muted)
            Text("They play on Home in this order. Hold a photo to move or remove it.")
                .font(Milni.inter(12))
                .foregroundStyle(HostStyle.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(covers.enumerated()), id: \.element) { index, url in
                    RemoteImage(url: URL(string: url), contentMode: .fill) { HostStyle.hairline }
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)")
                                .font(Milni.inter(11, weight: 700))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.black.opacity(0.5)))
                                .padding(6)
                        }
                        .contextMenu {
                            if index > 0 {
                                Button("Move earlier", systemImage: "arrow.left") { move(index, by: -1) }
                                Button("Make first", systemImage: "star") { move(index, by: -index) }
                            }
                            if index < covers.count - 1 {
                                Button("Move later", systemImage: "arrow.right") { move(index, by: 1) }
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                withAnimation(.calm) { _ = covers.remove(at: index) }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                ForEach(0..<uploading, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(HostStyle.hairline.opacity(0.6))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(ProgressView())
                }
                PhotosPicker(selection: $coverPicks, maxSelectionCount: 10, matching: .images) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(HostStyle.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 18, weight: .light))
                                Text("Add").font(Milni.inter(12, weight: 500))
                            }
                            .foregroundStyle(HostStyle.goldText)
                        }
                }
                .accessibilityLabel("Add cover photos")
            }
            .animation(.calm, value: covers)
        }
    }

    // MARK: Actions

    private func choosePreset(_ id: String) {
        withAnimation(.calm) {
            if id == "custom" {
                var restored = original
                restored.crest = theme.crest
                restored.appearance = theme.appearance
                theme = restored
            } else {
                var next = WeddingTheme.preset(id)
                next.crest = theme.crest
                if id != "midnight", !theme.isMidnight { next.appearance = theme.appearance }
                theme = next
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard covers.indices.contains(index), covers.indices.contains(target) else { return }
        BrandHaptics.tick()
        withAnimation(.calm) {
            let item = covers.remove(at: index)
            covers.insert(item, at: target)
        }
    }

    private func load() async {
        async let eventsTask = HostAPI.shared.events(weddingID: weddingID)
        async let rowTask = HostAPI.shared.weddingRow(weddingID: weddingID)
        if let loaded = try? await eventsTask {
            events = loaded.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
        }
        do {
            let row = try await rowTask
            let urls = (row["cover_urls"] as? [Any])?.compactMap { $0 as? String } ?? []
            covers = urls
            originalCovers = urls
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }

    private func uploadCrest(_ item: PhotosPickerItem) async {
        uploading += 1
        defer { uploading -= 1 }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
              let png = Self.png(image, maxSide: 900) else {
            error = "That image couldn't be read. Please pick another."
            return
        }
        do {
            let path = "\(weddingID.lowercased())/crest/\(UUID().uuidString.lowercased()).png"
            let url = try await HostAPI.shared.upload(png, path: path, contentType: "image/png")
            withAnimation(.calm) { theme.crest = url }
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }

    private func uploadCovers(_ picks: [PhotosPickerItem]) async {
        uploading += picks.count
        for item in picks {
            defer { uploading -= 1 }
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                error = "One photo couldn't be read. Try another."
                continue
            }
            do {
                let path = "\(weddingID.lowercased())/covers/\(UUID().uuidString.lowercased()).jpg"
                let url = try await HostAPI.shared.uploadPhoto(image, path: path, maxSide: 2400)
                withAnimation(.calm) { covers.append(url) }
            } catch {
                self.error = error.hostMessage
            }
        }
    }

    private func save() async {
        let link = rsvpURL.hostTrimmed
        if !link.isEmpty, URL(string: link)?.scheme?.hasPrefix("http") != true {
            withAnimation(.calm) { error = "The RSVP link should start with https://" }
            return
        }
        isSaving = true
        defer { isSaving = false }
        let fields: [String: AnyJSON] = [
            "theme": HostAPI.anyJSON(theme.json),
            "main_event_ref": mainEventRef.isEmpty ? .null : .string(mainEventRef),
            "rsvp_url": link.isEmpty ? .null : .string(link),
            "cover_urls": .array(covers.map { .string($0) }),
        ]
        do {
            try await HostAPI.shared.updateWedding(weddingID: weddingID, fields: fields)
            BrandHaptics.soft()
            await context.refreshCurrent()
            original = theme
            originalCovers = covers
            withAnimation(.calm) {
                saved = true
                error = nil
            }
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }

    static func png(_ image: UIImage, maxSide: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.pngData()
    }
}
