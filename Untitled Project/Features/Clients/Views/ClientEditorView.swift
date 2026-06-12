import SwiftUI

struct ClientEditorView: View {
    let client: Client
    let title: String
    let onSave: (Client) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Client
    @State private var lookupViewModel = CompanyLookupViewModel()

    private var labels: CompanyFieldLabels {
        draft.country.fieldLabels
    }

    private var canSave: Bool {
        !draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(client: Client, title: String, onSave: @escaping (Client) -> Void) {
        self.client = client
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: client)
    }

    var body: some View {
        editorContent
            .navigationTitle(title)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: configureLookup)
            .onChange(of: client) { _, newClient in
                draft = newClient
                configureLookup(for: newClient)
            }
            .onChange(of: lookupViewModel.selectedCountry) { _, country in
                draft.countryCode = country.code
            }
            .onChange(of: lookupViewModel.company) { _, company in
                guard company != .empty else { return }
                draft.apply(company: company, country: lookupViewModel.selectedCountry)
            }
    }

    @ViewBuilder
    private var editorContent: some View {
        #if os(macOS)
        macEditor
        #else
        mobileEditor
        #endif
    }

    private var mobileEditor: some View {
        Form {
            ClientCompanyLookupSection(viewModel: lookupViewModel)

            Section("Client") {
                ClientTextField("Client name", text: $draft.companyName, prompt: "Required")
                ClientTextField("Email", text: $draft.email, prompt: "name@example.com")
                ClientTextField("Additional email", text: $draft.additionalEmail, prompt: "Optional")
            }

            Section("Billing Address") {
                LabeledContent("Country", value: draft.country.rawValue)
                ClientTextField(labels.street, text: $draft.street, prompt: labels.street)
                ClientTextField("Address line 2", text: $draft.apartment, prompt: "Optional")
                ClientTextField(labels.city, text: $draft.city, prompt: labels.city)
                ClientTextField(labels.postalCode, text: $draft.postalCode, prompt: labels.postalCode)
            }

            Section("Identification") {
                ClientTextField(labels.companyId, text: $draft.registrationNumber, prompt: labels.companyId)
                ClientTextField(labels.taxId, text: $draft.taxId, prompt: labels.taxId)
                ClientTextField(labels.vatId, text: $draft.vatId, prompt: labels.vatId)
            }

            Section("Contact Information") {
                ClientTextField("Contact person", text: $draft.contactPerson, prompt: "Optional")
                ClientTextField("Phone", text: $draft.phone, prompt: "Optional")
                ClientTextField("Mobile", text: $draft.mobile, prompt: "Optional")
                ClientTextField("Web", text: $draft.website, prompt: "example.com")
            }

            Section("Shipping Address") {
                ClientTextField("Street", text: $draft.shippingStreet, prompt: "Optional")
                ClientTextField("Address line 2", text: $draft.shippingApartment, prompt: "Optional")
                ClientTextField("City", text: $draft.shippingCity, prompt: "Optional")
                ClientTextField("Postal Code", text: $draft.shippingPostalCode, prompt: "Optional")
            }
        }
    }

    #if os(macOS)
    private var macEditor: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ClientCompanyLookupSection(viewModel: lookupViewModel)

                    macEditorSections
                }
                .padding(24)
                .frame(width: min(proxy.size.width, 620), alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minHeight: 600, alignment: .topLeading)
    }
    @ViewBuilder
    private var macEditorSections: some View {
        MacEditorSection("Client") {
            MacClientTextField("Client name", text: $draft.companyName, prompt: "Required")
            MacClientTextField("Email", text: $draft.email, prompt: "name@example.com")
            MacClientTextField("Additional email", text: $draft.additionalEmail, prompt: "Optional")
        }

        MacEditorSection("Billing Address") {
            MacReadOnlyRow("Country", value: draft.country.rawValue)
            MacClientTextField(labels.street, text: $draft.street, prompt: labels.street)
            MacClientTextField("Address line 2", text: $draft.apartment, prompt: "Optional")
            MacClientTextField(labels.city, text: $draft.city, prompt: labels.city)
            MacClientTextField(labels.postalCode, text: $draft.postalCode, prompt: labels.postalCode)
        }

        MacEditorSection("Identification") {
            MacClientTextField(labels.companyId, text: $draft.registrationNumber, prompt: labels.companyId)
            MacClientTextField(labels.taxId, text: $draft.taxId, prompt: labels.taxId)
            MacClientTextField(labels.vatId, text: $draft.vatId, prompt: labels.vatId)
        }

        MacEditorSection("Contact Information") {
            MacClientTextField("Contact person", text: $draft.contactPerson, prompt: "Optional")
            MacClientTextField("Phone", text: $draft.phone, prompt: "Optional")
            MacClientTextField("Mobile", text: $draft.mobile, prompt: "Optional")
            MacClientTextField("Web", text: $draft.website, prompt: "example.com")
        }

        MacEditorSection("Shipping Address") {
            MacClientTextField("Street", text: $draft.shippingStreet, prompt: "Optional")
            MacClientTextField("Address line 2", text: $draft.shippingApartment, prompt: "Optional")
            MacClientTextField("City", text: $draft.shippingCity, prompt: "Optional")
            MacClientTextField("Postal Code", text: $draft.shippingPostalCode, prompt: "Optional")
        }
    }
    #endif

    private func configureLookup() {
        configureLookup(for: draft)
    }

    private func configureLookup(for client: Client) {
        let country = CompanyLookupCountry.country(forCode: client.countryCode)
        if lookupViewModel.selectedCountry != country {
            lookupViewModel.selectedCountry = country
        }
    }

    private func save() {
        onSave(draft)
        dismiss()
    }
}

