import Foundation

struct ClientCommunicationSettings: Codable, Equatable {
    static let defaultSubjectTemplate = "Invoice {{invoiceNumber}} from {{sellerName}}"
    static let defaultMessageTemplate = """
    Hello {{clientName}},

    Please find invoice {{invoiceNumber}} for {{total}} attached.

    Payment due date: {{dueDate}}

    Thank you.
    """

    private static let subjectTemplateKey = "clientCommunicationSettings.subjectTemplate"
    private static let messageTemplateKey = "clientCommunicationSettings.messageTemplate"

    var subjectTemplate: String
    var messageTemplate: String

    static func load(userDefaults: UserDefaults = .standard) -> ClientCommunicationSettings {
        let subjectTemplate = userDefaults.string(forKey: subjectTemplateKey) ?? defaultSubjectTemplate
        let messageTemplate = userDefaults.string(forKey: messageTemplateKey) ?? defaultMessageTemplate
        return ClientCommunicationSettings(subjectTemplate: subjectTemplate, messageTemplate: messageTemplate)
    }

    func save(userDefaults: UserDefaults = .standard) {
        userDefaults.set(subjectTemplate.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.subjectTemplateKey)
        userDefaults.set(messageTemplate.trimmingCharacters(in: .newlines), forKey: Self.messageTemplateKey)
    }

    static func reset(userDefaults: UserDefaults = .standard) -> ClientCommunicationSettings {
        userDefaults.removeObject(forKey: subjectTemplateKey)
        userDefaults.removeObject(forKey: messageTemplateKey)
        return load(userDefaults: userDefaults)
    }

    func subject(for invoice: Invoice, sellerName: String) -> String {
        render(subjectTemplate, invoice: invoice, sellerName: sellerName)
    }

    func message(for invoice: Invoice, sellerName: String) -> String {
        render(messageTemplate, invoice: invoice, sellerName: sellerName)
    }

    private func render(_ template: String, invoice: Invoice, sellerName: String) -> String {
        let resolvedClientName = nonEmpty(invoice.clientName, fallback: "Customer")
        let resolvedSellerName = nonEmpty(sellerName, fallback: "MyInvoice")
        let resolvedCurrency = nonEmpty(invoice.currencyCode, fallback: "EUR")
        let total = invoice.total.formatted(.currency(code: resolvedCurrency))
        let dueDate = invoice.dueDate.formatted(date: .numeric, time: .omitted)

        return template
            .replacingOccurrences(of: "{{invoiceNumber}}", with: invoice.displayTitle)
            .replacingOccurrences(of: "{{clientName}}", with: resolvedClientName)
            .replacingOccurrences(of: "{{sellerName}}", with: resolvedSellerName)
            .replacingOccurrences(of: "{{total}}", with: total)
            .replacingOccurrences(of: "{{dueDate}}", with: dueDate)
    }

    private func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
