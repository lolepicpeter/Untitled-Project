import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class CompanyLookupViewModel {
    var selectedCountry: CompanyLookupCountry = .slovakia {
        didSet { resetForCountryChange() }
    }
    var query = ""
    var searchResults: [CompanySearchResult] = []
    var company = CompanyFormData.empty
    var isSearching = false
    var isLoadingDetails = false
    var isShowingSuggestions = false
    var hasCompletedSuggestionSearch = false
    var shouldSkipNextSuggestion = false
    var message: StatusMessage?

    @ObservationIgnored private let services: [CompanyLookupCountry: CompanyLookupService]
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?

    var canSearch: Bool {
        selectedCountry.isAutomaticLookupSupported
            && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSearching
            && !isLoadingDetails
    }

    var isManualEntry: Bool {
        !selectedCountry.isAutomaticLookupSupported
    }

    init(services: [CompanyLookupCountry: CompanyLookupService]? = nil) {
        self.services = services ?? CompanyLookupServiceRegistry.defaultServices
    }

    func scheduleSuggestions(for query: String) {
        suggestionTask?.cancel()

        guard selectedCountry.isAutomaticLookupSupported else {
            searchResults = []
            isShowingSuggestions = false
            hasCompletedSuggestionSearch = false
            return
        }

        if shouldSkipNextSuggestion {
            shouldSkipNextSuggestion = false
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            searchResults = []
            isShowingSuggestions = false
            hasCompletedSuggestionSearch = false
            message = nil
            return
        }

        let country = selectedCountry
        if searchGuidance(for: trimmedQuery, country: country) != nil {
            searchResults = []
            isShowingSuggestions = false
            hasCompletedSuggestionSearch = false
            message = nil
            return
        }

        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await self?.fetchSuggestions(for: trimmedQuery, country: country)
        }
    }

    func search() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedCountry.isAutomaticLookupSupported, !trimmedQuery.isEmpty else { return }

        suggestionTask?.cancel()
        let country = selectedCountry
        hasCompletedSuggestionSearch = false

        if let guidance = searchGuidance(for: trimmedQuery, country: country) {
            searchResults = []
            isShowingSuggestions = false
            hasCompletedSuggestionSearch = false
            message = guidance
            return
        }

        Task {
            await fetchSuggestions(for: trimmedQuery, country: country)

            if searchResults.isEmpty {
                message = StatusMessage(text: "No company matches found for \"\(trimmedQuery)\" in \(country.rawValue). Try a registration number or a more specific name.", systemImage: "exclamationmark.magnifyingglass", color: .secondary)
            } else if trimmedQuery.isICO, let result = searchResults.first {
                try? await fillCompanyDetails(ico: result.ico, country: country)
            } else {
                message = StatusMessage(text: "Select a company match to fill the details.", systemImage: "list.bullet", color: .secondary)
            }
        }
    }

    func selectSuggestion(_ result: CompanySearchResult) {
        suggestionTask?.cancel()
        shouldSkipNextSuggestion = true
        query = result.name
        searchResults = []
        isShowingSuggestions = false
        hasCompletedSuggestionSearch = false
        loadCompany(ico: result.ico)
    }

    func loadCompany(ico: String) {
        let country = selectedCountry
        Task {
            do {
                try await fillCompanyDetails(ico: ico, country: country)
            } catch {
                message = StatusMessage(error: error)
            }
        }
    }

    func searchResults(for query: String, country: CompanyLookupCountry) async throws -> [CompanySearchResult] {
        try await service(for: country).search(query: query)
    }

    func loadCompanyDetails(ico: String, country: CompanyLookupCountry) async throws -> CompanyFormData {
        try await service(for: country).companyDetails(ico: ico)
    }

    func clear() {
        suggestionTask?.cancel()
        query = ""
        searchResults = []
        isShowingSuggestions = false
        hasCompletedSuggestionSearch = false
        company = .empty
        message = nil
    }

    private func searchGuidance(for query: String, country: CompanyLookupCountry) -> StatusMessage? {
        guard country == .czechRepublic, !query.isICO else { return nil }

        let words = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        if words.count == 1, query.count < 4 {
            return StatusMessage(text: "Type at least 4 characters for Czech company suggestions.", systemImage: "text.magnifyingglass", color: .secondary)
        }

        if words.count > 1, (words.dropFirst().first?.count ?? 0) < 4 {
            return StatusMessage(text: "Type at least 4 characters in the second word to narrow Czech results.", systemImage: "text.magnifyingglass", color: .secondary)
        }

        return nil
    }

    private func fetchSuggestions(for query: String, country: CompanyLookupCountry) async {
        isSearching = true
        message = nil
        defer { isSearching = false }

        do {
            let results = try await service(for: country).search(query: query)
            guard selectedCountry == country, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            searchResults = results
            isShowingSuggestions = !results.isEmpty
            hasCompletedSuggestionSearch = true
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            isShowingSuggestions = false
            hasCompletedSuggestionSearch = false
            message = StatusMessage(error: error)
        }
    }

    private func fillCompanyDetails(ico: String, country: CompanyLookupCountry) async throws {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        let details = try await service(for: country).companyDetails(ico: ico)
        guard selectedCountry == country else { return }
        company = details
        message = StatusMessage(text: "Filled company information for \(details.name).", systemImage: "checkmark.circle", color: .green)
    }

    private func service(for country: CompanyLookupCountry) throws -> CompanyLookupService {
        guard let service = services[country] else {
            throw CompanyLookupError.unsupportedCountry(country.rawValue)
        }
        return service
    }

    private func resetForCountryChange() {
        suggestionTask?.cancel()
        query = ""
        searchResults = []
        isShowingSuggestions = false
        hasCompletedSuggestionSearch = false
        company = .empty
        company.country = selectedCountry.rawValue
        message = nil
    }
}

enum CompanyLookupError: LocalizedError {
    case unsupportedCountry(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedCountry(country):
            "No company lookup service is configured for \(country)."
        }
    }
}
