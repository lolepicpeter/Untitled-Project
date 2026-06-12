import Foundation

struct Invoice: Identifiable, Codable, Equatable {
    var id: UUID
    var number: String
    var documentType: InvoiceDocumentType
    var sellerName: String
    var sellerTaxID: String
    var sellerVATID: String
    var issueDate: Date
    var deliveryDate: Date
    var dueDate: Date
    var clientID: UUID?
    var clientName: String
    var clientEmail: String
    var currencyCode: String
    var status: InvoiceStatus
    var discountPercent: Double
    var orderNumber: String
    var paymentMethod: String
    var paymentInstructions: String
    var notes: String
    var lineItems: [InvoiceLineItem]
    var payments: [InvoicePayment]
    var marketplaceReference: MarketplaceOrderReference?

    init(
        id: UUID,
        number: String,
        documentType: InvoiceDocumentType,
        sellerName: String,
        sellerTaxID: String,
        sellerVATID: String,
        issueDate: Date,
        deliveryDate: Date,
        dueDate: Date,
        clientID: UUID?,
        clientName: String,
        clientEmail: String,
        currencyCode: String,
        status: InvoiceStatus,
        discountPercent: Double,
        orderNumber: String,
        paymentMethod: String,
        paymentInstructions: String,
        notes: String,
        lineItems: [InvoiceLineItem],
        payments: [InvoicePayment],
        marketplaceReference: MarketplaceOrderReference? = nil
    ) {
        self.id = id
        self.number = number
        self.documentType = documentType
        self.sellerName = sellerName
        self.sellerTaxID = sellerTaxID
        self.sellerVATID = sellerVATID
        self.issueDate = issueDate
        self.deliveryDate = deliveryDate
        self.dueDate = dueDate
        self.clientID = clientID
        self.clientName = clientName
        self.clientEmail = clientEmail
        self.currencyCode = currencyCode
        self.status = status
        self.discountPercent = discountPercent
        self.orderNumber = orderNumber
        self.paymentMethod = paymentMethod
        self.paymentInstructions = paymentInstructions
        self.notes = notes
        self.lineItems = lineItems
        self.payments = payments
        self.marketplaceReference = marketplaceReference
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case documentType
        case sellerName
        case sellerTaxID
        case sellerVATID
        case issueDate
        case deliveryDate
        case dueDate
        case clientID
        case clientName
        case clientEmail
        case currencyCode
        case status
        case discountPercent
        case orderNumber
        case paymentMethod
        case paymentInstructions
        case notes
        case lineItems
        case payments
        case marketplaceReference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        number = try container.decode(String.self, forKey: .number)
        let decodedDocumentType = try container.decodeIfPresent(String.self, forKey: .documentType)
        documentType = decodedDocumentType.flatMap(InvoiceDocumentType.init(rawValue:)) ?? .invoice
        sellerName = try container.decodeIfPresent(String.self, forKey: .sellerName) ?? ""
        sellerTaxID = try container.decodeIfPresent(String.self, forKey: .sellerTaxID) ?? ""
        sellerVATID = try container.decodeIfPresent(String.self, forKey: .sellerVATID) ?? ""
        issueDate = try container.decode(Date.self, forKey: .issueDate)
        deliveryDate = try container.decodeIfPresent(Date.self, forKey: .deliveryDate) ?? issueDate
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        clientID = try container.decodeIfPresent(UUID.self, forKey: .clientID)
        clientName = try container.decode(String.self, forKey: .clientName)
        clientEmail = try container.decode(String.self, forKey: .clientEmail)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        status = try container.decode(InvoiceStatus.self, forKey: .status)
        discountPercent = try container.decodeIfPresent(Double.self, forKey: .discountPercent) ?? 0
        orderNumber = try container.decodeIfPresent(String.self, forKey: .orderNumber) ?? ""
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod) ?? InvoiceDefaults.standardPaymentMethod
        paymentInstructions = try container.decodeIfPresent(String.self, forKey: .paymentInstructions) ?? ""
        notes = try container.decode(String.self, forKey: .notes)
        lineItems = try container.decode([InvoiceLineItem].self, forKey: .lineItems)
        payments = try container.decodeIfPresent([InvoicePayment].self, forKey: .payments) ?? []
        marketplaceReference = try container.decodeIfPresent(MarketplaceOrderReference.self, forKey: .marketplaceReference)
    }

    static func empty(number: String) -> Invoice {
        let today = Date()
        let defaults = InvoiceDefaults.load()
        return Invoice(
            id: UUID(),
            number: number,
            documentType: .invoice,
            sellerName: "",
            sellerTaxID: "",
            sellerVATID: "",
            issueDate: today,
            deliveryDate: today,
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today,
            clientID: nil,
            clientName: "",
            clientEmail: "",
            currencyCode: "EUR",
            status: .draft,
            discountPercent: 0,
            orderNumber: "",
            paymentMethod: defaults.paymentMethod,
            paymentInstructions: defaults.paymentInstructions,
            notes: "",
            lineItems: [.empty],
            payments: []
        )
    }

    var displayTitle: String {
        number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Invoice" : number
    }

    var subtitle: String {
        let client = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalText = total.formatted(.currency(code: currencyCode))
        return client.isEmpty ? totalText : "\(client) • \(totalText)"
    }

    var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.netTotal }
    }

    var discountAmount: Double {
        subtotal * min(max(discountPercent, 0), 100) / 100
    }

    var netTotal: Double {
        max(subtotal - discountAmount, 0)
    }

    var vatTotal: Double {
        let discountMultiplier = subtotal > 0 ? netTotal / subtotal : 1
        return lineItems.reduce(0) { $0 + ($1.vatTotal * discountMultiplier) }
    }

    var total: Double {
        netTotal + vatTotal
    }

    var paidTotal: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    var balanceDue: Double {
        max(total - paidTotal, 0)
    }

    var displayStatus: InvoiceStatus {
        resolvedStatus(on: Date())
    }

    var canDiscardDraft: Bool {
        displayStatus == .draft
    }

    func resolvedStatus(on date: Date = Date()) -> InvoiceStatus {
        switch status {
        case .draft, .cancelled:
            return status
        case .sent, .paid, .overdue:
            if total > 0, balanceDue <= 0.005 {
                return .paid
            }

            let calendar = Calendar.current
            if balanceDue > 0.005,
               calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: date) {
                return .overdue
            }

            return .sent
        }
    }

    mutating func issue(on date: Date = Date()) {
        if status == .draft {
            status = .sent
        }
        refreshStatus(on: date)
    }

    mutating func refreshStatus(on date: Date = Date()) {
        status = resolvedStatus(on: date)
    }
}

