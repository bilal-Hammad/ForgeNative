import SwiftUI

/// A SwiftUI-native approximation of the classic UITableView section-index
/// sidebar — NOT the real system mechanism (see CategoryDetailView's doc
/// comment for why), built with `ScrollViewReader` + a drag gesture. Visually
/// matches the reference; scrolls the paired `List` to the tapped/dragged-over
/// section's first row.
struct SectionIndexStrip: View {
    let labels: [(id: String, initial: String)]
    let onSelect: (String) -> Void

    @State private var activeIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let rowHeight = geometry.size.height / CGFloat(max(labels.count, 1))

            VStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label.initial)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: rowHeight)
                }
            }
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = min(
                            labels.count - 1,
                            max(0, Int(value.location.y / rowHeight))
                        )
                        if index != activeIndex {
                            activeIndex = index
                            onSelect(labels[index].id)
                        }
                    }
                    .onEnded { _ in activeIndex = nil }
            )
        }
        .frame(width: 20)
    }
}
