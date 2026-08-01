import SwiftUI
import StoreKit

/// Forge Premium paywall (P1 Phase 8). Presents the subscription (monthly /
/// yearly) and, when reached from a specific pack, that pack's standalone
/// non-consumable with a prominent **"or free with Premium"** anchor. All
/// prices are the real StoreKit `Product.displayPrice` (never hardcoded, never
/// from remote config); headline / promo copy / decorative anchor text come
/// from `RemoteConfigService` (which falls back to built-in defaults, so the
/// paywall is always fully usable). Purchases go 100% through StoreKit.
struct PaywallView: View {
    /// The pack that triggered this paywall (a section/pack id, e.g.
    /// `"good-islamic-prayers"`), so we can offer "buy just this pack". `nil`
    /// = a generic premium paywall.
    var packID: String? = nil

    @Environment(StoreKitEntitlementService.self) private var storeKit
    @Environment(RemoteConfigService.self) private var remoteConfig
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var errorMessage: String?

    private var config: RemoteConfig { remoteConfig.config }

    private var subscriptionProducts: [Product] {
        storeKit.products
            .filter { ProductIdentifiers.subscriptions.contains($0.id) }
            .sorted { $0.price < $1.price }
    }

    private var packProduct: Product? {
        guard let packID, let productID = ProductIdentifiers.packProductID(for: packID) else { return nil }
        return storeKit.products.first { $0.id == productID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if config.bannerVisible, let banner = config.bannerText {
                        Text(banner)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if subscriptionProducts.isEmpty && packProduct == nil {
                        unavailableState
                    } else {
                        subscriptionSection
                        if let packProduct { packSection(packProduct) }
                    }

                    Button("Restore Purchases") {
                        Task { await storeKit.restore(); if await storeKit.isPremiumUnlocked() { dismiss() } }
                    }
                    .font(.subheadline)
                    .disabled(purchasing)

                    Text("Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period; manage them in Settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("Forge Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .overlay { if purchasing { ProgressView().controlSize(.large) } }
            .task { if storeKit.products.isEmpty { await storeKit.loadProducts() } }
            .alert("Purchase", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(config.paywallHeadline ?? RemoteConfig.fallback.paywallHeadline ?? "Unlock Forge Premium")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let sub = config.paywallSubheadline {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var subscriptionSection: some View {
        VStack(spacing: 12) {
            ForEach(subscriptionProducts, id: \.id) { product in
                Button { buy(product) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.headline)
                            Text("Unlocks everything, including every pack")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.displayPrice).font(.headline.monospacedDigit())
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(purchasing)
                .accessibilityIdentifier("paywall.buy.\(product.id)")
            }
        }
    }

    private func packSection(_ product: Product) -> some View {
        VStack(spacing: 8) {
            Text("Or just this pack").font(.subheadline).foregroundStyle(.secondary)
            Button { buy(product) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName).font(.headline)
                        if let anchor = config.anchorPriceText {
                            Text(anchor).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(product.displayPrice).font(.headline.monospacedDigit())
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(purchasing)
            .accessibilityIdentifier("paywall.buy.\(product.id)")

            Text("or free with Premium")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.title)
            Text("Products couldn't load. Check your connection and try again.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await storeKit.loadProducts() } }
        }
        .padding()
    }

    private func buy(_ product: Product) {
        Task {
            purchasing = true
            defer { purchasing = false }
            do {
                let success = try await storeKit.purchase(product)
                if success { dismiss() }
            } catch {
                errorMessage = "Couldn't complete the purchase. Please try again."
            }
        }
    }
}
