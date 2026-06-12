import SwiftUI

struct FieldView: View {
    let title: String
    @Binding var value: String
    let isEditable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditable {
                TextField(title, text: $value)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(value.displayValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )
            }
        }
    }
}
