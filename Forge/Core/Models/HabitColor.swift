import SwiftUI

/// A small preset color palette for habit cards — stored on `Habit` as a
/// stable string identifier (`rawValue`) rather than a raw `Color`, so it
/// round-trips through `Codable`/persistence cleanly.
enum HabitColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}
