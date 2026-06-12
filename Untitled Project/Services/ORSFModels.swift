import Foundation

struct SearchResponse: Decodable {
    let hits: [CompanySearchResult]
}

struct CompanySearchResult: Decodable, Identifiable {
    let ico: String
    let name: String
    let legalForm: String?
    let kind: String?
    let register: String?
    let status: String?
    let city: String?
    let establishedYear: Int?

    enum CodingKeys: String, CodingKey {
        case ico
        case companyId
        case name
        case legalForm
        case kind
        case register
        case status
        case city
        case establishedYear
    }

    init(
        ico: String,
        name: String,
        legalForm: String?,
        kind: String?,
        register: String?,
        status: String?,
        city: String?,
        establishedYear: Int?
    ) {
        self.ico = ico
        self.name = name
        self.legalForm = legalForm
        self.kind = kind
        self.register = register
        self.status = status
        self.city = city
        self.establishedYear = establishedYear
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ico = try container.decodeIfPresent(String.self, forKey: .ico)
            ?? container.decode(String.self, forKey: .companyId)
        name = try container.decode(String.self, forKey: .name)
        legalForm = try container.decodeIfPresent(String.self, forKey: .legalForm)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        register = try container.decodeIfPresent(String.self, forKey: .register)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        establishedYear = try container.decodeIfPresent(Int.self, forKey: .establishedYear)
    }

    var id: String { ico }

    var subtitle: String {
        [
            "IČO: \(ico)",
            city,
            legalForm,
            status,
            establishedYear.map(String.init)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }
}

struct Company: Decodable {
    let countryCode: String?
    let ico: String
    let nationalId: String?
    let dic: String?
    let taxId: String?
    let icdph: String?
    let vatId: String?
    let name: String
    let legalForm: String?
    let status: String?
    let statusCode: String?
    let nace: String?
    let street: String?
    let city: String?
    let psc: String?
    let establishedOn: String?
    let register: String?
    let registerCode: String?
    let address: CompanyAddress?
    let activities: [BusinessActivity]
    let vatRegistration: VATRegistration?

    enum CodingKeys: String, CodingKey {
        case countryCode
        case ico
        case nationalId
        case dic
        case taxId
        case icdph
        case vatId
        case name
        case legalForm
        case status
        case statusCode
        case nace
        case street
        case city
        case psc
        case establishedOn
        case register
        case registerCode
        case address
        case activities
        case vatRegistration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        ico = try container.decode(String.self, forKey: .ico)
        nationalId = try container.decodeIfPresent(String.self, forKey: .nationalId)
        dic = try container.decodeIfPresent(String.self, forKey: .dic)
        taxId = try container.decodeIfPresent(String.self, forKey: .taxId)
        icdph = try container.decodeIfPresent(String.self, forKey: .icdph)
        vatId = try container.decodeIfPresent(String.self, forKey: .vatId)
        name = try container.decode(String.self, forKey: .name)
        legalForm = try container.decodeIfPresent(String.self, forKey: .legalForm)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        nace = try container.decodeIfPresent(String.self, forKey: .nace)
        street = try container.decodeIfPresent(String.self, forKey: .street)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        psc = try container.decodeIfPresent(String.self, forKey: .psc)
        establishedOn = try container.decodeIfPresent(String.self, forKey: .establishedOn)
        register = try container.decodeIfPresent(String.self, forKey: .register)
        registerCode = try container.decodeIfPresent(String.self, forKey: .registerCode)
        address = try container.decodeIfPresent(CompanyAddress.self, forKey: .address)
        activities = (try? container.decodeIfPresent([BusinessActivity].self, forKey: .activities)) ?? []
        vatRegistration = try container.decodeIfPresent(VATRegistration.self, forKey: .vatRegistration)
    }

    var displayRegister: String {
        if let register, !register.isEmpty {
            return register
        }

        if let registerCode, registerCode != "unknown", !registerCode.isEmpty {
            return registerCode
        }

        return "Not available in ORSF"
    }
}

struct CompanyAddress: Decodable {
    let street: String?
    let city: String?
    let postalCode: String?
    let country: String?
}

struct BusinessActivity: Decodable {
    let description: String

    enum CodingKeys: String, CodingKey {
        case description
        case economicActivityDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .economicActivityDescription)
            ?? ""
    }
}

struct VATRegistration: Decodable {}

struct APIErrorResponse: Decodable {
    let message: String?
}
