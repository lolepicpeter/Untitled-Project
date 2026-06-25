import Foundation

struct AllegroOrderEvent: Decodable, Identifiable, Equatable {
    let id: String
    let type: String
    let occurredAt: Date?
    let checkoutFormID: String

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case occurredAt
        case order
        case checkoutForm
    }

    private enum OrderKeys: String, CodingKey {
        case checkoutForm
    }

    private enum CheckoutFormKeys: String, CodingKey {
        case id
    }

    init(id: String, type: String, occurredAt: Date?, checkoutFormID: String) {
        self.id = id
        self.type = type
        self.occurredAt = occurredAt
        self.checkoutFormID = checkoutFormID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        occurredAt = try container.decodeFlexibleDateIfPresent(forKey: .occurredAt)

        if let checkoutForm = try? container.nestedContainer(keyedBy: CheckoutFormKeys.self, forKey: .checkoutForm),
           let checkoutID = try checkoutForm.decodeIfPresent(String.self, forKey: .id) {
            checkoutFormID = checkoutID
        } else if let order = try? container.nestedContainer(keyedBy: OrderKeys.self, forKey: .order),
                  let checkoutForm = try? order.nestedContainer(keyedBy: CheckoutFormKeys.self, forKey: .checkoutForm),
                  let checkoutID = try checkoutForm.decodeIfPresent(String.self, forKey: .id) {
            checkoutFormID = checkoutID
        } else {
            checkoutFormID = ""
        }
    }
}

struct AllegroOrderEventsResponse: Decodable, Equatable {
    let events: [AllegroOrderEvent]
}

struct AllegroCheckoutForm: Decodable, Identifiable, Equatable {
    let id: String
    let revision: String
    let status: String
    let buyer: AllegroBuyer
    let invoice: AllegroInvoiceRequest?
    let lineItems: [AllegroLineItem]
    let delivery: AllegroDelivery?
    let payment: AllegroPayment?
    let summary: AllegroOrderSummary?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case status
        case buyer
        case invoice
        case lineItems
        case delivery
        case payment
        case summary
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decodeIfPresent(String.self, forKey: .revision) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        buyer = (try? container.decodeIfPresent(AllegroBuyer.self, forKey: .buyer)) ?? .empty
        invoice = try? container.decodeIfPresent(AllegroInvoiceRequest.self, forKey: .invoice)
        lineItems = (try? container.decodeIfPresent([AllegroLineItem].self, forKey: .lineItems)) ?? []
        delivery = try? container.decodeIfPresent(AllegroDelivery.self, forKey: .delivery)
        payment = try? container.decodeIfPresent(AllegroPayment.self, forKey: .payment)
        summary = try? container.decodeIfPresent(AllegroOrderSummary.self, forKey: .summary)
        updatedAt = try container.decodeFlexibleDateIfPresent(forKey: .updatedAt)
    }
}

struct AllegroBuyer: Decodable, Equatable {
    static let empty = AllegroBuyer(id: "", email: "", login: "", firstName: "", lastName: "", companyName: "", phoneNumber: "")

    let id: String
    let email: String
    let login: String
    let firstName: String
    let lastName: String
    let companyName: String
    let phoneNumber: String

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case login
        case firstName
        case lastName
        case companyName
        case phoneNumber
    }

    init(id: String, email: String, login: String, firstName: String, lastName: String, companyName: String, phoneNumber: String) {
        self.id = id
        self.email = email
        self.login = login
        self.firstName = firstName
        self.lastName = lastName
        self.companyName = companyName
        self.phoneNumber = phoneNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        login = try container.decodeIfPresent(String.self, forKey: .login) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
    }

    var displayName: String {
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !company.isEmpty { return company }

        let person = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return person.isEmpty ? login : person
    }
}

struct AllegroInvoiceRequest: Decodable, Equatable {
    let required: Bool
    let address: AllegroAddress?
    let dueDate: Date?

    private enum CodingKeys: String, CodingKey {
        case required
        case address
        case dueDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        address = try container.decodeIfPresent(AllegroAddress.self, forKey: .address)
        dueDate = try container.decodeFlexibleDateIfPresent(forKey: .dueDate)
    }
}

