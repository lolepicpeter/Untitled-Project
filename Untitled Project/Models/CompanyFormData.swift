import Foundation

struct CompanyFormData: Codable, Equatable {
    var name: String
    var ico: String
    var taxId: String
    var vatId: String
    var legalForm: String
    var status: String
    var street: String
    var city: String
    var postalCode: String
    var country: String
    var establishedOn: String
    var register: String
    var nace: String
    var vatPayer: String
    var businessActivities: String

    static let empty = CompanyFormData(
        name: "",
        ico: "",
        taxId: "",
        vatId: "",
        legalForm: "",
        status: "",
        street: "",
        city: "",
        postalCode: "",
        country: "",
        establishedOn: "",
        register: "",
        nace: "",
        vatPayer: "",
        businessActivities: ""
    )

    init(company: Company) {
        name = company.name
        ico = company.nationalId ?? company.ico
        taxId = company.taxId ?? company.dic ?? ""
        vatId = company.vatId ?? company.icdph ?? ""
        legalForm = company.legalForm ?? ""
        status = company.statusCode ?? company.status ?? ""
        street = company.address?.street ?? company.street ?? ""
        city = company.address?.city ?? company.city ?? ""
        postalCode = company.address?.postalCode ?? company.psc ?? ""
        country = company.address?.country ?? company.countryCode ?? ""
        establishedOn = company.establishedOn?.formattedISODate ?? ""
        register = company.displayRegister
        nace = company.nace ?? ""
        vatPayer = company.vatRegistration == nil ? "" : "Yes"
        businessActivities = company.activities.map(\.description).joined(separator: "\n")
    }

    init(aresCompany company: ARESEconomicSubject) {
        name = company.obchodniJmeno
        ico = company.resolvedIco
        taxId = company.dic ?? ""
        vatId = company.dic ?? ""
        legalForm = company.pravniForma?.legalFormDisplayName ?? ""
        status = company.seznamRegistraci?.isActive == true ? "active" : ""
        street = company.sidlo?.streetLine ?? ""
        city = company.sidlo?.nazevObce ?? ""
        postalCode = company.sidlo?.psc ?? ""
        country = company.sidlo?.nazevStatu ?? "CZ"
        establishedOn = company.datumVzniku ?? ""
        register = company.primarniZdroj?.uppercased() ?? "ARES"
        nace = (company.czNace ?? company.czNace2008 ?? []).joined(separator: ", ")
        vatPayer = company.seznamRegistraci?.isVatPayer == true ? "Yes" : ""
        businessActivities = ""
    }

    private init(
        name: String,
        ico: String,
        taxId: String,
        vatId: String,
        legalForm: String,
        status: String,
        street: String,
        city: String,
        postalCode: String,
        country: String,
        establishedOn: String,
        register: String,
        nace: String,
        vatPayer: String,
        businessActivities: String
    ) {
        self.name = name
        self.ico = ico
        self.taxId = taxId
        self.vatId = vatId
        self.legalForm = legalForm
        self.status = status
        self.street = street
        self.city = city
        self.postalCode = postalCode
        self.country = country
        self.establishedOn = establishedOn
        self.register = register
        self.nace = nace
        self.vatPayer = vatPayer
        self.businessActivities = businessActivities
    }
}
