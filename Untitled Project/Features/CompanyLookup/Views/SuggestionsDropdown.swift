import SwiftUI

struct SuggestionsDropdown: View {
    private static let rowHeight: CGFloat = 72
    private static let verticalPadding: CGFloat = 8
    private static let maxHeight: CGFloat = 288

    let results: [CompanySearchResult]
    let onSelect: (CompanySearchResult) -> Void

    private var dropdownHeight: CGFloat {
        min(CGFloat(results.count) * Self.rowHeight + Self.verticalPadding, Self.maxHeight)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results) { result in
                    Button {
                        onSelect(result)
                    } label: {
                        SuggestionRow(result: result)
                    }
                    .buttonStyle(.plain)

                    if result.id != results.last?.id {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .frame(height: dropdownHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }
}

private struct SuggestionRow: View {
    let result: CompanySearchResult

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Label("Fill", systemImage: "arrow.down.doc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Fill company details")
        }
        .frame(minHeight: 72, alignment: .leading)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}
