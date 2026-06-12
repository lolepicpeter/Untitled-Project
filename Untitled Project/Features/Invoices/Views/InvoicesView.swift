import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct InvoicesView: View {
    var body: some View {
        #if os(macOS)
        MacInvoicesView()
        #else
        MobileInvoicesView()
        #endif
    }
}

private enum InvoiceListFilter: String, CaseIterable, Identifiable {
    case all
    case drafts
    case issued
    case overdue
    case paid
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .drafts:
            "Drafts"
        case .issued:
            "Issued"
        case .overdue:
            "Overdue"
        case .paid:
            "Paid"
        case .cancelled:
            "Cancelled"
        }
    }

    func includes(_ invoice: Invoice) -> Bool {
        switch self {
        case .all:
            true
        case .drafts:
            invoice.displayStatus == .draft
        case .issued:
            invoice.displayStatus == .sent
        case .overdue:
            invoice.displayStatus == .overdue
        case .paid:
            invoice.displayStatus == .paid
        case .cancelled:
            invoice.displayStatus == .cancelled
        }
    }
}

private extension Invoice {
    func matchesSearch(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let searchableText = [
            number,
            clientName,
            clientEmail,
            sellerName,
            sellerTaxID,
            sellerVATID,
            orderNumber,
            displayStatus.title,
            lineItems.map(\.title).joined(separator: " ")
        ]
        .joined(separator: " ")

        return searchableText.localizedCaseInsensitiveContains(query)
    }

    var isReadyToIssue: Bool {
        issueBlockingMessages.isEmpty
    }

    var issueBlockingMessage: String? {
        issueBlockingMessages.first
    }

    var issueBlockingMessages: [String] {
        var messages: [String] = []

        if number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Add an invoice number before issuing.")
        }
        if sellerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Add seller details before issuing.")
        }
        if clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("Choose or create a client before issuing.")
        }
        if !lineItems.contains(where: { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.unitPrice > 0 }) {
            messages.append("Add at least one priced item before issuing.")
        }
        if total <= 0 {
            messages.append("Check item prices so the invoice total is above zero.")
        }

        return messages
    }
}

private struct MobileInvoicesView: View {
    @State private var store = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var invoiceDraft: Invoice?
    @State private var isShowingSellerSetup = false
    @State private var quickPaymentDraft: QuickPaymentDraft?
    @State private var invoicesPendingDiscard: [Invoice] = []
    @State private var searchText = ""
    @State private var statusFilter: InvoiceListFilter = .all

    private var filteredInvoices: [Invoice] {
        store.invoices.filter { invoice in
            statusFilter.includes(invoice) && invoice.matchesSearch(searchText)
        }
    }

    private var hasActiveFilters: Bool {
        statusFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyFilteredTitle: String {
        statusFilter == .all ? "No Matching Invoices" : "No \(statusFilter.title) Invoices"
    }

    private var emptyFilteredMessage: String {
        if hasActiveFilters {
            return "Clear the current search or status filter to get back to your invoice list."
        }
        return "Create an invoice to start tracking revenue, payments, and overdue work."
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.invoices.isEmpty {
                    InvoiceEmptyStateView(
                        title: "No Invoices",
                        systemImage: "doc.text",
                        message: "Create your first invoice with client details, line items, VAT, and due dates.",
                        primaryActionTitle: "Create Invoice",
                        primaryActionSystemImage: "plus",
                        primaryAction: addInvoice
                    )
                } else if filteredInvoices.isEmpty {
                    InvoiceEmptyStateView(
                        title: emptyFilteredTitle,
                        systemImage: "doc.text.magnifyingglass",
                        message: emptyFilteredMessage,
                        primaryActionTitle: "Clear Filters",
                        primaryActionSystemImage: "line.3.horizontal.decrease.circle",
                        primaryAction: clearFilters
                    )
                } else {
                    List {
                        ForEach(filteredInvoices) { invoice in
                            NavigationLink {
                                MobileInvoiceDetailView(
                                    invoice: invoice,
                                    onSave: { updatedInvoice in
                                        store.save(updatedInvoice)
                                    },
                                    onDuplicate: { sourceInvoice in
                                        let duplicate = store.duplicateDraft(from: sourceInvoice)
                                        store.save(duplicate)
                                        return duplicate
                                    },
                                    onDiscardDraft: { draftInvoice in
                                        store.delete(draftInvoice)
                                    }
                                )
                            } label: {
                                InvoiceRow(invoice: invoice)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if invoice.canDiscardDraft {
                                    Button(role: .destructive) {
                                        requestDiscardDraft(invoice)
                                    } label: {
                                        Label("Discard", systemImage: "trash")
                                    }
                                }

                                Button {
                                    duplicate(invoice)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if canRecordPayment(for: invoice) {
                                    Button {
                                        beginQuickPayment(for: invoice)
                                    } label: {
                                        Label("Pay", systemImage: "banknote")
                                    }
                                    .tint(.green)
                                }
                            }
                            .contextMenu {
                                if canRecordPayment(for: invoice) {
                                    Button {
                                        beginQuickPayment(for: invoice)
                                    } label: {
                                        Label("Record Payment", systemImage: "banknote")
                                    }
                                }

                                Button {
                                    duplicate(invoice)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }

                                if invoice.canDiscardDraft {
                                    Button(role: .destructive) {
                                        requestDiscardDraft(invoice)
                                    } label: {
                                        Label("Discard Draft", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $searchText, prompt: "Search invoices")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(InvoiceListFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addInvoice()
                    } label: {
                        Label("New Invoice", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $invoiceDraft) { invoice in
                NavigationStack {
                    InvoiceEditorView(invoice: invoice, title: "New Invoice") { savedInvoice in
                        store.save(savedInvoice)
                        invoiceDraft = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { invoiceDraft = nil }
                        }
                    }
                }
            }
            .sheet(item: $quickPaymentDraft) { draft in
                InvoicePaymentSheet(invoice: draft.invoice, payment: draft.payment) { payment in
                    recordQuickPayment(payment, for: draft.invoice)
                    quickPaymentDraft = nil
                } onDelete: { payment in
                    deleteQuickPayment(payment, from: draft.invoice)
                    quickPaymentDraft = nil
                }
            }
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
            }
            .confirmationDialog(
                discardConfirmationTitle,
                isPresented: discardConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button(discardConfirmationActionTitle, role: .destructive, action: confirmDiscardDrafts)
                Button("Keep Draft", role: .cancel) { invoicesPendingDiscard = [] }
            } message: {
                Text("Discarded drafts are removed from your invoice list. Issued invoices stay in your records.")
            }
            .onAppear {
                store.load()
                profileStore.load()
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                    profileStore.load()
                }
            }
        }
    }

    private func addInvoice() {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        invoiceDraft = store.newInvoiceDraft()
    }

    private func canRecordPayment(for invoice: Invoice) -> Bool {
        let status = invoice.displayStatus
        return invoice.balanceDue > 0.005 && (status == .sent || status == .overdue)
    }

    private func beginQuickPayment(for invoice: Invoice) {
        quickPaymentDraft = QuickPaymentDraft(
            invoice: invoice,
            payment: InvoicePayment(
                id: UUID(),
                date: Date(),
                amount: invoice.balanceDue,
                method: invoice.defaultPaymentRecordMethod,
                reference: "",
                note: ""
            )
        )
    }

    private func recordQuickPayment(_ payment: InvoicePayment, for invoice: Invoice) {
        var updatedInvoice = invoice
        if let index = updatedInvoice.payments.firstIndex(where: { $0.id == payment.id }) {
            updatedInvoice.payments[index] = payment
        } else {
            updatedInvoice.payments.append(payment)
        }
        updatedInvoice.refreshStatus()
        store.save(updatedInvoice)
    }

    private func deleteQuickPayment(_ payment: InvoicePayment, from invoice: Invoice) {
        var updatedInvoice = invoice
        updatedInvoice.payments.removeAll { $0.id == payment.id }
        updatedInvoice.refreshStatus()
        store.save(updatedInvoice)
    }

    private func duplicate(_ invoice: Invoice) {
        store.save(store.duplicateDraft(from: invoice))
    }

    private func clearFilters() {
        searchText = ""
        statusFilter = .all
    }

    private var discardConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !invoicesPendingDiscard.isEmpty },
            set: { isPresented in
                if !isPresented {
                    invoicesPendingDiscard = []
                }
            }
        )
    }

    private var discardConfirmationTitle: String {
        if invoicesPendingDiscard.count == 1, let invoice = invoicesPendingDiscard.first {
            return "Discard \(invoice.displayTitle)?"
        }
        return "Discard \(invoicesPendingDiscard.count) Drafts?"
    }

    private var discardConfirmationActionTitle: String {
        invoicesPendingDiscard.count == 1 ? "Discard Draft" : "Discard Drafts"
    }

    private func requestDiscardDraft(_ invoice: Invoice) {
        requestDiscardDrafts([invoice])
    }

    private func requestDiscardDrafts(_ invoices: [Invoice]) {
        let drafts = invoices.filter(\.canDiscardDraft)
        guard !drafts.isEmpty else { return }
        invoicesPendingDiscard = drafts
    }

    private func confirmDiscardDrafts() {
        for invoice in invoicesPendingDiscard {
            store.delete(invoice)
        }
        invoicesPendingDiscard = []
    }

    private func delete(at offsets: IndexSet) {
        let drafts = offsets.compactMap { index in
            filteredInvoices.indices.contains(index) ? filteredInvoices[index] : nil
        }
        requestDiscardDrafts(drafts)
    }
}

private struct InvoiceEmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    let primaryActionTitle: String
    let primaryActionSystemImage: String
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(message)
            )

