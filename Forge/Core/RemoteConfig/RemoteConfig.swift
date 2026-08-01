import Foundation

/// Lightweight remote **marketing** config (P1 Phase 8) — controls the
/// featured pack, an optional promo banner, and the paywall's headline / promo
/// copy / **anchor-price text**. Static, public, read-only JSON.
///
/// **Hard boundary:** this never carries anything that's charged. The paywall
/// always renders the real `Product.displayPrice` from StoreKit and purchases
/// go 100% through StoreKit; `anchorPriceText` here is *decorative* copy only
/// (e.g. "Normally $4.99"), never used as an actual price. So there are no
/// secrets and nothing security-sensitive in this payload — it's marketing
/// text fetched over HTTPS with a graceful fallback.
struct RemoteConfig: Codable, Equatable, Sendable {
    /// Which pack to feature on the paywall (a pack id, e.g. `"islamic"`).
    var featuredPackID: String?
    /// Optional promo banner (shown somewhere like the paywall top / a future
    /// home banner) — only when `bannerVisible`.
    var bannerText: String?
    var bannerVisible: Bool
    /// Paywall copy.
    var paywallHeadline: String?
    var paywallSubheadline: String?
    /// Decorative anchor-price copy shown near a pack's real StoreKit price to
    /// frame the "or free with Premium" value — never a charged amount.
    var anchorPriceText: String?

    /// Built-in defaults used when the remote config hasn't loaded (or can't).
    /// The paywall must always be fully usable from these alone.
    static let fallback = RemoteConfig(
        featuredPackID: "islamic",
        bannerText: nil,
        bannerVisible: false,
        paywallHeadline: "Unlock Forge Premium",
        paywallSubheadline: "Every premium feature and every template pack — including the Islamic pack.",
        anchorPriceText: nil
    )
}
