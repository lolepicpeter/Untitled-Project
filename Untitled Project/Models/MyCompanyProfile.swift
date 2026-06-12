import Foundation
import Observation
import SwiftUI

struct StoredMyCompanyProfile: Codable {
    let countryCode: String
    let company: CompanyFormData
}

struct MyCompanySellerProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var countryCode: String
    var company: CompanyFormData

    var displayName: String {
        let name = company.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Seller" : name
    }
}

@MainActor
@Observable
final class MyCompanyProfileStore {
    static let profilesDidChange = Notification.Name("MyCompanyProfileStoreProfilesDidChange")

    var profiles: [MyCompanySellerProfile] = []
    var selectedProfileID: UUID?
    var company = CompanyFormData.empty
    var country = CompanyLookupCountry.slovakia
    var hasSavedProfile = false
    var message: StatusMessage?

    @ObservationIgnored private let legacyStorageKey = "myCompanyProfile"
    @ObservationIgnored private let profilesStorageKey = "myCompanyProfiles"
    @ObservationIgnored private let selectedProfileIDKey = "myCompanySelectedProfileID"
    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    var selectedProfile: MyCompanySellerProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    func load() {
        loadProfiles()
        applySelectedProfile()
    }

    func selectProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        userDefaults.set(id.uuidString, forKey: selectedProfileIDKey)
        applySelectedProfile()
        NotificationCenter.default.post(name: Self.profilesDidChange, object: nil)
    }

    func save(company: CompanyFormData, country: CompanyLookupCountry) {
        let countryCode = country.code

        if let selectedProfileID,
           let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
            profiles[index].company = company
            profiles[index].countryCode = countryCode
        } else {
            let profile = MyCompanySellerProfile(id: UUID(), countryCode: countryCode, company: company)
            profiles.append(profile)
            selectedProfileID = profile.id
        }

        persistProfiles()
        self.company = company
        self.country = country
        hasSavedProfile = true
        message = StatusMessage(text: "Saved seller profile.", systemImage: "checkmark.circle", color: .green)
    }

    func saveAsNew(company: CompanyFormData, country: CompanyLookupCountry) {
        let profile = MyCompanySellerProfile(id: UUID(), countryCode: country.code, company: company)
        profiles.append(profile)
        selectedProfileID = profile.id
        persistProfiles()
        self.company = company
        self.country = country
        hasSavedProfile = true
        message = StatusMessage(text: "Added seller profile.", systemImage: "plus.circle", color: .green)
    }

    func clear() {
        if let selectedProfileID {
            removeProfile(id: selectedProfileID)
        } else {
            profiles.removeAll()
            selectedProfileID = nil
            persistProfiles()
            applySelectedProfile()
            message = StatusMessage(text: "Removed seller profile.", systemImage: "trash", color: .secondary)
        }
    }

    func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }

        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }

        persistProfiles()
        applySelectedProfile()
        message = StatusMessage(text: "Removed seller profile.", systemImage: "trash", color: .secondary)
    }

    func replaceAll(profiles newProfiles: [MyCompanySellerProfile], selectedProfileID newSelectedProfileID: UUID?) {
        profiles = newProfiles
        selectedProfileID = newSelectedProfileID.flatMap { selectedID in
            newProfiles.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? newProfiles.first?.id
        persistProfiles()
        applySelectedProfile()
    }

    private func loadProfiles() {
        profiles = []
        selectedProfileID = userDefaults.string(forKey: selectedProfileIDKey).flatMap(UUID.init(uuidString:))

        if let data = userDefaults.data(forKey: profilesStorageKey),
           let decodedProfiles = try? JSONDecoder().decode([MyCompanySellerProfile].self, from: data) {
            profiles = decodedProfiles
        }

        if profiles.isEmpty,
           let data = userDefaults.data(forKey: legacyStorageKey),
           let legacyProfile = try? JSONDecoder().decode(StoredMyCompanyProfile.self, from: data) {
            let migratedProfile = MyCompanySellerProfile(
                id: UUID(),
                countryCode: legacyProfile.countryCode,
                company: legacyProfile.company
            )
            profiles = [migratedProfile]
            selectedProfileID = migratedProfile.id
            persistProfiles()
        }
    }

    private func applySelectedProfile() {
        guard let selectedProfile else {
            company = .empty
            country = .slovakia
            selectedProfileID = nil
            hasSavedProfile = false
            return
        }

        selectedProfileID = selectedProfile.id
        company = selectedProfile.company
        country = CompanyLookupCountry.country(forCode: selectedProfile.countryCode)
        hasSavedProfile = true
    }

    private func persistProfiles() {
        defer {
            NotificationCenter.default.post(name: Self.profilesDidChange, object: nil)
        }

        if profiles.isEmpty {
            userDefaults.removeObject(forKey: profilesStorageKey)
            userDefaults.removeObject(forKey: selectedProfileIDKey)
            userDefaults.removeObject(forKey: legacyStorageKey)
            return
        }

        if let data = try? JSONEncoder().encode(profiles) {
            userDefaults.set(data, forKey: profilesStorageKey)
        }

        if let selectedProfileID {
            userDefaults.set(selectedProfileID.uuidString, forKey: selectedProfileIDKey)
        }
    }
}
