import Foundation

struct CompanyFieldLabels {
    let companyName: String
    let companyId: String
    let taxId: String
    let vatId: String
    let legalForm: String
    let status: String
    let street: String
    let city: String
    let postalCode: String
    let country: String
    let established: String
    let register: String
    let industryCode: String
    let vatPayer: String
    let businessActivities: String

    static let generic = CompanyFieldLabels(
        companyName: "Company name",
        companyId: "Registration number",
        taxId: "Tax ID",
        vatId: "VAT ID",
        legalForm: "Legal form",
        status: "Status",
        street: "Street",
        city: "City",
        postalCode: "Postal code",
        country: "Country",
        established: "Established",
        register: "Register",
        industryCode: "Industry code",
        vatPayer: "VAT payer",
        businessActivities: "Business activities"
    )

    static let slovakia = CompanyFieldLabels(
        companyName: "Obchodné meno",
        companyId: "IČO",
        taxId: "DIČ",
        vatId: "IČ DPH",
        legalForm: "Právna forma",
        status: "Stav",
        street: "Ulica",
        city: "Obec",
        postalCode: "PSČ",
        country: "Štát",
        established: "Vznik",
        register: "Register",
        industryCode: "SK NACE",
        vatPayer: "Platiteľ DPH",
        businessActivities: "Predmety činnosti"
    )

    static let czechRepublic = CompanyFieldLabels(
        companyName: "Obchodní jméno",
        companyId: "IČO",
        taxId: "DIČ",
        vatId: "DIČ / VAT ID",
        legalForm: "Právní forma",
        status: "Stav",
        street: "Ulice",
        city: "Obec",
        postalCode: "PSČ",
        country: "Stát",
        established: "Datum vzniku",
        register: "Rejstřík",
        industryCode: "CZ-NACE",
        vatPayer: "Plátce DPH",
        businessActivities: "Předmět činnosti"
    )

    static let norway = CompanyFieldLabels(
        companyName: "Foretaksnavn",
        companyId: "Organisasjonsnummer",
        taxId: "Organisasjonsnummer",
        vatId: "MVA-nummer",
        legalForm: "Organisasjonsform",
        status: "Status",
        street: "Adresse",
        city: "Poststed",
        postalCode: "Postnummer",
        country: "Land",
        established: "Stiftelsesdato",
        register: "Register",
        industryCode: "Næringskode",
        vatPayer: "MVA-registrert",
        businessActivities: "Aktivitet"
    )

    static let finland = CompanyFieldLabels(
        companyName: "Yrityksen nimi",
        companyId: "Y-tunnus",
        taxId: "Y-tunnus",
        vatId: "ALV-tunniste",
        legalForm: "Yritysmuoto",
        status: "Tila",
        street: "Katuosoite",
        city: "Postitoimipaikka",
        postalCode: "Postinumero",
        country: "Maa",
        established: "Rekisteröintipäivä",
        register: "Rekisteri",
        industryCode: "Toimiala",
        vatPayer: "ALV-rekisterissä",
        businessActivities: "Toiminnan kuvaus"
    )
}
