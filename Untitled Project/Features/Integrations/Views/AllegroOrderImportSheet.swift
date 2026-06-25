import SwiftUI

struct AllegroOrderImportSheet: View {
    let existingInvoices: [Invoice]
    let makeInvoiceNumber: (Int) -> String
    let seller: CompanyFormData?
    let onImport: ([Invoice], [Client]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orders: [AllegroCheckoutForm] = []
    @State private var selectedOrderIDs: Set<String> = []
    @State private var statusMessage: StatusMessage?
    @State private var isLoading = false
    @State private var selectedRange: AllegroImportRange = .thirtyDays
    @State private var responseMeta: AllegroBackendOrdersMeta?
    @State private var connectedAccount: AllegroBackendAccount?
    @State private var hasCheckedAccount = false

    private var existingAllegroOrderIDs: Set<String> {
        Set(existingInvoices.compactMap { invoice in
            guard invoice.marketplaceReference?.source == .allegro else { return nil }
            return invoice.marketplaceReference?.orderID
        })
    }

    private var importableOrders: [AllegroCheckoutForm] {
        orders.filter { !existingAllegroOrderIDs.contains($0.id) }
    }

    private var selectedOrders: [AllegroCheckoutForm] {
        importableOrders.filter { selectedOrderIDs.contains($0.id) }
    }

    private var skippedOrderCount: Int {
        max(orders.count - importableOrders.count, 0)
    }

    private var sellerName: String {
        seller?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Not selected"
    }

    private var connectedAccountName: String {
        connectedAccount?.displayName ?? (hasCheckedAccount ? "Unavailable" : "Checking...")
    }

    var body: some View {
        NavigationStack {
            List {
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
                    LabeledContent("Invoice seller", value: sellerName)
                    if seller == nil {
                        Label("Set the correct seller profile before importing invoices.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Seller")
                } footer: {
                    Text("Imported invoices use the selected My Company seller profile, not the Allegro login name.")
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage.text, systemImage: statusMessage.systemImage)
                            .foregroundStyle(statusMessage.color)
                    }
                }

                if isLoading {
                    Section {
                        ProgressView("Loading Allegro orders...")
                    }
                } else if !orders.isEmpty {
                    Section {
                        LabeledContent("Fetched", value: "\(responseMeta?.fetched ?? orders.count)")
                        if let totalAvailable = responseMeta?.totalAvailable {
                            LabeledContent("Available in Allegro", value: "\(totalAvailable)")
                        }
                        LabeledContent("Ready to import", value: "\(importableOrders.count)")
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
                }

                if !isLoading && importableOrders.isEmpty {
                    Section {
                        ContentUnavailableView(
                            orders.isEmpty ? "No Allegro Orders" : "No New Orders",
                            systemImage: "cart.badge.questionmark",
                            description: Text(orders.isEmpty ? "Try a wider history range or import again after receiving orders." : "All fetched Allegro orders already have invoice drafts.")
                        )
                    }
                } else if !isLoading {
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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reloadOrders() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: importSelectedOrders)
                        .disabled(selectedOrders.isEmpty || seller == nil)
                }
            }
            .task { await loadOrders() }
            .onChange(of: selectedRange) { _, _ in
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
        statusMessage = nil
        await loadOrders(forceReload: true)
    }

    private func loadOrders(forceReload: Bool = false) async {
        guard forceReload || orders.isEmpty else { return }
        guard let connection = AllegroBackendConnectionStore().load(),
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
            hasCheckedAccount = true
            selectedOrderIDs = Set(importableOrders.map(\.id))
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

    private func importSelectedOrders() {
        guard seller != nil else {
            statusMessage = StatusMessage(text: "Set the correct seller profile before importing invoices.", systemImage: "exclamationmark.triangle", color: .orange)
            return
        }

        let invoices = selectedOrders.enumerated().map { offset, order in
            AllegroInvoiceMapper.makeInvoiceDraft(
                from: order,
                invoiceNumber: makeInvoiceNumber(offset),
                seller: seller
            )
        }
        let clients = selectedOrders.map { AllegroInvoiceMapper.makeClient(from: $0) }
        onImport(invoices, clients)
        dismiss()
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
