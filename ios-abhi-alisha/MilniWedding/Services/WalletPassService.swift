import Foundation
import Observation
import PassKit
import SwiftUI
import Supabase

/// The wedding's Apple Wallet pass, made by the `wallet-pass` function. The button only
/// shows once a real pass has come back: any missing function, error or sign-out simply
/// keeps it hidden.
@MainActor
@Observable
final class WalletPassService {
    static let shared = WalletPassService()

    enum State: Equatable {
        case hidden
        case ready(PKPass)
        case inWallet(PKPass)
    }

    private(set) var state: State = .hidden
    private var loadedFor: String?
    private var loading: String?
    private var wanted: String?

    private init() {}

    var isAvailable: Bool { PKAddPassesViewController.canAddPasses() }

    /// Fetches the pass for a wedding (the current one by default), once per wedding per launch.
    func prepare(weddingID requested: String? = nil, force: Bool = false) async {
        let weddingID = (requested ?? ActiveWedding.snapshot.id).lowercased()
        guard isAvailable else { return }
        if !force, loadedFor == weddingID {
            refreshWalletState()
            return
        }
        guard loading != weddingID else { return }
        loading = weddingID
        wanted = weddingID
        defer { if loading == weddingID { loading = nil } }

        if loadedFor != weddingID { state = .hidden }
        let pass = await fetch(weddingID: weddingID)
        guard wanted == weddingID else { return }
        loadedFor = weddingID
        if let pass {
            state = PKPassLibrary().containsPass(pass) ? .inWallet(pass) : .ready(pass)
        } else {
            state = .hidden
        }
    }

    /// After the Add sheet closes, check whether the guest added it.
    func refreshWalletState() {
        switch state {
        case .ready(let pass), .inWallet(let pass):
            state = PKPassLibrary().containsPass(pass) ? .inWallet(pass) : .ready(pass)
        case .hidden:
            break
        }
    }

    func forget() {
        state = .hidden
        loadedFor = nil
    }

    private func fetch(weddingID: String) async -> PKPass? {
        guard let token = try? await ChatBackend.client.auth.session.accessToken else { return nil }
        var request = URLRequest(url: ChatBackend.url.appendingPathComponent("functions/v1/wallet-pass"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(ChatBackend.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["wedding_id": weddingID])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty
        else { return nil }
        return try? PKPass(data: data)
    }
}

/// Apple's own "Add to Apple Wallet" button, or "View in Wallet" once it's there.
/// Shows nothing until the wedding has a pass.
struct WalletPassButton: View {
    /// The wedding whose pass to offer; the current wedding when nil.
    var weddingID: String? = nil

    @State private var wallet = WalletPassService.shared
    @State private var isAdding = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch wallet.state {
            case .hidden:
                EmptyView()
            case .ready:
                AddPassButton(style: colorScheme == .dark ? .blackOutline : .black) {
                    BrandHaptics.soft()
                    isAdding = true
                }
                .frame(height: 48)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Add your wedding pass to Apple Wallet"))
                .transition(.opacity)
            case .inWallet(let pass):
                Button {
                    BrandHaptics.soft()
                    if let url = pass.passURL { openURL(url) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wallet.pass")
                        Text("View in Wallet")
                            .font(BrandLabel.font(size: 12, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.6), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
        }
        .animation(.softFade, value: wallet.state)
        .sheet(isPresented: $isAdding, onDismiss: { wallet.refreshWalletState() }) {
            if case .ready(let pass) = wallet.state {
                AddPassesSheet(pass: pass)
                    .ignoresSafeArea()
            }
        }
        .task(id: weddingID ?? ActiveWedding.snapshot.id) {
            await wallet.prepare(weddingID: weddingID)
        }
    }
}

private struct AddPassButton: UIViewRepresentable {
    let style: PKAddPassButtonStyle
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: style)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {
        uiView.addPassButtonStyle = style
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

private struct AddPassesSheet: UIViewControllerRepresentable {
    let pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
