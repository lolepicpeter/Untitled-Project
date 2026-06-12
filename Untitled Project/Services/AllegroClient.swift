import Foundation

struct AllegroClient {
    private let environment: AllegroEnvironment
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(environment: AllegroEnvironment, urlSession: URLSession = .shared) {
        self.environment = environment
        self.urlSession = urlSession
        decoder = JSONDecoder()
    }

    func authorizationURL(
        clientID: String,
        redirectURI: String,
        state: String,
        scopes: [String] = [],
        codeChallenge: String? = nil,
        codeChallengeMethod: String? = nil
    ) throws -> URL {
        guard var components = URLComponents(url: environment.authorizationBaseURL, resolvingAgainstBaseURL: false) else {
            throw AllegroClientError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "redirect_uri", value: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "state", value: state)
        ]

        if !scopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }
        if let codeChallenge, !codeChallenge.isEmpty {
            queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
        }
        if let codeChallengeMethod, !codeChallengeMethod.isEmpty {
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw AllegroClientError.invalidURL
        }
        return url
    }

    func exchangeAuthorizationCode(
        code: String,
        clientID: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> AllegroOAuthTokenResponse {
        let bodyItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]
        return try await tokenRequest(bodyItems: bodyItems)
    }

    func refreshAccessToken(
        refreshToken: String,
        clientID: String
    ) async throws -> AllegroOAuthTokenResponse {
        let bodyItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        return try await tokenRequest(bodyItems: bodyItems)
    }

    func orderEvents(accessToken: String, from eventID: String? = nil, limit: Int = 100) async throws -> [AllegroOrderEvent] {
        var queryItems = [URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 1000))")]
        if let eventID, !eventID.isEmpty {
            queryItems.append(URLQueryItem(name: "from", value: eventID))
        }

        let url = try makeURL(path: "/order/events", queryItems: queryItems)
        let response: AllegroOrderEventsResponse = try await request(url: url, accessToken: accessToken)
        return response.events
    }

    func checkoutForm(id: String, accessToken: String) async throws -> AllegroCheckoutForm {
        let url = try makeURL(path: "/order/checkout-forms/\(id)", queryItems: [])
        return try await request(url: url, accessToken: accessToken)
    }

    private func tokenRequest<T: Decodable>(bodyItems: [URLQueryItem]) async throws -> T {
        var request = URLRequest(url: environment.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = bodyItems
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AllegroClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw AllegroClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AllegroClientError.decodingFailed(error)
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: environment.apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw AllegroClientError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw AllegroClientError.invalidURL
        }
        return url
    }

    private func request<T: Decodable>(url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.allegro.public.v1+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AllegroClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw AllegroClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AllegroClientError.decodingFailed(error)
        }
    }
}

enum AllegroClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not build the Allegro API URL."
        case .invalidResponse:
            "Allegro returned an invalid response."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                "Allegro request failed (HTTP \(statusCode)): \(message)"
            } else {
                "Allegro request failed with HTTP \(statusCode)."
            }
        case let .decodingFailed(error):
            "Could not read Allegro response: \(error.localizedDescription)"
        }
    }
}

enum AllegroInvoiceMapper {
    static func makeInvoiceDraft(
        from order: AllegroCheckoutForm,
        invoiceNumber: String,
        seller: CompanyFormData?,
        defaults: InvoiceDefaults = .load(),
        importedAt: Date = Date()
    ) -> Invoice {
        let issueDate = order.payment?.finishedAt ?? order.updatedAt ?? importedAt
        let invoiceAddress = order.invoice?.address ?? order.delivery?.address
        let clientName = resolvedClientName(order: order, address: invoiceAddress)
        let currencyCode = resolvedCurrency(order: order, defaults: defaults)
        let vatRate = defaults.vatRate

        var invoice = Invoice.empty(number: invoiceNumber)
        invoice.issueDate = issueDate
        invoice.deliveryDate = issueDate
        invoice.dueDate = order.invoice?.dueDate ?? Calendar.current.date(byAdding: .day, value: defaults.dueDays, to: issueDate) ?? issueDate
        invoice.clientName = clientName
        invoice.clientEmail = order.buyer.email
        invoice.currencyCode = currencyCode
        invoice.paymentMethod = paymentMethod(from: order)
        invoice.paymentInstructions = defaults.paymentInstructions
        invoice.orderNumber = order.id
        invoice.notes = notes(from: order, address: invoiceAddress)
        invoice.lineItems = lineItems(from: order, fallbackVATRate: vatRate)
        invoice.marketplaceReference = MarketplaceOrderReference(
            source: .allegro,
            orderID: order.id,
            orderNumber: order.id,
            importedAt: importedAt,
            externalStatus: order.status
        )

        if let seller {
            invoice.sellerName = seller.name
            invoice.sellerTaxID = seller.taxId
            invoice.sellerVATID = seller.vatId
        }

        if let paidAmount = order.payment?.paidAmount?.amount, paidAmount > 0 {
            invoice.payments = [
                InvoicePayment(
                    id: UUID(),
                    date: order.payment?.finishedAt ?? issueDate,
                    amount: min(paidAmount, invoice.total),
                    method: invoice.paymentMethod,
                    reference: order.id,
                    note: "Imported from Allegro"
                )
            ]
        }

        invoice.refreshStatus(on: importedAt)
        return invoice
    }

