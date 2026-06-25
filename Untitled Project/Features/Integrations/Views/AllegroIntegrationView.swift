import SwiftUI

struct AllegroIntegrationView: View {
    @State private var connector = AllegroOAuthConnector()
    @State private var settings = AllegroConnectionSettings.load()
    @State private var showsTroubleshooting = false

    private var statusTitle: String {
        switch connector.backendConnections.count {
        case 0:
            "No sales channels connected"
        case 1:
            "1 sales channel connected"
        default:
            "\(connector.backendConnections.count) sales channels connected"
        }
    }

    private var statusColor: Color {
        connector.isConnected ? .green : .secondary
    }

    private var accountDisplayName: String {
        connector.backendConnection?.displayName.nonEmpty
        ?? connector.backendAccount?.displayName.nonEmpty
        ?? settings.connectedAccountName.nonEmpty
        ?? "Allegro account"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    allegroIcon

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allegro Sales Channels")
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
                Button {
                    Task { await connectAnotherShop() }
                } label: {
                    Label(connector.isConnecting ? "Opening Allegro..." : "Add Allegro Sales Channel", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(connector.isConnecting)
            } footer: {
                Text("Add each Allegro shop as a separate sales channel. Orders imported from each channel stay marked with their marketplace source.")
            }

            if connector.isConnected {
                Section {
                    ForEach(connector.backendConnections) { connection in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(connection.shopName)
                                        .font(.headline)
                                    Text(connection.legalSellerName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let taxID = connection.companyTaxID?.nonEmpty {
                                        Text(taxID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if connection.connectionID == connector.backendConnection?.connectionID {
                                    Text("Default")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.green.opacity(0.14), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }

                            HStack {
                                if connection.connectionID != connector.backendConnection?.connectionID {
                                    Button("Use by Default") {
                                        activate(connection)
                                    }
                                }

                                Button("Disconnect", role: .destructive) {
                                    Task { await disconnect(connection) }
                                }
                                .disabled(connector.isConnecting)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Sales Channels")
                } footer: {
                    Text("The default channel is preselected when importing Allegro orders. You can still choose another channel in the import sheet.")
                }

                Section {
                    LabeledContent("Default channel", value: accountDisplayName)
                    if let connectedAt = connector.backendConnection?.connectedAt {
                        LabeledContent("Connected", value: connectedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                } header: {
                    Text("Default Channel")
                }
            }

            Section {
                DisclosureGroup("Troubleshooting", isExpanded: $showsTroubleshooting) {
                    LabeledContent("Service", value: serviceHost)
                    LabeledContent("Environment", value: settings.environment.title)

                    if connector.isConnected {
                        Button {
                            Task { await switchAccount() }
                        } label: {
                            Label(connector.isConnecting ? "Opening Allegro..." : "Replace Default Channel", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(connector.isConnecting)
                    }

                    Button("Reset All Allegro Connections", role: .destructive) {
                        Task { await resetConnection() }
                    }
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
        .task {
            connector.reload()
            settings = connector.settings
            ensureProductionBrokerConfigured()
            await connector.refreshBackendAccount()
            settings = connector.settings
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

    private func connectAnotherShop() async {
        ensureProductionBrokerConfigured()
        await connector.connectAnotherShop()
        settings = connector.settings
    }

    private func switchAccount() async {
        ensureProductionBrokerConfigured()
        await connector.switchAccount()
        settings = connector.settings
    }

    private func activate(_ connection: AllegroBackendConnection) {
        connector.activate(connection: connection)
        settings = connector.settings
        Task { await connector.refreshBackendAccount() }
    }

    private func disconnect(_ connection: AllegroBackendConnection) async {
        await connector.disconnect(connection: connection)
        settings = connector.settings
    }

    private func resetConnection() async {
        await connector.disconnectAllConnections()
        settings = AllegroConnectionSettings.reset()
        connector.saveSettings(settings)
        connector.statusMessage = nil
        connector.backendAccount = nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        AllegroIntegrationView()
    }
}
