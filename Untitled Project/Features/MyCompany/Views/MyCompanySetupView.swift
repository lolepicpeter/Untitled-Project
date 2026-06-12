import SwiftUI

struct MyCompanySetupView: View {
    var onSave: (() -> Void)? = nil

    @State private var lookupViewModel = CompanyLookupViewModel()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var isCreatingNewSeller = false
    @State private var isShowingSellerForm = false
    @State private var sellerPendingRemoval: MyCompanySellerProfile?

    private var canSave: Bool {
        !lookupViewModel.company.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryActionTitle: String {
        isCreatingNewSeller || !profileStore.hasSavedProfile ? "Create Seller" : "Save Seller"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sellerManagementPanel
            }
            .padding()
            .frame(maxWidth: 920, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sellers")
        .onAppear {
            profileStore.load()
            loadSavedProfile()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                let shouldKeepEditing = isShowingSellerForm
                profileStore.load()

                if !shouldKeepEditing {
                    loadSavedProfile()
                }
            }
        }
        .alert(
            "Remove Seller?",
            isPresented: Binding(
                get: { sellerPendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        sellerPendingRemoval = nil
                    }
                }
            ),
            presenting: sellerPendingRemoval
        ) { seller in
            Button("Remove", role: .destructive) {
                removeSeller(seller)
            }
            Button("Cancel", role: .cancel) {}
        } message: { seller in
            Text("Remove \(seller.displayName) from saved sellers. Existing invoices remain unchanged.")
        }
        .sheet(isPresented: $isShowingSellerForm) {
            NavigationStack {
                ScrollView {
                    sellerFormPanel
                        .padding()
                        .frame(maxWidth: 920, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(isCreatingNewSeller ? "New Seller" : "Seller Details")
            }
            .frame(minWidth: 760, minHeight: 620)
        }
    }

    private var sellerFormPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isCreatingNewSeller ? "Create a seller profile" : "Edit seller profile")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    isShowingSellerForm = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            SearchPanel(viewModel: lookupViewModel)
            StatusMessageView(message: lookupViewModel.message)
            StatusMessageView(message: profileStore.message)

            CompanyInformationPanel(
                company: $lookupViewModel.company,
                country: lookupViewModel.selectedCountry,
                isLoading: lookupViewModel.isLoadingDetails,
                isEditable: true
            )

            HStack(spacing: 12) {
                Button(action: saveCurrentSeller) {
                    Label(primaryActionTitle, systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)

                if profileStore.hasSavedProfile && !isCreatingNewSeller {
                    Button(action: saveAsNewProfile) {
                        Label("Save as New Seller", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSave)
                }
            }

            AttributionView(country: lookupViewModel.selectedCountry)
        }
    }

    private var sellerManagementPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Sellers")
                        .font(.headline)
                    Text("Choose who new invoices are issued from, or add another seller profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: startNewSeller) {
                    Label("New Seller", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            StatusMessageView(message: profileStore.message)

            if profileStore.profiles.isEmpty {
                ContentUnavailableView(
                    "No Saved Sellers",
                    systemImage: "building.2",
                    description: Text("Search for a company or enter seller details manually, then create the first seller.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(profileStore.profiles) { profile in
                        SellerProfileRow(
                            profile: profile,
                            isSelected: profile.id == profileStore.selectedProfileID && !isCreatingNewSeller,
                            onSelect: { selectSeller(profile) },
                            onEdit: { editSeller(profile) },
                            onRemove: { sellerPendingRemoval = profile }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadSavedProfile() {
        guard profileStore.hasSavedProfile else {
            isCreatingNewSeller = true
            isShowingSellerForm = true
            if lookupViewModel.company.country.isEmpty {
                lookupViewModel.company.country = lookupViewModel.selectedCountry.rawValue
            }
            return
        }

        isCreatingNewSeller = false
        isShowingSellerForm = false
        loadSelectedSellerIntoForm()
    }

    private func loadSelectedSellerIntoForm() {
        lookupViewModel.selectedCountry = profileStore.country
        lookupViewModel.company = profileStore.company
    }

    private func selectSeller(_ seller: MyCompanySellerProfile) {
        profileStore.selectProfile(id: seller.id)
        isCreatingNewSeller = false
        isShowingSellerForm = false
        loadSelectedSellerIntoForm()
    }

    private func editSeller(_ seller: MyCompanySellerProfile) {
        profileStore.selectProfile(id: seller.id)
        isCreatingNewSeller = false
        isShowingSellerForm = true
        loadSelectedSellerIntoForm()
    }

    private func startNewSeller() {
        isCreatingNewSeller = true
        isShowingSellerForm = true
        lookupViewModel.clear()
        lookupViewModel.selectedCountry = profileStore.country
        lookupViewModel.company.country = lookupViewModel.selectedCountry.rawValue
        profileStore.message = nil
    }

    private func saveCurrentSeller() {
        if isCreatingNewSeller || !profileStore.hasSavedProfile {
            profileStore.saveAsNew(company: lookupViewModel.company, country: lookupViewModel.selectedCountry)
        } else {
            profileStore.save(company: lookupViewModel.company, country: lookupViewModel.selectedCountry)
        }

        isCreatingNewSeller = false
        isShowingSellerForm = false
        onSave?()
    }

    private func saveAsNewProfile() {
        profileStore.saveAsNew(company: lookupViewModel.company, country: lookupViewModel.selectedCountry)
        isCreatingNewSeller = false
        isShowingSellerForm = false
        onSave?()
    }

    private func removeSeller(_ seller: MyCompanySellerProfile) {
        profileStore.removeProfile(id: seller.id)
        sellerPendingRemoval = nil

        if profileStore.hasSavedProfile {
            isCreatingNewSeller = false
            isShowingSellerForm = false
            loadSelectedSellerIntoForm()
        } else {
            startNewSeller()
        }
    }
}

private struct SellerProfileRow: View {
    let profile: MyCompanySellerProfile
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var detailLine: String {
        let country = CompanyLookupCountry.country(forCode: profile.countryCode).rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = profile.company.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let registrationNumber = profile.company.ico.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = [country, city, registrationNumber].filter { !$0.isEmpty }

        return details.isEmpty ? "No identification details" : details.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "building.2.crop.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if isSelected {
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            Menu {
                Button(action: onEdit) {
                    Label("Edit Details", systemImage: "pencil")
                }

                Button(role: .destructive, action: onRemove) {
                    Label("Remove Seller", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .controlSize(.small)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? .blue.opacity(0.35) : .secondary.opacity(0.12), lineWidth: 1)
        }
    }
}
