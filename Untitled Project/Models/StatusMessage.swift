import SwiftUI

struct StatusMessage {
    let text: String
    let systemImage: String
    let color: Color

    init(text: String, systemImage: String, color: Color) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    init(error: Error) {
        if let apiError = error as? ORSFError {
            self.text = apiError.localizedDescription
        } else {
            self.text = error.localizedDescription
        }
        self.systemImage = "exclamationmark.triangle"
        self.color = .red
    }
}
