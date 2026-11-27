import SwiftUI

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.onAccent : .primary)
            .background(
                Capsule().fill(isSelected ? accent : Color(UIColor.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }
}