struct InvoicePayment: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var amount: Double
    var method: String
    var reference: String
    var note: String

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case amount
        case method
        case reference
        case note
    }

    init(id: UUID, date: Date, amount: Double, method: String, reference: String, note: String) {
        self.id = id
        self.date = date
        self.amount = amount
        self.method = method
        self.reference = reference
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        amount = try container.decode(Double.self, forKey: .amount)
        method = try container.decode(String.self, forKey: .method)
        reference = try container.decodeIfPresent(String.self, forKey: .reference) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum InvoiceDocumentType: String, CaseIterable, Identifiable, Codable {
    case invoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invoice: "Invoice"
        }
    }
}

enum InvoiceStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case sent
    case paid
    case overdue
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .sent: "Issued"
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .cancelled: "Cancelled"
        }
    }
}

struct InvoiceLineItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var description: String
    var quantity: Double
    var unitPrice: Double
    var vatRate: Double
    var discountPercent: Double

    static var empty: InvoiceLineItem {
        empty(vatRate: InvoiceDefaults.load().vatRate)
    }

    static func empty(vatRate: Double) -> InvoiceLineItem {
        InvoiceLineItem(
            id: UUID(),
            title: "",
            description: "",
            quantity: 1,
            unitPrice: 0,
            vatRate: vatRate,
            discountPercent: 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case quantity
        case unitPrice
        case vatRate
        case discountPercent
    }

    init(id: UUID, title: String, description: String, quantity: Double, unitPrice: Double, vatRate: Double, discountPercent: Double) {
        self.id = id
        self.title = title
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.vatRate = vatRate
        self.discountPercent = discountPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        quantity = try container.decode(Double.self, forKey: .quantity)
        unitPrice = try container.decode(Double.self, forKey: .unitPrice)
        vatRate = try container.decode(Double.self, forKey: .vatRate)
        discountPercent = try container.decodeIfPresent(Double.self, forKey: .discountPercent) ?? 0
    }

    var subtotal: Double {
        quantity * unitPrice
    }

    var discountAmount: Double {
        subtotal * min(max(discountPercent, 0), 100) / 100
    }

    var netTotal: Double {
        max(subtotal - discountAmount, 0)
    }

    var vatTotal: Double {
        netTotal * vatRate / 100
    }

    var grossTotal: Double {
        netTotal + vatTotal
    }
}