    static func makeClient(from order: AllegroCheckoutForm) -> Client {
        let address = order.invoice?.address ?? order.delivery?.address
        var client = Client.empty
        client.countryCode = address?.countryCode.isEmpty == false ? address?.countryCode ?? client.countryCode : client.countryCode
        client.companyName = resolvedClientName(order: order, address: address)
        client.email = order.buyer.email
        client.street = address?.street ?? ""
        client.city = address?.city ?? ""
        client.postalCode = address?.postCode ?? ""
        client.taxId = address?.taxID ?? ""
        client.vatId = address?.taxID ?? ""
        client.phone = address?.phoneNumber ?? order.buyer.phoneNumber
        return client
    }

    private static func lineItems(from order: AllegroCheckoutForm, fallbackVATRate: Double) -> [InvoiceLineItem] {
        var items = order.lineItems.map { item in
            let grossUnitPrice = item.price?.amount ?? item.originalPrice?.amount ?? 0
            let vatRate = item.tax?.rate ?? fallbackVATRate
            let netUnitPrice = grossUnitPrice / (1 + vatRate / 100)
            return InvoiceLineItem(
                id: UUID(),
                title: item.offerName,
                description: item.id,
                quantity: max(item.quantity, 0),
                unitPrice: netUnitPrice,
                vatRate: vatRate,
                discountPercent: 0
            )
        }

        if let deliveryCost = order.delivery?.cost, deliveryCost.amount > 0 {
            let netDelivery = deliveryCost.amount / (1 + fallbackVATRate / 100)
            items.append(
                InvoiceLineItem(
                    id: UUID(),
                    title: order.delivery?.methodName ?? "Delivery",
                    description: "Allegro delivery",
                    quantity: 1,
                    unitPrice: netDelivery,
                    vatRate: fallbackVATRate,
                    discountPercent: 0
                )
            )
        }

        return items.isEmpty ? [.empty(vatRate: fallbackVATRate)] : items
    }

    private static func resolvedClientName(order: AllegroCheckoutForm, address: AllegroAddress?) -> String {
        if let companyName = address?.companyName.trimmingCharacters(in: .whitespacesAndNewlines), !companyName.isEmpty {
            return companyName
        }

        let addressName = [address?.firstName, address?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !addressName.isEmpty {
            return addressName
        }

        return order.buyer.displayName
    }

    private static func resolvedCurrency(order: AllegroCheckoutForm, defaults: InvoiceDefaults) -> String {
        order.summary?.totalToPay?.currency ??
        order.payment?.paidAmount?.currency ??
        order.lineItems.first?.price?.currency ??
        defaults.normalizedCurrencyCode
    }

    private static func paymentMethod(from order: AllegroCheckoutForm) -> String {
        let type = order.payment?.type.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return type.isEmpty ? "Allegro payment" : "Allegro \(type)"
    }

    private static func notes(from order: AllegroCheckoutForm, address: AllegroAddress?) -> String {
        var parts = ["Imported from Allegro order \(order.id)."]
        if order.invoice?.required == true {
            parts.append("Buyer requested an invoice.")
        }
        if let taxID = address?.taxID, !taxID.isEmpty {
            parts.append("Buyer tax ID: \(taxID)")
        }
        return parts.joined(separator: "\n")
    }
}
