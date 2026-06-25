import SwiftUI

struct AllegroOrderImportSheet: View {
    let existingInvoices: [Invoice]
    let makeInvoiceNumber: (Int) -> String
    let seller: CompanyFormData?
    let onImport: ([Invoice], [Client]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var connections: [AllegroBackendConnection] = []
    @State private var selectedConnectionID: String?
    @State private var orders: [AllegroCheckoutForm] = []
    @State private var selectedOrderIDs: Set<String> = []
    @State private var statusMessage: StatusMessage?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var selectedRange: AllegroImportRange = .thirtyDays
    @State private var responseMeta: AllegroBackendOrdersMeta?
    @State private var connectedAccount: AllegroBackendAccount?
    @State private var hasCheckedAccount = false
    @State private var showsOrderList = false

    private let compactImportThreshold = 50

    private var selectedConnection: AllegroBackendConnection? {
        let activeID = selectedConnectionID ?? connections.first?.connectionID
        return connections.first { $0.connectionID == activeID }
    }

    private var selectedSourceAccountID: String? {
        selectedConnection?.accountID ?? selectedConnection?.connectionID
    }

    private var importableOrders: [AllegroCheckoutForm] {
        orders.filter { order in
            !existingInvoices.contains { invoice in
                guard let reference = invoice.marketplaceReference, reference.source == .allegro else { return false }
                guard reference.orderID == order.id else { return false }
                guard let selectedSourceAccountID else { return true }
                return reference.sourceAccountID == nil || reference.sourceAccountID == selectedSourceAccountID
            }
        }
    }

    private var selectedOrders: [AllegroCheckoutForm] {
        importableOrders.filter { selectedOrderIDs.contains($0.id) }
    }

    private var skippedOrderCount: Int {
        max(orders.count - importableOrders.count, 0)
    }

    private var usesCompactImport: Bool {
        importableOrders.count > compactImportThreshold
    }

    private var shouldShowOrderRows: Bool {
        !usesCompactImport || showsOrderList
    }

    private var localSellerName: String {
        seller?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Not selected"
    }

    private var allegroSellerName: String {
        allegroSeller?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unavailable"
    }

    private var connectedAccountName: String {
        connectedAccount?.displayName ?? selectedConnection?.shopName ?? (hasCheckedAccount ? "Unavailable" : "Checking...")
    }

    private var allegroSeller: CompanyFormData? {
        guard let connectedAccount else { return nil }
        let companyName = connectedAccount.companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let taxID = connectedAccount.companyTaxID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !companyName.isEmpty || !taxID.isEmpty else { return nil }

        var company = CompanyFormData.empty
        company.name = companyName.isEmpty ? connectedAccount.displayName : companyName
        company.taxId = taxID
        company.vatId = taxID
        return company
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if connections.isEmpty {
                        Label("Connect an Allegro shop before importing orders.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Picker("Shop", selection: Binding(
                            get: { selectedConnectionID ?? connections.first?.connectionID ?? "" },
                            set: { selectedConnectionID = $0 }
                        )) {
                            ForEach(connections) { connection in
                                Text(connection.shopName).tag(connection.connectionID)
                            }
                        }
                    }
                } header: {
                    Text("Shop")
                } footer: {
                    Text("Each Allegro shop is imported separately, even when several shops share the same legal seller and VAT ID.")
                }

                Section {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(AllegroImportRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Order History")
                } footer: {
                    Text("Fetches up to \(selectedRange.limit) Allegro orders from the selected period.")
                }

                Section {
                    LabeledContent("Connected account", value: connectedAccountName)
                    LabeledContent("Allegro seller", value: allegroSellerName)
                    LabeledContent("Local seller", value: localSellerName)
                    if hasCheckedAccount && allegroSeller == nil {
                        Label("Allegro did not return seller company details for this account.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Seller")
                } footer: {
                    Text("Imported invoices use the seller company returned by the connected Allegro account. Local seller profiles are shown only for comparison.")
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage.text, systemImage: statusMessage.systemImage)
                            .foregroundStyle(statusMessage.color)
                    }
                }

