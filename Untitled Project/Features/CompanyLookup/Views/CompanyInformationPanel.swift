import SwiftUI

struct CompanyInformationPanel: View {
    @Binding var company: CompanyFormData
    let country: CompanyLookupCountry
    let isLoading: Bool
    let isEditable: Bool

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    private var labels: CompanyFieldLabels {
        country.fieldLabels
    }

    private var modeText: String {
        isEditable ? "Editable company details" : "Filled from public lookup"
    }

    private var modeSystemImage: String {
        isEditable ? "square.and.pencil" : "checkmark.seal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Company Details")
                        .font(.headline)
                    Label(modeText, systemImage: modeSystemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                FieldView(title: labels.companyName, value: $company.name, isEditable: isEditable)
                FieldView(title: labels.companyId, value: $company.ico, isEditable: isEditable)
                FieldView(title: labels.taxId, value: $company.taxId, isEditable: isEditable)
                FieldView(title: labels.vatId, value: $company.vatId, isEditable: isEditable)
                FieldView(title: labels.legalForm, value: $company.legalForm, isEditable: isEditable)
                FieldView(title: labels.status, value: $company.status, isEditable: isEditable)
                FieldView(title: labels.street, value: $company.street, isEditable: isEditable)
                FieldView(title: labels.city, value: $company.city, isEditable: isEditable)
                FieldView(title: labels.postalCode, value: $company.postalCode, isEditable: isEditable)
                FieldView(title: labels.country, value: $company.country, isEditable: isEditable)
                FieldView(title: labels.established, value: $company.establishedOn, isEditable: isEditable)
                FieldView(title: labels.register, value: $company.register, isEditable: isEditable)
                FieldView(title: labels.industryCode, value: $company.nace, isEditable: isEditable)
                FieldView(title: labels.vatPayer, value: $company.vatPayer, isEditable: isEditable)
            }

            ActivitiesView(title: labels.businessActivities, value: $company.businessActivities, isEditable: isEditable)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
