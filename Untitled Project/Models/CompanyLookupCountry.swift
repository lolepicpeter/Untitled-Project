import Foundation

struct CompanyLookupCountry: Identifiable, Hashable {
    let code: String
    let rawValue: String

    var id: String { code }

    static let slovakia = CompanyLookupCountry(code: "SK", rawValue: "Slovakia")
    static let czechRepublic = CompanyLookupCountry(code: "CZ", rawValue: "Czech Republic")
    static let norway = CompanyLookupCountry(code: "NO", rawValue: "Norway")
    static let finland = CompanyLookupCountry(code: "FI", rawValue: "Finland")

    static let supportedCountries: [CompanyLookupCountry] = [
        .slovakia,
        .czechRepublic,
        .norway,
        .finland
    ]

    static let allCountries: [CompanyLookupCountry] = {
        let locale = Locale.current
        return Locale.Region.isoRegions
            .compactMap { region -> CompanyLookupCountry? in
                let code = region.identifier.uppercased()
                guard code.count == 2 else { return nil }

                if code == slovakia.code { return .slovakia }
                if code == czechRepublic.code { return .czechRepublic }
                if code == norway.code { return .norway }
                if code == finland.code { return .finland }

                guard let name = locale.localizedString(forRegionCode: code) else { return nil }
                return CompanyLookupCountry(code: code, rawValue: name)
            }
            .uniqued()
            .sorted { $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending }
    }()

    var searchPrompt: String {
        isAutomaticLookupSupported ? "Company name or IČO" : "Manual entry only"
    }

    var dataSourceName: String {
        switch self {
        case .slovakia:
            "ORSF"
        case .czechRepublic:
            "ARES"
        case .norway:
            "Brønnøysund Register Centre"
        case .finland:
            "PRH/YTJ Open Data"
        default:
            "Manual entry"
        }
    }

    var fieldLabels: CompanyFieldLabels {
        switch self {
        case .slovakia:
            .slovakia
        case .czechRepublic:
            .czechRepublic
        case .norway:
            .norway
        case .finland:
            .finland
        default:
            .generic
        }
    }

    var isAutomaticLookupSupported: Bool {
        Self.supportedCountries.contains(self)
    }

    static func country(forCode code: String) -> CompanyLookupCountry {
        allCountries.first { $0.code == code.uppercased() }
            ?? CompanyLookupCountry(code: code.uppercased(), rawValue: code.uppercased())
    }

    static func == (lhs: CompanyLookupCountry, rhs: CompanyLookupCountry) -> Bool {
        lhs.code == rhs.code
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

private extension Array where Element == CompanyLookupCountry {
    func uniqued() -> [CompanyLookupCountry] {
        var seenCodes: Set<String> = []
        return filter { country in
            seenCodes.insert(country.code).inserted
        }
    }
}
