import XCTest
@testable import Forge

/// P1 Phase 8 — remote marketing config: the deterministic, automatable part
/// (fallback + graceful-degradation + JSON decode). The paywall UI + live
/// StoreKit purchase can't be automated here (system purchase sheet + sandbox
/// account) — that's Bilal's device (Phase 9).
@MainActor
final class RemoteConfigTests: XCTestCase {

    private let cacheKey = "forge.remoteConfig.cache.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        super.tearDown()
    }

    func testUsesFallbackWhenNoURLAndNoCache() {
        let service = RemoteConfigService(remoteURL: nil)
        XCTAssertEqual(service.config, RemoteConfig.fallback)
        // The fallback must be a fully usable paywall config.
        XCTAssertNotNil(service.config.paywallHeadline)
        XCTAssertEqual(service.config.featuredPackID, "islamic")
    }

    func testRefreshWithNoURLKeepsFallbackAndNeverThrows() async {
        let service = RemoteConfigService(remoteURL: nil)
        await service.refresh() // must be a silent no-op, never blocking/erroring
        XCTAssertEqual(service.config, RemoteConfig.fallback)
    }

    func testRemoteConfigDecodesFromJSON() throws {
        let json = Data("""
        {"featuredPackID":"islamic","bannerVisible":true,"bannerText":"Ramadan offer",
         "paywallHeadline":"Unlock everything","paywallSubheadline":"All packs included",
         "anchorPriceText":"Normally $4.99"}
        """.utf8)
        let config = try JSONDecoder().decode(RemoteConfig.self, from: json)
        XCTAssertEqual(config.featuredPackID, "islamic")
        XCTAssertTrue(config.bannerVisible)
        XCTAssertEqual(config.bannerText, "Ramadan offer")
        XCTAssertEqual(config.anchorPriceText, "Normally $4.99")
    }

    func testCachedConfigIsUsedOnInit() throws {
        // Seed a cached config, then a fresh service must load it (not fallback).
        let cached = RemoteConfig(featuredPackID: "islamic", bannerText: "Hi", bannerVisible: true,
                                  paywallHeadline: "Cached", paywallSubheadline: nil, anchorPriceText: nil)
        UserDefaults.standard.set(try JSONEncoder().encode(cached), forKey: cacheKey)
        let service = RemoteConfigService(remoteURL: nil)
        XCTAssertEqual(service.config, cached)
    }
}
