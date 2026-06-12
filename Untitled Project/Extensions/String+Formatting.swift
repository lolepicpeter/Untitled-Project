import Foundation

extension String {
    var displayValue: String {
        isEmpty ? "Not available" : self
    }

    var isICO: Bool {
        (6...8).contains(count) && allSatisfy(\.isNumber)
    }

    var formattedISODate: String {
        if let date = ISO8601DateFormatter().date(from: self) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }

        return String(prefix(10))
    }
}
