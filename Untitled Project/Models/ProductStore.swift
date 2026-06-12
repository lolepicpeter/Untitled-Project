import Foundation
import Observation

@Observable
final class ProductStore {
    private let storageKey = "savedProducts"
    private(set) var products: [ProductItem] = []

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            products = []
            return
        }

        do {
            products = try JSONDecoder().decode([ProductItem].self, from: data).sortedForDisplay()
        } catch {
            products = []
        }
    }

    func save(_ product: ProductItem) {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        } else {
            products.append(product)
        }
        products = products.sortedForDisplay()
        persist()
    }

    func delete(_ product: ProductItem) {
        products.removeAll { $0.id == product.id }
        persist()
    }

    func replaceAll(_ newProducts: [ProductItem]) {
        products = newProducts.sortedForDisplay()
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(products)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            assertionFailure("Failed to persist products: \(error.localizedDescription)")
        }
    }
}

private extension Array where Element == ProductItem {
    func sortedForDisplay() -> [ProductItem] {
        sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
