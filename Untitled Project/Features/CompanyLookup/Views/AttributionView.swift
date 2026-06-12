import SwiftUI

struct AttributionView: View {
    let country: CompanyLookupCountry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dataSourceText)
            Text("For legally binding extracts, use the official source register.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var dataSourceText: String {
        switch country {
        case .slovakia:
            "Data source: ORSF, an independent open API built from public Slovak registers. ORSF is beta and not an official state register. License: CC-BY 4.0."
        case .czechRepublic:
            "Data source: ARES, the Czech public register API for economic entities."
        case .norway:
            "Data source: Brønnøysund Register Centre, official Norwegian register data published under NLOD."
        case .finland:
            "Data source: PRH/YTJ Open Data, Finnish company data published under CC BY 4.0."
        default:
            "Manual entry: no automatic public lookup source is configured for this country."
        }
    }
}
