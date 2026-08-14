import SwiftUI

/// A transient confirmation toast with an optional recovery action.
struct ActionToast: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    /// Content-swap animation state, applied to the inner content only — the
    /// pill shell stays put while replacements roll out and in.
    var contentOffset: CGFloat = 0
    var contentOpacity: Double = 1

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .lineLimit(1)
                .truncationMode(.middle)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .liquidGlassCapsule()
            }
        }
        .font(.callout.weight(.medium))
        .offset(y: contentOffset)
        .opacity(contentOpacity)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlassToast()
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }
}
