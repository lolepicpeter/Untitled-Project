import SwiftUI

struct IntegrationsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AllegroIntegrationView()
                    } label: {
                        HStack(spacing: 14) {
                            allegroIcon

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allegro")
                                    .font(.headline)
                                Text("Connect your seller account and import orders for invoicing.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Marketplaces")
                }
            }
            .navigationTitle("Integrations")
        }
    }

    private var allegroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange)
            Text("a")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

#Preview {
    IntegrationsView()
}
