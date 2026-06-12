import Foundation

struct ORSFClient: CompanyLookupService {
    private let baseURL = URL(string: "https://api.orsf.sk/v1")!

    func search(query: String) async throws -> [CompanySearchResult] {
        let url = try makeURL(endpoint: "search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "10")
        ])
        let response: SearchResponse = try await request(url: url)
        return response.hits
    }

    func companyDetails(ico: String) async throws -> CompanyFormData {
        let company: Company = try await request(url: makeURL(endpoint: "companies/\(ico)"))
        return CompanyFormData(company: company)
    }

    private func makeURL(endpoint: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL.appending(path: endpoint), resolvingAgainstBaseURL: false) else {
            throw ORSFError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ORSFError.invalidURL
        }
        return url
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ORSFError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw ORSFError.requestFailed(statusCode: httpResponse.statusCode, message: apiError?.message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ORSFError.decodingFailed
        }
    }
}

enum ORSFError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not build the ORSF request URL."
        case .invalidResponse:
            "ORSF returned an invalid response."
        case .decodingFailed:
            "ORSF returned data in an unexpected format."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                "ORSF request failed (HTTP \(statusCode)): \(message)"
            } else {
                "ORSF request failed with HTTP \(statusCode)."
            }
        }
    }
}