struct AllegroAddress: Decodable, Equatable {
    let firstName: String
    let lastName: String
    let companyName: String
    let street: String
    let city: String
    let postCode: String
    let countryCode: String
    let phoneNumber: String
    let taxID: String

    private enum CodingKeys: String, CodingKey {
        case firstName
        case lastName
        case companyName
        case street
        case city
        case postCode
        case zipCode
        case countryCode
        case phoneNumber
        case taxID
        case taxId
        case vatID
        case vatId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        street = try container.decodeIfPresent(String.self, forKey: .street) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        postCode = try container.decodeIfPresent(String.self, forKey: .postCode) ?? container.decodeIfPresent(String.self, forKey: .zipCode) ?? ""
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        taxID = try container.decodeIfPresent(String.self, forKey: .taxID) ?? container.decodeIfPresent(String.self, forKey: .taxId) ?? container.decodeIfPresent(String.self, forKey: .vatID) ?? container.decodeIfPresent(String.self, forKey: .vatId) ?? ""
    }
}

struct AllegroLineItem: Decodable, Identifiable, Equatable {
    let id: String
    let offerName: String
    let quantity: Double
    let originalPrice: AllegroAmount?
    let price: AllegroAmount?
    let tax: AllegroTax?

    private enum CodingKeys: String, CodingKey {
        case id
        case offer
        case quantity
        case originalPrice
        case price
        case tax
    }

    private enum OfferKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        quantity = try container.decodeFlexibleDoubleIfPresent(forKey: .quantity) ?? 0
        originalPrice = try? container.decodeIfPresent(AllegroAmount.self, forKey: .originalPrice)
        price = try? container.decodeIfPresent(AllegroAmount.self, forKey: .price)
        tax = try? container.decodeIfPresent(AllegroTax.self, forKey: .tax)

        if let offer = try? container.nestedContainer(keyedBy: OfferKeys.self, forKey: .offer) {
            offerName = try offer.decodeIfPresent(String.self, forKey: .name) ?? "Allegro item"
        } else {
            offerName = "Allegro item"
        }
    }
}

struct AllegroTax: Decodable, Equatable {
    let rate: Double?

    private enum CodingKeys: String, CodingKey {
        case rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rate = try container.decodeFlexibleDoubleIfPresent(forKey: .rate)
    }
}

struct AllegroDelivery: Decodable, Equatable {
    let cost: AllegroAmount?
    let address: AllegroAddress?
    let methodName: String

    private enum CodingKeys: String, CodingKey {
        case cost
        case address
        case method
    }

    private enum MethodKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cost = try container.decodeIfPresent(AllegroAmount.self, forKey: .cost)
        address = try container.decodeIfPresent(AllegroAddress.self, forKey: .address)

        if let method = try? container.nestedContainer(keyedBy: MethodKeys.self, forKey: .method) {
            methodName = try method.decodeIfPresent(String.self, forKey: .name) ?? "Delivery"
        } else {
            methodName = "Delivery"
        }
    }
}

struct AllegroPayment: Decodable, Equatable {
    let type: String
    let paidAmount: AllegroAmount?
    let finishedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case type
        case paidAmount
        case finishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        paidAmount = try container.decodeIfPresent(AllegroAmount.self, forKey: .paidAmount)
        finishedAt = try container.decodeFlexibleDateIfPresent(forKey: .finishedAt)
    }
}

struct AllegroOrderSummary: Decodable, Equatable {
    let totalToPay: AllegroAmount?
}

struct AllegroAmount: Decodable, Equatable {
    let amount: Double
    let currency: String

    private enum CodingKeys: String, CodingKey {
        case amount
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeFlexibleDoubleIfPresent(forKey: .amount) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? InvoiceDefaults.standardCurrencyCode
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try? decodeIfPresent(String.self, forKey: key), !value.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter.allegro.date(from: value) {
            return date
        }
        if let date = ISO8601DateFormatter.allegroNoFractions.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let allegro: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let allegroNoFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
