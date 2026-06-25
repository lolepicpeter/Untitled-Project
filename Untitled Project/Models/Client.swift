import Foundation

struct Client: Identifiable, Codable, Equatable {
    var id: UUID
    var countryCode: String
    var companyName: String
    var email: String
    var additionalEmail: String
    var street: String
    var apartment: String
    var city: String
    var postalCode: String
    var registrationNumber: String
    var taxId: String
    var vatId: String
    var contactPerson: String
    var phone: String
    var mobile: String
    var fax: String
    var website: String
    var shippingStreet: String
    var shippingApartment: String
    var shippingCity: String
    var shippingPostalCode: String
    var marketplaceSource: MarketplaceSource?

    static var empty: Client {
        Client(
            id: UUID(),
            countryCode: CompanyLookupCountry.slovakia.code,
            companyName: "",
            email: "",
            additionalEmail: "",
            street: "",
            apartment: "",
            city: "",
            postalCode: "",
            registrationNumber: "",
            taxId: "",
            vatId: "",
            contactPerson: "",
            phone: "",
            mobile: "",
            fax: "",
            website: "",
            shippingStreet: "",
            shippingApartment: "",
            shippingCity: "",
            shippingPostalCode: "",
            marketplaceSource: nil
        )
    }

    var country: CompanyLookupCountry {
        CompanyLookupCountry.country(forCode: countryCode)
    }

    var displayName: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Client" : companyName
    }

    var subtitle: String {
        let parts = [city, email, registrationNumber]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " • ")
    }

    mutating func apply(company: CompanyFormData, country: CompanyLookupCountry) {
        countryCode = country.code
        companyName = company.name
        street = company.street
        city = company.city
        postalCode = company.postalCode
        registrationNumber = company.ico
        taxId = company.taxId
        vatId = company.vatId
    }

    mutating func fillMissingDetails(from importedClient: Client) {
        if countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { countryCode = importedClient.countryCode }
        if companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { companyName = importedClient.companyName }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { email = importedClient.email }
        if street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { street = importedClient.street }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { city = importedClient.city }
        if postalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { postalCode = importedClient.postalCode }
        if registrationNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { registrationNumber = importedClient.registrationNumber }
        if taxId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { taxId = importedClient.taxId }
        if vatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { vatId = importedClient.vatId }
        if contactPerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { contactPerson = importedClient.contactPerson }
        if phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { phone = importedClient.phone }
        if mobile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { mobile = importedClient.mobile }
        if shippingStreet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { shippingStreet = importedClient.shippingStreet }
        if shippingCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { shippingCity = importedClient.shippingCity }
        if shippingPostalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { shippingPostalCode = importedClient.shippingPostalCode }
        if marketplaceSource == nil { marketplaceSource = importedClient.marketplaceSource }
    }
}
