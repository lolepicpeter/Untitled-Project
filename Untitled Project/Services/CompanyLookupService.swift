import Foundation

protocol CompanyLookupService {
    func search(query: String) async throws -> [CompanySearchResult]
    func companyDetails(ico: String) async throws -> CompanyFormData
}