                if isLoading || isImporting {
                    Section {
                        ProgressView(isImporting ? "Importing selected orders..." : "Loading Allegro orders...")
                    }
                } else if !orders.isEmpty {
                    Section {
                        LabeledContent("Fetched", value: "\(responseMeta?.fetched ?? orders.count)")
                        if let totalAvailable = responseMeta?.totalAvailable {
                            LabeledContent("Available in Allegro", value: "\(totalAvailable)")
                        }
                        LabeledContent("Ready to import", value: "\(importableOrders.count)")
                        LabeledContent("Selected", value: "\(selectedOrderIDs.count)")
                        if skippedOrderCount > 0 {
                            LabeledContent("Already imported", value: "\(skippedOrderCount)")
                        }
                        if responseMeta?.filterMode == "updatedAt" {
                            LabeledContent("Matched by", value: "Updated date")
                        }
                    } header: {
                        Text("Summary")
                    } footer: {
                        if let totalAvailable = responseMeta?.totalAvailable, totalAvailable > orders.count {
                            Text("Allegro has more matching orders than this import can fetch at once. Narrow the date range or import in batches.")
                        }
                    }

                    if !importableOrders.isEmpty {
                        Section {
                            Button(selectedOrderIDs.count == importableOrders.count ? "Deselect All" : "Select All") {
                                toggleAllOrders()
                            }

                            if usesCompactImport {
                                Toggle("Show order list", isOn: $showsOrderList)
                                Label("Large imports are summarized to keep the app responsive.", systemImage: "speedometer")
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Selection")
                        }
                    }
                }

                if !isLoading && !isImporting && importableOrders.isEmpty {
                    Section {
                        ContentUnavailableView(
                            orders.isEmpty ? "No Allegro Orders" : "No New Orders",
                            systemImage: "cart.badge.questionmark",
                            description: Text(orders.isEmpty ? "Try a wider history range or import again after receiving orders." : "All fetched Allegro orders already have invoice drafts.")
                        )
                    }
                } else if !isLoading && !isImporting && shouldShowOrderRows {
                    Section("Orders") {
                        ForEach(importableOrders) { order in
                            Button {
                                toggle(order)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedOrderIDs.contains(order.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedOrderIDs.contains(order.id) ? .green : .secondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(order.buyer.displayName.isEmpty ? order.id : order.buyer.displayName)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(orderSubtitle(order))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(orderTotal(order))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Import from Allegro")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reloadOrders() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importing..." : "Import", action: importSelectedOrders)
                        .disabled(selectedOrders.isEmpty || allegroSeller == nil || isImporting)
                }
            }
            .task { await loadOrders() }
            .onChange(of: selectedRange) { _, _ in
                Task { await reloadOrders() }
            }
            .onChange(of: selectedConnectionID) { _, _ in
                Task { await reloadOrders() }
            }
        }
    }

    private func reloadOrders() async {
        orders = []
        selectedOrderIDs = []
        responseMeta = nil
        connectedAccount = nil
        hasCheckedAccount = false
        showsOrderList = false
        statusMessage = nil
        await loadOrders(forceReload: true)
    }

    private func loadOrders(forceReload: Bool = false) async {
        let store = AllegroBackendConnectionStore()
        connections = store.loadAll()
        if selectedConnectionID == nil {
            selectedConnectionID = store.load()?.connectionID ?? connections.first?.connectionID
        }
        guard forceReload || orders.isEmpty else { return }
        guard let connection = selectedConnection,
              let client = AllegroBackendConnectionClient(brokerBaseURL: connection.brokerBaseURL) else {
            statusMessage = StatusMessage(text: "Connect Allegro before importing orders.", systemImage: "exclamationmark.triangle", color: .orange)
            return
        }

        isLoading = true
        defer { isLoading = false }

        async let account = try? client.account(connectionID: connection.connectionID)

        do {
            let result = try await client.orders(connectionID: connection.connectionID, days: selectedRange.days, limit: selectedRange.limit)
            orders = result.orders
            responseMeta = result.meta
            connectedAccount = await account
            if let connectedAccount {
                let enrichedConnection = connection.enriched(with: connectedAccount)
                store.save(enrichedConnection)
                connections = store.loadAll()
                selectedConnectionID = enrichedConnection.connectionID
            }
            hasCheckedAccount = true
            selectedOrderIDs = Set(importableOrders.map(\.id))
            showsOrderList = importableOrders.count <= compactImportThreshold
        } catch {
            connectedAccount = await account
            hasCheckedAccount = true
            statusMessage = StatusMessage(error: error)
        }
    }

    private func toggle(_ order: AllegroCheckoutForm) {
        if selectedOrderIDs.contains(order.id) {
            selectedOrderIDs.remove(order.id)
        } else {
            selectedOrderIDs.insert(order.id)
        }
    }

    private func toggleAllOrders() {
        if selectedOrderIDs.count == importableOrders.count {
            selectedOrderIDs = []
        } else {
            selectedOrderIDs = Set(importableOrders.map(\.id))
        }
    }

    private func importSelectedOrders() {
        guard let allegroSeller else {
            statusMessage = StatusMessage(text: "Allegro did not return seller company details for this account.", systemImage: "exclamationmark.triangle", color: .orange)
            return
        }

        let sourceConnection = selectedConnection
        let ordersToImport = selectedOrders
        isImporting = true
        Task { @MainActor in
            await Task.yield()
            let invoices = ordersToImport.enumerated().map { offset, order in
                AllegroInvoiceMapper.makeInvoiceDraft(
                    from: order,
                    invoiceNumber: makeInvoiceNumber(offset),
                    seller: allegroSeller,
                    sourceConnection: sourceConnection
                )
            }
            let clients = ordersToImport.map { AllegroInvoiceMapper.makeClient(from: $0, sourceConnection: sourceConnection) }
            onImport(invoices, clients)
            isImporting = false
            dismiss()
        }
    }

    private func orderSubtitle(_ order: AllegroCheckoutForm) -> String {
        let itemCount = order.lineItems.count
        let status = order.status.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            itemCount == 1 ? "1 item" : "\(itemCount) items",
            status.isEmpty ? nil : status
        ].compactMap { $0 }
        return parts.joined(separator: " • ")
    }

    private func orderTotal(_ order: AllegroCheckoutForm) -> String {
        guard let total = order.summary?.totalToPay ?? order.payment?.paidAmount else {
            return ""
        }
        return total.amount.formatted(.currency(code: total.currency))
    }
}

private enum AllegroImportRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        }
    }

    var limit: Int {
        switch self {
        case .sevenDays: 300
        case .thirtyDays: 1000
        case .ninetyDays: 1000
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
