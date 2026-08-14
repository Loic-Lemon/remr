import SwiftUI

/// Compact table of shipped functionality, opened from the bottom of Settings.
struct FeatureInventoryView: View {
    private let featureColumnWidth: CGFloat = 156
    private let statusColumnWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(FeatureInventory.all.enumerated()), id: \.element.id) { index, feature in
                            featureRow(feature)
                            if index < FeatureInventory.all.count - 1 {
                                Divider()
                            }
                        }
                    } header: {
                        tableHeader
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .clipped()
        }
        .frame(width: 520, height: 480)
        .liquidGlassGrouping()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feature inventory")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Feature inventory")
                    .font(.headline)
                Text("Shipped functionality and ideas to track next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(FeatureInventory.implementedCount) shipped")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)
                Text("\(FeatureInventory.ideaCount) ideas")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.purple)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(FeatureInventory.implementedCount) shipped, \(FeatureInventory.ideaCount) ideas")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Feature")
                .frame(width: featureColumnWidth, alignment: .leading)
            Text("Status")
                .frame(width: statusColumnWidth, alignment: .leading)
            Text("Details")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.regularMaterial)
        }
        .zIndex(1)
    }

    private func featureRow(_ feature: FeatureInventoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(feature.name)
                .font(.callout.weight(.medium))
                .frame(width: featureColumnWidth, alignment: .leading)

            statusBadge(feature.status)
                .frame(width: statusColumnWidth, alignment: .leading)

            Text(feature.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    /// Status badges stay a clipped, flat semantic capsule instead of using a
    /// nested glass effect. Nested glass can lens content above the ScrollView
    /// while a row is moving past the fixed table header.
    private func statusBadge(_ status: FeatureInventoryStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
            Text(status.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(status.tint.opacity(0.34), lineWidth: 0.75))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}
