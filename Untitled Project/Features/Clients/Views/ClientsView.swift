import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ClientsView: View {
    var body: some View {
        #if os(macOS)
        MacClientsView()
        #else
        MobileClientsView()
        #endif
    }
}

private extension String {
    var normalizedClientName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct MobileClientsView: View {
    @State private var store = ClientStore()
    @State private var invoiceStore = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var searchText = ""
    @State private var newClientDraft: Client?
    @State private var invoiceDraft: Invoice?
    @State private var isShowingSellerSetup = false
    @State private var invoiceHistoryClient: Client?
    @State private var clientPendingDeletion: Client?

    private var filteredClients: [Client] {
        store.clients.filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.clients.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Clients",
                            systemImage: "person.2",
                            description: Text("Add a client manually or use company lookup to fill invoice details.")
                        )

                        Button {
                            addClient()
                        } label: {
                            Label("New Client", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredClients.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Matching Clients",
                            systemImage: "person.text.rectangle",
                            description: Text("No saved clients match the current search.")
                        )

                        Button {
                            searchText = ""
                        } label: {
                            Label("Clear Search", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(filteredClients) { client in
                            NavigationLink {
                                ClientEditorView(client: client, title: "Client Details") { updatedClient in
                                    store.save(updatedClient)
                                }
                            } label: {
                                ClientRow(
                                    client: client,
                                    invoiceSummary: invoiceSummary(for: client),
                                    onShowInvoiceHistory: {
                                        invoiceHistoryClient = client
                                    }
                                )
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    createInvoice(for: client)
                                } label: {
                                    Label("Invoice", systemImage: "doc.badge.plus")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    createInvoice(for: client)
                                } label: {
                                    Label("New Invoice", systemImage: "doc.badge.plus")
                                }

                                Button(role: .destructive) {
                                    requestDelete(client)
                                } label: {
                                    Label("Delete Client", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Clients")
            .searchable(text: $searchText, prompt: "Search clients")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addClient()
                    } label: {
                        Label("New Client", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $newClientDraft) { clientDraft in
                NavigationStack {
                    ClientEditorView(client: clientDraft, title: "New Client") { client in
                        store.save(client)
                        newClientDraft = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { newClientDraft = nil }
                        }
                    }
                }
            }
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
            .sheet(item: $invoiceHistoryClient) { client in
                NavigationStack {
                    ClientInvoiceHistoryView(
                        client: client,
                        summary: invoiceSummary(for: client),
                        onCreateInvoice: {
                            invoiceHistoryClient = nil
                            createInvoice(for: client)
                        },
                        onSaveInvoice: saveInvoiceFromHistory,
                        onDuplicateInvoice: duplicateInvoiceFromHistory,
                        onDiscardDraftInvoice: discardDraftInvoiceFromHistory
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { invoiceHistoryClient = nil }
                        }
                    }
                }
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Client", role: .destructive, action: confirmDelete)
                Button("Cancel", role: .cancel) { clientPendingDeletion = nil }
            } message: {
                Text(deleteConfirmationMessage)
            }
            .onAppear {
                store.load()
                invoiceStore.load()
                profileStore.load()
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                    profileStore.load()
                }
            }
        }
    }

    private func addClient() {
        newClientDraft = Client.empty
    }

    private func createInvoice(for client: Client) {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        invoiceDraft = invoiceStore.newInvoiceDraft(for: client)
    }

    private func saveInvoiceFromHistory(_ invoice: Invoice) {
        invoiceStore.save(invoice)
    }

    private func duplicateInvoiceFromHistory(_ invoice: Invoice) -> Invoice {
        let duplicate = invoiceStore.duplicateDraft(from: invoice)
        invoiceStore.save(duplicate)
        return duplicate
    }

    private func discardDraftInvoiceFromHistory(_ invoice: Invoice) {
        invoiceStore.delete(invoice)
    }

    private func invoiceSummary(for client: Client) -> ClientInvoiceSummary {
        ClientInvoiceSummary(client: client, invoices: invoiceStore.invoices)
    }


    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { clientPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    clientPendingDeletion = nil
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        guard let clientPendingDeletion else { return "Delete Client?" }
        return "Delete \(clientPendingDeletion.displayName)?"
    }

    private var deleteConfirmationMessage: String {
        guard let clientPendingDeletion else { return "" }
        let summary = invoiceSummary(for: clientPendingDeletion)
        if summary.invoiceCount > 0 {
            return "This removes the saved client only. Existing invoices stay intact with their current client details."
        }
        return "This client has no invoices and will be removed from your saved clients."
    }

    private func requestDelete(_ client: Client) {
        clientPendingDeletion = client
    }

    private func confirmDelete() {
        guard let client = clientPendingDeletion else { return }
        store.delete(client)
        clientPendingDeletion = nil
    }

    private func delete(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        requestDelete(filteredClients[index])
    }
}

#if os(macOS)
private struct MacClientsView: View {
    @State private var store = ClientStore()
    @State private var invoiceStore = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var searchText = ""
    @State private var selectedClientIDs: Set<Client.ID> = []
    @State private var selectionAnchorClientID: Client.ID?
    @State private var selectionExtentClientID: Client.ID?
    @State private var newClientDraft: Client?
    @State private var invoiceDraft: Invoice?
    @State private var isShowingSellerSetup = false
    @State private var invoiceHistoryClient: Client?
    @State private var editingClient: Client?
    @State private var clientsPendingDeletion: [Client] = []
    @State private var isClientListFocused = false

    private var filteredClients: [Client] {
        store.clients.filter { $0.matchesSearch(searchText) }
    }

    private var selectedClient: Client? {
        guard selectedClientIDs.count == 1,
              let selectedClientID = selectedClientIDs.first else { return nil }
        return store.clients.first { $0.id == selectedClientID }
    }

    private var selectedSavedClients: [Client] {
        store.clients.filter { selectedClientIDs.contains($0.id) }
    }

    private var selectedClientSummaries: [Client.ID: ClientInvoiceSummary] {
        Dictionary(uniqueKeysWithValues: selectedSavedClients.map { client in
            (client.id, invoiceSummary(for: client))
        })
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredClients) { client in
                            VStack(spacing: 0) {
                                Button {
                                    selectClient(client)
                                } label: {
                                    ClientRow(
                                        client: client,
                                        invoiceSummary: invoiceSummary(for: client),
                                        isSelected: selectedClientIDs.contains(client.id),
                                        onShowInvoiceHistory: {
                                            invoiceHistoryClient = client
                                        }
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    let contextClients = contextClients(for: client)

                                    if contextClients.count == 1 {
                                        Button {
                                            createInvoice(for: client)
                                        } label: {
                                            Label("New Invoice", systemImage: "doc.badge.plus")
                                        }
                                    }

                                    Button(role: .destructive) {
                                        requestDelete(contextClients)
                                    } label: {
                                        Label(contextClients.count > 1 ? "Delete Selected Clients" : "Delete Client", systemImage: "trash")
                                    }
                                }

                                if client.id != filteredClients.last?.id {
                                    Divider()
                                        .padding(.leading, 10)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(width: 300)
                .onMacKeyDown(perform: handleClientListKeyDown)
                .onDeleteCommand {
                    requestDelete(selectedSavedClients)
                }

                Divider()

                Group {
                    if selectedSavedClients.count > 1 {
                        SelectedClientsPanel(
                            clients: selectedSavedClients,
                            summaries: selectedClientSummaries,
                            onDeleteClients: {
                                requestDelete(selectedSavedClients)
                            },
                            onClearSelection: clearSelection
                        )
                    } else if let selectedClient {
                        ClientContactDetailView(
                            client: selectedClient,
                            summary: invoiceSummary(for: selectedClient),
                            onEdit: {
                                editingClient = selectedClient
                            },
                            onCreateInvoice: {
                                createInvoice(for: selectedClient)
                            },
                            onShowInvoiceHistory: {
                                invoiceHistoryClient = selectedClient
                            }
                        )
                    } else {
                        ClientEmptySelectionView(
                            title: filteredClients.isEmpty && !store.clients.isEmpty ? "No Matching Clients" : "No Client Selected",
                            message: filteredClients.isEmpty && !store.clients.isEmpty ? "No saved clients match the current search." : "Select a client or create a new one.",
                            hint: filteredClients.isEmpty && !store.clients.isEmpty ? "Clear the search to return to your saved clients." : "Use the toolbar + button to add a saved client.",
                            actionTitle: filteredClients.isEmpty && !store.clients.isEmpty ? "Clear Search" : nil,
                            actionSystemImage: "xmark.circle",
                            action: filteredClients.isEmpty && !store.clients.isEmpty ? { searchText = "" } : nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .navigationTitle("Clients")
        .searchable(text: $searchText, prompt: "Search clients")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !filteredClients.isEmpty {
                    Button(action: selectAllVisibleClients) {
                        Label("Select All", systemImage: "checklist")
                    }
                    .keyboardShortcut("a", modifiers: .command)
                    .help("Select All Clients")
                }

                if selectedClient != nil && selectedSavedClients.count <= 1 {
                    Button {
                        if let selectedClient {
                            createInvoice(for: selectedClient)
                        }
                    } label: {
                        Label("New Invoice", systemImage: "doc.badge.plus")
                    }
                }

                if !selectedSavedClients.isEmpty {
                    Button(role: .destructive) {
                        requestDelete(selectedSavedClients)
                    } label: {
                        Label(selectedSavedClients.count > 1 ? "Delete Clients" : "Delete Client", systemImage: "trash")
                    }
                }

                Button(action: addClient) {
                    Label("New Client", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $newClientDraft) { client in
            NavigationStack {
                ClientEditorView(client: client, title: "New Client") { savedClient in
                    store.save(savedClient)
                    searchText = ""
                    selectedClientIDs = [savedClient.id]
                    selectionAnchorClientID = savedClient.id
                    selectionExtentClientID = savedClient.id
                    newClientDraft = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { newClientDraft = nil }
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 720)
        }
        .sheet(item: $editingClient) { client in
            NavigationStack {
                ClientEditorView(client: client, title: "Edit Client") { updatedClient in
                    store.save(updatedClient)
                    selectedClientIDs = [updatedClient.id]
                    selectionAnchorClientID = updatedClient.id
                    selectionExtentClientID = updatedClient.id
                    editingClient = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingClient = nil }
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 720)
        }
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
        .sheet(item: $invoiceHistoryClient) { client in
            NavigationStack {
                ClientInvoiceHistoryView(
                    client: client,
                    summary: invoiceSummary(for: client),
                    onCreateInvoice: {
                        invoiceHistoryClient = nil
                        createInvoice(for: client)
                    },
                    onSaveInvoice: saveInvoiceFromHistory,
                    onDuplicateInvoice: duplicateInvoiceFromHistory,
                    onDiscardDraftInvoice: discardDraftInvoiceFromHistory
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { invoiceHistoryClient = nil }
                    }
                }
            }
            .frame(minWidth: 560, minHeight: 520)
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(clientsPendingDeletion.count > 1 ? "Delete Clients" : "Delete Client", role: .destructive, action: confirmDelete)
            Button("Cancel", role: .cancel) { clientsPendingDeletion = [] }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .onAppear {
            store.load()
            invoiceStore.load()
            profileStore.load()
            if selectedClientIDs.isEmpty, let firstClientID = store.clients.first?.id {
                selectedClientIDs = [firstClientID]
                selectionAnchorClientID = firstClientID
                selectionExtentClientID = firstClientID
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                profileStore.load()
            }
        }
        .onChange(of: searchText) { _, _ in
            trimMultiSelectionToVisibleClients()
        }
    }

    private func addClient() {
        newClientDraft = Client.empty
    }

    private func contextClients(for client: Client) -> [Client] {
        if selectedClientIDs.contains(client.id), selectedSavedClients.count > 1 {
            return selectedSavedClients
        }
        return [client]
    }

    private func selectClient(_ client: Client) {
        isClientListFocused = true
        let modifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags.contains(.shift) {
            extendClientSelection(to: client.id)
        } else if modifierFlags.contains(.command) {
            toggleClientSelection(client.id)
        } else {
            selectedClientIDs = [client.id]
            selectionAnchorClientID = client.id
            selectionExtentClientID = client.id
        }
    }

    private func toggleClientSelection(_ clientID: Client.ID) {
        if selectedClientIDs.contains(clientID) {
            selectedClientIDs.remove(clientID)
        } else {
            selectedClientIDs.insert(clientID)
        }
        selectionAnchorClientID = clientID
        selectionExtentClientID = clientID
    }

    private func extendClientSelection(to clientID: Client.ID) {
        guard let targetIndex = filteredClients.firstIndex(where: { $0.id == clientID }) else { return }
        let anchorID = selectionAnchorClientID ?? selectedClientIDs.first { selectedID in
            filteredClients.contains { $0.id == selectedID }
        } ?? clientID
        guard let anchorIndex = filteredClients.firstIndex(where: { $0.id == anchorID }) else {
            selectedClientIDs = [clientID]
            selectionAnchorClientID = clientID
            selectionExtentClientID = clientID
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedClientIDs = Set(range.map { filteredClients[$0].id })
        selectionAnchorClientID = anchorID
        selectionExtentClientID = clientID
    }

    private func selectAllVisibleClients() {
        selectedClientIDs = Set(filteredClients.map(\.id))
        selectionAnchorClientID = filteredClients.first?.id
        selectionExtentClientID = filteredClients.last?.id
    }

    private func createInvoice(for client: Client) {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        invoiceDraft = invoiceStore.newInvoiceDraft(for: client)
    }


    private func clearSelection() {
        selectedClientIDs = []
        selectionAnchorClientID = nil
        selectionExtentClientID = nil
    }

    private func saveInvoiceFromHistory(_ invoice: Invoice) {
        invoiceStore.save(invoice)
    }

    private func duplicateInvoiceFromHistory(_ invoice: Invoice) -> Invoice {
        let duplicate = invoiceStore.duplicateDraft(from: invoice)
        invoiceStore.save(duplicate)
        return duplicate
    }

    private func discardDraftInvoiceFromHistory(_ invoice: Invoice) {
        invoiceStore.delete(invoice)
    }

    private func invoiceSummary(for client: Client) -> ClientInvoiceSummary {
        ClientInvoiceSummary(client: client, invoices: invoiceStore.invoices)
    }

    private func handleClientListKeyDown(_ event: NSEvent) -> Bool {
        guard isClientListFocused, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }

        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 126 where modifierFlags.contains(.shift):
            selectAdjacentClient(offset: -1, extendingSelection: true)
            return true
        case 125 where modifierFlags.contains(.shift):
            selectAdjacentClient(offset: 1, extendingSelection: true)
            return true
        case 126:
            selectAdjacentClient(offset: -1)
            return true
        case 125:
            selectAdjacentClient(offset: 1)
            return true
        case 51:
            requestDelete(selectedSavedClients)
            return true
        case 0 where modifierFlags.contains(.command):
            selectAllVisibleClients()
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            selectAdjacentClient(offset: -1)
        case .down:
            selectAdjacentClient(offset: 1)
        default:
            break
        }
    }

    private func selectAdjacentClient(offset: Int, extendingSelection: Bool = false) {
        guard !filteredClients.isEmpty else {
            selectedClientIDs = []
            selectionAnchorClientID = nil
            selectionExtentClientID = nil
            return
        }

        let currentID = selectionExtentClientID ?? selectionAnchorClientID ?? selectedSavedClients.first?.id

        guard let currentID,
              let currentIndex = filteredClients.firstIndex(where: { $0.id == currentID }) else {
            let firstID = filteredClients.first!.id
            selectedClientIDs = [firstID]
            selectionAnchorClientID = firstID
            selectionExtentClientID = firstID
            return
        }

        let nextIndex = min(max(currentIndex + offset, filteredClients.startIndex), filteredClients.index(before: filteredClients.endIndex))
        let nextID = filteredClients[nextIndex].id
        if extendingSelection || NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
            if selectionAnchorClientID == nil {
                selectionAnchorClientID = currentID
            }
            extendClientSelection(to: nextID)
        } else {
            selectedClientIDs = [nextID]
            selectionAnchorClientID = nextID
            selectionExtentClientID = nextID
        }
    }

    private func trimMultiSelectionToVisibleClients() {
        guard selectedClientIDs.count > 1 else { return }

        let visibleIDs = Set(filteredClients.map(\.id))
        selectedClientIDs = selectedClientIDs.intersection(visibleIDs)
        if let selectionAnchorClientID, !visibleIDs.contains(selectionAnchorClientID) {
            self.selectionAnchorClientID = selectedClientIDs.first
        }
        if let selectionExtentClientID, !visibleIDs.contains(selectionExtentClientID) {
            self.selectionExtentClientID = selectedClientIDs.first
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !clientsPendingDeletion.isEmpty },
            set: { isPresented in
                if !isPresented {
                    clientsPendingDeletion = []
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        if clientsPendingDeletion.count == 1, let client = clientsPendingDeletion.first {
            return "Delete \(client.displayName)?"
        }
        return "Delete \(clientsPendingDeletion.count) Clients?"
    }

    private var deleteConfirmationMessage: String {
        let invoiceCount = clientsPendingDeletion.reduce(0) { $0 + invoiceSummary(for: $1).invoiceCount }
        if invoiceCount > 0 {
            return "This removes the selected saved clients only. Existing invoices stay intact with their current client details."
        }
        return "The selected clients have no invoices and will be removed from your saved clients."
    }

    private func requestDelete(_ client: Client) {
        requestDelete([client])
    }

    private func requestDelete(_ clients: [Client]) {
        guard !clients.isEmpty else { return }
        clientsPendingDeletion = clients
    }

    private func confirmDelete() {
        let deletedIDs = Set(clientsPendingDeletion.map(\.id))
        for client in clientsPendingDeletion {
            store.delete(client)
        }
        clientsPendingDeletion = []
        selectedClientIDs.subtract(deletedIDs)
        if selectedClientIDs.isEmpty, let firstClientID = filteredClients.first?.id ?? store.clients.first?.id {
            selectedClientIDs = [firstClientID]
            selectionAnchorClientID = firstClientID
            selectionExtentClientID = firstClientID
        }
    }

    private func delete(at offsets: IndexSet) {
        let clients = offsets.compactMap { index in
            filteredClients.indices.contains(index) ? filteredClients[index] : nil
        }
        requestDelete(clients)
    }
}

private struct MacClientsHeader: View {
    @Binding var searchText: String
    let selectedClients: [Client]
    let selectedClient: Client?
    let onCreateInvoice: () -> Void
    let onDeleteClients: () -> Void
    let onAddClient: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Clients")
                .font(.title3.weight(.semibold))

            Spacer()

            if selectedClient != nil && selectedClients.count <= 1 {
                Button(action: onCreateInvoice) {
                    Label("New Invoice", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            if !selectedClients.isEmpty {
                Button(role: .destructive, action: onDeleteClients) {
                    Label(selectedClients.count > 1 ? "Delete Clients" : "Delete Client", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help(selectedClients.count > 1 ? "Delete Clients" : "Delete Client")
            }

            Button(action: onAddClient) {
                Label("New Client", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("New Client")

            TextField("Search clients", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct ClientContactDetailView: View {
    let client: Client
    let summary: ClientInvoiceSummary
    let onEdit: () -> Void
    let onCreateInvoice: () -> Void
    let onShowInvoiceHistory: () -> Void

    private var initials: String {
        let words = client.displayName.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? "?" : value
    }

    private var address: String {
        [client.street, client.apartment, client.city, client.postalCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var hasContactActions: Bool {
        client.primaryEmailURL != nil || client.phoneURL != nil || client.mobileMessageURL != nil || client.websiteURL != nil
    }

    private var source: MarketplaceSource? {
        client.marketplaceSource ?? summary.marketplaceSource
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                contactActions

                HStack(spacing: 12) {
                    Button(action: onCreateInvoice) {
                        Label("Create Invoice", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Invoices")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ClientProfileCard {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: summary.iconName)
                                .foregroundStyle(summary.tint)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(summary.hasInvoices ? summary.caption : "No invoices yet")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(summary.hasInvoices ? summary.tint : .secondary)

                                if let latestInvoiceCaption = summary.latestInvoiceCaption {
                                    Text(latestInvoiceCaption)
                                        .font(.callout)
                                        .foregroundStyle(summary.latestInvoiceTint)
                                        .lineLimit(1)
                                } else {
                                    Text("Create the first invoice for this client.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if summary.hasInvoices {
                                Button("View History", action: onShowInvoiceHistory)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                detailSections
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(initials)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.blue.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(client.displayName)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)

                    if let source {
                        ClientSourceBadge(source: source)
                    }

                    if client.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Needs details")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                }

                let subtitle = client.subtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var contactActions: some View {
        if hasContactActions {
            HStack(spacing: 10) {
                ContactActionLink(title: "Email", systemImage: "envelope", destination: client.primaryEmailURL)
                ContactActionLink(title: "Call", systemImage: "phone", destination: client.phoneURL)
                ContactActionLink(title: "Message", systemImage: "message", destination: client.mobileMessageURL)
                ContactActionLink(title: "Website", systemImage: "safari", destination: client.websiteURL)
            }
        } else {
            ClientProfileCard {
                Label("No email, phone, mobile number, or website saved yet.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            ClientProfileSection(title: "Contact") {
                ClientProfileRow(title: "Contact person", value: client.contactPerson)
                ClientProfileRow(title: "Email", value: client.email)
                ClientProfileRow(title: "Additional email", value: client.additionalEmail)
                ClientProfileRow(title: "Phone", value: client.phone)
                ClientProfileRow(title: "Mobile", value: client.mobile)
                ClientProfileRow(title: "Website", value: client.website)
            }

            ClientProfileSection(title: "Billing") {
                ClientProfileRow(title: "Country", value: client.country.rawValue)
                ClientProfileRow(title: "Address", value: address)
            }

            ClientProfileSection(title: "Identification") {
                ClientProfileRow(title: client.country.fieldLabels.companyId, value: client.registrationNumber)
                ClientProfileRow(title: client.country.fieldLabels.taxId, value: client.taxId)
                ClientProfileRow(title: client.country.fieldLabels.vatId, value: client.vatId)
            }
        }
    }
}

private struct ContactActionLink: View {
    let title: String
    let systemImage: String
    let destination: URL?

    var body: some View {
        if let destination {
            Link(destination: destination) {
                Label(title, systemImage: systemImage)
                    .frame(minWidth: 84)
            }
            .buttonStyle(.bordered)
        } else {
            Label(title, systemImage: systemImage)
                .frame(minWidth: 84)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct ClientProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            ClientProfileCard {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct ClientProfileCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct ClientProfileRow: View {
    let title: String
    let value: String

    private var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not provided" : trimmed
    }

    private var isMissing: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)

            Text(displayValue)
                .font(.callout)
                .foregroundStyle(isMissing ? .tertiary : .secondary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.45)
        }
    }
}

private struct ClientEmptySelectionView: View {
    let title: String
    let message: String
    let hint: String
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            Text(hint)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)

            if let actionTitle, let action {
                Button(action: action) {
                    if let actionSystemImage {
                        Label(actionTitle, systemImage: actionSystemImage)
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(28)
    }
}

private struct SelectedClientsPanel: View {
    let clients: [Client]
    let summaries: [Client.ID: ClientInvoiceSummary]
    let onDeleteClients: () -> Void
    let onClearSelection: () -> Void

    private var totalInvoices: Int {
        clients.reduce(0) { total, client in
            total + (summaries[client.id]?.invoiceCount ?? 0)
        }
    }

    private var openInvoices: Int {
        clients.reduce(0) { total, client in
            total + (summaries[client.id]?.openCount ?? 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected clients")
                            .font(.title2.weight(.semibold))
                        Text("\(clients.count) selected • \(totalInvoices) invoices • \(openInvoices) open")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear Selection", action: onClearSelection)
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button(role: .destructive, action: onDeleteClients) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: 10) {
                    ForEach(clients) { client in
                        SelectedClientSummaryRow(
                            client: client,
                            summary: summaries[client.id] ?? ClientInvoiceSummary(client: client, invoices: [])
                        )
                    }
                }

                Text("Remove the selected saved clients when they are no longer needed. Existing invoices remain unchanged when clients are deleted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct SelectedClientSummaryRow: View {
    let client: Client
    let summary: ClientInvoiceSummary

    private var source: MarketplaceSource? {
        client.marketplaceSource ?? summary.marketplaceSource
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: summary.iconName)
                .foregroundStyle(summary.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(client.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if let source {
                        ClientSourceBadge(source: source)
                    }
                }

                let subtitle = client.subtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 4) {
                Text(summary.caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summary.tint)
                    .lineLimit(1)

                if let latestInvoiceCaption = summary.latestInvoiceCaption {
                    Text(latestInvoiceCaption)
                        .font(.caption)
                        .foregroundStyle(summary.latestInvoiceTint)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary.opacity(0.6), lineWidth: 1)
        }
    }
}
#endif

private extension Invoice {
    var resolvedCurrencyCode: String {
        let code = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? "EUR" : code
    }
}

private struct ClientInvoiceSummary {
    let invoiceCount: Int
    let openCount: Int
    let overdueCount: Int
    let latestInvoice: Invoice?
    let allInvoices: [Invoice]

    init(client: Client, invoices: [Invoice]) {
        let clientName = client.companyName.normalizedClientName
        let matchingInvoices = invoices.filter { invoice in
            if invoice.clientID == client.id {
                return true
            }
            return !clientName.isEmpty && invoice.clientName.normalizedClientName == clientName
        }
        let sortedInvoices = matchingInvoices.sorted { lhs, rhs in
            if lhs.issueDate == rhs.issueDate {
                return lhs.number.localizedStandardCompare(rhs.number) == .orderedDescending
            }
            return lhs.issueDate > rhs.issueDate
        }

        invoiceCount = matchingInvoices.count
        latestInvoice = sortedInvoices.first
        allInvoices = sortedInvoices
        openCount = matchingInvoices.filter { invoice in
            let status = invoice.displayStatus
            return status == .sent || status == .overdue
        }.count
        overdueCount = matchingInvoices.filter { $0.displayStatus == .overdue }.count
    }

    var hasInvoices: Bool {
        invoiceCount > 0
    }

    var historyButtonTitle: String {
        invoiceCount > 3 ? "View all \(invoiceCount) invoices" : "View invoices"
    }

    var caption: String {
        if overdueCount > 0 {
            return "\(overdueCount) \(plural("overdue", count: overdueCount)) • \(openCount) open • \(invoiceCount) \(plural("invoice", count: invoiceCount))"
        }
        if openCount > 0 {
            return "\(openCount) open • \(invoiceCount) \(plural("invoice", count: invoiceCount))"
        }
        return "\(invoiceCount) \(plural("invoice", count: invoiceCount))"
    }

    var latestInvoiceCaption: String? {
        guard let latestInvoice else { return nil }
        return "Latest \(latestInvoice.displayTitle) • \(latestInvoice.displayStatus.title) • \(latestInvoice.total.formatted(.currency(code: latestInvoice.resolvedCurrencyCode)))"
    }

    var latestInvoiceTint: Color {
        guard let latestInvoice else { return .secondary }
        switch latestInvoice.displayStatus {
        case .draft, .cancelled:
            return .secondary
        case .sent:
            return .blue
        case .paid:
            return .green
        case .overdue:
            return .red
        }
    }

    var marketplaceSource: MarketplaceSource? {
        allInvoices.compactMap { $0.marketplaceReference?.source }.first
    }

    var iconName: String {
        overdueCount > 0 ? "exclamationmark.triangle.fill" : "doc.text"
    }

    var tint: Color {
        if overdueCount > 0 {
            return .red
        }
        if openCount > 0 {
            return .orange
        }
        return .secondary
    }

    private func plural(_ word: String, count: Int) -> String {
        count == 1 ? word : "\(word)s"
    }
}

private struct ClientSourceBadge: View {
    let source: MarketplaceSource

    var body: some View {
        Label(source.title, systemImage: "shippingbox")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.12), in: Capsule())
    }
}

private struct ClientRow: View {
    let client: Client
    let invoiceSummary: ClientInvoiceSummary
    var isSelected = false
    let onShowInvoiceHistory: () -> Void

    private var isMissingCompanyName: Bool {
        client.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var subtitleText: String {
        if !client.subtitle.isEmpty {
            return client.subtitle
        }
        return isMissingCompanyName ? "Missing company name" : "No contact details"
    }

    private var subtitleTint: Color {
        isMissingCompanyName ? .orange : .secondary
    }

    private var source: MarketplaceSource? {
        client.marketplaceSource ?? invoiceSummary.marketplaceSource
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(client.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                if let source {
                    ClientSourceBadge(source: source)
                }

                if isMissingCompanyName {
                    Text("Needs details")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
            }

            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(subtitleTint)
                .lineLimit(1)

            if invoiceSummary.hasInvoices {
                Label(invoiceSummary.caption, systemImage: invoiceSummary.iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(invoiceSummary.tint)
                    .lineLimit(1)

                if let latestInvoiceCaption = invoiceSummary.latestInvoiceCaption {
                    Label(latestInvoiceCaption, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(invoiceSummary.latestInvoiceTint)
                        .lineLimit(1)
                }

                Label(invoiceSummary.historyButtonTitle, systemImage: "doc.text.magnifyingglass")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .onTapGesture(perform: onShowInvoiceHistory)
            } else {
                Label("No invoices yet", systemImage: "doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ClientInvoiceHistoryView: View {
    let client: Client
    let summary: ClientInvoiceSummary
    let onCreateInvoice: () -> Void
    let onSaveInvoice: (Invoice) -> Void
    let onDuplicateInvoice: (Invoice) -> Invoice
    let onDiscardDraftInvoice: (Invoice) -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.displayName)
                        .font(.title3.weight(.semibold))
                    Text(summary.caption)
                        .font(.subheadline)
                        .foregroundStyle(summary.tint)
                }
                .padding(.vertical, 6)
            }

            Section("Invoices") {
                ForEach(summary.allInvoices) { invoice in
                    NavigationLink {
                        MobileInvoiceDetailView(
                            invoice: invoice,
                            onSave: onSaveInvoice,
                            onDuplicate: onDuplicateInvoice,
                            onDiscardDraft: onDiscardDraftInvoice
                        )
                    } label: {
                        ClientInvoiceHistoryRow(invoice: invoice)
                    }
                }
            }
        }
        .navigationTitle("Invoice History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreateInvoice) {
                    Label("New Invoice", systemImage: "doc.badge.plus")
                }
            }
        }
    }
}

private struct ClientInvoiceHistoryRow: View {
    let invoice: Invoice

    private var tint: Color {
        switch invoice.displayStatus {
        case .draft, .cancelled:
            return .secondary
        case .sent:
            return .blue
        case .paid:
            return .green
        case .overdue:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.displayTitle)
                    .font(.body.weight(.semibold))
                Text(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.total.formatted(.currency(code: invoice.resolvedCurrencyCode)))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(invoice.displayStatus.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension Client {
    var primaryEmailURL: URL? {
        let emailAddress = [email, additionalEmail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let emailAddress,
              let encodedEmail = emailAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "mailto:\(encodedEmail)")
    }

    var phoneURL: URL? {
        let number = sanitizedPhoneNumber(phone.isEmpty ? mobile : phone)
        guard !number.isEmpty else { return nil }
        return URL(string: "tel:\(number)")
    }

    var mobileMessageURL: URL? {
        let number = sanitizedPhoneNumber(mobile.isEmpty ? phone : mobile)
        guard !number.isEmpty else { return nil }
        return URL(string: "sms:\(number)")
    }

    var websiteURL: URL? {
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWebsite.isEmpty else { return nil }
        if let url = URL(string: trimmedWebsite), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmedWebsite)")
    }

    private func sanitizedPhoneNumber(_ value: String) -> String {
        value.filter { character in
            character.isNumber || character == "+"
        }
    }

    func matchesSearch(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return searchableFields.contains { field in
            field.localizedCaseInsensitiveContains(query)
        }
    }

    var searchableFields: [String] {
        [
            displayName,
            companyName,
            email,
            additionalEmail,
            street,
            apartment,
            city,
            postalCode,
            registrationNumber,
            taxId,
            vatId,
            contactPerson,
            phone,
            mobile,
            fax,
            website,
            country.rawValue,
            countryCode,
            shippingStreet,
            shippingApartment,
            shippingCity,
            shippingPostalCode
        ]
    }
}
