import Foundation

struct CompanyLookupServiceRegistry {
    static let defaultServices: [CompanyLookupCountry: CompanyLookupService] = [
        .slovakia: BackendCompanyLookupClient(country: .slovakia),
        .czechRepublic: BackendCompanyLookupClient(country: .czechRepublic),
        .norway: BackendCompanyLookupClient(country: .norway),
        .finland: BackendCompanyLookupClient(country: .finland)
    ]

    static func service(for country: CompanyLookupCountry) throws -> CompanyLookupService {
        guard let service = defaultServices[country] else {
            throw CompanyLookupError.unsupportedCountry(country.rawValue)
        }
        return service
    }
}
