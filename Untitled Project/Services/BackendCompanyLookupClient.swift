import Foundation

struct BackendCompanyLookupClient: CompanyLookupService {
    private let country: CompanyLookupCountry
    private let baseURL: URL

    init(country: CompanyLookupCountry, baseURL: URL = BackendConfiguration.baseURL) {
        self.country = country
        self.baseURL = baseURL
    }

    func search(query: String) async throws -> [CompanySearchResult] {
        let url = try makeURL(endpoint: "v1/companies/search", queryItems: [
            URLQueryItem(name: "country", value: country.code),
            URLQueryItem(name: "q", value: query)
        ])
        let response: BackendSearchResponse = try await request(url: url)
        return response.results
    }

    func companyDetails(ico: String) async throws -> CompanyFormData {
        let url = try makeURL(endpoint: "v1/companies/details", queryItems: [
            URLQueryItem(name: "country", value: country.code),
            URLQueryItem(name: "id", value: ico)
        ])
        let response: BackendDetailsResponse = try await request(url: url)
        return CompanyFormData(backendCompany: response.company)
    }

    private func makeURL(endpoint: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appending(path: endpoint), resolvingAgainstBaseURL: false) else {
            throw BackendLookupError.invalidURL
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw BackendLookupError.invalidURL
        }
        return url
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendLookupError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(BackendErrorResponse.self, from: data)
            throw BackendLookupError.requestFailed(statusCode: httpResponse.statusCode, message: apiError?.error.message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendLookupError.decodingFailed
        }
    }
}

struct BackendConfiguration {
    static let baseURL = URL(string: "http://localhost:3000")!
}

private struct BackendSearchResponse: Decodable {
    let results: [CompanySearchResult]
}

private struct BackendDetailsResponse: Decodable {
    let company: BackendCompany
}

private struct BackendCompany: Decodable {
    let name: String
    let companyId: String
    let taxId: String
    let vatId: String
    let legalForm: String
    let status: String
    let street: String
    let city: String
    let postalCode: String
    let country: String
    let establishedOn: String
    let register: String
    let industryCode: String
    let vatPayer: String
    let businessActivities: String
}

private struct BackendErrorResponse: Decodable {
    let error: BackendErrorBody
}

private struct BackendErrorBody: Decodable {
    let status: Int
    let message: String
}

enum BackendLookupError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not build the backend request URL."
        case .invalidResponse:
            "The lookup backend returned an invalid response."
        case .decodingFailed:
            "The lookup backend returned data in an unexpected format."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                "Lookup backend request failed (HTTP \(statusCode)): \(message)"
            } else {
                "Lookup backend request failed with HTTP \(statusCode)."
            }
        }
    }
}

extension CompanyFormData {
    fileprivate init(backendCompany company: BackendCompany) {
        name = company.name
        ico = company.companyId
        taxId = company.taxId
        vatId = company.vatId
        legalForm = company.legalForm
        status = company.status
        street = company.street
        city = company.city
        postalCode = company.postalCode
        country = company.country
        establishedOn = company.establishedOn
        register = company.register
        nace = company.industryCode
        vatPayer = company.vatPayer
        businessActivities = company.businessActivities
    }
}
