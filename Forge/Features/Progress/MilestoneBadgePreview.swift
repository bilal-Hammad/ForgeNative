import SwiftUI

/// Flat, cheap 2D stand-in for `Badge3DView`, used anywhere multiple badges
/// render at once (the Milestones list, the Progress card's horizontal
/// strip). Same rounded-square shape/color language as the real 3D badge,
/// but without a live SceneKit renderer + `CMMotionManager` subscription
/// per instance — a list of a few dozen milestones would otherwise mean
/// that many concurrent Metal-backed views and motion callbacks at once,
/// which doesn't scale the way a single, one-at-a-time detail-page badge
/// does. Apple's own Fitness Awards grid does the same thing: flat tiles in
/// the grid, the real interactive 3D badge only on the detail page.
struct MilestoneBadgePreview: View {
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.9), color.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            )
            .frame(width: size, height: size)
    }
}

#Preview {
    MilestoneBadgePreview(color: .green)
        .padding()
}
