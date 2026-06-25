import Foundation
import Observation

struct InvoiceDefaults: Codable, Equatable {
    static let standardDueDays = 14
    static let standardVATRate = 20.0
    static let standardCurrencyCode = "EUR"
    static let standardPaymentMethod = "Bank transfer"
    static let supportedCurrencyCodes = ["EUR", "CZK", "USD", "GBP", "PLN", "HUF", "CHF", "SEK", "NOK", "DKK"]
    static let supportedPaymentMethods = ["Bank transfer", "Cash", "Card", "Cash on delivery", "Other"]

    private static let dueDaysKey = "invoiceDefaults.dueDays"
    private static let vatRateKey = "invoiceDefaults.vatRate"
    private static let currencyCodeKey = "invoiceDefaults.currencyCode"
    private static let paymentMethodKey = "invoiceDefaults.paymentMethod"
    private static let paymentInstructionsKey = "invoiceDefaults.paymentInstructions"

    var dueDays: Int
    var vatRate: Double
    var currencyCode: String
    var paymentMethod: String
    var paymentInstructions: String

    var normalizedCurrencyCode: String {
        Self.normalizedCurrencyCode(currencyCode)
    }

    static func load(userDefaults: UserDefaults = .standard) -> InvoiceDefaults {
        let rawDueDays = userDefaults.object(forKey: dueDaysKey) as? Int ?? standardDueDays
        let rawVATRate = userDefaults.object(forKey: vatRateKey) as? Double ?? standardVATRate
        let rawCurrencyCode = userDefaults.string(forKey: currencyCodeKey) ?? standardCurrencyCode
        let rawPaymentMethod = userDefaults.string(forKey: paymentMethodKey) ?? standardPaymentMethod
        let rawPaymentInstructions = userDefaults.string(forKey: paymentInstructionsKey) ?? ""
        return InvoiceDefaults(
            dueDays: min(max(rawDueDays, 0), 120),
            vatRate: normalizedVATRate(rawVATRate),
            currencyCode: normalizedCurrencyCode(rawCurrencyCode),
            paymentMethod: normalizedPaymentMethod(rawPaymentMethod),
            paymentInstructions: rawPaymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func save(userDefaults: UserDefaults = .standard) {
        userDefaults.set(min(max(dueDays, 0), 120), forKey: Self.dueDaysKey)
        userDefaults.set(Self.normalizedVATRate(vatRate), forKey: Self.vatRateKey)
        userDefaults.set(normalizedCurrencyCode, forKey: Self.currencyCodeKey)
        userDefaults.set(Self.normalizedPaymentMethod(paymentMethod), forKey: Self.paymentMethodKey)
        userDefaults.set(paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.paymentInstructionsKey)
    }

    static func reset(userDefaults: UserDefaults = .standard) -> InvoiceDefaults {
        userDefaults.removeObject(forKey: dueDaysKey)
        userDefaults.removeObject(forKey: vatRateKey)
        userDefaults.removeObject(forKey: currencyCodeKey)
        userDefaults.removeObject(forKey: paymentMethodKey)
        userDefaults.removeObject(forKey: paymentInstructionsKey)
        return load(userDefaults: userDefaults)
    }

    private static func normalizedVATRate(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func normalizedCurrencyCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? standardCurrencyCode : trimmed
    }

    private static func normalizedPaymentMethod(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? standardPaymentMethod : trimmed
    }
}

struct InvoiceNumberingSettings: Codable, Equatable {
    static let standardPrefix = "INV"
    static let standardNextNumber = 1
    static let standardMinimumDigits = 4

    private static let prefixKey = "invoiceNumbering.prefix"
    private static let includesYearKey = "invoiceNumbering.includesYear"
    private static let nextNumberKey = "invoiceNumbering.nextNumber"
    private static let minimumDigitsKey = "invoiceNumbering.minimumDigits"

    var prefix: String
    var includesYear: Bool
    var nextNumber: Int
    var minimumDigits: Int

    var resolvedPrefix: String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.standardPrefix : trimmed
    }

    var normalizedNextNumber: Int {
        max(nextNumber, 1)
    }

    var normalizedMinimumDigits: Int {
        min(max(minimumDigits, 1), 8)
    }

    static func load(userDefaults: UserDefaults = .standard) -> InvoiceNumberingSettings {
        InvoiceNumberingSettings(
            prefix: userDefaults.string(forKey: prefixKey) ?? standardPrefix,
            includesYear: userDefaults.object(forKey: includesYearKey) as? Bool ?? true,
            nextNumber: max(userDefaults.object(forKey: nextNumberKey) as? Int ?? standardNextNumber, 1),
            minimumDigits: min(max(userDefaults.object(forKey: minimumDigitsKey) as? Int ?? standardMinimumDigits, 1), 8)
        )
    }

    func save(userDefaults: UserDefaults = .standard) {
        userDefaults.set(resolvedPrefix, forKey: Self.prefixKey)
        userDefaults.set(includesYear, forKey: Self.includesYearKey)
        userDefaults.set(normalizedNextNumber, forKey: Self.nextNumberKey)
        userDefaults.set(normalizedMinimumDigits, forKey: Self.minimumDigitsKey)
    }

    static func reset(userDefaults: UserDefaults = .standard) -> InvoiceNumberingSettings {
        userDefaults.removeObject(forKey: prefixKey)
        userDefaults.removeObject(forKey: includesYearKey)
        userDefaults.removeObject(forKey: nextNumberKey)
        userDefaults.removeObject(forKey: minimumDigitsKey)
        return load(userDefaults: userDefaults)
    }

    func formattedNumber(sequence: Int, date: Date = Date()) -> String {
        let sequenceText = String(format: "%0\(normalizedMinimumDigits)d", max(sequence, 1))
        if includesYear {
            let year = Calendar.current.component(.year, from: date)
            return "\(resolvedPrefix)-\(year)-\(sequenceText)"
        }
        return "\(resolvedPrefix)-\(sequenceText)"
    }

    func nextSequence(from invoices: [Invoice], date: Date = Date()) -> Int {
        let inferredSequence = invoices.compactMap { sequence(from: $0.number, date: date) }.max().map { $0 + 1 } ?? 1
        return max(normalizedNextNumber, inferredSequence)
    }

    private func sequence(from invoiceNumber: String, date: Date) -> Int? {
        let trimmedNumber = invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedPrefix: String
        if includesYear {
            let year = Calendar.current.component(.year, from: date)
            expectedPrefix = "\(resolvedPrefix)-\(year)-"
        } else {
            expectedPrefix = "\(resolvedPrefix)-"
        }

        guard trimmedNumber.hasPrefix(expectedPrefix) else { return nil }
        return Int(trimmedNumber.dropFirst(expectedPrefix.count))
    }
}

@MainActor
@Observable
final class InvoiceStore {
    var invoices: [Invoice] = []

