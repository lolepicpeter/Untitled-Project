import SwiftUI

struct IntegrationsView: View {
    @State private var allegroConnector = AllegroOAuthConnector()

    private var allegroStatusText: String {
        switch allegroConnector.backendConnections.count {
        case 0:
            "Add Allegro shops as separate sales channels."
        case 1:
            "1 sales channel connected"
        default:
            "\(allegroConnector.backendConnections.count) sales channels connected"
        }
    }

    private var allegroStatusColor: Color {
        allegroConnector.isConnected ? .green : .secondary
    }

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
                                Text("Allegro Sales Channels")
                                    .font(.headline)
                                Text(allegroStatusText)
                                    .font(.subheadline)
                                    .foregroundStyle(allegroStatusColor)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Sales Channels")
                }
            }
            .navigationTitle("Integrations")
            .onAppear { allegroConnector.reload() }
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
