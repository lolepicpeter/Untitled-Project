import SwiftUI

struct SearchPanel: View {
    @Bindable var viewModel: CompanyLookupViewModel

    private var title: String {
        viewModel.selectedCountry.isAutomaticLookupSupported ? "Company Lookup" : "Manual Company Entry"
    }

    private var subtitle: String {
        if viewModel.selectedCountry.isAutomaticLookupSupported {
            return "Search public company data for \(viewModel.selectedCountry.rawValue)."
        }
        return "Automatic lookup is not configured for \(viewModel.selectedCountry.rawValue). Enter company details manually below."
    }

    private var hasSearchText: Bool {
        !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowNoMatches: Bool {
        hasSearchText
            && viewModel.hasCompletedSuggestionSearch
            && !viewModel.isSearching
            && viewModel.searchResults.isEmpty
            && viewModel.message == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            CountrySearchField(selectedCountry: $viewModel.selectedCountry)

            if viewModel.selectedCountry.isAutomaticLookupSupported {
                TextField(viewModel.selectedCountry.searchPrompt, text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { viewModel.search() }
                    .onChange(of: viewModel.query) { _, newQuery in
                        viewModel.scheduleSuggestions(for: newQuery)
                    }

                if viewModel.isShowingSuggestions && !viewModel.searchResults.isEmpty {
                    SuggestionsDropdown(
                        results: viewModel.searchResults,
                        onSelect: viewModel.selectSuggestion
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if shouldShowNoMatches {
                    Label("No matches found. Try a registration number or a more specific name.", systemImage: "exclamationmark.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(action: viewModel.search) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(!viewModel.canSearch)
                    .buttonStyle(.borderedProminent)

                    Button(action: viewModel.clear) {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSearchText && viewModel.searchResults.isEmpty && viewModel.company == .empty)
                }
            } else {
                Label("Manual entry mode", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
