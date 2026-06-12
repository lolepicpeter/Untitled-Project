import Foundation

struct ARESClient: CompanyLookupService {
    private let baseURL = URL(string: "https://ares.gov.cz/ekonomicke-subjekty-v-be/rest")!

    func search(query: String) async throws -> [CompanySearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isICO {
            let company = try await economicSubject(ico: trimmedQuery)
            return [company.searchResult]
        }

        let exactResults = try await searchByName(trimmedQuery)
        let rankedExactResults = rankedFallbackResults(exactResults, for: trimmedQuery)
        if !rankedExactResults.isEmpty {
            return Array(rankedExactResults.prefix(10))
        }

        for fallbackQuery in fallbackSearchTerms(for: trimmedQuery) {
            let fallbackResults = try await searchByName(fallbackQuery, limit: 100)
            let rankedResults = rankedFallbackResults(fallbackResults, for: trimmedQuery)
            if !rankedResults.isEmpty {
                return Array(rankedResults.prefix(10))
            }
        }

        return []
    }

    func companyDetails(ico: String) async throws -> CompanyFormData {
        let company = try await economicSubject(ico: ico)
        return CompanyFormData(aresCompany: company)
    }

    private func searchByName(_ query: String, limit: Int = 10) async throws -> [CompanySearchResult] {
        let url = baseURL.appending(path: "ekonomicke-subjekty/vyhledat")
        let body = ARESSearchRequest(obchodniJmeno: query, pocet: limit)

        do {
            let response: ARESSearchResponse = try await request(url: url, method: "POST", body: body)
            return response.ekonomickeSubjekty?.map(\.searchResult) ?? []
        } catch let error as ARESError where error.isTooManyResults {
            return []
        }
    }

    private func rankedFallbackResults(_ results: [CompanySearchResult], for query: String) -> [CompanySearchResult] {
        let tokens = searchTokens(for: query)
        guard !tokens.isEmpty else { return results }

        return results
            .filter { result in
                let nameWords = result.name.normalizedCompanySearchWords

                if tokens.count == 1, let token = tokens.first {
                    return result.name.firstSearchableCompanySearchWord?.hasPrefix(token) == true
                }

                return tokens.allSatisfy { token in
                    nameWords.contains { $0.hasPrefix(token) }
                }
            }
            .sorted { first, second in
                let firstName = first.name.normalizedForCompanySearch
                let secondName = second.name.normalizedForCompanySearch
                let normalizedQuery = query.normalizedForCompanySearch

                if firstName.hasPrefix(normalizedQuery) != secondName.hasPrefix(normalizedQuery) {
                    return firstName.hasPrefix(normalizedQuery)
                }
                return firstName < secondName
            }
    }

    private func searchTokens(for query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).normalizedForCompanySearch }
            .filter { $0.count >= 2 }
    }

    private func fallbackSearchTerms(for query: String) -> [String] {
        var candidates: [String] = []
        let words = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 3 }

        func appendCandidate(_ candidate: String) {
            guard candidate != query, !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        for word in words {
            appendCandidate(word)
            if word.count >= 4 {
                appendCandidate("\(word)a")
            }
        }

        let baseQuery = words.first ?? query
        if baseQuery.count > 3 {
            for length in stride(from: baseQuery.count - 1, through: 3, by: -1) {
                appendCandidate(String(baseQuery.prefix(length)))
            }
        }

        return candidates
    }

    private func economicSubject(ico: String) async throws -> ARESEconomicSubject {
        try await request(url: baseURL.appending(path: "ekonomicke-subjekty/\(ico)"), method: "GET")
    }

    private func request<T: Decodable>(url: URL, method: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(request: request)
    }

    private func request<T: Decodable, Body: Encodable>(url: URL, method: String, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await execute(request: request)
    }

    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ARESError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(ARESErrorResponse.self, from: data)
            throw ARESError.requestFailed(statusCode: httpResponse.statusCode, message: apiError?.popis)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ARESError.decodingFailed
        }
    }
}

private struct ARESSearchRequest: Encodable {
    let obchodniJmeno: String
    let pocet: Int
}

private extension String {
    var normalizedForCompanySearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
    }

    var normalizedCompanySearchWords: [String] {
        normalizedForCompanySearch
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    var firstSearchableCompanySearchWord: String? {
        normalizedCompanySearchWords.first { !Self.ignoredSearchPrefixes.contains($0) }
    }

    private static var ignoredSearchPrefixes: Set<String> {
        ["ing", "mgr", "bc", "mudr", "judr", "phdr", "mga", "mvdr", "doc", "prof"]
    }
}

enum ARESError: LocalizedError {
    case invalidResponse
    case decodingFailed
    case requestFailed(statusCode: Int, message: String?)

    var isTooManyResults: Bool {
        guard case let .requestFailed(statusCode, message) = self, statusCode == 400 else {
            return false
        }

        return message?.localizedCaseInsensitiveContains("příliš mnoho výsledků") == true
            || message?.localizedCaseInsensitiveContains("maximálně 1 000") == true
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "ARES returned an invalid response."
        case .decodingFailed:
            "ARES returned data in an unexpected format."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                "ARES request failed (HTTP \(statusCode)): \(message)"
            } else {
                "ARES request failed with HTTP \(statusCode)."
            }
        }
    }
}
