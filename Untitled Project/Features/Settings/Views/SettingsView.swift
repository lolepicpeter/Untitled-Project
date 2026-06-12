import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

private enum SettingsDestination: Hashable {
    case businessDetails
    case paymentOptions
    case vatSettings
    case invoiceNumbering
    case documentTemplate
    case clientCommunication
    case allegro
}

struct SettingsView: View {
    @State private var profileStore = MyCompanyProfileStore()
    @State private var isShowingSellerSetup = false
    @State private var navigationPath: [SettingsDestination] = []
    @State private var backupDocument = InvoiceFlowBackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupMessage: StatusMessage?

    private var selectedSellerBinding: Binding<UUID?> {
        Binding(
            get: { profileStore.selectedProfileID },
            set: { newValue in
                guard let newValue else { return }
                profileStore.selectProfile(id: newValue)
            }
        )
    }

    private var backupFilename: String {
        let date = Date().formatted(.iso8601.year().month().day())
        return "InvoiceFlow Backup \(date).json"
    }

    var body: some View {
        rootContent
            .sheet(isPresented: $isShowingSellerSetup, onDismiss: {
                profileStore.load()
            }) {
                NavigationStack {
                    MyCompanySetupView {
                        isShowingSellerSetup = false
                    }
                    .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    isShowingSellerSetup = false
                                }
                            }
                        }
                }
                .frame(minWidth: 760, minHeight: 620)
            }
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                handleBackupExport(result)
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImport(result)
            }
            .onAppear { profileStore.load() }
            .task {
                for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                    profileStore.load()
                }
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        NavigationStack(path: $navigationPath) {
            settingsList
                .navigationTitle("Settings")
                .navigationDestination(for: SettingsDestination.self) { destination in
                    settingsDestinationView(for: destination)
                }
        }
        #else
        NavigationStack(path: $navigationPath) {
            settingsList
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                settingsDestinationView(for: destination)
            }
        }
        #endif
    }

    private var settingsList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(profileStore.hasSavedProfile && !profileStore.company.name.isEmpty ? profileStore.company.name : "No seller selected")
                        .font(.headline)
                    Text("This seller is used for new invoices and invoice document details.")
                        .foregroundStyle(.secondary)

                    if profileStore.profiles.count > 1 {
                        Picker("Active seller", selection: selectedSellerBinding) {
                            ForEach(profileStore.profiles) { profile in
                                Text(profile.displayName).tag(Optional(profile.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if profileStore.hasSavedProfile {
                        Button(action: { isShowingSellerSetup = true }) {
                            Label("Manage Sellers", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(action: { isShowingSellerSetup = true }) {
                            Label("Set Up Seller", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Business Settings") {
                settingsRowButton(destination: .businessDetails, icon: "building.2.crop.circle", color: .blue, title: "Sellers")
                settingsRowButton(destination: .paymentOptions, icon: "creditcard", color: .green, title: "Payment options")
                settingsRowButton(destination: .vatSettings, icon: "percent", color: .red, title: "VAT settings")
            }

            Section("Documents") {
                settingsRowButton(destination: .invoiceNumbering, icon: "number", color: .blue, title: "Invoice numbering")
                settingsRowButton(destination: .documentTemplate, icon: "doc.text", color: .indigo, title: "Document template")
                settingsRowButton(destination: .clientCommunication, icon: "envelope", color: .red, title: "Client communication")
            }

            Section("Integrations") {
                settingsRowButton(destination: .allegro, icon: "cart", color: .purple, title: "Allegro")
            }

            Section {
                Button {
                    exportBackup()
                } label: {
                    SettingsRow(icon: "square.and.arrow.up", color: .teal, title: "Export backup")
                }
                .buttonStyle(.plain)

                Button {
                    isImportingBackup = true
                } label: {
                    SettingsRow(icon: "square.and.arrow.down", color: .orange, title: "Restore backup")
                }
                .buttonStyle(.plain)

                if let backupMessage {
                    Label(backupMessage.text, systemImage: backupMessage.systemImage)
                        .foregroundStyle(backupMessage.color)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Backups include invoices, clients, products, seller profiles, and invoice settings. Restoring a backup replaces the current local data.")
            }
        }
    }

    private func settingsRowButton(destination: SettingsDestination, icon: String, color: Color, title: String) -> some View {
        Button {
            navigationPath.append(destination)
        } label: {
            SettingsRow(icon: icon, color: color, title: title)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func exportBackup() {
        do {
            let data = try AppBackupService.makeBackupData()
            #if os(macOS)
            exportBackupWithSavePanel(data)
            #else
            backupDocument = InvoiceFlowBackupDocument(data: data)
            isExportingBackup = true
            #endif
        } catch {
            backupMessage = StatusMessage(error: error)
        }
    }

    #if os(macOS)
    private func exportBackupWithSavePanel(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = backupFilename

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
            backupMessage = StatusMessage(text: "Backup exported.", systemImage: "checkmark.circle", color: .green)
        } catch {
            backupMessage = StatusMessage(error: error)
        }
    }
    #endif

    private func handleBackupExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            backupMessage = StatusMessage(text: "Backup exported.", systemImage: "checkmark.circle", color: .green)
        case .failure(let error):
            backupMessage = StatusMessage(error: error)
        }
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            restoreBackup(from: url)
        case .failure(let error):
            backupMessage = StatusMessage(error: error)
        }
    }

    private func restoreBackup(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let backup = try AppBackupService.decodeBackup(from: data)
            AppBackupService.restore(backup)
            profileStore.load()
            backupMessage = StatusMessage(text: "Backup restored.", systemImage: "checkmark.circle", color: .green)
        } catch {
            backupMessage = StatusMessage(error: error)
        }
    }

    @ViewBuilder
    private func settingsDestinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .businessDetails:
            MyCompanySetupView()
        case .paymentOptions:
            PaymentOptionsSettingsView()
        case .vatSettings:
            VATSettingsView()
        case .invoiceNumbering:
            InvoiceNumberingSettingsView()
        case .documentTemplate:
            DocumentTemplateSettingsView()
        case .clientCommunication:
            ClientCommunicationSettingsView()
        case .allegro:
            AllegroIntegrationView()
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 6))

            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PaymentOptionsSettingsView: View {
    @State private var defaults = InvoiceDefaults.load()

    private var dueDescription: String {
        switch defaults.dueDays {
        case 0:
            "Due on the issue date"
        case 1:
            "Due 1 day after issue"
        default:
            "Due \(defaults.dueDays) days after issue"
        }
    }

    var body: some View {
        List {
            Section {
                Stepper(value: $defaults.dueDays, in: 0...120) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payment due")
                        Text(dueDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Default currency", selection: $defaults.currencyCode) {
                    ForEach(InvoiceDefaults.supportedCurrencyCodes, id: \.self) { currencyCode in
                        Text(currencyLabel(for: currencyCode)).tag(currencyCode)
                    }
                }
            } header: {
                Text("Invoice Defaults")
            } footer: {
                Text("These defaults are applied when creating a new invoice. Existing invoices keep their own due dates and currency.")
            }

            Section {
                Picker("Default method", selection: $defaults.paymentMethod) {
                    ForEach(InvoiceDefaults.supportedPaymentMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }

                TextField("Bank account, variable symbol, or payment note", text: $defaults.paymentInstructions, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Payment Details")
            } footer: {
                Text("Shown on invoice previews and printed documents.")
            }

            Section {
                Button("Reset Payment Defaults") {
                    defaults = InvoiceDefaults.reset()
                }
            }
        }
        .navigationTitle("Payment Options")
        .onChange(of: defaults) { _, newValue in
            newValue.save()
        }
    }

    private func currencyLabel(for currencyCode: String) -> String {
        let code = currencyCode.uppercased()
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) - \(name)"
    }
}

private struct VATSettingsView: View {
    @State private var defaults = InvoiceDefaults.load()

    private var vatDescription: String {
        "New invoices and products start with \(formattedVATRate) VAT. Existing saved records keep their own rates."
    }

    private var formattedVATRate: String {
        if defaults.vatRate.rounded() == defaults.vatRate {
            return "\(Int(defaults.vatRate))%"
        }
        return "\(defaults.vatRate.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    var body: some View {
        List {
            Section {
                Stepper(value: $defaults.vatRate, in: 0...100, step: 1) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default VAT rate")
                        Text(formattedVATRate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Invoice Defaults")
            } footer: {
                Text(vatDescription)
            }

            Section {
                Button("Reset to 20%") {
                    defaults.vatRate = InvoiceDefaults.standardVATRate
                    defaults.save()
                }
            }
        }
        .navigationTitle("VAT Settings")
        .onChange(of: defaults) { _, newValue in
            newValue.save()
        }
    }
}

private struct InvoiceNumberingSettingsView: View {
    @State private var settings = InvoiceNumberingSettings.load()

    private var previewNumber: String {
        settings.formattedNumber(sequence: settings.normalizedNextNumber)
    }

    var body: some View {
        List {
            Section {
                TextField("Prefix", text: $settings.prefix)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.characters)
                    #endif

                Toggle("Include year", isOn: $settings.includesYear)

                Stepper(value: $settings.nextNumber, in: 1...999_999) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next number")
                        Text("\(settings.normalizedNextNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $settings.minimumDigits, in: 1...8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Minimum digits")
                        Text("\(settings.normalizedMinimumDigits) digits")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Number Format")
            } footer: {
                Text("Used for new invoice drafts. Existing invoices keep their current numbers.")
            }

            Section("Preview") {
                LabeledContent("Next invoice", value: previewNumber)
            }

            Section {
                Button("Reset Numbering") {
                    settings = InvoiceNumberingSettings.reset()
                }
            }
        }
        .navigationTitle("Invoice Numbering")
        .onChange(of: settings) { _, newValue in
            newValue.save()
        }
    }
}

private struct DocumentTemplateSettingsView: View {
    @State private var settings = DocumentTemplateSettings.load()

    var body: some View {
        List {
            Section {
                TextField("Footer text", text: $settings.footerText)
                Toggle("Show signature lines", isOn: $settings.showsSignatureLines)
            } header: {
                Text("Invoice Document")
            } footer: {
                Text("Controls the invoice preview and printed document layout. Existing invoice data is unchanged.")
            }

            Section {
                Button("Reset Template Settings") {
                    settings = DocumentTemplateSettings.reset()
                }
            }
        }
        .navigationTitle("Document Template")
        .onChange(of: settings) { _, newValue in
            newValue.save()
        }
    }
}

private struct ClientCommunicationSettingsView: View {
    @State private var settings = ClientCommunicationSettings.load()

    var body: some View {
        List {
            Section {
                TextField("Subject", text: $settings.subjectTemplate)

                TextEditor(text: $settings.messageTemplate)
                    .font(.body)
                    .frame(minHeight: 160)
                    .padding(.vertical, 4)
            } header: {
                Text("Default Email")
            } footer: {
                Text("Available placeholders: {{invoiceNumber}}, {{clientName}}, {{sellerName}}, {{total}}, and {{dueDate}}.")
            }

            Section {
                Button("Reset Communication Settings") {
                    settings = ClientCommunicationSettings.reset()
                }
            }
        }
        .navigationTitle("Client Communication")
        .onChange(of: settings) { _, newValue in
            newValue.save()
        }
    }
}
