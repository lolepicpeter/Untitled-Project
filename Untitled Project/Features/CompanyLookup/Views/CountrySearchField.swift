import SwiftUI

struct CountrySearchField: View {
    @Binding var selectedCountry: CompanyLookupCountry
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCountries: [CompanyLookupCountry] {
        if trimmedQuery.isEmpty {
            return CompanyLookupCountry.supportedCountries
        }

        let normalizedQuery = trimmedQuery.normalizedCountrySearchText
        return CompanyLookupCountry.allCountries
            .filter { country in
                country.rawValue.normalizedCountrySearchText.contains(normalizedQuery)
                    || country.code.normalizedCountrySearchText.contains(normalizedQuery)
            }
            .prefix(12)
            .map { $0 }
    }

    private var shouldShowResults: Bool {
        isFocused && !filteredCountries.isEmpty
    }

    private var shouldShowNoResults: Bool {
        isFocused && !trimmedQuery.isEmpty && filteredCountries.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Country")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search country", text: $query)
                    .focused($isFocused)
                    .countrySearchTextFieldStyle()
                    .submitLabel(.done)
                    .onSubmit(selectFirstMatch)

                if !query.isEmpty {
                    Button {
                        query = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear country search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.25), lineWidth: 1)
            }

            if shouldShowResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredCountries) { country in
                            Button {
                                select(country)
                            } label: {
                                CountrySearchRow(country: country, isSelected: country == selectedCountry)
                            }
                            .buttonStyle(.plain)

                            if country.id != filteredCountries.last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .countryResultPanelStyle()
            } else if shouldShowNoResults {
                Label("No countries match \"\(trimmedQuery)\"", systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .countryResultPanelStyle()
            }
        }
        .onAppear {
            query = selectedCountry.rawValue
        }
        .onChange(of: selectedCountry) { _, newCountry in
            query = newCountry.rawValue
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                query = ""
            } else if trimmedQuery.isEmpty || !matchesSelectedCountry {
                query = selectedCountry.rawValue
            }
        }
    }

    private var matchesSelectedCountry: Bool {
        trimmedQuery.caseInsensitiveCompare(selectedCountry.rawValue) == .orderedSame
            || trimmedQuery.caseInsensitiveCompare(selectedCountry.code) == .orderedSame
    }

    private func selectFirstMatch() {
        guard let country = filteredCountries.first else { return }
        select(country)
    }

    private func select(_ country: CompanyLookupCountry) {
        selectedCountry = country
        query = country.rawValue
        isFocused = false
    }
}

private struct CountrySearchRow: View {
    let country: CompanyLookupCountry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(country.rawValue)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(countrySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var countrySubtitle: String {
        if country.isAutomaticLookupSupported {
            "\(country.code) • Automatic lookup • \(country.dataSourceName)"
        } else {
            "\(country.code) • Manual entry"
        }
    }
}

private extension View {
    func countryResultPanelStyle() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }

    @ViewBuilder
    func countrySearchTextFieldStyle() -> some View {
        #if os(iOS) || os(visionOS)
        self
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
        #else
        self
        #endif
    }
}

private extension String {
    var normalizedCountrySearchText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