private struct ClientTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if os(macOS)
private struct MacEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 4)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MacClientTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 118, alignment: .leading)

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct MacReadOnlyRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 118, alignment: .leading)

            Text(value)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
#endif

private struct ClientCompanyLookupSection: View {
    @Bindable var viewModel: CompanyLookupViewModel
    @State private var companyQuery = ""
    @State private var isShowingCountryPicker = false
    @State private var querySyncTask: Task<Void, Never>?

    private var visibleSuggestions: [CompanySearchResult] {
        Array(viewModel.searchResults.prefix(4))
    }

    private var shouldShowSuggestions: Bool {
        viewModel.isShowingSuggestions && !visibleSuggestions.isEmpty
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        mobileBody
        #endif
    }

    private var mobileBody: some View {
        Group {
            Section {
                lookupCard
            } header: {
                Text("Look Up Client")
            } footer: {
                Text("Search by company name or registration number to autofill billing and identification details.")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if viewModel.message != nil {
                Section {
                    StatusMessageView(message: viewModel.message)
                }
                .listRowBackground(Color.clear)
            }
        }
        .lookupLifecycle(
            isShowingCountryPicker: $isShowingCountryPicker,
            selectedCountry: $viewModel.selectedCountry,
            query: viewModel.query,
            onAppear: { syncLocalCompanyQuery(viewModel.query) },
            onQueryChange: syncLocalCompanyQuery,
            onDisappear: { querySyncTask?.cancel() }
        )
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Look Up Client")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Search by company name or registration number to autofill billing and identification details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            lookupCard
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.message != nil {
                StatusMessageView(message: viewModel.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lookupLifecycle(
            isShowingCountryPicker: $isShowingCountryPicker,
            selectedCountry: $viewModel.selectedCountry,
            query: viewModel.query,
            onAppear: { syncLocalCompanyQuery(viewModel.query) },
            onQueryChange: syncLocalCompanyQuery,
            onDisappear: { querySyncTask?.cancel() }
        )
    }
    #endif

    private var lookupCard: some View {
        VStack(spacing: 0) {
            Button {
                isShowingCountryPicker = true
            } label: {
                HStack(spacing: 12) {
                    Text("Country")
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Text(viewModel.selectedCountry.rawValue)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 16)

            if viewModel.selectedCountry.isAutomaticLookupSupported {
                companySearchRow

                if shouldShowSuggestions {
                    Divider()
                        .padding(.leading, 16)

                    VStack(spacing: 0) {
                        ForEach(visibleSuggestions) { result in
                            InlineCompanySuggestionRow(result: result) {
                                viewModel.selectSuggestion(result)
                            }

                            if result.id != visibleSuggestions.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .padding(.leading, 16)

                actionRow

                if hasLookupCompany {
                    Divider()
                        .padding(.leading, 16)

                    lookupResultRow
                }
            } else {
                manualEntryRow
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var hasLookupCompany: Bool {
        !viewModel.company.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lookupResultRow: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Client details filled from lookup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(viewModel.company.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var companySearchRow: some View {
        HStack(spacing: 12) {
            Text("Client company")
                .foregroundStyle(.primary)

            TextField(viewModel.selectedCountry.searchPrompt, text: $companyQuery)
                .multilineTextAlignment(.trailing)
                .companyLookupTextFieldStyle()
                .submitLabel(.search)
                .onSubmit(searchCompany)
                .onChange(of: companyQuery) { _, query in
                    syncLookupCompanyQuery(query)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button(action: searchCompany) {
                if viewModel.isSearching {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Label("Search & Fill", systemImage: "magnifyingglass")
                        .frame(minWidth: 118)
                }
            }
            .disabled(!viewModel.canSearch)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Search company")

            Button(action: clearCompanySearch) {
                Image(systemName: "xmark.circle")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Clear company search")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func syncLookupCompanyQuery(_ query: String) {
        querySyncTask?.cancel()
        querySyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            if viewModel.query != query {
                viewModel.query = query
            }
            viewModel.scheduleSuggestions(for: query)
        }
    }

    private func syncLocalCompanyQuery(_ query: String) {
        if companyQuery != query {
            companyQuery = query
        }
    }

    private func searchCompany() {
        querySyncTask?.cancel()
        if viewModel.query != companyQuery {
            viewModel.query = companyQuery
        }
        viewModel.search()
    }

    private func clearCompanySearch() {
        querySyncTask?.cancel()
        companyQuery = ""
        viewModel.clear()
    }

    private var manualEntryRow: some View {
        Label("Manual entry mode. Enter the client details below.", systemImage: "square.and.pencil")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineCompanySuggestionRow: View {
    let result: CompanySearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ClientCountryPickerView: View {
    @Binding var selectedCountry: CompanyLookupCountry
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredCountries: [CompanyLookupCountry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return CompanyLookupCountry.allCountries }

        let normalizedQuery = trimmedQuery.normalizedCountryPickerText
        return CompanyLookupCountry.allCountries.filter { country in
            country.rawValue.normalizedCountryPickerText.contains(normalizedQuery)
                || country.code.normalizedCountryPickerText.contains(normalizedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    selectedCountry = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(country.rawValue)
                                .foregroundStyle(.primary)
                            Text(countrySubtitle(for: country))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if country == selectedCountry {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Country")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Search country")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func countrySubtitle(for country: CompanyLookupCountry) -> String {
        if country.isAutomaticLookupSupported {
            "\(country.code) • Automatic lookup • \(country.dataSourceName)"
        } else {
            "\(country.code) • Manual entry"
        }
    }
}

private extension View {
    @ViewBuilder
    func companyLookupTextFieldStyle() -> some View {
        #if os(iOS) || os(visionOS)
        self
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
        #else
        self
        #endif
    }

    func lookupLifecycle(
        isShowingCountryPicker: Binding<Bool>,
        selectedCountry: Binding<CompanyLookupCountry>,
        query: String,
        onAppear: @escaping () -> Void,
        onQueryChange: @escaping (String) -> Void,
        onDisappear: @escaping () -> Void
    ) -> some View {
        self
            .onAppear(perform: onAppear)
            .onChange(of: query) { _, newQuery in
                onQueryChange(newQuery)
            }
            .sheet(isPresented: isShowingCountryPicker) {
                ClientCountryPickerView(selectedCountry: selectedCountry)
                    #if os(macOS)
                    .frame(minWidth: 420, idealWidth: 480, minHeight: 520, idealHeight: 620)
                    #endif
            }
            .onDisappear(perform: onDisappear)
    }
}

private extension String {
    var normalizedCountryPickerText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
