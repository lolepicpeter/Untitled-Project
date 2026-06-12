import SwiftUI

struct DashboardView: View {
    @State private var invoiceStore = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var invoiceDraft: Invoice?
    @State private var selectedInvoice: Invoice?
    @State private var isShowingSellerSetup = false

    private var activeInvoices: [Invoice] {
        invoiceStore.invoices.filter { $0.displayStatus != .cancelled }
    }

    private var issuedInvoices: [Invoice] {
        activeInvoices.filter { $0.displayStatus != .draft }
    }

    private var draftInvoices: [Invoice] {
        activeInvoices.filter { $0.displayStatus == .draft }
    }

    private var unpaidInvoices: [Invoice] {
        activeInvoices.filter { invoice in
            let status = invoice.displayStatus
            return status == .sent || status == .overdue
        }
    }

    private var overdueInvoices: [Invoice] {
        activeInvoices.filter { $0.displayStatus == .overdue }
    }

    private var paidInvoices: [Invoice] {
        activeInvoices.filter { $0.displayStatus == .paid }
    }

    private var currentMonthInvoices: [Invoice] {
        issuedInvoices.filter { Calendar.current.isDate($0.issueDate, equalTo: Date(), toGranularity: .month) }
    }

    private var dueSoonInvoices: [Invoice] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let soon = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        return unpaidInvoices.filter { invoice in
            let dueDate = calendar.startOfDay(for: invoice.dueDate)
            return dueDate >= today && dueDate <= soon
        }
    }

    private var attentionInvoices: [Invoice] {
        Array((overdueInvoices + dueSoonInvoices + draftInvoices).prefix(5))
    }

    private var recentInvoices: [Invoice] {
        Array(activeInvoices.sorted { $0.issueDate > $1.issueDate }.prefix(6))
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)]
    }

    var body: some View {
        rootContent
            .sheet(item: $invoiceDraft) { invoice in
                NavigationStack {
                    InvoiceEditorView(invoice: invoice, title: "New Invoice") { savedInvoice in
                        invoiceStore.save(savedInvoice)
                        invoiceDraft = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { invoiceDraft = nil }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 1080, minHeight: 760)
                #endif
            }
            .sheet(item: $selectedInvoice) { invoice in
                NavigationStack {
                    MobileInvoiceDetailView(
                        invoice: invoice,
                        onSave: saveSelectedInvoice,
                        onDuplicate: duplicateSelectedInvoice,
                        onDiscardDraft: discardSelectedDraft
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedInvoice = nil }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 760)
                #endif
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
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 620)
                #endif
            }
            .onAppear {
                invoiceStore.load()
                profileStore.load()
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                    profileStore.load()
                }
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        NavigationStack {
            dashboardScrollView
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: createInvoice) {
                            Label(profileStore.hasSavedProfile ? "New Invoice" : "Set Up Seller", systemImage: profileStore.hasSavedProfile ? "plus" : "building.2")
                        }
                    }
                }
        }
        #else
        NavigationStack {
            dashboardScrollView
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createInvoice) {
                        Label(profileStore.hasSavedProfile ? "New Invoice" : "Set Up Seller", systemImage: profileStore.hasSavedProfile ? "plus" : "building.2")
                    }
                }
            }
        }
        #endif
    }

    private var dashboardScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sellerSetupPrompt
                metricsGrid
                attentionSection
                recentSection
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(24)
        }
    }

    @ViewBuilder
    private var sellerSetupPrompt: some View {
        if !profileStore.hasSavedProfile {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "building.2")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a seller before invoicing")
                        .font(.headline)
                    Text("Seller details are used on new invoices and printed documents.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { isShowingSellerSetup = true }) {
                    Label("Set Up Seller", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
            DashboardMetricCard(
                title: "This Month",
                value: amountSummary(for: currentMonthInvoices) { $0.total },
                subtitle: "\(currentMonthInvoices.count) issued",
                systemImage: "calendar",
                tint: .blue
            )

            DashboardMetricCard(
                title: "Unpaid",
                value: amountSummary(for: unpaidInvoices) { $0.balanceDue },
                subtitle: "\(unpaidInvoices.count) open",
                systemImage: "clock",
                tint: .orange
            )

            DashboardMetricCard(
                title: "Overdue",
                value: amountSummary(for: overdueInvoices) { $0.balanceDue },
                subtitle: "\(overdueInvoices.count) late",
                systemImage: "exclamationmark.triangle",
                tint: .red
            )

            DashboardMetricCard(
                title: "Drafts",
                value: amountSummary(for: draftInvoices) { $0.total },
                subtitle: "\(draftInvoices.count) not issued",
                systemImage: "doc.text",
                tint: .gray
            )

            DashboardMetricCard(
                title: "Paid",
                value: amountSummary(for: paidInvoices) { $0.total },
                subtitle: "\(paidInvoices.count) complete",
                systemImage: "checkmark.circle",
                tint: .green
            )
        }
    }

    private var attentionSection: some View {
        DashboardAttentionSection(invoices: attentionInvoices, onSelectInvoice: openInvoice)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Invoices")
                .font(.title3.weight(.semibold))

            if recentInvoices.isEmpty {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "No invoices yet",
                        systemImage: "doc.text",
                        description: Text("Create an invoice to start tracking revenue, payments, and overdue work.")
                    )

                    Button(action: createInvoice) {
                        Label(profileStore.hasSavedProfile ? "Create Invoice" : "Set Up Seller", systemImage: profileStore.hasSavedProfile ? "plus" : "building.2")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(recentInvoices) { invoice in
                        Button {
                            openInvoice(invoice)
                        } label: {
                            DashboardInvoiceRow(invoice: invoice)
                        }
                        .buttonStyle(.plain)

                        if invoice.id != recentInvoices.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func createInvoice() {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        invoiceDraft = invoiceStore.newInvoiceDraft()
    }

    private func openInvoice(_ invoice: Invoice) {
        if let currentInvoice = invoiceStore.invoices.first(where: { $0.id == invoice.id }) {
            selectedInvoice = currentInvoice
        } else {
            selectedInvoice = invoice
        }
    }

    private func saveSelectedInvoice(_ invoice: Invoice) {
        invoiceStore.save(invoice)
        selectedInvoice = invoice
    }

    private func duplicateSelectedInvoice(_ invoice: Invoice) -> Invoice {
        let duplicate = invoiceStore.duplicateDraft(from: invoice)
        invoiceStore.save(duplicate)
        selectedInvoice = duplicate
        return duplicate
    }

    private func discardSelectedDraft(_ invoice: Invoice) {
        invoiceStore.delete(invoice)
        selectedInvoice = nil
    }

    private func amountSummary(for invoices: [Invoice], amount: (Invoice) -> Double) -> String {
        let grouped = Dictionary(grouping: invoices, by: { normalizedCurrency($0.currencyCode) })
            .mapValues { groupedInvoices in
                groupedInvoices.reduce(0) { partialResult, invoice in
                    partialResult + amount(invoice)
                }
            }
            .filter { abs($0.value) > 0.005 }
            .sorted { $0.key < $1.key }

        guard !grouped.isEmpty else {
            return 0.formatted(.currency(code: "EUR"))
        }

        let visible = grouped.prefix(2).map { currencyCode, total in
            total.formatted(.currency(code: currencyCode))
        }
        .joined(separator: " / ")

        if grouped.count > 2 {
            return "\(visible) +\(grouped.count - 2)"
        }

        return visible
    }

    private func normalizedCurrency(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "EUR" : trimmed
    }
}

#if os(macOS)
private struct DashboardHeader: View {
    let hasSavedProfile: Bool
    let onCreateInvoice: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Dashboard")
                .font(.title3.weight(.semibold))

            Spacer()

            Button(action: onCreateInvoice) {
                Label(hasSavedProfile ? "New Invoice" : "Set Up Seller", systemImage: hasSavedProfile ? "plus" : "building.2")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
#endif

private struct DashboardAttentionSection: View {
    let invoices: [Invoice]
    let onSelectInvoice: (Invoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Needs Attention")
                    .font(.title3.weight(.semibold))

                Spacer()

                if !invoices.isEmpty {
                    Text("\(invoices.count) open")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if invoices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No urgent invoice work", systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Overdue, due-soon, and draft invoices will appear here when they need action.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(invoices) { invoice in
                        Button {
                            onSelectInvoice(invoice)
                        } label: {
                            DashboardAttentionRow(invoice: invoice)
                        }
                        .buttonStyle(.plain)

                        if invoice.id != invoices.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct DashboardAttentionRow: View {
    let invoice: Invoice

    private var draftMissingCount: Int {
        var count = 0
        if invoice.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if invoice.sellerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if invoice.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !invoice.lineItems.contains(where: { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.unitPrice > 0 }) { count += 1 }
        if invoice.total <= 0 { count += 1 }
        return count
    }

    private var actionText: String {
        switch invoice.displayStatus {
        case .draft:
            draftMissingCount == 0 ? "Ready to issue" : "\(draftMissingCount) steps remaining"
        case .overdue:
            "Record payment or remind client"
        case .sent:
            "Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))"
        case .paid:
            "Payment complete"
        case .cancelled:
            "Cancelled"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: invoice.displayStatus.dashboardSystemImage)
                .font(.headline)
                .foregroundStyle(invoice.displayStatus.dashboardTint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(invoice.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? actionText : invoice.clientName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.balanceDue.formatted(.currency(code: normalizedCurrency(invoice.currencyCode))))
                    .font(.headline.weight(.semibold))
                Text(actionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func normalizedCurrency(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "EUR" : trimmed
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardInvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: invoice.displayStatus.dashboardSystemImage)
                .font(.headline)
                .foregroundStyle(invoice.displayStatus.dashboardTint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.number)
                    .font(.headline)
                    .lineLimit(1)

                Text(invoice.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(invoice.total.formatted(.currency(code: normalizedCurrency(invoice.currencyCode))))
                    .font(.headline)

                DashboardStatusPill(status: invoice.displayStatus)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func normalizedCurrency(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "EUR" : trimmed
    }
}

private struct DashboardStatusPill: View {
    let status: InvoiceStatus

    var body: some View {
        Label(status.title, systemImage: status.dashboardSystemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.dashboardTint)
            .background(status.dashboardTint.opacity(0.14), in: Capsule())
    }
}

private extension InvoiceStatus {
    var dashboardSystemImage: String {
        switch self {
        case .draft:
            "doc.text"
        case .sent:
            "paperplane"
        case .paid:
            "checkmark.circle"
        case .overdue:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        }
    }

    var dashboardTint: Color {
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
