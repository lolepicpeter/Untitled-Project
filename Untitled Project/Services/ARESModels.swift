import Foundation

struct ARESSearchResponse: Decodable {
    let ekonomickeSubjekty: [ARESEconomicSubject]?
}

struct ARESEconomicSubject: Decodable {
    let ico: String?
    let icoId: String?
    let obchodniJmeno: String
    let sidlo: ARESAddress?
    let pravniForma: String?
    let datumVzniku: String?
    let dic: String?
    let czNace: [String]?
    let czNace2008: [String]?
    let seznamRegistraci: ARESRegistrations?
    let primarniZdroj: String?

    var resolvedIco: String {
        if let ico, !ico.isEmpty {
            return ico
        }

        return icoId?.replacingOccurrences(of: "ARES_", with: "") ?? ""
    }

    var searchResult: CompanySearchResult {
        CompanySearchResult(
            ico: resolvedIco,
            name: obchodniJmeno,
            legalForm: pravniForma?.legalFormDisplayName,
            kind: nil,
            register: primarniZdroj?.uppercased(),
            status: seznamRegistraci?.isActive == true ? "active" : nil,
            city: sidlo?.nazevObce,
            establishedYear: datumVzniku?.yearPrefix
        )
    }
}

struct ARESAddress: Decodable {
    let nazevStatu: String?
    let nazevObce: String?
    let nazevUlice: String?
    let cisloDomovni: String?
    let cisloOrientacni: String?
    let psc: String?
    let textovaAdresa: String?

    enum CodingKeys: String, CodingKey {
        case nazevStatu
        case nazevObce
        case nazevUlice
        case cisloDomovni
        case cisloOrientacni
        case psc
        case textovaAdresa
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nazevStatu = try container.decodeIfPresent(String.self, forKey: .nazevStatu)
        nazevObce = try container.decodeIfPresent(String.self, forKey: .nazevObce)
        nazevUlice = try container.decodeIfPresent(String.self, forKey: .nazevUlice)
        cisloDomovni = container.decodeFlexibleStringIfPresent(forKey: .cisloDomovni)
        cisloOrientacni = container.decodeFlexibleStringIfPresent(forKey: .cisloOrientacni)
        psc = container.decodeFlexibleStringIfPresent(forKey: .psc)
        textovaAdresa = try container.decodeIfPresent(String.self, forKey: .textovaAdresa)
    }

    var streetLine: String {
        if let nazevUlice, let cisloDomovni {
            if let cisloOrientacni {
                return "\(nazevUlice) \(cisloDomovni)/\(cisloOrientacni)"
            }
            return "\(nazevUlice) \(cisloDomovni)"
        }

        return textovaAdresa ?? ""
    }
}

struct ARESRegistrations: Decodable {
    let stavZdrojeRos: String?
    let stavZdrojeVr: String?
    let stavZdrojeRes: String?
    let stavZdrojeRzp: String?
    let stavZdrojeDph: String?

    var isActive: Bool {
        [stavZdrojeRos, stavZdrojeVr, stavZdrojeRes, stavZdrojeRzp].contains("AKTIVNI")
    }

    var isVatPayer: Bool {
        stavZdrojeDph == "AKTIVNI"
    }
}

struct ARESErrorResponse: Decodable {
    let popis: String?
}

extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        return nil
    }
}

extension String {
    var yearPrefix: Int? {
        guard count >= 4 else { return nil }
        return Int(prefix(4))
    }

    var legalFormDisplayName: String {
        switch self {
        case "101":
            "sole trader"
        case "112":
            "společnost s ručením omezeným"
        case "121":
            "akciová společnost"
        default:
            "Legal form \(self)"
        }
    }
}
