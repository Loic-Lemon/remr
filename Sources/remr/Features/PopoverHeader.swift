import SwiftUI

/// Shared header chrome for the guide and recovery popovers.
struct RemrPopoverHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let onClose: () -> Void
    var tint: Color = Color(red: 0.38, green: 0.68, blue: 0.98)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .accessibilityLabel("Close \(title.lowercased())")
            .help("Close \(title.lowercased())")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}