            Button(action: primaryAction) {
                Label(primaryActionTitle, systemImage: primaryActionSystemImage)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickPaymentDraft: Identifiable {
    let id = UUID()
    let invoice: Invoice
    let payment: InvoicePayment
}

#if os(macOS)
private struct MacInvoiceFilterBar: View {
    @Binding var selection: InvoiceListFilter
    let invoices: [Invoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Invoice status", selection: $selection) {
                ForEach(InvoiceListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .transaction { transaction in
                transaction.animation = nil
            }

            Text(filterSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterSummary: String {
        let visibleCount = invoices.filter { selection.includes($0) }.count
        let totalCount = invoices.count
        return selection == .all ? "\(totalCount) invoices" : "\(visibleCount) of \(totalCount) invoices"
    }
}

private struct MacInvoicesView: View {
    @State private var store = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var selectedInvoiceIDs: Set<Invoice.ID> = []
    @State private var selectionAnchorInvoiceID: Invoice.ID?
    @State private var selectionExtentInvoiceID: Invoice.ID?
    @State private var editingInvoice: Invoice?
    @State private var isShowingSellerSetup = false
    @State private var invoicesPendingDiscard: [Invoice] = []
    @State private var searchText = ""
    @State private var statusFilter: InvoiceListFilter = .all
    @State private var isInvoiceListFocused = false

    private var filteredInvoices: [Invoice] {
        store.invoices.filter { invoice in
            statusFilter.includes(invoice) && invoice.matchesSearch(searchText)
        }
    }

    private var selectedInvoice: Invoice? {
        guard selectedInvoiceIDs.count == 1,
              let selectedInvoiceID = selectedInvoiceIDs.first else { return nil }
        return store.invoices.first { $0.id == selectedInvoiceID }
    }

    private var selectedInvoices: [Invoice] {
        filteredInvoices.filter { selectedInvoiceIDs.contains($0.id) }
    }

    private var hasActiveFilters: Bool {
        statusFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptySelectionTitle: String {
        if store.invoices.isEmpty { return "No Invoices" }
        if filteredInvoices.isEmpty {
            return statusFilter == .all ? "No Matching Invoices" : "No \(statusFilter.title) Invoices"
        }
        return "No Invoice Selected"
    }

    private var emptySelectionMessage: String {
        if store.invoices.isEmpty {
            return "Create an invoice to start tracking revenue, payments, and overdue work."
        }
        if filteredInvoices.isEmpty {
            return "Clear the current search or status filter to get back to your invoice list."
        }
        return "Select an invoice or create a new one."
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    MacInvoiceFilterBar(selection: $statusFilter, invoices: store.invoices)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredInvoices) { invoice in
                                VStack(spacing: 0) {
                                    Button {
                                        selectInvoice(invoice)
                                    } label: {
                                        InvoiceRow(
                                            invoice: invoice,
                                            isSelected: selectedInvoiceIDs.contains(invoice.id)
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        let contextInvoices = contextInvoices(for: invoice)

                                        if contextInvoices.contains(where: { $0.displayStatus == .draft }) {
                                            Button {
                                                issue(contextInvoices)
                                            } label: {
                                                Label(contextInvoices.count > 1 ? "Issue Selected Drafts" : "Issue Draft", systemImage: "checkmark.seal")
                                            }
                                        }

                                        Button {
                                            if contextInvoices.count > 1 {
                                                duplicate(contextInvoices)
                                            } else {
                                                duplicate(invoice)
                                            }
                                        } label: {
                                            Label(contextInvoices.count > 1 ? "Duplicate Selected" : "Duplicate", systemImage: "doc.on.doc")
                                        }

                                        if contextInvoices.contains(where: { ($0.displayStatus == .sent || $0.displayStatus == .overdue) && $0.balanceDue > 0.005 }) {
                                            Button {
                                                markPaid(contextInvoices)
                                            } label: {
                                                Label(contextInvoices.count > 1 ? "Mark Selected Paid" : "Mark Paid", systemImage: "checkmark.circle")
                                            }
                                        }

                                        if contextInvoices.contains(where: { $0.displayStatus == .sent || $0.displayStatus == .overdue }) {
                                            Button(role: .destructive) {
                                                cancel(contextInvoices)
                                            } label: {
                                                Label(contextInvoices.count > 1 ? "Cancel Selected" : "Cancel", systemImage: "xmark.circle")
                                            }
                                        }

                                        if contextInvoices.contains(where: { $0.displayStatus == .cancelled }) {
                                            Button {
                                                restore(contextInvoices)
                                            } label: {
                                                Label(contextInvoices.count > 1 ? "Restore Selected" : "Restore", systemImage: "arrow.uturn.backward.circle")
                                            }
                                        }

                                        if contextInvoices.contains(where: \.canDiscardDraft) {
                                            Button(role: .destructive) {
                                                requestDiscardDrafts(contextInvoices)
                                            } label: {
                                                Label(contextInvoices.count > 1 ? "Discard Selected Drafts" : "Discard Draft", systemImage: "trash")
                                            }
                                        }
                                    }

                                    if invoice.id != filteredInvoices.last?.id {
                                        Divider()
                                            .padding(.leading, 10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onMacKeyDown(perform: handleInvoiceListKeyDown)
                    .onDeleteCommand {
                        discardSelectedDraft()
                    }
                }
                .frame(width: 360)

                Divider()

                Group {
                    if selectedInvoices.count > 1 {
                        SelectedInvoicesPanel(
                            invoices: selectedInvoices,
                            onIssueDrafts: {
                                issue(selectedInvoices)
                            },
                            onDuplicate: {
                                duplicate(selectedInvoices)
                            },
                            onMarkPaid: {
                                markPaid(selectedInvoices)
                            },
                            onCancel: {
                                cancel(selectedInvoices)
                            },
                            onRestore: {
                                restore(selectedInvoices)
                            },
                            onDiscardDrafts: {
                                requestDiscardDrafts(selectedInvoices)
                            },
                            onClearSelection: {
                                selectedInvoiceIDs = []
                                selectionAnchorInvoiceID = nil
                                selectionExtentInvoiceID = nil
                            }
                        )
                    } else if let selectedInvoice {
                        MacInvoicePreviewView(
                            invoice: selectedInvoice,
                            onIssue: {
                                issue(selectedInvoice)
                            },
                            onRecordPayment: { payment in
                                recordPayment(payment, for: selectedInvoice)
                            },
                            onDeletePayment: { payment in
                                deletePayment(payment, from: selectedInvoice)
                            },
                            onEdit: {
                                editingInvoice = selectedInvoice
                            },
                            onDuplicate: {
                                duplicate(selectedInvoice)
                            },
                            onMarkPaid: {
                                markPaid(selectedInvoice)
                            },
                            onCancel: {
                                cancel(selectedInvoice)
                            },
                            onRestore: {
                                restore(selectedInvoice)
                            },
                            onDiscardDraft: {
                                requestDiscardDraft(selectedInvoice)
                            }
                        )
                    } else {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                emptySelectionTitle,
                                systemImage: filteredInvoices.isEmpty ? "doc.text.magnifyingglass" : "doc.text",
                                description: Text(emptySelectionMessage)
                            )

                            if filteredInvoices.isEmpty && !store.invoices.isEmpty && hasActiveFilters {
                                Button(action: clearFilters) {
                                    Label("Clear Filters", systemImage: "line.3.horizontal.decrease.circle")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button(action: addInvoice) {
                                    Label("Create Invoice", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .navigationTitle("Invoices")
        .searchable(text: $searchText, prompt: "Search invoices")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !filteredInvoices.isEmpty {
                    Button(action: selectAllVisibleInvoices) {
                        Label("Select All", systemImage: "checklist")
                    }
                    .keyboardShortcut("a", modifiers: .command)
                    .help("Select All Invoices")
                }

                if !selectedInvoices.isEmpty {
                    Button(action: { duplicate(selectedInvoices) }) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .help("Duplicate Selected Invoices")
                }

                Button(action: addInvoice) {
                    Label("New Invoice", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $editingInvoice) { invoice in
            NavigationStack {
                InvoiceEditorView(invoice: invoice, title: invoice.displayTitle) { updatedInvoice in
                    store.save(updatedInvoice)
                    selectedInvoiceIDs = [updatedInvoice.id]
                    selectionAnchorInvoiceID = updatedInvoice.id
                    selectionExtentInvoiceID = updatedInvoice.id
                    editingInvoice = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingInvoice = nil }
                    }
                }
            }
            .frame(minWidth: 1080, minHeight: 760)
        }
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
        .confirmationDialog(
            discardConfirmationTitle,
            isPresented: discardConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(discardConfirmationActionTitle, role: .destructive, action: confirmDiscardDrafts)
            Button("Keep Draft", role: .cancel) { invoicesPendingDiscard = [] }
        } message: {
            Text("Discarded drafts are removed from your invoice list. Issued invoices stay in your records.")
        }
        .onAppear {
            store.load()
            profileStore.load()
            if selectedInvoiceIDs.isEmpty, let firstInvoiceID = store.invoices.first?.id {
                selectedInvoiceIDs = [firstInvoiceID]
                selectionAnchorInvoiceID = firstInvoiceID
                selectionExtentInvoiceID = firstInvoiceID
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                profileStore.load()
            }
        }
        .onChange(of: searchText) { _, _ in
            trimMultiSelectionToVisibleInvoices()
        }
        .onChange(of: statusFilter) { _, _ in
            trimMultiSelectionToVisibleInvoices()
        }
    }

    private func addInvoice() {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        editingInvoice = store.newInvoiceDraft()
    }

    private func contextInvoices(for invoice: Invoice) -> [Invoice] {
        if selectedInvoiceIDs.contains(invoice.id), selectedInvoices.count > 1 {
            return selectedInvoices
        }
        return [invoice]
    }

    private func selectInvoice(_ invoice: Invoice) {
        isInvoiceListFocused = true
        let modifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags.contains(.shift) {
            extendInvoiceSelection(to: invoice.id)
        } else if modifierFlags.contains(.command) {
            toggleInvoiceSelection(invoice.id)
        } else {
            selectedInvoiceIDs = [invoice.id]
            selectionAnchorInvoiceID = invoice.id
            selectionExtentInvoiceID = invoice.id
        }
    }

    private func toggleInvoiceSelection(_ invoiceID: Invoice.ID) {
        if selectedInvoiceIDs.contains(invoiceID) {
            selectedInvoiceIDs.remove(invoiceID)
        } else {
            selectedInvoiceIDs.insert(invoiceID)
        }
        selectionAnchorInvoiceID = invoiceID
        selectionExtentInvoiceID = invoiceID
    }

    private func extendInvoiceSelection(to invoiceID: Invoice.ID) {
        guard let targetIndex = filteredInvoices.firstIndex(where: { $0.id == invoiceID }) else { return }
        let anchorID = selectionAnchorInvoiceID ?? selectedInvoiceIDs.first { selectedID in
            filteredInvoices.contains { $0.id == selectedID }
        } ?? invoiceID
        guard let anchorIndex = filteredInvoices.firstIndex(where: { $0.id == anchorID }) else {
            selectedInvoiceIDs = [invoiceID]
            selectionAnchorInvoiceID = invoiceID
            selectionExtentInvoiceID = invoiceID
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedInvoiceIDs = Set(range.map { filteredInvoices[$0].id })
        selectionAnchorInvoiceID = anchorID
        selectionExtentInvoiceID = invoiceID
    }

    private func selectAllVisibleInvoices() {
        selectedInvoiceIDs = Set(filteredInvoices.map(\.id))
        selectionAnchorInvoiceID = filteredInvoices.first?.id
        selectionExtentInvoiceID = filteredInvoices.last?.id
    }

    private func issue(_ invoice: Invoice) {
        guard invoice.displayStatus == .draft, invoice.isReadyToIssue else { return }
        var updatedInvoice = invoice
        updatedInvoice.issue()
        store.save(updatedInvoice)
        selectedInvoiceIDs = [updatedInvoice.id]
    }

    private func issue(_ invoices: [Invoice]) {
        let drafts = invoices.filter { $0.displayStatus == .draft && $0.isReadyToIssue }
        guard !drafts.isEmpty else { return }
        var updatedIDs: Set<Invoice.ID> = []
        for invoice in drafts {
            var updatedInvoice = invoice
            updatedInvoice.issue()
            store.save(updatedInvoice)
            updatedIDs.insert(updatedInvoice.id)
        }
        selectedInvoiceIDs = updatedIDs
    }

    private func duplicate(_ invoice: Invoice) {
        let duplicate = store.duplicateDraft(from: invoice)
        store.save(duplicate)
        selectedInvoiceIDs = [duplicate.id]
        editingInvoice = duplicate
    }

    private func duplicate(_ invoices: [Invoice]) {
        guard !invoices.isEmpty else { return }
        var duplicateIDs: Set<Invoice.ID> = []
        for invoice in invoices {
            let duplicate = store.duplicateDraft(from: invoice)
            store.save(duplicate)
            duplicateIDs.insert(duplicate.id)
        }
        selectedInvoiceIDs = duplicateIDs
    }

    private func clearFilters() {
        searchText = ""
        statusFilter = .all
    }

    private func markPaid(_ invoice: Invoice) {
        var updatedInvoice = invoice
        updatedInvoice.payments.append(
            InvoicePayment(
                id: UUID(),
                date: Date(),
                amount: invoice.balanceDue,
                method: invoice.defaultPaymentRecordMethod,
                reference: "",
                note: "Marked paid"
            )
        )
        updatedInvoice.refreshStatus()
        store.save(updatedInvoice)
        selectedInvoiceIDs = [updatedInvoice.id]
    }

    private func markPaid(_ invoices: [Invoice]) {
        let payableInvoices = invoices.filter { ($0.displayStatus == .sent || $0.displayStatus == .overdue) && $0.balanceDue > 0.005 }
        guard !payableInvoices.isEmpty else { return }
        var updatedIDs: Set<Invoice.ID> = []
        for invoice in payableInvoices {
            var updatedInvoice = invoice
            updatedInvoice.payments.append(
                InvoicePayment(
                    id: UUID(),
                    date: Date(),
                    amount: invoice.balanceDue,
                    method: invoice.defaultPaymentRecordMethod,
                    reference: "",
                    note: "Marked paid"
                )
            )
            updatedInvoice.refreshStatus()
            store.save(updatedInvoice)
            updatedIDs.insert(updatedInvoice.id)
        }
        selectedInvoiceIDs = updatedIDs
    }

    private func cancel(_ invoice: Invoice) {
        var updatedInvoice = invoice
        updatedInvoice.status = .cancelled
        store.save(updatedInvoice)
        selectedInvoiceIDs = [updatedInvoice.id]
    }

    private func cancel(_ invoices: [Invoice]) {
        let cancellableInvoices = invoices.filter { $0.displayStatus == .sent || $0.displayStatus == .overdue }
        guard !cancellableInvoices.isEmpty else { return }
        var updatedIDs: Set<Invoice.ID> = []
        for invoice in cancellableInvoices {
            var updatedInvoice = invoice
            updatedInvoice.status = .cancelled
            store.save(updatedInvoice)
            updatedIDs.insert(updatedInvoice.id)
        }
        selectedInvoiceIDs = updatedIDs
    }

    private func restore(_ invoice: Invoice) {
        var updatedInvoice = invoice
        updatedInvoice.status = .sent
        updatedInvoice.refreshStatus()
        store.save(updatedInvoice)
        selectedInvoiceIDs = [updatedInvoice.id]
    }

    private func restore(_ invoices: [Invoice]) {
        let restorableInvoices = invoices.filter { $0.displayStatus == .cancelled }
        guard !restorableInvoices.isEmpty else { return }
        var updatedIDs: Set<Invoice.ID> = []
        for invoice in restorableInvoices {
            var updatedInvoice = invoice
            updatedInvoice.status = .sent
            updatedInvoice.refreshStatus()
            store.save(updatedInvoice)
            updatedIDs.insert(updatedInvoice.id)
        }
        selectedInvoiceIDs = updatedIDs
    }

    private func recordPayment(_ payment: InvoicePayment, for invoice: Invoice) {
        var updatedInvoice = invoice
        if let index = updatedInvoice.payments.firstIndex(where: { $0.id == payment.id }) {
            updatedInvoice.payments[index] = payment
        } else {
            updatedInvoice.payments.append(payment)
        }
        updatedInvoice.refreshStatus()
        store.save(updatedInvoice)
        selectedInvoiceIDs = [updatedInvoice.id]
    }

    private func deletePayment(_ payment: InvoicePayment, from invoice: Invoice) {
        var updatedInvoice = invoice
        updatedInvoice.payments.removeAll { $0.id == payment.id }
        updatedInvoice.refreshStatus()
        store.save(updatedInvoice)
        selectedInvoiceIDs = [updatedInvoice.id]
    }

    private func handleInvoiceListKeyDown(_ event: NSEvent) -> Bool {
        guard isInvoiceListFocused, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }

        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 126 where modifierFlags.contains(.shift):
            selectAdjacentInvoice(offset: -1, extendingSelection: true)
            return true
        case 125 where modifierFlags.contains(.shift):
            selectAdjacentInvoice(offset: 1, extendingSelection: true)
            return true
        case 126:
            selectAdjacentInvoice(offset: -1)
            return true
        case 125:
            selectAdjacentInvoice(offset: 1)
            return true
        case 51:
            discardSelectedDraft()
            return true
        case 0 where modifierFlags.contains(.command):
            selectAllVisibleInvoices()
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            selectAdjacentInvoice(offset: -1)
        case .down:
            selectAdjacentInvoice(offset: 1)
        default:
            break
        }
    }

    private func selectAdjacentInvoice(offset: Int, extendingSelection: Bool = false) {
        guard !filteredInvoices.isEmpty else {
            selectedInvoiceIDs = []
            selectionAnchorInvoiceID = nil
            selectionExtentInvoiceID = nil
            return
        }

        let currentID = selectionExtentInvoiceID ?? selectionAnchorInvoiceID ?? selectedInvoices.first?.id

        guard let currentID,
              let currentIndex = filteredInvoices.firstIndex(where: { $0.id == currentID }) else {
            let firstID = filteredInvoices.first!.id
            selectedInvoiceIDs = [firstID]
            selectionAnchorInvoiceID = firstID
            selectionExtentInvoiceID = firstID
            return
        }

        let nextIndex = min(max(currentIndex + offset, filteredInvoices.startIndex), filteredInvoices.index(before: filteredInvoices.endIndex))
        let nextID = filteredInvoices[nextIndex].id
        if extendingSelection || NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
            if selectionAnchorInvoiceID == nil {
                selectionAnchorInvoiceID = currentID
            }
            extendInvoiceSelection(to: nextID)
        } else {
            selectedInvoiceIDs = [nextID]
            selectionAnchorInvoiceID = nextID
            selectionExtentInvoiceID = nextID
        }
    }

    private func trimMultiSelectionToVisibleInvoices() {
        guard selectedInvoiceIDs.count > 1 else { return }

        let visibleIDs = Set(filteredInvoices.map(\.id))
        selectedInvoiceIDs = selectedInvoiceIDs.intersection(visibleIDs)
        if let selectionAnchorInvoiceID, !visibleIDs.contains(selectionAnchorInvoiceID) {
            self.selectionAnchorInvoiceID = selectedInvoiceIDs.first
        }
        if let selectionExtentInvoiceID, !visibleIDs.contains(selectionExtentInvoiceID) {
            self.selectionExtentInvoiceID = selectedInvoiceIDs.first
        }
    }

    private func discardSelectedDraft() {
        requestDiscardDrafts(selectedInvoices)
    }

    private var discardConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !invoicesPendingDiscard.isEmpty },
            set: { isPresented in
                if !isPresented {
                    invoicesPendingDiscard = []
                }
            }
        )
    }

    private var discardConfirmationTitle: String {
        if invoicesPendingDiscard.count == 1, let invoice = invoicesPendingDiscard.first {
            return "Discard \(invoice.displayTitle)?"
        }
        return "Discard \(invoicesPendingDiscard.count) Drafts?"
    }

    private var discardConfirmationActionTitle: String {
        invoicesPendingDiscard.count == 1 ? "Discard Draft" : "Discard Drafts"
    }

    private func requestDiscardDraft(_ invoice: Invoice) {
        requestDiscardDrafts([invoice])
    }

    private func requestDiscardDrafts(_ invoices: [Invoice]) {
        let drafts = invoices.filter(\.canDiscardDraft)
        guard !drafts.isEmpty else { return }
        invoicesPendingDiscard = drafts
    }

    private func confirmDiscardDrafts() {
        let discardedIDs = Set(invoicesPendingDiscard.map(\.id))
        for invoice in invoicesPendingDiscard {
            store.delete(invoice)
        }
        invoicesPendingDiscard = []
        selectedInvoiceIDs.subtract(discardedIDs)
        if selectedInvoiceIDs.isEmpty, let firstInvoiceID = filteredInvoices.first?.id ?? store.invoices.first?.id {
            selectedInvoiceIDs = [firstInvoiceID]
            selectionAnchorInvoiceID = firstInvoiceID
            selectionExtentInvoiceID = firstInvoiceID
        }
    }

    private func delete(at offsets: IndexSet) {
        let drafts = offsets.compactMap { index in
            filteredInvoices.indices.contains(index) ? filteredInvoices[index] : nil
        }
        requestDiscardDrafts(drafts)
    }
}

private struct MacInvoicesHeader: View {
    @Binding var searchText: String
    let onAddInvoice: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Invoices")
                .font(.title3.weight(.semibold))

            Spacer()

            Button(action: onAddInvoice) {
                Label("New Invoice", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
            .help("New Invoice")

            TextField("Search invoices", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct InvoiceReadinessChecklist: View {
    let messages: [String]

    private var isReady: Bool {
        messages.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isReady ? "Ready to issue" : "Before issuing", systemImage: isReady ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isReady ? .green : .orange)

            if isReady {
                Text("This draft has the required seller, client, invoice number, and billable item details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isReady ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SelectedInvoicesPanel: View {
    let invoices: [Invoice]
    let onIssueDrafts: () -> Void
    let onDuplicate: () -> Void
    let onMarkPaid: () -> Void
    let onCancel: () -> Void
    let onRestore: () -> Void
    let onDiscardDrafts: () -> Void
    let onClearSelection: () -> Void

    private var draftCount: Int {
        invoices.filter(\.canDiscardDraft).count
    }

    private var issueReadyDraftCount: Int {
        invoices.filter { $0.displayStatus == .draft && $0.isReadyToIssue }.count
    }

    private var payableCount: Int {
        invoices.filter { ($0.displayStatus == .sent || $0.displayStatus == .overdue) && $0.balanceDue > 0.005 }.count
    }

    private var cancellableCount: Int {
        invoices.filter { $0.displayStatus == .sent || $0.displayStatus == .overdue }.count
    }

    private var restorableCount: Int {
        invoices.filter { $0.displayStatus == .cancelled }.count
    }

    private var totalAmount: Double {
        invoices.reduce(0) { $0 + $1.total }
    }

    private var primaryCurrencyCode: String {
        invoices.first?.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? invoices.first!.currencyCode : "EUR"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("\(invoices.count) Invoices Selected")
                    .font(.title2.weight(.semibold))

                Text("\(draftCount) drafts • Total \(totalAmount.formatted(.currency(code: primaryCurrencyCode)))")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: onIssueDrafts) {
                        Label(issueReadyDraftCount == 1 ? "Issue Draft" : "Issue Drafts", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(issueReadyDraftCount == 0)

                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button(action: onMarkPaid) {
                        Label("Mark Paid", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(payableCount == 0)

                    Button(role: .destructive, action: onCancel) {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(cancellableCount == 0)

                    Button(action: onRestore) {
                        Label("Restore", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(restorableCount == 0)
                }

                HStack(spacing: 10) {
                    Button(role: .destructive, action: onDiscardDrafts) {
                        Label("Discard Drafts", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(draftCount == 0)

                    Button("Clear Selection", action: onClearSelection)
                        .buttonStyle(.bordered)
                }
            }

            Text("Use Shift-click to select a range, Command-click to toggle individual invoices, Delete to discard selected drafts, or right-click for batch actions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MacInvoicePreviewView: View {
    let invoice: Invoice
    let onIssue: () -> Void
    let onRecordPayment: (InvoicePayment) -> Void
    let onDeletePayment: (InvoicePayment) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onMarkPaid: () -> Void
    let onCancel: () -> Void
    let onRestore: () -> Void
    let onDiscardDraft: () -> Void

    @State private var clientStore = ClientStore()
    @State private var companyProfileStore = MyCompanyProfileStore()
    @State private var isShowingDocumentPreview = false
    @State private var isShowingEmailDraft = false
    @State private var isConfirmingCancel = false
    @State private var isConfirmingMarkPaid = false
    @State private var paymentDraft: InvoicePayment?

    private var currencyCode: String {
        invoice.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "EUR" : invoice.currencyCode
    }

    private var canCancelInvoice: Bool {
        invoice.displayStatus == .sent || invoice.displayStatus == .overdue
    }

    private var canMarkPaid: Bool {
        canCancelInvoice && invoice.balanceDue > 0.005
    }

    private var canRestoreInvoice: Bool {
        invoice.displayStatus == .cancelled
    }

    private var canAddPayment: Bool {
        canCancelInvoice && invoice.balanceDue > 0.005
    }

    private var paymentMethodText: String {
        let method = invoice.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        return method.isEmpty ? InvoiceDefaults.standardPaymentMethod : method
    }

    private var paymentInstructionsText: String {
        invoice.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var paymentProgress: Double {
        guard invoice.total > 0 else { return 0 }
        return min(max(invoice.paidTotal / invoice.total, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if invoice.displayStatus == .draft {
                        InvoiceReadinessChecklist(messages: invoice.issueBlockingMessages)
                    }
                    heroCard
                    partyCards
                    if emailRecipientText == Invoice.missingRecipientText {
                        Label("No client email saved for this invoice.", systemImage: "envelope.badge")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    paymentSummary
                    itemsTable(isCompact: false)
                    totalsSummary
                    paymentsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(width: min(proxy.size.width, 780), alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .sheet(isPresented: $isShowingDocumentPreview) {
            InvoiceDocumentPreviewSheet(
                invoice: invoice,
                sellerName: sellerPrimaryText,
                sellerDetails: sellerDetails,
                buyerName: buyerPrimaryText,
                buyerDetails: buyerDetails
            )
        }
        .sheet(isPresented: $isShowingEmailDraft) {
            InvoiceEmailDraftSheet(
                invoice: invoice,
                sellerName: sellerPrimaryText,
                recipient: emailRecipientText
            )
        }
        .sheet(item: $paymentDraft) { payment in
            InvoicePaymentSheet(invoice: invoice, payment: payment) { updatedPayment in
                onRecordPayment(updatedPayment)
                paymentDraft = nil
            } onDelete: { paymentToDelete in
                onDeletePayment(paymentToDelete)
                paymentDraft = nil
            }
        }
        .confirmationDialog("Cancel this invoice?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel Invoice", role: .destructive, action: onCancel)
            Button("Keep Invoice", role: .cancel) {}
        } message: {
            Text("Cancelled invoices stay in your records but are removed from active revenue and payment work.")
        }
        .confirmationDialog("Record full payment?", isPresented: $isConfirmingMarkPaid, titleVisibility: .visible) {
            Button("Mark Paid", action: onMarkPaid)
            Button("Keep Open", role: .cancel) {}
        } message: {
            Text("This records the remaining balance as paid today.")
        }
        .onAppear {
            clientStore.load()
            companyProfileStore.load()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                companyProfileStore.load()
            }
        }
    }

    private func exportPDF() {
        InvoicePrintService.exportPDF(
            invoice: invoice,
            sellerName: sellerPrimaryText,
            sellerDetails: sellerDetails,
            buyerName: buyerPrimaryText,
            buyerDetails: buyerDetails
        )
    }

    private func printInvoice() {
        InvoicePrintService.printInvoice(
            invoice: invoice,
            sellerName: sellerPrimaryText,
            sellerDetails: sellerDetails,
            buyerName: buyerPrimaryText,
            buyerDetails: buyerDetails
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Issue date: \(formattedDate(invoice.issueDate))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                if invoice.displayStatus == .draft {
                    Button(action: onIssue) {
                        Label("Issue", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!invoice.isReadyToIssue)
                    .help(invoice.issueBlockingMessage ?? "Issue invoice")

                    Button(role: .destructive, action: onDiscardDraft) {
                        Label("Discard Draft", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Discard draft")
                }

                Button {
                    printInvoice()
                } label: {
                    Label("Print", systemImage: "printer")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("p", modifiers: .command)
                .help("Print invoice")

                Button {
                    isShowingDocumentPreview = true
                } label: {
                    Label("Preview", systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Preview printable invoice")

                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Export invoice PDF")

                Button {
                    isShowingEmailDraft = true
                } label: {
                    Label("Email", systemImage: "envelope")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Prepare email draft")

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Duplicate invoice")

                if canMarkPaid {
                    Button {
                        isConfirmingMarkPaid = true
                    } label: {
                        Label("Mark Paid", systemImage: "checkmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .help("Record full payment")
                }

                if canCancelInvoice {
                    Button(role: .destructive) {
                        isConfirmingCancel = true
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .help("Cancel invoice")
                }

                if canRestoreInvoice {
                    Button(action: onRestore) {
                        Label("Restore", systemImage: "arrow.uturn.backward.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .help("Restore invoice")
                }

                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }

    private var heroCard: some View {
        VStack(spacing: 7) {
            Text("Invoice")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(invoice.displayTitle)
                .font(.title.weight(.bold))
            Text(invoice.total.formatted(.currency(code: currencyCode)))
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)
            MacInvoiceStatusChip(status: invoice.displayStatus)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var partyCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                sellerCard
                buyerCard
            }
            VStack(alignment: .leading, spacing: 12) {
                sellerCard
                buyerCard
            }
        }
    }

    private var sellerCard: some View {
        MacInvoicePartyCard(
            title: "Seller",
            primaryText: sellerPrimaryText,
            details: sellerDetails
        )
    }

    private var buyerCard: some View {
        MacInvoicePartyCard(
            title: "Buyer",
            primaryText: buyerPrimaryText,
            details: buyerDetails
        )
    }

    private var selectedClient: Client? {
        guard let clientID = invoice.clientID else { return nil }
        return clientStore.clients.first { $0.id == clientID }
    }

    private var sellerPrimaryText: String {
        if let invoiceSellerProfile {
            return invoiceSellerProfile.displayName
        }

        let invoiceName = invoice.sellerName.trimmedForInvoicePreview
        return invoiceName.isEmpty ? "Seller not set" : invoiceName
    }

    private var buyerPrimaryText: String {
        if let selectedClient {
            return selectedClient.displayName
        }

        let invoiceName = invoice.clientName.trimmedForInvoicePreview
        return invoiceName.isEmpty ? "No customer selected" : invoiceName
    }

    private var emailRecipientText: String {
        let recipientCandidates = [
            selectedClient?.email,
            selectedClient?.additionalEmail,
            invoice.clientEmail
        ]
        let recipients = recipientCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return recipients.isEmpty ? Invoice.missingRecipientText : recipients.joined(separator: ", ")
    }

    private var invoiceSellerProfile: MyCompanySellerProfile? {
        companyProfileStore.profiles.first { profile in
            profile.company.name.trimmedForInvoicePreview == invoice.sellerName.trimmedForInvoicePreview
                && profile.company.taxId.trimmedForInvoicePreview == invoice.sellerTaxID.trimmedForInvoicePreview
                && profile.company.vatId.trimmedForInvoicePreview == invoice.sellerVATID.trimmedForInvoicePreview
        }
    }

    private var sellerDetails: [String] {
        let profile = invoiceSellerProfile?.company
        let taxID = profile?.taxId ?? invoice.sellerTaxID
        let vatID = profile?.vatId ?? invoice.sellerVATID

        return invoicePreviewDetails([
            profile.map { addressLine(street: $0.street, apartment: "", city: $0.city, postalCode: $0.postalCode) } ?? nil,
            profile.map { labeledDetail("IČO", $0.ico) } ?? nil,
            labeledDetail("DIČ", taxID),
            labeledDetail("IČ DPH", vatID)
        ])
    }

    private var buyerDetails: [String] {
        if let selectedClient {
            return invoicePreviewDetails([
                addressLine(
                    street: selectedClient.street,
                    apartment: selectedClient.apartment,
                    city: selectedClient.city,
                    postalCode: selectedClient.postalCode
                ),
                labeledDetail("IČO", selectedClient.registrationNumber),
                labeledDetail("DIČ", selectedClient.taxId),
                labeledDetail("IČ DPH", selectedClient.vatId),
                labeledDetail("Email", selectedClient.email),
                labeledDetail("Phone", selectedClient.phone)
            ])
        }

        return invoicePreviewDetails([
            labeledDetail("Email", invoice.clientEmail)
        ])
    }

    private func addressLine(street: String, apartment: String, city: String, postalCode: String) -> String? {
        let streetParts = [street, apartment]
            .map(\.trimmedForInvoicePreview)
            .filter { !$0.isEmpty }
        let cityParts = [postalCode, city]
            .map(\.trimmedForInvoicePreview)
            .filter { !$0.isEmpty }

        let lines = [streetParts.joined(separator: " "), cityParts.joined(separator: " ")]
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func labeledDetail(_ label: String, _ value: String) -> String? {
        let trimmedValue = value.trimmedForInvoicePreview
        return trimmedValue.isEmpty ? nil : "\(label): \(trimmedValue)"
    }

    private func invoicePreviewDetails(_ details: [String?]) -> [String] {
        details.compactMap { $0 }.filter { !$0.isEmpty }
    }

    private var paymentSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                MacInvoiceInfoCell(title: "Currency", value: currencyCode)
                Divider()
                MacInvoiceInfoCell(title: "Delivery date", value: formattedDate(invoice.deliveryDate))
                Divider()
                MacInvoiceInfoCell(title: "Due date", value: formattedDate(invoice.dueDate))
            }

            HStack(spacing: 0) {
                MacInvoiceInfoCell(title: "Payment method", value: paymentMethodText)
                if !paymentInstructionsText.isEmpty {
                    Divider()
                    MacInvoiceInfoCell(title: "Payment note", value: paymentInstructionsText)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    paymentAmountBlock(title: "Total", value: invoice.total, color: .primary)
                    paymentAmountBlock(title: "Paid", value: invoice.paidTotal, color: .green)
                    paymentAmountBlock(title: "Balance", value: invoice.balanceDue, color: invoice.balanceDue > 0.005 ? .orange : .green)
                }

                ProgressView(value: paymentProgress)
                    .tint(invoice.balanceDue > 0.005 ? .orange : .green)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.vertical, 8)
    }

    private func paymentAmountBlock(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.formatted(.currency(code: currencyCode)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemsTable(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(.title3.weight(.bold))

            if invoice.displayLineItems.isEmpty {
                Text("No items added")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    if isCompact {
                        compactTableHeader
                    } else {
                        tableHeader
                    }
                    Divider()
                    ForEach(Array(invoice.displayLineItems.enumerated()), id: \.element.id) { index, item in
                        if isCompact {
                            compactTableRow(index: index, item: item)
                        } else {
                            tableRow(index: index, item: item)
                        }
                        if item.id != invoice.displayLineItems.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 4) {
            Text("#").frame(width: 14, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Qty").frame(width: 46, alignment: .trailing)
            Text("Price").frame(width: 46, alignment: .trailing)
            Text("Disc.").frame(width: 30, alignment: .trailing)
            Text("VAT").frame(width: 30, alignment: .trailing)
            Text("Total").frame(width: 48, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.vertical, 5)
    }

    private var compactTableHeader: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 18, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Qty").frame(width: 50, alignment: .trailing)
            Text("Total").frame(width: 76, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func tableRow(index: Int, item: InvoiceLineItem) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(index + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            itemTitle(item)
                .frame(minWidth: 76, maxWidth: .infinity, alignment: .leading)
            tableValue("\(decimal(item.quantity)) pcs.", width: 46)
            tableValue(item.unitPrice.formatted(.currency(code: currencyCode)), width: 46)
            tableValue(item.discountPercent > 0 ? "\(decimal(item.discountPercent))%" : "-", width: 30)
                .foregroundStyle(item.discountPercent > 0 ? .orange : .secondary)
            tableValue("\(decimal(item.vatRate))%", width: 30)
            tableValue(item.grossTotal.formatted(.currency(code: currencyCode)), width: 48, weight: .semibold)
        }
        .font(.callout)
        .padding(.vertical, 8)
    }

    private func tableValue(_ value: String, width: CGFloat, weight: Font.Weight = .regular) -> some View {
        Text(value)
            .font(.callout.weight(weight))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .frame(width: width, alignment: .trailing)
    }


    private func compactTableRow(index: Int, item: InvoiceLineItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                itemTitle(item)
                Text("Price \(item.unitPrice.formatted(.currency(code: currencyCode))) • VAT \(decimal(item.vatRate))%" + (item.discountPercent > 0 ? " • Discount \(decimal(item.discountPercent))%" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(decimal(item.quantity)) pcs.")
                .frame(width: 50, alignment: .trailing)
            Text(item.grossTotal.formatted(.currency(code: currencyCode)))
                .font(.body.weight(.semibold))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private func itemTitle(_ item: InvoiceLineItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled item" : item.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var totalsSummary: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if invoice.discountPercent > 0 {
                totalRow("Invoice discount", value: "-\(invoice.discountAmount.formatted(.currency(code: currencyCode)))", color: .orange)
            }
            totalRow("Total net", value: invoice.netTotal.formatted(.currency(code: currencyCode)))
            totalRow("Total VAT", value: invoice.vatTotal.formatted(.currency(code: currencyCode)))
            totalRow("Total gross", value: invoice.total.formatted(.currency(code: currencyCode)), color: .green, isProminent: true)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func totalRow(_ title: String, value: String, color: Color = .secondary, isProminent: Bool = false) -> some View {
        HStack(spacing: 28) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(isProminent ? .bold : .semibold)
                .foregroundStyle(color)
                .monospacedDigit()
                .frame(width: 140, alignment: .trailing)
        }
        .font(isProminent ? .headline : .body)
    }

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payments")
                .font(.title3.weight(.bold))

            if invoice.payments.isEmpty {
                Text("No payments recorded")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(invoice.payments) { payment in
                        Button {
                            paymentDraft = payment
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(payment.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Payment" : payment.method)
                                        .font(.subheadline.weight(.semibold))
                                    Text(formattedDate(payment.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(payment.amount.formatted(.currency(code: currencyCode)))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }

            if invoice.paidTotal > 0 {
                totalRow("Paid", value: invoice.paidTotal.formatted(.currency(code: currencyCode)), color: .green)
                totalRow("Balance due", value: invoice.balanceDue.formatted(.currency(code: currencyCode)), color: invoice.balanceDue > 0 ? .orange : .green)
            }

            Button {
                paymentDraft = InvoicePayment(
                    id: UUID(),
                    date: Date(),
                    amount: min(max(invoice.balanceDue, 0), invoice.total),
                    method: invoice.defaultPaymentRecordMethod,
                    reference: "",
                    note: ""
                )
            } label: {
                Label("Add Payment", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!canAddPayment)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private extension String {
    var trimmedForInvoicePreview: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Invoice {
    static let missingRecipientText = "No recipient email saved"

    var displayLineItems: [InvoiceLineItem] {
        lineItems.filter(\.hasDisplayContent)
    }

    var defaultPaymentRecordMethod: String {
        let method = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        return method.isEmpty ? InvoiceDefaults.standardPaymentMethod : method
    }
}

private extension InvoiceLineItem {
    var hasDisplayContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || unitPrice > 0
            || discountPercent > 0
    }
}

private struct InvoiceEmailDraftSheet: View {
    let invoice: Invoice
    let sellerName: String
    let recipient: String

    @Environment(\.dismiss) private var dismiss
    @State private var copiedMessage: String?

    private var settings: ClientCommunicationSettings {
        ClientCommunicationSettings.load()
    }

    private var subject: String {
        settings.subject(for: invoice, sellerName: sellerName)
    }

    private var message: String {
        settings.message(for: invoice, sellerName: sellerName)
    }

    private var hasRecipient: Bool {
        recipient != Invoice.missingRecipientText
    }

    private var fullEmailText: String {
        let recipientLine = hasRecipient ? "To: \(recipient)\n" : ""
        return "\(recipientLine)Subject: \(subject)\n\n\(message)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Recipient") {
                    if hasRecipient {
                        Text(recipient)
                            .textSelection(.enabled)
                    } else {
                        Label(Invoice.missingRecipientText, systemImage: "envelope.badge")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Subject") {
                    Text(subject)
                        .textSelection(.enabled)
                    Button {
                        copy(subject, confirmation: "Subject copied")
                    } label: {
                        Label("Copy Subject", systemImage: "doc.on.doc")
                    }
                }

                Section("Message") {
                    Text(message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button {
                        copy(message, confirmation: "Message copied")
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                }

                Section {
                    Button {
                        copy(fullEmailText, confirmation: "Email draft copied")
                    } label: {
                        Label("Copy Email Draft", systemImage: "envelope")
                    }
                } footer: {
                    Text(hasRecipient ? "This uses the client communication template from Settings. Attach the invoice PDF from Preview or Print before sending." : "Add a client email before sending. The copied draft still includes the subject and message.")
                }
            }
            .navigationTitle("Email Draft")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let copiedMessage {
                    Text(copiedMessage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 18)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    private func copy(_ text: String, confirmation: String) {
        InvoiceClipboard.copy(text)
        copiedMessage = confirmation
    }
}

private enum InvoiceClipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

private struct MacInvoicePartyCard: View {
    let title: String
    let primaryText: String
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryText)
                    .font(.body.weight(.semibold))
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacInvoiceInfoCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

private struct MacInvoiceStatusChip: View {
    let status: InvoiceStatus

    private var color: Color {
        switch status {
        case .draft:
            .orange
        case .sent:
            .blue
        case .paid:
            .green
        case .overdue:
            .red
        case .cancelled:
            .secondary
        }
    }

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct InvoicePaymentSheet: View {
    let invoice: Invoice
    let payment: InvoicePayment
    let onSave: (InvoicePayment) -> Void
    let onDelete: (InvoicePayment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var paymentDate: Date
    @State private var method: String
    @State private var reference: String
    @State private var note: String
    @State private var hasAttemptedSave = false

    private var methods: [String] {
        let currentMethod = method.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentMethod.isEmpty, !InvoiceDefaults.supportedPaymentMethods.contains(currentMethod) else {
            return InvoiceDefaults.supportedPaymentMethods
        }
        return [currentMethod] + InvoiceDefaults.supportedPaymentMethods
    }

    init(
        invoice: Invoice,
        payment: InvoicePayment,
        onSave: @escaping (InvoicePayment) -> Void,
        onDelete: @escaping (InvoicePayment) -> Void
    ) {
        self.invoice = invoice
        self.payment = payment
        self.onSave = onSave
        self.onDelete = onDelete
        _amountText = State(initialValue: payment.amount.formatted(.number.precision(.fractionLength(2))))
        _paymentDate = State(initialValue: payment.date)
        _method = State(initialValue: payment.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? invoice.defaultPaymentRecordMethod : payment.method)
        _reference = State(initialValue: payment.reference)
        _note = State(initialValue: payment.note)
    }

    private var currencyCode: String {
        invoice.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "EUR" : invoice.currencyCode
    }

    private var amount: Double? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var existingPaymentAmount: Double {
        invoice.payments.first(where: { $0.id == payment.id })?.amount ?? 0
    }

    private var editableBalanceDue: Double {
        invoice.balanceDue + existingPaymentAmount
    }

    private var isEditingExistingPayment: Bool {
        invoice.payments.contains { $0.id == payment.id }
    }

    private var canSave: Bool {
        guard let amount else { return false }
        return editableBalanceDue > 0.005 && amount > 0 && amount <= editableBalanceDue + 0.005
    }

    private var validationMessage: String {
        if editableBalanceDue <= 0.005 {
            return "There is no balance due. Add invoice items before recording a payment."
        }
        guard let amount, amount > 0 else {
            return "Enter a payment amount greater than zero."
        }
        return "Payment cannot be greater than the balance due."
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditingExistingPayment ? "Edit Payment" : "New Incoming Payment")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    paymentDetailsSection
                    attachedInvoiceSection
                    notesSection

                    if hasAttemptedSave && !canSave {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                if isEditingExistingPayment {
                    Button("Delete", role: .destructive) {
                        onDelete(payment)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    savePayment()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 680)
    }

    private var paymentDetailsSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                paymentReadOnlyRow("Est. Document Number", value: paymentNumber)
                Divider().padding(.leading, 12)
                paymentReadOnlyRow("Seller", value: invoice.sellerName.trimmedForInvoicePreview.isEmpty ? "Set in Sellers" : invoice.sellerName)
                Divider().padding(.leading, 12)
                paymentReadOnlyRow("Customer", value: invoice.clientName.trimmedForInvoicePreview.isEmpty ? "No customer selected" : invoice.clientName)
                Divider().padding(.leading, 12)
                paymentReadOnlyRow("Customer balance", value: editableBalanceDue.formatted(.currency(code: currencyCode)), valueColor: .orange)
                Divider().padding(.leading, 12)
                paymentPickerRow
                Divider().padding(.leading, 12)
                paymentDateRow
                Divider().padding(.leading, 12)
                paymentTextRow("Reference", text: $reference, prompt: "Optional")
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 0) {
                paymentReadOnlyRow("Currency", value: currencyCode, valueColor: .secondary)
                Divider().padding(.leading, 12)
                paymentAmountRow
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var attachedInvoiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attached Documents")
                .font(.headline.weight(.semibold))

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(invoice.displayTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(invoice.clientName.trimmedForInvoicePreview.isEmpty ? "No customer selected" : invoice.clientName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(invoice.total.formatted(.currency(code: currencyCode)))
                            .font(.subheadline.weight(.semibold))
                        Text("of \(editableBalanceDue.formatted(.currency(code: currencyCode)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)

                Divider().padding(.leading, 12)

                HStack {
                    Spacer()
                    Text("Total")
                        .foregroundStyle(.secondary)
                    Text((amount ?? 0).formatted(.currency(code: currencyCode)))
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.headline.weight(.semibold))
            TextField("Optional", text: $note, axis: .vertical)
                .lineLimit(4...6)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var paymentPickerRow: some View {
        LabeledContent("Payment Method") {
            Picker("Payment Method", selection: $method) {
                ForEach(methods, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var paymentDateRow: some View {
        LabeledContent("Payment Date") {
            DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var paymentAmountRow: some View {
        LabeledContent("Total Amount") {
            HStack(spacing: 6) {
                TextField("0.00", text: $amountText)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.semibold))
                    .frame(width: 120)
                Text(currencyCode)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func paymentReadOnlyRow(_ title: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func paymentTextRow(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(prompt, text: text)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var paymentNumber: String {
        "PAY-\(invoice.number.replacingOccurrences(of: "INV-", with: ""))"
    }

    private func savePayment() {
        hasAttemptedSave = true
        guard canSave, let amount else { return }
        onSave(
            InvoicePayment(
                id: payment.id,
                date: paymentDate,
                amount: amount,
                method: method,
                reference: reference,
                note: note
            )
        )
    }
}
#endif

private struct InvoiceRow: View {
    let invoice: Invoice
    var isSelected = false

    private var currencyCode: String {
        invoice.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "EUR" : invoice.currencyCode
    }

    private var clientText: String {
        let client = invoice.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return client.isEmpty ? "No client" : client
    }

    private var timingText: String {
        switch invoice.displayStatus {
        case .draft:
            "Draft from \(formattedDate(invoice.issueDate))"
        case .paid:
            "Paid • issued \(formattedDate(invoice.issueDate))"
        case .cancelled:
            "Cancelled • issued \(formattedDate(invoice.issueDate))"
        case .sent, .overdue:
            dueText
        }
    }

    private var dueText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: invoice.dueDate)
        let days = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0

        if days < 0 {
            return "Overdue by \(abs(days)) day\(abs(days) == 1 ? "" : "s")"
        }
        if days == 0 {
            return "Due today"
        }
        if days == 1 {
            return "Due tomorrow"
        }
        if days <= 7 {
            return "Due in \(days) days"
        }
        return "Due \(formattedDate(invoice.dueDate))"
    }

    private var paymentProgressText: String? {
        guard invoice.paidTotal > 0, invoice.balanceDue > 0.005 else { return nil }
        return "Part-paid: \(invoice.paidTotal.formatted(.currency(code: currencyCode))) received"
    }

    private var primaryAmount: Double {
        showsTotalAmount ? invoice.total : invoice.balanceDue
    }

    private var primaryAmountTitle: String {
        switch invoice.displayStatus {
        case .draft:
            "Draft total"
        case .paid, .cancelled:
            "Total"
        case .sent, .overdue:
            "Balance"
        }
    }

    private var amountColor: Color {
        switch invoice.displayStatus {
        case .overdue:
            return .red
        case .sent where invoice.balanceDue > 0.005:
            return .orange
        default:
            return .primary
        }
    }

    private var secondaryTextColor: Color {
        .secondary
    }

    private var timingColor: Color {
        switch invoice.displayStatus {
        case .overdue:
            return .red
        case .sent:
            return .orange
        default:
            return .secondary
        }
    }

    private var showsTotalAmount: Bool {
        invoice.displayStatus == .paid || invoice.displayStatus == .cancelled
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(invoice.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    InvoiceStatusBadge(status: invoice.displayStatus, isSelected: isSelected)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(clientText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)

                    Text(timingText)
                        .font(.caption2.weight(invoice.displayStatus == .overdue ? .semibold : .regular))
                        .foregroundStyle(timingColor)
                        .lineLimit(1)

                    if let paymentProgressText {
                        Text(paymentProgressText)
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(primaryAmount.formatted(.currency(code: currencyCode)))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(primaryAmountTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            isSelected ? Color.accentColor.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 9)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct InvoiceStatusBadge: View {
    let status: InvoiceStatus
    var isSelected = false

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.invoiceRowTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                status.invoiceRowTint.opacity(isSelected ? 0.18 : 0.13),
                in: Capsule()
            )
            .lineLimit(1)
    }
}

private extension InvoiceStatus {
    var invoiceRowTint: Color {
        switch self {
        case .draft:
            .orange
        case .sent:
            .blue
        case .paid:
            .green
        case .overdue:
            .red
        case .cancelled:
            .secondary
        }
    }
}

struct MobileInvoiceDetailView: View {
    let onSave: (Invoice) -> Void
    let onDuplicate: (Invoice) -> Invoice
    let onDiscardDraft: (Invoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var invoice: Invoice
    @State private var isEditing = false
    @State private var isShowingDocumentPreview = false
    @State private var isShowingEmailDraft = false
    @State private var isConfirmingCancel = false
    @State private var isConfirmingMarkPaid = false
    @State private var isConfirmingDiscardDraft = false
    @State private var paymentDraft: InvoicePayment?

    init(
        invoice: Invoice,
        onSave: @escaping (Invoice) -> Void,
        onDuplicate: @escaping (Invoice) -> Invoice,
        onDiscardDraft: @escaping (Invoice) -> Void
    ) {
        _invoice = State(initialValue: invoice)
        self.onSave = onSave
        self.onDuplicate = onDuplicate
        self.onDiscardDraft = onDiscardDraft
    }

    private var currencyCode: String {
        invoice.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "EUR" : invoice.currencyCode
    }

    private var sellerName: String {
        let name = invoice.sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Seller not set" : name
    }

    private var buyerName: String {
        let name = invoice.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "No client selected" : name
    }

    private var canCancelInvoice: Bool {
        invoice.displayStatus == .sent || invoice.displayStatus == .overdue
    }

    private var canMarkPaid: Bool {
        canCancelInvoice && invoice.balanceDue > 0.005
    }

    private var canRestoreInvoice: Bool {
        invoice.displayStatus == .cancelled
    }

    private var canAddPayment: Bool {
        canCancelInvoice && invoice.balanceDue > 0.005
    }

    private var paymentMethodText: String {
        let method = invoice.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        return method.isEmpty ? InvoiceDefaults.standardPaymentMethod : method
    }

    private var paymentInstructionsText: String {
        invoice.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mobileEmailRecipientText: String {
        let email = invoice.clientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? Invoice.missingRecipientText : email
    }

    private var paymentProgress: Double {
        guard invoice.total > 0 else { return 0 }
        return min(max(invoice.paidTotal / invoice.total, 0), 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                actionGrid
                if invoice.displayStatus == .draft {
                    InvoiceReadinessChecklist(messages: invoice.issueBlockingMessages)
                }
                partiesSection
                if mobileEmailRecipientText == Invoice.missingRecipientText {
                    Label("No client email saved for this invoice.", systemImage: "envelope.badge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                }
                datesSection
                totalsSection
                itemsSection
                paymentsSection
            }
            .padding()
            .frame(maxWidth: 720, alignment: .topLeading)
        }
        .navigationTitle(invoice.displayTitle)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isShowingDocumentPreview) {
            InvoiceDocumentPreviewSheet(
                invoice: invoice,
                sellerName: sellerName,
                sellerDetails: sellerDetails,
                buyerName: buyerName,
                buyerDetails: buyerDetails
            )
        }
        .sheet(isPresented: $isShowingEmailDraft) {
            InvoiceEmailDraftSheet(
                invoice: invoice,
                sellerName: sellerName,
                recipient: mobileEmailRecipientText
            )
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                InvoiceEditorView(invoice: invoice, title: invoice.displayTitle) { updatedInvoice in
                    invoice = updatedInvoice
                    onSave(updatedInvoice)
                    isEditing = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isEditing = false }
                    }
                }
            }
        }
        .sheet(item: $paymentDraft) { payment in
            InvoicePaymentSheet(invoice: invoice, payment: payment) { updatedPayment in
                recordPayment(updatedPayment)
                paymentDraft = nil
            } onDelete: { paymentToDelete in
                deletePayment(paymentToDelete)
                paymentDraft = nil
            }
        }
        .confirmationDialog("Cancel this invoice?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel Invoice", role: .destructive, action: cancelInvoice)
            Button("Keep Invoice", role: .cancel) {}
        } message: {
            Text("Cancelled invoices stay in your records but are removed from active revenue and payment work.")
        }
        .confirmationDialog("Record full payment?", isPresented: $isConfirmingMarkPaid, titleVisibility: .visible) {
            Button("Mark Paid", action: markPaid)
            Button("Keep Open", role: .cancel) {}
        } message: {
            Text("This records the remaining balance as paid today.")
        }
        .confirmationDialog("Discard \(invoice.displayTitle)?", isPresented: $isConfirmingDiscardDraft, titleVisibility: .visible) {
            Button("Discard Draft", role: .destructive, action: discardDraft)
            Button("Keep Draft", role: .cancel) {}
        } message: {
            Text("This removes the draft from your invoice list. Issued invoices stay in your records.")
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            Text(invoice.total.formatted(.currency(code: currencyCode)))
                .font(.title2.weight(.bold))
                .foregroundStyle(.green)
            InvoiceStatusBadge(status: invoice.displayStatus)
            if invoice.displayStatus != .draft {
                VStack(spacing: 6) {
                    ProgressView(value: paymentProgress)
                        .tint(invoice.balanceDue > 0.005 ? .orange : .green)
                    Text(invoice.balanceDue > 0.005 ? "Balance due: \(invoice.balanceDue.formatted(.currency(code: currencyCode)))" : "Paid in full")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(invoice.balanceDue > 0.005 ? (invoice.displayStatus == .overdue ? .red : .orange) : .green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionGrid: some View {
        VStack(spacing: 10) {
            primaryActionButton

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { secondaryActionButtons }
                VStack(spacing: 10) { secondaryActionButtons }
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if invoice.displayStatus == .draft {
            Button(action: issueInvoice) {
                Label("Issue", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!invoice.isReadyToIssue)
        } else if canMarkPaid {
            Button {
                isConfirmingMarkPaid = true
            } label: {
                Label("Mark Paid", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else {
            Button { isShowingDocumentPreview = true } label: {
                Label("Preview", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var secondaryActionButtons: some View {
        Button { isEditing = true } label: {
            Label("Edit", systemImage: "pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button { isShowingDocumentPreview = true } label: {
            Label("Preview", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(invoice.displayStatus != .draft && !canMarkPaid)

        Button { isShowingEmailDraft = true } label: {
            Label("Email", systemImage: "envelope")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Menu {
            Button(action: duplicateInvoice) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            if invoice.displayStatus == .draft {
                Button(role: .destructive) {
                    isConfirmingDiscardDraft = true
                } label: {
                    Label("Discard Draft", systemImage: "trash")
                }
            }

            if canCancelInvoice {
                Button(role: .destructive) {
                    isConfirmingCancel = true
                } label: {
                    Label("Cancel Invoice", systemImage: "xmark.circle")
                }
            }

            if canRestoreInvoice {
                Button(action: restoreInvoice) {
                    Label("Restore Invoice", systemImage: "arrow.uturn.backward.circle")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var partiesSection: some View {
        MobileInvoiceSection(title: "Parties") {
            LabeledContent("Seller", value: sellerName)
            LabeledContent("Client", value: buyerName)
        }
    }

    private var datesSection: some View {
        MobileInvoiceSection(title: "Dates & Payment") {
            LabeledContent("Issue date", value: invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Delivery date", value: invoice.deliveryDate.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Due date", value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("Payment method", value: paymentMethodText)
            if !paymentInstructionsText.isEmpty {
                LabeledContent("Payment note") {
                    Text(paymentInstructionsText)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var totalsSection: some View {
        MobileInvoiceSection(title: "Totals") {
            LabeledContent("Net", value: invoice.netTotal.formatted(.currency(code: currencyCode)))
            LabeledContent("VAT", value: invoice.vatTotal.formatted(.currency(code: currencyCode)))
            LabeledContent("Gross", value: invoice.total.formatted(.currency(code: currencyCode)))
                .font(.headline)
            if invoice.displayStatus != .draft {
                LabeledContent("Paid", value: invoice.paidTotal.formatted(.currency(code: currencyCode)))
                LabeledContent("Balance", value: invoice.balanceDue.formatted(.currency(code: currencyCode)))
            }
        }
    }

    private var itemsSection: some View {
        MobileInvoiceSection(title: "Items") {
            if invoice.displayLineItems.isEmpty {
                Text("No items added")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(invoice.displayLineItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed item" : item.title)
                                .font(.subheadline.weight(.semibold))
                            Text("Qty \(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) • VAT \(item.vatRate.formatted(.number.precision(.fractionLength(0...2))))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.grossTotal.formatted(.currency(code: currencyCode)))
                            .font(.subheadline.weight(.semibold))
                    }
                    Divider()
                }
            }
        }
    }

    private var paymentsSection: some View {
        MobileInvoiceSection(title: "Payments") {
            if invoice.payments.isEmpty {
                Text("No payments recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(invoice.payments) { payment in
                    Button {
                        paymentDraft = payment
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(payment.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Payment" : payment.method)
                                    .font(.subheadline.weight(.semibold))
                                Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(payment.amount.formatted(.currency(code: currencyCode)))
                                .font(.subheadline.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }

            Button(action: addPayment) {
                Label("Add Payment", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canAddPayment)
        }
    }

    private var sellerDetails: [String] {
        [
            labeledDetail("Tax ID", invoice.sellerTaxID),
            labeledDetail("VAT ID", invoice.sellerVATID)
        ].compactMap { $0 }
    }

    private var buyerDetails: [String] {
        [labeledDetail("Email", invoice.clientEmail)].compactMap { $0 }
    }

    private func labeledDetail(_ label: String, _ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "\(label): \(trimmed)"
    }

    private func issueInvoice() {
        guard invoice.isReadyToIssue else { return }
        invoice.issue()
        onSave(invoice)
    }

    private func duplicateInvoice() {
        invoice = onDuplicate(invoice)
        isEditing = true
    }

    private func markPaid() {
        invoice.payments.append(
            InvoicePayment(
                id: UUID(),
                date: Date(),
                amount: invoice.balanceDue,
                method: invoice.defaultPaymentRecordMethod,
                reference: "",
                note: "Marked paid"
            )
        )
        invoice.refreshStatus()
        onSave(invoice)
    }

    private func cancelInvoice() {
        invoice.status = .cancelled
        onSave(invoice)
    }

    private func discardDraft() {
        guard invoice.canDiscardDraft else { return }
        onDiscardDraft(invoice)
        dismiss()
    }

    private func restoreInvoice() {
        invoice.status = .sent
        invoice.refreshStatus()
        onSave(invoice)
    }

    private func addPayment() {
        paymentDraft = InvoicePayment(
            id: UUID(),
            date: Date(),
            amount: min(max(invoice.balanceDue, 0), invoice.total),
            method: invoice.defaultPaymentRecordMethod,
            reference: "",
            note: ""
        )
    }

    private func recordPayment(_ payment: InvoicePayment) {
        if let index = invoice.payments.firstIndex(where: { $0.id == payment.id }) {
            invoice.payments[index] = payment
        } else {
            invoice.payments.append(payment)
        }
        invoice.refreshStatus()
        onSave(invoice)
    }

    private func deletePayment(_ payment: InvoicePayment) {
        invoice.payments.removeAll { $0.id == payment.id }
        invoice.refreshStatus()
        onSave(invoice)
    }
}

private struct MobileInvoiceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct InvoiceEditorView: View {
    let title: String
    let onSave: (Invoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Invoice
    @State private var clientStore = ClientStore()
    @State private var companyProfileStore = MyCompanyProfileStore()
    @State private var productStore = ProductStore()
    @State private var clientEditorDraft: Client?
    @State private var lineItemEditorDraft: EditableInvoiceLineItem?
    @State private var hasAttemptedSave = false
    @State private var isShowingDetails = false

    private let supportedCurrencies = InvoiceDefaults.supportedCurrencyCodes

    private var canSaveDraft: Bool {
        !isMissingInvoiceNumber
    }

    private var canIssue: Bool {
        draft.isReadyToIssue
    }

    init(invoice: Invoice, title: String, onSave: @escaping (Invoice) -> Void) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: invoice)
    }

    var body: some View {
        editorContent
            .navigationTitle(title)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(canSaveDraft ? "Save Draft" : "Review", action: attemptSaveDraft)
                }
            }
            .sheet(item: $clientEditorDraft) { client in
                NavigationStack {
                    ClientEditorView(client: client, title: clientEditorTitle(for: client), onSave: saveClientFromInvoice)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { clientEditorDraft = nil }
                            }
                        }
                }
            }
            .sheet(item: $lineItemEditorDraft) { editableItem in
                NavigationStack {
                    InvoiceLineItemSheet(
                        editableItem: editableItem,
                        currencyCode: draft.currencyCode,
                        products: productStore.products,
                        onCancel: { lineItemEditorDraft = nil },
                        onSave: saveLineItem
                    )
                }
            }
            .onAppear(perform: loadEditorDependencies)
            .task {
                for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                    refreshSellerProfiles(applyToEmptyDraft: true)
                }
            }
    }

    @ViewBuilder
    private var editorContent: some View {
        #if os(macOS)
        macEditor
        #else
        mobileEditor
        #endif
    }

    private var mobileEditor: some View {
        Form {
            Section {
                invoiceReadinessSummary
            }

            Section("Document") {
                LabeledContent("Est. document number", value: draft.number)
                if hasAttemptedSave && isMissingInvoiceNumber {
                    InvoiceValidationMessage("Invoice number is required.")
                }
                sellerSelectionContent
            }

            Section("Customer") {
                customerSelectionContent
            }

            Section("Dates") {
                DatePicker("Issue date", selection: $draft.issueDate, displayedComponents: .date)
                DatePicker("Delivery date", selection: $draft.deliveryDate, displayedComponents: .date)
                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
            }

            Section("Payment Terms") {
                Picker("Method", selection: $draft.paymentMethod) {
                    ForEach(paymentMethodOptions, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }

                TextField("Payment note", text: $draft.paymentInstructions, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Currency") {
                currencyPicker
            }

            Section("Items") {
                invoiceItems
                Button(action: addLineItem) {
                    Label("Add item", systemImage: "plus")
                }
            }

            Section("Totals") {
                LabeledContent("Invoice discount") {
                    HStack(spacing: 6) {
                        DecimalTextField("0", value: $draft.discountPercent)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Total net", value: money(draft.netTotal))
                LabeledContent("Total VAT", value: money(draft.vatTotal))
                LabeledContent("Total gross", value: money(draft.total))
                    .font(.headline)
            }

            Section {
                DisclosureGroup("Details", isExpanded: $isShowingDetails) {
                    InvoiceTextField("Invoice number", text: $draft.number, prompt: "Required")
                    InvoiceTextField("Order number", text: $draft.orderNumber, prompt: "Optional")
                }
            }

            Section("Notes") {
                TextField("Optional", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                editorActionFooter
            }
        }
    }

    #if os(macOS)
    private var macEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                macEditorForm
                    .frame(minWidth: 520, idealWidth: 600, maxWidth: 660)

                Divider()

                macLivePreview
                    .frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity)
            }
            .frame(minWidth: 980, minHeight: 680, alignment: .topLeading)

            macEditorForm
                .frame(minWidth: 560, minHeight: 600, alignment: .topLeading)
        }
    }

    private var macEditorForm: some View {
        VStack(spacing: 0) {
            invoiceReadinessSummary
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 14)
                .frame(maxWidth: 620)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    macInvoiceSections
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()

            editorActionFooter
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var macLivePreview: some View {
        GeometryReader { proxy in
            let previewScale = min(max((proxy.size.width - 48) / 720, 0.34), 0.62)
            let previewSize = CGSize(width: 720 * previewScale, height: 1018 * previewScale)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Preview")
                            .font(.headline)
                        Text("Updates as invoice details change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(money(draft.total))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                ScrollView {
                    InvoiceDocumentPage(
                        invoice: draft,
                        sellerName: documentSellerName,
                        sellerDetails: documentSellerDetails,
                        buyerName: documentBuyerName,
                        buyerDetails: documentBuyerDetails
                    )
                    .frame(width: 720, height: 1018, alignment: .top)
                    .background(.white)
                    .foregroundStyle(.black)
                    .scaleEffect(previewScale, anchor: .top)
                    .frame(width: previewSize.width, height: previewSize.height, alignment: .top)
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    @ViewBuilder
    private var macInvoiceSections: some View {
        MacInvoiceSection("Invoice") {
            MacReadOnlyInvoiceRow("Document number", value: draft.number)
            if hasAttemptedSave && isMissingInvoiceNumber {
                InvoiceValidationMessage("Invoice number is required.")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            Divider()
            sellerSelectionContent
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            customerSelectionContent
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }

        MacInvoiceSection("Dates") {
            DatePicker("Issue date", selection: $draft.issueDate, displayedComponents: .date)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            Divider()
            DatePicker("Delivery date", selection: $draft.deliveryDate, displayedComponents: .date)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            Divider()
            DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }

        MacInvoiceSection("Payment Terms") {
            Picker("Method", selection: $draft.paymentMethod) {
                ForEach(paymentMethodOptions, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
            TextField("Payment note", text: $draft.paymentInstructions, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }

        MacInvoiceSection("Currency") {
            currencyPicker
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }

        MacInvoiceSection("Items") {
            invoiceItems
                .padding(.vertical, 4)
            Divider()
            Button(action: addLineItem) {
                Label("Add item", systemImage: "plus")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }

        MacInvoiceSection("Totals") {
            MacInvoiceNumberField(title: "Invoice discount", value: $draft.discountPercent, suffix: "%")
            Divider()
            MacReadOnlyInvoiceRow("Total net", value: money(draft.netTotal))
            Divider()
            MacReadOnlyInvoiceRow("Total VAT", value: money(draft.vatTotal))
            Divider()
            MacReadOnlyInvoiceRow("Total gross", value: money(draft.total), isProminent: true)
        }

        MacInvoiceSection("More") {
            DisclosureGroup("Details", isExpanded: $isShowingDetails) {
                MacInvoiceTextField("Invoice number", text: $draft.number, prompt: "Required")
                MacInvoiceTextField("Order number", text: $draft.orderNumber, prompt: "Optional")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            DisclosureGroup("Notes") {
                TextField("Optional", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
    #endif

    private var sellerDisplayName: String {
        let sellerName = draft.sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return sellerName.isEmpty ? "Set in Sellers" : sellerName
    }

    #if os(macOS)
    private var documentSellerProfile: CompanyFormData? {
        companyProfileStore.profiles.first { profile in
            profile.company.name.trimmedForInvoicePreview == draft.sellerName.trimmedForInvoicePreview
                && profile.company.taxId.trimmedForInvoicePreview == draft.sellerTaxID.trimmedForInvoicePreview
                && profile.company.vatId.trimmedForInvoicePreview == draft.sellerVATID.trimmedForInvoicePreview
        }?.company
    }

    private var documentSellerName: String {
        let name = (documentSellerProfile?.name ?? draft.sellerName).trimmedForInvoicePreview
        return name.isEmpty ? "Seller not set" : name
    }

    private var documentBuyerName: String {
        let name = selectedClient?.displayName.trimmedForInvoicePreview ?? draft.clientName.trimmedForInvoicePreview
        return name.isEmpty ? "No client selected" : name
    }

    private var documentSellerDetails: [String] {
        let profile = documentSellerProfile
        return compactDocumentDetails([
            profile.map { documentAddressLine(street: $0.street, apartment: "", city: $0.city, postalCode: $0.postalCode) } ?? nil,
            profile.map { documentDetail("Registration", $0.ico) } ?? nil,
            documentDetail("Tax ID", profile?.taxId ?? draft.sellerTaxID),
            documentDetail("VAT ID", profile?.vatId ?? draft.sellerVATID)
        ])
    }

    private var documentBuyerDetails: [String] {
        if let selectedClient {
            return compactDocumentDetails([
                documentAddressLine(
                    street: selectedClient.street,
                    apartment: selectedClient.apartment,
                    city: selectedClient.city,
                    postalCode: selectedClient.postalCode
                ),
                documentDetail("Registration", selectedClient.registrationNumber),
                documentDetail("Tax ID", selectedClient.taxId),
                documentDetail("VAT ID", selectedClient.vatId),
                documentDetail("Email", selectedClient.email),
                documentDetail("Phone", selectedClient.phone)
            ])
        }

        return compactDocumentDetails([
            documentDetail("Email", draft.clientEmail)
        ])
    }

    private func documentAddressLine(street: String, apartment: String, city: String, postalCode: String) -> String? {
        let streetParts = [street, apartment]
            .map(\.trimmedForInvoicePreview)
            .filter { !$0.isEmpty }
        let cityParts = [postalCode, city]
            .map(\.trimmedForInvoicePreview)
            .filter { !$0.isEmpty }
        let lines = [streetParts.joined(separator: " "), cityParts.joined(separator: " ")]
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func documentDetail(_ label: String, _ value: String) -> String? {
        let trimmedValue = value.trimmedForInvoicePreview
        return trimmedValue.isEmpty ? nil : "\(label): \(trimmedValue)"
    }

    private func compactDocumentDetails(_ details: [String?]) -> [String] {
        details.compactMap { $0 }.filter { !$0.isEmpty }
    }
    #endif

    private var currencyPicker: some View {
        Picker("Currency", selection: $draft.currencyCode) {
            ForEach(currencyOptions, id: \.self) { currencyCode in
                Text(currencyLabel(for: currencyCode)).tag(currencyCode)
            }
        }
    }

    private var sellerSelectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if companyProfileStore.profiles.count > 1 {
                Picker("Seller", selection: selectedSellerBinding) {
                    ForEach(companyProfileStore.profiles) { profile in
                        Text(profile.displayName).tag(Optional(profile.id))
                    }
                }
            } else {
                LabeledContent("Seller") {
                    Text(sellerDisplayName)
                        .foregroundStyle(draft.sellerName.isEmpty ? .secondary : .primary)
                }
            }

            if !draft.sellerTaxID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledContent("Seller Tax ID", value: draft.sellerTaxID)
            }

            if !draft.sellerVATID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledContent("Seller VAT ID", value: draft.sellerVATID)
            }
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private var customerSelectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            savedClientPicker

            if hasSelectedCustomer {
                InvoiceCustomerSummaryView(
                    title: customerSummaryTitle,
                    subtitle: customerSummarySubtitle
                )

                if !hasCustomerEmail {
                    Label("Add a client email before sending this invoice.", systemImage: "envelope.badge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            } else if hasAttemptedSave {
                InvoiceValidationMessage("Choose or add a client before saving.")
            } else {
                Label("Choose an existing client or add a new one.", systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: addClientFromInvoice) {
                    Label("New Client", systemImage: "plus")
                }

                if selectedClient != nil {
                    Button(action: editSelectedClient) {
                        Label("Edit Client", systemImage: "pencil")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(hasAttemptedSave && isMissingCustomer ? 10 : 0)
        .background {
            if hasAttemptedSave && isMissingCustomer {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.red.opacity(0.07))
            }
        }
        .overlay {
            if hasAttemptedSave && isMissingCustomer {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.red.opacity(0.55), lineWidth: 1)
            }
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private var currencyOptions: [String] {
        let currentCode = draft.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !currentCode.isEmpty, !supportedCurrencies.contains(currentCode) else {
            return supportedCurrencies
        }
        return [currentCode] + supportedCurrencies
    }

    private var paymentMethodOptions: [String] {
        let currentMethod = draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentMethod.isEmpty, !InvoiceDefaults.supportedPaymentMethods.contains(currentMethod) else {
            return InvoiceDefaults.supportedPaymentMethods
        }
        return [currentMethod] + InvoiceDefaults.supportedPaymentMethods
    }

    private func currencyLabel(for currencyCode: String) -> String {
        let code = currencyCode.uppercased()
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) - \(name)"
    }

    private var savedClientPicker: some View {
        Picker("Saved client", selection: selectedClientBinding) {
            Text("Select client").tag(Client.ID?.none)
            ForEach(clientStore.clients) { client in
                Text(client.displayName).tag(Client.ID?.some(client.id))
            }
        }
        .disabled(clientStore.clients.isEmpty)
    }

    private var selectedClient: Client? {
        guard let clientID = draft.clientID else { return nil }
        return clientStore.clients.first { $0.id == clientID }
    }

    private var isMissingInvoiceNumber: Bool {
        draft.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isMissingCustomer: Bool {
        !hasSelectedCustomer
    }

    private var hasSelectedCustomer: Bool {
        selectedClient != nil || !draft.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasCustomerEmail: Bool {
        let emailCandidates = [
            selectedClient?.email,
            selectedClient?.additionalEmail,
            draft.clientEmail
        ]
        return emailCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }

    private var validLineItemCount: Int {
        draft.lineItems.filter { item in
            !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && item.quantity > 0
                && item.unitPrice > 0
        }.count
    }

    private var hasValidLineItems: Bool {
        validLineItemCount > 0
    }

    private var hasSellerDetails: Bool {
        !draft.sellerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var readinessItems: [InvoiceReadinessItem] {
        [
            InvoiceReadinessItem(title: "Seller", detail: sellerDisplayName, isComplete: hasSellerDetails),
            InvoiceReadinessItem(title: "Customer", detail: hasSelectedCustomer ? customerSummaryTitle : "Choose a client", isComplete: hasSelectedCustomer),
            InvoiceReadinessItem(title: "Items", detail: hasValidLineItems ? "\(validLineItemCount) priced" : "Add a priced item", isComplete: hasValidLineItems),
            InvoiceReadinessItem(title: "Total", detail: money(draft.total), isComplete: draft.total > 0)
        ]
    }

    private var invoiceReadinessSummary: some View {
        InvoiceReadinessSummary(
            items: readinessItems,
            statusTitle: draft.displayStatus.title,
            total: money(draft.total),
            canSaveDraft: canSaveDraft,
            canIssue: canIssue,
            hasAttemptedSave: hasAttemptedSave,
            blockingMessage: readinessBlockingMessage
        )
    }

    private var readinessBlockingMessage: String? {
        if isMissingInvoiceNumber {
            return "Add an invoice number."
        }
        if !hasSelectedCustomer {
            return "Choose or create a client."
        }
        if !hasValidLineItems {
            return "Add at least one priced invoice item."
        }
        if draft.total <= 0 {
            return "Check item prices so the invoice total is above zero."
        }
        return nil
    }

    private var customerSummaryTitle: String {
        selectedClient?.displayName ?? draft.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customerSummarySubtitle: String {
        if let selectedClient, !selectedClient.subtitle.isEmpty {
            return selectedClient.subtitle
        }
        let invoiceEmail = draft.clientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return invoiceEmail.isEmpty ? "No email saved" : invoiceEmail
    }

    private var selectedSellerBinding: Binding<MyCompanySellerProfile.ID?> {
        Binding(
            get: { selectedSellerID },
            set: { profileID in
                guard let profileID,
                      let profile = companyProfileStore.profiles.first(where: { $0.id == profileID }) else { return }
                companyProfileStore.selectProfile(id: profileID)
                applySellerProfile(profile.company)
            }
        )
    }

    private var selectedSellerID: MyCompanySellerProfile.ID? {
        companyProfileStore.profiles.first { profile in
            profile.company.name.trimmedForInvoicePreview == draft.sellerName.trimmedForInvoicePreview
                && profile.company.taxId.trimmedForInvoicePreview == draft.sellerTaxID.trimmedForInvoicePreview
                && profile.company.vatId.trimmedForInvoicePreview == draft.sellerVATID.trimmedForInvoicePreview
        }?.id ?? companyProfileStore.selectedProfileID
    }

    private var selectedClientBinding: Binding<Client.ID?> {
        Binding(
            get: { draft.clientID },
            set: { clientID in
                guard let clientID else {
                    draft.clientID = nil
                    draft.clientName = ""
                    draft.clientEmail = ""
                    return
                }

                guard let client = clientStore.clients.first(where: { $0.id == clientID }) else { return }
                apply(client)
            }
        )
    }

    private var invoiceItems: some View {
        Group {
            if draft.lineItems.isEmpty {
                Text("No items added yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                if hasAttemptedSave && !hasValidLineItems {
                    InvoiceValidationMessage("Add at least one item with a name, quantity, and unit price.")
                }

                ForEach(draft.lineItems.indices, id: \.self) { index in
                    InvoiceLineItemRow(
                        item: $draft.lineItems[index],
                        currencyCode: draft.currencyCode,
                        itemNumber: index + 1,
                        canDelete: draft.lineItems.count > 1,
                        onEdit: { editLineItem(at: index) },
                        onDelete: { deleteLineItem(at: index) }
                    )
                }
            }
        }
    }

    private func apply(_ client: Client) {
        draft.clientID = client.id
        draft.clientName = client.displayName
        draft.clientEmail = client.email
    }

    private func addClientFromInvoice() {
        clientEditorDraft = .empty
    }

    private func editSelectedClient() {
        guard let selectedClient else { return }
        clientEditorDraft = selectedClient
    }

    private func saveClientFromInvoice(_ client: Client) {
        clientStore.save(client)
        apply(client)
        clientEditorDraft = nil
    }

    private func clientEditorTitle(for client: Client) -> String {
        client.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Client" : "Client Details"
    }

    private func loadEditorDependencies() {
        clientStore.load()
        refreshSellerProfiles(applyToEmptyDraft: true)
        productStore.load()
    }

    private func refreshSellerProfiles(applyToEmptyDraft: Bool) {
        companyProfileStore.load()

        if applyToEmptyDraft,
           draft.sellerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           companyProfileStore.hasSavedProfile {
            applySellerProfile()
        }
    }

    private func applySellerProfile() {
        applySellerProfile(companyProfileStore.company)
    }

    private func applySellerProfile(_ company: CompanyFormData) {
        draft.sellerName = company.name
        draft.sellerTaxID = company.taxId
        draft.sellerVATID = company.vatId
    }

    private func addLineItem() {
        lineItemEditorDraft = EditableInvoiceLineItem(index: nil, item: .empty)
    }

    private func editLineItem(at index: Int) {
        guard draft.lineItems.indices.contains(index) else { return }
        lineItemEditorDraft = EditableInvoiceLineItem(index: index, item: draft.lineItems[index])
    }

    private func saveLineItem(_ editableItem: EditableInvoiceLineItem) {
        if let index = editableItem.index, draft.lineItems.indices.contains(index) {
            draft.lineItems[index] = editableItem.item
        } else {
            draft.lineItems.append(editableItem.item)
        }
        lineItemEditorDraft = nil
    }

    private func deleteLineItem(at offsets: IndexSet) {
        draft.lineItems.remove(atOffsets: offsets)
    }

    private func deleteLineItem(at index: Int) {
        guard draft.lineItems.indices.contains(index) else { return }
        draft.lineItems.remove(at: index)
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: draft.currencyCode.isEmpty ? "EUR" : draft.currencyCode))
    }

    private func attemptSaveDraft() {
        hasAttemptedSave = true
        guard canSaveDraft else { return }
        save()
    }

    private func attemptIssue() {
        hasAttemptedSave = true
        guard canIssue else { return }
        draft.issue()
        save()
    }

    private func save() {
        draft.currencyCode = draft.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        draft.paymentMethod = draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.paymentMethod.isEmpty {
            draft.paymentMethod = InvoiceDefaults.standardPaymentMethod
        }
        draft.paymentInstructions = draft.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.refreshStatus()
        onSave(draft)
        #if !os(macOS)
        dismiss()
        #endif
    }

    private var editorActionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let readinessBlockingMessage {
                Label(readinessBlockingMessage, systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    editorActionButtons
                }
                VStack(spacing: 10) {
                    editorActionButtons
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var editorActionButtons: some View {
        Button(action: attemptSaveDraft) {
            Label(canSaveDraft ? "Save Draft" : "Review", systemImage: canSaveDraft ? "tray.and.arrow.down" : "exclamationmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button(action: attemptIssue) {
            Label("Issue Invoice", systemImage: "checkmark.seal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canIssue)
    }
}

private struct InvoiceReadinessItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
}

private struct InvoiceReadinessSummary: View {
    let items: [InvoiceReadinessItem]
    let statusTitle: String
    let total: String
    let canSaveDraft: Bool
    let canIssue: Bool
    let hasAttemptedSave: Bool
    let blockingMessage: String?

    private var chipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(canIssue ? "Ready to issue" : (canSaveDraft ? "Draft can be saved" : "Needs attention"))
                        .font(.headline)
                    Text("\(statusTitle) • \(total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Image(systemName: canIssue ? "checkmark.seal.fill" : (canSaveDraft ? "doc.badge.clock" : "exclamationmark.triangle.fill"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(canIssue ? .green : (canSaveDraft ? .blue : .orange))
            }

            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    InvoiceReadinessChip(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !canIssue, let blockingMessage {
                Label(blockingMessage, systemImage: hasAttemptedSave ? "exclamationmark.circle.fill" : "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(canSaveDraft ? .blue : .orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((canIssue ? Color.green : (canSaveDraft ? Color.blue : Color.orange)).opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct InvoiceReadinessChip: View {
    let item: InvoiceReadinessItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                Text(item.detail.isEmpty ? "Missing" : item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? .green : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InvoiceCustomerSummaryView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title.isEmpty ? "Unnamed Client" : title, systemImage: "person.crop.square")
                .font(.body.weight(.medium))

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct InvoiceValidationMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.red)
    }
}

private struct EditableInvoiceLineItem: Identifiable {
    let id = UUID()
    let index: Int?
    var item: InvoiceLineItem
}

private struct InvoiceLineItemRow: View {
    @Binding var item: InvoiceLineItem
    let currencyCode: String
    let itemNumber: Int
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var resolvedTitle: String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Unnamed item" : title
    }

    private var resolvedCurrencyCode: String {
        currencyCode.isEmpty ? "EUR" : currencyCode
    }

    private var quantityBinding: Binding<Double> {
        Binding(
            get: { item.quantity },
            set: { item.quantity = max($0, 0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("VAT \(formatted(item.vatRate))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InlineQuantityControl(quantity: quantityBinding)

            Button(action: onEdit) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.grossTotal.formatted(.currency(code: resolvedCurrencyCode)))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Item \(itemNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 82, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove item", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary.opacity(0.7), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct InlineQuantityControl: View {
    @Binding var quantity: Double

    private var stepperBinding: Binding<Double> {
        Binding(
            get: { quantity },
            set: { quantity = max($0, 0) }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Qty")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            DecimalTextField("1", value: stepperBinding)
                .frame(width: 48)

            Stepper("Quantity", value: stepperBinding, in: 0...9999, step: 1)
                .labelsHidden()
                .frame(width: 52)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

private extension ProductItem {
    func matchesInvoiceItemSearch(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        var fields = [displayName, name, description, unit, category, kind.title, comments]
        for price in prices {
            fields.append(contentsOf: [
                price.customerCategory,
                price.currencyCode,
                price.netPrice.formatted(.number.precision(.fractionLength(0...2))),
                price.grossPrice.formatted(.number.precision(.fractionLength(0...2))),
                price.taxRate.formatted(.number.precision(.fractionLength(0...2)))
            ])
        }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct ProductSearchResultRow: View {
    let product: ProductItem
    let currencyCode: String
    let isSelected: Bool
    let action: () -> Void

    private var price: ProductPrice {
        product.primaryPrice
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(product.category) • VAT \(price.taxRate.formatted(.number.precision(.fractionLength(0...2))))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(price.netPrice.formatted(.currency(code: price.currencyCode.isEmpty ? currencyCode : price.currencyCode)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct InvoiceLineItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editableItem: EditableInvoiceLineItem
    @State private var selectedProductID: ProductItem.ID?
    @State private var productSearchText = ""
    @State private var hasAttemptedSave = false

    let currencyCode: String
    let products: [ProductItem]
    let onCancel: () -> Void
    let onSave: (EditableInvoiceLineItem) -> Void

    private var title: String {
        editableItem.index == nil ? "New Item" : "Edit Item"
    }

    private var actionTitle: String {
        editableItem.index == nil ? "Add" : "Done"
    }

    private var resolvedCurrencyCode: String {
        currencyCode.isEmpty ? "EUR" : currencyCode
    }

    private var grossUnitPrice: Double {
        editableItem.item.unitPrice * (1 + editableItem.item.vatRate / 100)
    }

    private var discountMultiplier: Double {
        1 - min(max(editableItem.item.discountPercent, 0), 100) / 100
    }

    private var discountedUnitPrice: Double {
        editableItem.item.unitPrice * discountMultiplier
    }

    private var discountedGrossUnitPrice: Double {
        grossUnitPrice * discountMultiplier
    }

    private var hasItemDiscount: Bool {
        editableItem.item.discountPercent > 0
    }

    private var isMissingItemName: Bool {
        editableItem.item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isMissingQuantity: Bool {
        editableItem.item.quantity <= 0
    }

    private var isMissingUnitPrice: Bool {
        editableItem.item.unitPrice <= 0
    }

    private var canSave: Bool {
        !isMissingItemName && !isMissingQuantity && !isMissingUnitPrice
    }

    private var filteredProducts: [ProductItem] {
        products.filter { $0.matchesInvoiceItemSearch(productSearchText) }
    }

    private var productSearchQuery: String {
        productSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleProductLimit: Int {
        productSearchQuery.isEmpty ? 3 : 6
    }

    private var visibleProducts: [ProductItem] {
        Array(filteredProducts.prefix(visibleProductLimit))
    }

    private var selectedProduct: ProductItem? {
        guard let selectedProductID else { return nil }
        return products.first { $0.id == selectedProductID }
    }

    private var selectedProductCurrencyMismatch: Bool {
        guard let selectedProduct else { return false }
        return selectedProduct.primaryPrice.currencyCode.uppercased() != resolvedCurrencyCode.uppercased()
    }

    private var selectedProductBinding: Binding<ProductItem.ID?> {
        Binding(
            get: { selectedProductID },
            set: { productID in
                selectedProductID = productID
                guard let productID,
                      let product = products.first(where: { $0.id == productID }) else { return }
                apply(product)
            }
        )
    }

    init(
        editableItem: EditableInvoiceLineItem,
        currencyCode: String,
        products: [ProductItem],
        onCancel: @escaping () -> Void,
        onSave: @escaping (EditableInvoiceLineItem) -> Void
    ) {
        _editableItem = State(initialValue: editableItem)
        self.currencyCode = currencyCode
        self.products = products
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        mobileBody
            .navigationTitle(title)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle, action: commit)
                }
            }
        #endif
    }

    private var productSelectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search products", text: $productSearchText)
                    .textFieldStyle(.plain)
                if !productSearchText.isEmpty {
                    Button {
                        productSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                selectedProductBinding.wrappedValue = nil
            } label: {
                Label("Custom item", systemImage: selectedProductID == nil ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedProductID == nil ? .blue : .secondary)

            if filteredProducts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No saved products match this search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !productSearchQuery.isEmpty {
                        Button {
                            productSearchText = ""
                        } label: {
                            Label("Clear Search", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(visibleProducts) { product in
                        ProductSearchResultRow(
                            product: product,
                            currencyCode: resolvedCurrencyCode,
                            isSelected: selectedProductID == product.id,
                            action: {
                                selectedProductBinding.wrappedValue = product.id
                            }
                        )
                    }
                }
            }

            if filteredProducts.count > visibleProducts.count {
                Text(productSearchQuery.isEmpty ? "Showing \(visibleProducts.count) suggestions from \(filteredProducts.count) saved products. Search to find another product." : "Showing first \(visibleProducts.count) of \(filteredProducts.count) matches. Refine the search to narrow results.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if selectedProductCurrencyMismatch, let selectedProduct {
                Label(
                    "Product price is \(selectedProduct.primaryPrice.currencyCode.uppercased()); invoice uses \(resolvedCurrencyCode). Price copied without conversion.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mobileBody: some View {
        Form {
            if !products.isEmpty {
                Section("Saved Product") {
                    productSelectionContent
                }
            }

            Section("Item Information") {
                InvoiceTextField("Item name", text: $editableItem.item.title, prompt: "Required")
                InvoiceTextField("Description", text: $editableItem.item.description, prompt: "Optional")
            }

            Section("Quantity & Unit") {
                LabeledContent("Qty") {
                    InlineQuantityControl(quantity: $editableItem.item.quantity)
                }
            }

            Section("Unit Pricing") {
                LabeledContent("Unit price") {
                    HStack(spacing: 6) {
                        DecimalTextField("0", value: $editableItem.item.unitPrice)
                        Text(resolvedCurrencyCode)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("VAT rate") {
                    HStack(spacing: 6) {
                        DecimalTextField("20", value: $editableItem.item.vatRate)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Discount") {
                    HStack(spacing: 6) {
                        DecimalTextField("0", value: $editableItem.item.discountPercent)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Totals") {
                LabeledContent("Total net", value: editableItem.item.netTotal.formatted(.currency(code: resolvedCurrencyCode)))
                LabeledContent("Total VAT", value: editableItem.item.vatTotal.formatted(.currency(code: resolvedCurrencyCode)))
                LabeledContent("Total gross", value: editableItem.item.grossTotal.formatted(.currency(code: resolvedCurrencyCode)))
                    .font(.headline)
            }
        }
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .padding(.top, 4)

                    if !products.isEmpty {
                        MacItemSheetSection("Saved Product") {
                            productSelectionContent
                                .padding(.vertical, 10)
                        }
                    }

                    MacItemSheetSection("Item Information") {
                        MacItemSheetTextRow(
                            "Item name",
                            text: $editableItem.item.title,
                            prompt: "Required",
                            isMissing: hasAttemptedSave && isMissingItemName
                        )
                        Divider()
                        MacItemSheetTextRow("Description", text: $editableItem.item.description, prompt: "Optional")
                    }

                    MacItemSheetSection("Quantity & Unit") {
                        MacItemSheetNumberRow(
                            "Qty",
                            value: $editableItem.item.quantity,
                            prompt: "1",
                            showsStepper: true,
                            isMissing: hasAttemptedSave && isMissingQuantity
                        )
                    }

                    MacItemSheetSection("Unit Pricing") {
                        MacItemSheetNumberRow(
                            "Net",
                            value: $editableItem.item.unitPrice,
                            prompt: "0",
                            suffix: resolvedCurrencyCode,
                            afterDiscountText: hasItemDiscount ? "After discount: \(discountedUnitPrice.formatted(.currency(code: resolvedCurrencyCode)))" : nil,
                            isMissing: hasAttemptedSave && isMissingUnitPrice
                        )
                        Divider()
                        MacItemSheetComputedRow(
                            "Gross",
                            value: grossUnitPrice,
                            suffix: resolvedCurrencyCode,
                            afterDiscountText: hasItemDiscount ? "After discount: \(discountedGrossUnitPrice.formatted(.currency(code: resolvedCurrencyCode)))" : nil
                        )
                        Divider()
                        MacItemSheetNumberRow("VAT rate", value: $editableItem.item.vatRate, prompt: "20", suffix: "%")
                        Divider()
                        MacItemSheetNumberRow("Discount", value: $editableItem.item.discountPercent, prompt: "0", suffix: "%")
                    }

                    MacItemTotalsView(item: editableItem.item, currencyCode: resolvedCurrencyCode)
                }
                .padding(32)
                .padding(.bottom, 12)
            }

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 760, height: 700)
    }
    #endif

    private func apply(_ product: ProductItem) {
        let price = product.primaryPrice
        editableItem.item.title = product.displayName
        editableItem.item.description = product.description
        editableItem.item.quantity = price.quantity > 0 ? price.quantity : 1
        editableItem.item.unitPrice = price.netPrice
        editableItem.item.vatRate = price.taxRate
    }

    private func cancel() {
        onCancel()
        dismiss()
    }

    private func commit() {
        hasAttemptedSave = true
        guard canSave else { return }
        onSave(editableItem)
        dismiss()
    }
}

#if os(macOS)
private struct MacItemSheetSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct MacItemSheetTextRow: View {
    let title: String
    let prompt: String
    let isMissing: Bool
    @Binding var text: String

    init(_ title: String, text: Binding<String>, prompt: String, isMissing: Bool = false) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.isMissing = isMissing
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(isMissing ? .red : .primary)
                .frame(width: 150, alignment: .leading)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isMissing ? .red : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 46)
        .overlay(alignment: .leading) {
            if isMissing {
                Capsule()
                    .fill(.red)
                    .frame(width: 3, height: 24)
                    .offset(x: -10)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct MacItemSheetNumberRow: View {
    let title: String
    let prompt: String
    let suffix: String?
    let afterDiscountText: String?
    let showsStepper: Bool
    let isMissing: Bool
    @Binding var value: Double

    private var stepperBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = max($0, 0) }
        )
    }

    init(_ title: String, value: Binding<Double>, prompt: String, suffix: String? = nil, afterDiscountText: String? = nil, showsStepper: Bool = false, isMissing: Bool = false) {
        self.title = title
        self._value = value
        self.prompt = prompt
        self.suffix = suffix
        self.afterDiscountText = afterDiscountText
        self.showsStepper = showsStepper
        self.isMissing = isMissing
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(isMissing ? .red : .primary)
                .frame(width: 150, alignment: .leading)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 10) {
                    DecimalTextField(prompt, value: showsStepper ? stepperBinding : $value)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(isMissing ? .red : .primary)
                        .frame(width: showsStepper ? 76 : (suffix == nil ? 180 : 150), alignment: .trailing)

                    if showsStepper {
                        Stepper(title, value: stepperBinding, in: 0...9999, step: 1)
                            .labelsHidden()
                            .frame(width: 52)
                    }

                    if let suffix {
                        Text(suffix)
                            .foregroundStyle(isMissing ? .red : .secondary)
                            .frame(width: 52, alignment: .leading)
                    }
                }

                if let afterDiscountText {
                    Text(afterDiscountText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(minHeight: afterDiscountText == nil ? 46 : 70)
        .overlay(alignment: .leading) {
            if isMissing {
                Capsule()
                    .fill(.red)
                    .frame(width: 3, height: 24)
                    .offset(x: -10)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct MacItemSheetComputedRow: View {
    let title: String
    let value: Double
    let suffix: String
    let afterDiscountText: String?

    init(_ title: String, value: Double, suffix: String, afterDiscountText: String? = nil) {
        self.title = title
        self.value = value
        self.suffix = suffix
        self.afterDiscountText = afterDiscountText
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 150, alignment: .leading)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 10) {
                    Text(value.formatted(.number.precision(.fractionLength(2))))
                        .foregroundStyle(.primary)
                        .frame(width: 150, alignment: .trailing)

                    Text(suffix)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                }

                if let afterDiscountText {
                    Text(afterDiscountText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(minHeight: afterDiscountText == nil ? 46 : 70)
    }
}

private struct MacItemTotalsView: View {
    let item: InvoiceLineItem
    let currencyCode: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if item.discountAmount > 0 {
                totalRow("Discount", value: -item.discountAmount, isDiscount: true)
            }
            totalRow("Total net", value: item.netTotal)
            totalRow("Total VAT", value: item.vatTotal)
            totalRow("Total gross", value: item.grossTotal, isProminent: true)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func totalRow(_ title: String, value: Double, isProminent: Bool = false, isDiscount: Bool = false) -> some View {
        HStack(spacing: 18) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.formatted(.currency(code: currencyCode)))
                .fontWeight(isProminent ? .semibold : .regular)
                .foregroundStyle(isDiscount ? .orange : (isProminent ? .primary : .secondary))
                .frame(width: 120, alignment: .trailing)
        }
        .font(.body)
    }
}
#endif

private struct InvoiceLineItemEditor: View {
    @Binding var item: InvoiceLineItem
    let currencyCode: String
    let itemNumber: Int
    let canDelete: Bool
    let onDelete: () -> Void

    private var resolvedCurrencyCode: String {
        currencyCode.isEmpty ? "EUR" : currencyCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Item \(itemNumber)")
                    .font(.headline)

                Spacer()

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Remove item", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }

            VStack(spacing: 0) {
                InvoiceLineTextField("Description", text: $item.title, prompt: "Item or service")
                InvoiceLineNumberField("Quantity", value: $item.quantity, prompt: "1")
                InvoiceLineNumberField("Unit price", value: $item.unitPrice, prompt: "0")
                InvoiceLineNumberField("VAT rate", value: $item.vatRate, prompt: "20", suffix: "%")
                InvoiceLineNumberField("Discount", value: $item.discountPercent, prompt: "0", suffix: "%")
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .trailing, spacing: 6) {
                InvoiceLineTotalRow(title: "Net", value: item.netTotal, currencyCode: resolvedCurrencyCode)
                InvoiceLineTotalRow(title: "VAT", value: item.vatTotal, currencyCode: resolvedCurrencyCode)
                InvoiceLineTotalRow(title: "Gross", value: item.grossTotal, currencyCode: resolvedCurrencyCode, isProminent: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

private struct InvoiceLineTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct InvoiceLineNumberField: View {
    let title: String
    let prompt: String
    let suffix: String?
    @Binding var value: Double

    init(_ title: String, value: Binding<Double>, prompt: String, suffix: String? = nil) {
        self.title = title
        self._value = value
        self.prompt = prompt
        self.suffix = suffix
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                DecimalTextField(prompt, value: $value)
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct InvoiceLineTotalRow: View {
    let title: String
    let value: Double
    let currencyCode: String
    var isProminent = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.formatted(.currency(code: currencyCode)))
                .fontWeight(isProminent ? .semibold : .regular)
                .foregroundStyle(isProminent ? .primary : .secondary)
        }
        .font(.caption)
    }
}

private struct InvoiceTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if os(macOS)
private struct MacInvoiceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 4)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MacInvoiceTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 132, alignment: .leading)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct MacInvoiceNumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 132, alignment: .leading)
            DecimalTextField("0", value: $value)
                .textFieldStyle(.roundedBorder)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct MacReadOnlyInvoiceRow: View {
    let title: String
    let value: String
    let isProminent: Bool

    init(_ title: String, value: String, isProminent: Bool = false) {
        self.title = title
        self.value = value
        self.isProminent = isProminent
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 132, alignment: .leading)
            Text(value)
                .fontWeight(isProminent ? .bold : .regular)
                .foregroundStyle(isProminent ? .green : .secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
#endif

private struct DecimalTextField: View {
    let prompt: String
    @Binding var value: Double
    @State private var text: String

    init(_ prompt: String, value: Binding<Double>) {
        self.prompt = prompt
        self._value = value
        self._text = State(initialValue: DecimalTextField.displayText(for: value.wrappedValue))
    }

    var body: some View {
        TextField(prompt, text: $text)
            .multilineTextAlignment(.trailing)
            #if os(iOS) || os(visionOS)
            .keyboardType(.decimalPad)
            #endif
            .onChange(of: text) { _, newValue in
                updateValue(from: newValue)
            }
            .onChange(of: value) { _, newValue in
                let displayText = Self.displayText(for: newValue)
                if text != displayText, Double(text.replacingOccurrences(of: ",", with: ".")) != newValue {
                    text = displayText
                }
            }
    }

    private func updateValue(from input: String) {
        let normalizedInput = input
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedInput.isEmpty {
            value = 0
            return
        }

        guard let parsedValue = Double(normalizedInput) else { return }
        value = parsedValue
    }

    private static func displayText(for value: Double) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...2))
        )
    }
}
