import SwiftUI

struct AllegroIntegrationView: View {
    @State private var connector = AllegroOAuthConnector()
    @State private var settings = AllegroConnectionSettings.load()

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    allegroIcon

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allegro")
                            .font(.headline)
                        Text(connector.connectionStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
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
                    .disabled(connector.isConnecting)
                }
            } footer: {
                if settings.isConfigured {
                    Text("This opens Allegro login and asks the seller to grant API access.")
                } else {
                    Text("Add your Allegro Developer Portal client ID and HTTPS callback URL below before connecting.")
                }
            }

            Section {
                TextField("Broker URL", text: $settings.brokerBaseURL)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Backend Broker")
            } footer: {
                Text("Use the HTTPS URL of your Allegro OAuth broker. The broker handles the Allegro callback and keeps the client secret out of the app.")
            }

            Section {
                Picker("Environment", selection: $settings.environment) {
                    ForEach(AllegroEnvironment.allCases) { environment in
                        Text(environment.title).tag(environment)
                    }
                }

                TextField("Client ID", text: $settings.clientID)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                TextField("Redirect URI", text: $settings.redirectURI)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Advanced Direct OAuth")
            } footer: {
                Text("Most Allegro apps should use the backend broker above. Direct OAuth is only for app types that Allegro allows without a client secret.")
            }

            Section {
                Button("Reset Allegro Settings", role: .destructive) {
                    connector.disconnect()
                    settings = AllegroConnectionSettings.reset()
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
        }
        .onChange(of: settings) { _, newValue in
            connector.saveSettings(newValue)
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

    private func connect() async {
        connector.saveSettings(settings)
        await connector.connect()
        settings = connector.settings
    }
}

#Preview {
    NavigationStack {
        AllegroIntegrationView()
    }
}