    @ObservationIgnored private let storageKey = "invoices"
    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func load() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            invoices = []
            return
        }

        invoices = (try? JSONDecoder().decode([Invoice].self, from: data)) ?? []
        sortInvoices()
    }

    func save(_ invoice: Invoice) {
        saveAll([invoice])
    }

    func saveAll(_ invoicesToSave: [Invoice]) {
        guard !invoicesToSave.isEmpty else { return }
        for invoice in invoicesToSave {
            if let index = invoices.firstIndex(where: { $0.id == invoice.id }) {
                invoices[index] = invoice
            } else {
                invoices.append(invoice)
            }
        }

        sortInvoices()
        persist()
    }

    func delete(_ invoice: Invoice) {
        invoices.removeAll { $0.id == invoice.id }
        persist()
    }

    func replaceAll(_ newInvoices: [Invoice]) {
        invoices = newInvoices
        sortInvoices()
        persist()
    }

    func nextInvoiceNumber() -> String {
        let settings = InvoiceNumberingSettings.load(userDefaults: userDefaults)
        let sequence = settings.nextSequence(from: invoices)
        return settings.formattedNumber(sequence: sequence)
    }

    func newInvoiceDraft() -> Invoice {
        let defaults = InvoiceDefaults.load(userDefaults: userDefaults)
        let sellerStore = MyCompanyProfileStore(userDefaults: userDefaults)
        var invoice = Invoice.empty(number: nextInvoiceNumber())
        invoice.currencyCode = defaults.normalizedCurrencyCode
        invoice.paymentMethod = defaults.paymentMethod
        invoice.paymentInstructions = defaults.paymentInstructions
        invoice.dueDate = Calendar.current.date(byAdding: .day, value: defaults.dueDays, to: invoice.issueDate) ?? invoice.dueDate
        invoice.lineItems = [InvoiceLineItem.empty(vatRate: defaults.vatRate)]

        if sellerStore.hasSavedProfile {
            applySellerProfile(sellerStore.company, to: &invoice)
        }

        return invoice
    }

    func newInvoiceDraft(for client: Client) -> Invoice {
        var invoice = newInvoiceDraft()
        invoice.clientID = client.id
        invoice.clientName = client.displayName
        invoice.clientEmail = client.email
        return invoice
    }

    func duplicateDraft(from source: Invoice) -> Invoice {
        let defaults = InvoiceDefaults.load(userDefaults: userDefaults)
        let today = Date()
        var invoice = source
        invoice.id = UUID()
        invoice.number = nextInvoiceNumber()
        invoice.status = .draft
        invoice.issueDate = today
        invoice.deliveryDate = today
        invoice.dueDate = Calendar.current.date(byAdding: .day, value: defaults.dueDays, to: today) ?? today
        invoice.payments = []
        invoice.marketplaceReference = nil
        invoice.lineItems = invoice.lineItems.map { item in
            InvoiceLineItem(
                id: UUID(),
                title: item.title,
                description: item.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                vatRate: item.vatRate,
                discountPercent: item.discountPercent
            )
        }
        return invoice
    }

    private func applySellerProfile(_ company: CompanyFormData, to invoice: inout Invoice) {
        invoice.sellerName = company.name
        invoice.sellerTaxID = company.taxId
        invoice.sellerVATID = company.vatId
    }

    private func sortInvoices() {
        invoices.sort { lhs, rhs in
            if lhs.issueDate == rhs.issueDate {
                return lhs.number.localizedStandardCompare(rhs.number) == .orderedDescending
            }
            return lhs.issueDate > rhs.issueDate
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(invoices) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
