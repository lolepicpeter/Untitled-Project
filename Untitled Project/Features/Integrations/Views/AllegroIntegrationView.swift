import SwiftUI

struct AllegroIntegrationView: View {
    @State private var connector = AllegroOAuthConnector()
    @State private var settings = AllegroConnectionSettings.load()

    private var statusTitle: String {
        connector.isConnected ? "Connected" : "Not Connected"
    }

    private var statusColor: Color {
        connector.isConnected ? .green : .secondary
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    allegroIcon

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allegro")
                            .font(.headline)
                        Text(statusTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }

                    Spacer()

                    statusIndicator
                }
                .padding(.vertical, 8)
            }

            Section {
                if connector.isConnected {
                    Button(role: .destructive) {
                        connector.disconnect()
                    } label: {
                        Label("Disconnect Allegro", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        Label(connector.isConnecting ? "Opening Allegro..." : "Connect Allegro", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connector.isConnecting)
                }
            } footer: {
                Text("Orders can be imported into invoice drafts after the seller grants access.")
            }

            if connector.isConnected {
                Section {
                    LabeledContent("Account", value: connector.backendConnection?.displayName ?? settings.connectedAccountName)
                    if let connectedAt = connector.backendConnection?.connectedAt {
                        LabeledContent("Connected", value: connectedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                } header: {
                    Text("Connection")
                }
            }

            Section {
                LabeledContent("Service", value: serviceHost)
                LabeledContent("Environment", value: settings.environment.title)
            } header: {
                Text("Service Details")
            }

            Section {
                Button("Reset Allegro Connection", role: .destructive) {
                    connector.disconnect()
                    settings = AllegroConnectionSettings.reset()
                    connector.saveSettings(settings)
                    connector.statusMessage = nil
                }
            }

            if let statusMessage = connector.statusMessage {
                Section {
                    Label(statusMessage.text, systemImage: statusMessage.systemImage)
                        .foregroundStyle(statusMessage.color)
                }
            }
        }
        .navigationTitle("Allegro")
        .onAppear {
            connector.reload()
            settings = connector.settings
            ensureProductionBrokerConfigured()
        }
    }

    private var allegroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange)
            Text("a")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    private var statusIndicator: some View {
        Image(systemName: connector.isConnected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(statusColor)
            .accessibilityLabel(statusTitle)
    }

    private var serviceHost: String {
        guard let host = URL(string: settings.normalizedBrokerBaseURL)?.host else {
            return "SnapBuy"
        }
        return host
    }

    private func ensureProductionBrokerConfigured() {
        var updatedSettings = settings
        if updatedSettings.normalizedBrokerBaseURL.isEmpty {
            updatedSettings.brokerBaseURL = AllegroConnectionSettings.defaultBrokerBaseURL
        }
        updatedSettings.environment = .production
        if updatedSettings != settings {
            settings = updatedSettings
            connector.saveSettings(updatedSettings)
        }
    }

    private func connect() async {
        ensureProductionBrokerConfigured()
        await connector.connect()
        settings = connector.settings
    }
}

#Preview {
    NavigationStack {
        AllegroIntegrationView()
    }
}
