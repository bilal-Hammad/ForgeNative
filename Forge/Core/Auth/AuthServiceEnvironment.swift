import SwiftUI

private struct AuthServiceKey: EnvironmentKey {
    static let defaultValue: AuthService = AppleAuthService()
}

extension EnvironmentValues {
    var authService: AuthService {
        get { self[AuthServiceKey.self] }
        set { self[AuthServiceKey.self] = newValue }
    }
}
