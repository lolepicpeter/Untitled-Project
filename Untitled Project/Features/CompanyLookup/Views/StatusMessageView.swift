import SwiftUI

struct StatusMessageView: View {
    let message: StatusMessage?

    var body: some View {
        if let message {
            Label(message.text, systemImage: message.systemImage)
                .foregroundStyle(message.color)
                .font(.callout)
        }
    }
}
