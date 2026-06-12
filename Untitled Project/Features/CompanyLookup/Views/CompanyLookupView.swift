import SwiftUI

struct CompanyLookupView: View {
    @Bindable var viewModel: CompanyLookupViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SearchPanel(viewModel: viewModel)
                    StatusMessageView(message: viewModel.message)
                    CompanyInformationPanel(company: $viewModel.company, country: viewModel.selectedCountry, isLoading: viewModel.isLoadingDetails, isEditable: viewModel.isManualEntry)
                    AttributionView(country: viewModel.selectedCountry)
                }
                .padding()
                .frame(maxWidth: 920, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Company Lookup")
        }
    }
}
