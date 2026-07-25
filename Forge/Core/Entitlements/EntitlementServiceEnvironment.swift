import SwiftUI

private struct EntitlementServiceKey: EnvironmentKey {
    static let defaultValue: EntitlementService = StubEntitlementService()
}

extension EnvironmentValues {
    var entitlementService: EntitlementService {
        get { self[EntitlementServiceKey.self] }
        set { self[EntitlementServiceKey.self] = newValue }
    }
}
