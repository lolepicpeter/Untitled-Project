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

    var body: some View {
        NavigationStack {
            List {
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
                        LabeledContent("Fetched", value: "\(orders.count)")
                        LabeledContent("Ready to import", value: "\(importableOrders.count)")
                        if skippedOrderCount > 0 {
                            LabeledContent("Already imported", value: "\(skippedOrderCount)")
                        }
                    } header: {
                        Text("Summary")
                    }
                }

                if !isLoading && importableOrders.isEmpty {
                    Section {
                        ContentUnavailableView(
                            orders.isEmpty ? "No Allegro Orders" : "No New Orders",
                            systemImage: "cart.badge.questionmark",
                            description: Text(orders.isEmpty ? "Connect Allegro and try again after receiving orders." : "All fetched Allegro orders already have invoice drafts.")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: importSelectedOrders)
                        .disabled(selectedOrders.isEmpty)
                }
            }
            .task { await loadOrders() }
        }
    }

    private func loadOrders() async {
        guard orders.isEmpty else { return }
        guard let connection = AllegroBackendConnectionStore().load(),
              let client = AllegroBackendConnectionClient(brokerBaseURL: connection.brokerBaseURL) else {
            statusMessage = StatusMessage(text: "Connect Allegro before importing orders.", systemImage: "exclamationmark.triangle", color: .orange)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            orders = try await client.orders(connectionID: connection.connectionID)
            selectedOrderIDs = Set(importableOrders.map(\.id))
        } catch {
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
