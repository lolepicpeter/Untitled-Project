import Foundation

struct ProductItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ProductKind
    var name: String
    var description: String
    var unit: String
    var category: String
    var prices: [ProductPrice]
    var comments: String

    static var empty: ProductItem {
        ProductItem(
            id: UUID(),
            kind: .good,
            name: "",
            description: "",
            unit: "pcs.",
            category: "General",
            prices: [.empty],
            comments: ""
        )
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled product" : trimmedName
    }

    var primaryPrice: ProductPrice {
        prices.first ?? .empty
    }
}

enum ProductKind: String, CaseIterable, Identifiable, Codable {
    case good
    case service

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: "Good"
        case .service: "Service"
        }
    }
}

enum ProductPriceType: String, CaseIterable, Identifiable, Codable {
    case net
    case gross

    var id: String { rawValue }

    var title: String {
        switch self {
        case .net: "Net Price"
        case .gross: "Gross Price"
        }
    }
}

struct ProductPrice: Identifiable, Codable, Equatable {
    var id: UUID
    var customerCategory: String
    var priceType: ProductPriceType
    var quantity: Double
    var currencyCode: String
    var netPrice: Double
    var taxRate: Double

    static var empty: ProductPrice {
        let defaults = InvoiceDefaults.load()
        return ProductPrice(
            id: UUID(),
            customerCategory: "General",
            priceType: .net,
            quantity: 1,
            currencyCode: defaults.normalizedCurrencyCode,
            netPrice: 0,
            taxRate: defaults.vatRate
        )
    }

    var grossPrice: Double {
        netPrice * (1 + taxRate / 100)
    }
}
