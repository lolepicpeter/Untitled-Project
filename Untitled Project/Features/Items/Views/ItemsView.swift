import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ItemsView: View {
    var body: some View {
        #if os(macOS)
        MacProductsView()
        #else
        MobileProductsView()
        #endif
    }
}

#if os(macOS)
private struct MacProductsView: View {
    @State private var store = ProductStore()
    @State private var invoiceStore = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var searchText = ""
    @State private var selectedProductIDs: Set<ProductItem.ID> = []
    @State private var selectionAnchorProductID: ProductItem.ID?
    @State private var selectionExtentProductID: ProductItem.ID?
    @State private var editingProduct: ProductItem?
    @State private var invoiceDraft: Invoice?
    @State private var isShowingSellerSetup = false
    @State private var productsPendingDeletion: [ProductItem] = []
    @State private var isProductListFocused = false

    private var filteredProducts: [ProductItem] {
        store.products.filter { $0.matchesSearch(searchText) }
    }

    private var selectedProduct: ProductItem? {
        guard selectedProductIDs.count == 1,
              let selectedProductID = selectedProductIDs.first else { return nil }
        return store.products.first { $0.id == selectedProductID }
    }

    private var selectedProducts: [ProductItem] {
        store.products.filter { selectedProductIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                ProductListView(
                    products: filteredProducts,
                    selectedProductIDs: $selectedProductIDs,
                    onSelect: selectProduct,
                    onCreateInvoice: createInvoice,
                    onDelete: { requestDelete([$0]) }
                )
                .frame(width: 360)
                .onMacKeyDown(perform: handleProductListKeyDown)

                Divider()

                Group {
                    if selectedProducts.count > 1 {
                        SelectedProductsPanel(
                            products: selectedProducts,
                            onDeleteProducts: {
                                requestDelete(selectedProducts)
                            },
                            onClearSelection: {
                                selectedProductIDs = []
                                selectionAnchorProductID = nil
                                selectionExtentProductID = nil
                            }
                        )
                    } else if let selectedProduct {
                        ProductDetailView(product: selectedProduct)
                    } else {
                        let hasSearchResults = filteredProducts.isEmpty && !store.products.isEmpty

                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                hasSearchResults ? "No Matching Products" : "No Product Selected",
                                systemImage: "shippingbox",
                                description: Text(hasSearchResults ? "No saved products match the current search." : "Select a product or create a new one.")
                            )

                            if hasSearchResults {
                                Button {
                                    searchText = ""
                                } label: {
                                    Label("Clear Search", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button(action: addProduct) {
                                    Label("New Product", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Products")
        .searchable(text: $searchText, prompt: "Search products")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !filteredProducts.isEmpty {
                    Button(action: selectAllVisibleProducts) {
                        Label("Select All", systemImage: "checklist")
                    }
                    .keyboardShortcut("a", modifiers: .command)
                    .help("Select All Products")
                }

                if let selectedProduct {
                    Button {
                        createInvoice(for: selectedProduct)
                    } label: {
                        Label("Create Invoice", systemImage: "doc.badge.plus")
                    }

                    Button {
                        editingProduct = selectedProduct
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                }

                if !selectedProducts.isEmpty {
                    Button(role: .destructive) {
                        requestDelete(selectedProducts)
                    } label: {
                        Label(selectedProducts.count > 1 ? "Delete Products" : "Delete Product", systemImage: "trash")
                    }
                }

                Button(action: addProduct) {
                    Label("New Product", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $editingProduct) { product in
            ProductEditorView(product: product, title: product.displayName == "Untitled product" ? "New Product" : "Edit Product") { updatedProduct in
                store.save(updatedProduct)
                selectedProductIDs = [updatedProduct.id]
                selectionAnchorProductID = updatedProduct.id
                selectionExtentProductID = updatedProduct.id
                editingProduct = nil
            }
            .frame(width: 560, height: 680)
        }
        .sheet(item: $invoiceDraft) { invoice in
            InvoiceEditorView(invoice: invoice, title: "New Invoice") { savedInvoice in
                invoiceStore.save(savedInvoice)
                invoiceDraft = nil
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
            deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(productsPendingDeletion.count > 1 ? "Delete Products" : "Delete Product", role: .destructive, action: confirmDelete)
            Button("Cancel", role: .cancel) { productsPendingDeletion = [] }
        } message: {
            Text("This removes the selected saved products only. Existing invoices keep their current item details.")
        }
        .onAppear {
            store.load()
            invoiceStore.load()
            profileStore.load()
            if selectedProductIDs.isEmpty, let firstProductID = store.products.first?.id {
                selectedProductIDs = [firstProductID]
                selectionAnchorProductID = firstProductID
                selectionExtentProductID = firstProductID
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: MyCompanyProfileStore.profilesDidChange) {
                profileStore.load()
            }
        }
        .onDeleteCommand {
            requestDelete(selectedProducts)
        }
        .onChange(of: searchText) { _, _ in
            trimMultiSelectionToVisibleProducts()
        }
    }

    private func addProduct() {
        editingProduct = .empty
    }

    private func createInvoice(for product: ProductItem) {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        invoiceDraft = invoiceStore.newInvoiceDraft(with: product)
    }

    private func selectProduct(_ product: ProductItem) {
        isProductListFocused = true
        let modifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags.contains(.shift) {
            extendProductSelection(to: product.id)
        } else if modifierFlags.contains(.command) {
            toggleProductSelection(product.id)
        } else {
            selectedProductIDs = [product.id]
            selectionAnchorProductID = product.id
            selectionExtentProductID = product.id
        }
    }

    private func handleProductListKeyDown(_ event: NSEvent) -> Bool {
        guard isProductListFocused, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }

        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 126 where modifierFlags.contains(.shift):
            selectAdjacentProduct(offset: -1, extendingSelection: true)
            return true
        case 125 where modifierFlags.contains(.shift):
            selectAdjacentProduct(offset: 1, extendingSelection: true)
            return true
        case 126:
            selectAdjacentProduct(offset: -1)
            return true
        case 125:
            selectAdjacentProduct(offset: 1)
            return true
        case 51:
            requestDelete(selectedProducts)
            return true
        case 0 where modifierFlags.contains(.command):
            selectAllVisibleProducts()
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            selectAdjacentProduct(offset: -1)
        case .down:
            selectAdjacentProduct(offset: 1)
        default:
            break
        }
    }

    private func selectAdjacentProduct(offset: Int, extendingSelection: Bool = false) {
        guard !filteredProducts.isEmpty else {
            selectedProductIDs = []
            selectionAnchorProductID = nil
            selectionExtentProductID = nil
            return
        }

        let currentID = selectionExtentProductID ?? selectionAnchorProductID ?? selectedProducts.first?.id

        guard let currentID,
              let currentIndex = filteredProducts.firstIndex(where: { $0.id == currentID }) else {
            let firstID = filteredProducts.first!.id
            selectedProductIDs = [firstID]
            selectionAnchorProductID = firstID
            selectionExtentProductID = firstID
            return
        }

        let nextIndex = min(max(currentIndex + offset, filteredProducts.startIndex), filteredProducts.index(before: filteredProducts.endIndex))
        let nextID = filteredProducts[nextIndex].id
        if extendingSelection || NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
            if selectionAnchorProductID == nil {
                selectionAnchorProductID = currentID
            }
            extendProductSelection(to: nextID)
        } else {
            selectedProductIDs = [nextID]
            selectionAnchorProductID = nextID
            selectionExtentProductID = nextID
        }
    }

    private func toggleProductSelection(_ productID: ProductItem.ID) {
        if selectedProductIDs.contains(productID) {
            selectedProductIDs.remove(productID)
        } else {
            selectedProductIDs.insert(productID)
        }
        selectionAnchorProductID = productID
        selectionExtentProductID = productID
    }

    private func extendProductSelection(to productID: ProductItem.ID) {
        guard let targetIndex = filteredProducts.firstIndex(where: { $0.id == productID }) else { return }
        let anchorID = selectionAnchorProductID ?? selectedProductIDs.first { selectedID in
            filteredProducts.contains { $0.id == selectedID }
        } ?? productID
        guard let anchorIndex = filteredProducts.firstIndex(where: { $0.id == anchorID }) else {
            selectedProductIDs = [productID]
            selectionAnchorProductID = productID
            selectionExtentProductID = productID
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedProductIDs = Set(range.map { filteredProducts[$0].id })
        selectionAnchorProductID = anchorID
        selectionExtentProductID = productID
    }

    private func selectAllVisibleProducts() {
        selectedProductIDs = Set(filteredProducts.map(\.id))
        selectionAnchorProductID = filteredProducts.first?.id
        selectionExtentProductID = filteredProducts.last?.id
    }

    private func trimMultiSelectionToVisibleProducts() {
        guard selectedProductIDs.count > 1 else { return }

        let visibleIDs = Set(filteredProducts.map(\.id))
        selectedProductIDs = selectedProductIDs.intersection(visibleIDs)
        if let selectionAnchorProductID, !visibleIDs.contains(selectionAnchorProductID) {
            self.selectionAnchorProductID = selectedProductIDs.first
        }
        if let selectionExtentProductID, !visibleIDs.contains(selectionExtentProductID) {
            self.selectionExtentProductID = selectedProductIDs.first
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !productsPendingDeletion.isEmpty },
            set: { isPresented in
                if !isPresented {
                    productsPendingDeletion = []
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        if productsPendingDeletion.count == 1, let product = productsPendingDeletion.first {
            return "Delete \(product.displayName)?"
        }
        return "Delete \(productsPendingDeletion.count) Products?"
    }

    private func requestDelete(_ products: [ProductItem]) {
        guard !products.isEmpty else { return }
        productsPendingDeletion = products
    }

    private func confirmDelete() {
        let deletedIDs = Set(productsPendingDeletion.map(\.id))
        for product in productsPendingDeletion {
            store.delete(product)
        }
        productsPendingDeletion = []
        selectedProductIDs.subtract(deletedIDs)
        if selectedProductIDs.isEmpty, let firstProductID = filteredProducts.first?.id ?? store.products.first?.id {
            selectedProductIDs = [firstProductID]
            selectionAnchorProductID = firstProductID
            selectionExtentProductID = firstProductID
        }
    }
}

private struct ProductListView: View {
    let products: [ProductItem]
    @Binding var selectedProductIDs: Set<ProductItem.ID>
    let onSelect: (ProductItem) -> Void
    let onCreateInvoice: (ProductItem) -> Void
    let onDelete: (ProductItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedProducts, id: \.letter) { group in
                    Text(group.letter)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(group.products) { product in
                        Button {
                            onSelect(product)
                        } label: {
                            ProductRow(product: product, isSelected: selectedProductIDs.contains(product.id))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedProductIDs.contains(product.id) ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    onCreateInvoice(product)
                                } label: {
                                    Label("Create Invoice", systemImage: "doc.badge.plus")
                                }

                                Button("Delete", role: .destructive) {
                                    onDelete(product)
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var groupedProducts: [(letter: String, products: [ProductItem])] {
        let groups = Dictionary(grouping: products) { product in
            product.displayName.first.map { String($0).uppercased() } ?? "#"
        }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
}

private struct SelectedProductsPanel: View {
    let products: [ProductItem]
    let onDeleteProducts: () -> Void
    let onClearSelection: () -> Void

    private var primaryCurrencyCode: String {
        products.first?.primaryPrice.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? products.first!.primaryPrice.currencyCode : "EUR"
    }

    private var totalNetPrice: Double {
        products.reduce(0) { $0 + $1.primaryPrice.netPrice }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("\(products.count) Products Selected")
                    .font(.title2.weight(.semibold))

                Text("Combined default net price \(totalNetPrice.formatted(.currency(code: primaryCurrencyCode)))")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDeleteProducts) {
                    Label("Delete Products", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button("Clear Selection", action: onClearSelection)
                    .buttonStyle(.bordered)
            }

            Text("Use Shift-click to select a range, Command-click to toggle individual products, Command-A to select visible products, or Delete to remove selected products.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ProductDetailView: View {
    let product: ProductItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 10) {
                    Text(product.displayName)
                        .font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        ProductBadge(text: product.kind.title, tint: product.kind == .good ? .cyan : .purple)
                        ProductBadge(text: product.category, tint: .blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(product.unit)
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Prices")
                        .font(.title3.weight(.semibold))
                    ForEach(product.prices) { price in
                        HStack(alignment: .firstTextBaseline) {
                            Text(price.customerCategory)
                                .font(.headline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(price.netPrice.formatted(.currency(code: price.currencyCode)))
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Text("VAT \(price.taxRate.formatted(.number.precision(.fractionLength(0...2))))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
#endif

private struct MobileProductsView: View {
    @State private var store = ProductStore()
    @State private var invoiceStore = InvoiceStore()
    @State private var profileStore = MyCompanyProfileStore()
    @State private var searchText = ""
    @State private var editingProduct: ProductItem?
    @State private var invoiceDraft: Invoice?
    @State private var isShowingSellerSetup = false
    @State private var productPendingDeletion: ProductItem?

    private var filteredProducts: [ProductItem] {
        store.products.filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredProducts) { product in
                    NavigationLink {
                        MobileProductDetailView(
                            product: product,
                            onCreateInvoice: {
                                createInvoice(for: product)
                            },
                            onEdit: {
                                editingProduct = product
                            }
                        )
                    } label: {
                        ProductRow(product: product)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            createInvoice(for: product)
                        } label: {
                            Label("Invoice", systemImage: "doc.badge.plus")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            createInvoice(for: product)
                        } label: {
                            Label("Create Invoice", systemImage: "doc.badge.plus")
                        }

                        Button(role: .destructive) {
                            requestDelete(product)
                        } label: {
                            Label("Delete Product", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if store.products.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Products",
                            systemImage: "shippingbox",
                            description: Text("Create saved products with units, pricing, VAT, and comments.")
                        )

                        Button(action: addProduct) {
                            Label("New Product", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredProducts.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Matching Products",
                            systemImage: "shippingbox",
                            description: Text("No saved products match the current search.")
                        )

                        Button {
                            searchText = ""
                        } label: {
                            Label("Clear Search", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Products")
            .searchable(text: $searchText, prompt: "Search products")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addProduct) {
                        Label("New Product", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editingProduct) { product in
                ProductEditorView(product: product, title: product.displayName == "Untitled product" ? "New Product" : "Edit Product") { updatedProduct in
                    store.save(updatedProduct)
                    editingProduct = nil
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
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Product", role: .destructive, action: confirmDelete)
                Button("Cancel", role: .cancel) { productPendingDeletion = nil }
            } message: {
                Text("This removes the saved product only. Existing invoices keep their current item details.")
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

    private func addProduct() {
        editingProduct = .empty
    }

    private func createInvoice(for product: ProductItem) {
        profileStore.load()

        guard profileStore.hasSavedProfile else {
            isShowingSellerSetup = true
            return
        }

        invoiceDraft = invoiceStore.newInvoiceDraft(with: product)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { productPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    productPendingDeletion = nil
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        guard let productPendingDeletion else { return "Delete Product?" }
        return "Delete \(productPendingDeletion.displayName)?"
    }

    private func requestDelete(_ product: ProductItem) {
        productPendingDeletion = product
    }

    private func confirmDelete() {
        guard let product = productPendingDeletion else { return }
        store.delete(product)
        productPendingDeletion = nil
    }

    private func delete(at offsets: IndexSet) {
        guard let index = offsets.first, filteredProducts.indices.contains(index) else { return }
        requestDelete(filteredProducts[index])
    }
}

private struct MobileProductDetailView: View {
    let product: ProductItem
    let onCreateInvoice: () -> Void
    let onEdit: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(product.displayName)
                        .font(.title2.weight(.semibold))
                    HStack {
                        ProductBadge(text: product.kind.title, tint: product.kind == .good ? .cyan : .purple)
                        ProductBadge(text: product.category, tint: .blue)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Unit") {
                Text(product.unit)
            }

            Section("Prices") {
                ForEach(product.prices) { price in
                    HStack {
                        Text(price.customerCategory)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(price.netPrice.formatted(.currency(code: price.currencyCode)))
                                .fontWeight(.semibold)
                            Text("VAT \(price.taxRate.formatted(.number.precision(.fractionLength(0...2))))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Product")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onCreateInvoice) {
                    Label("Create Invoice", systemImage: "doc.badge.plus")
                }

                Button("Edit", action: onEdit)
            }
        }
    }
}

private struct ProductEditorView: View {
    let title: String
    let onSave: (ProductItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProductItem
    @State private var quantityText: String
    @State private var netPriceText: String
    @State private var grossPriceText: String
    @State private var taxRateText: String
    @State private var hasAttemptedSave = false

    private let units = ["pcs.", "hours", "days", "kg", "m", "set"]
    private let currencies = InvoiceDefaults.supportedCurrencyCodes
    private let categories = ["General", "Goods", "Services", "Shipping"]

    init(product: ProductItem, title: String, onSave: @escaping (ProductItem) -> Void) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: product)
        _quantityText = State(initialValue: product.primaryPrice.quantity.formatted(.number.precision(.fractionLength(0...2))))
        _netPriceText = State(initialValue: product.primaryPrice.netPrice.formatted(.number.precision(.fractionLength(0...2))))
        _grossPriceText = State(initialValue: product.primaryPrice.grossPrice.formatted(.number.precision(.fractionLength(0...2))))
        _taxRateText = State(initialValue: product.primaryPrice.taxRate.formatted(.number.precision(.fractionLength(0...2))))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title2.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    productInformationSection
                    pricesSection
                    commentsSection
                }
                .padding(22)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var productInformationSection: some View {
        ProductFormSection("Product Information") {
            ProductFormCard {
                ProductSegmentedRow(title: "Type") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ProductKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
                ProductEditableRow(
                    title: "Product Name",
                    text: $draft.name,
                    prompt: "Required",
                    isMissing: hasAttemptedSave && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                ProductEditableRow(title: "Description", text: $draft.description, prompt: "Optional")
                ProductMenuRow(title: "Unit", selection: $draft.unit, options: units)
                ProductMenuRow(title: "Category", selection: $draft.category, options: categories)
            }
        }
    }

    private var pricesSection: some View {
        ProductFormSection("Prices") {
            ProductFormCard {
                ProductEditableRow(title: "Price group", text: priceCustomerCategory, prompt: "General")
                ProductSegmentedRow(title: "Entered price") {
                    Picker("Entered price", selection: priceType) {
                        ForEach(ProductPriceType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 210)
                }
                ProductEditableRow(title: "Default quantity", text: $quantityText, prompt: "1")
                ProductMenuRow(title: "Currency", selection: priceCurrency, options: currencies)
                if currentPrice.priceType == .net {
                    ProductPriceEditableRow(
                        title: "Net price",
                        text: $netPriceText,
                        prompt: "0,00",
                        currencySymbol: currencySymbol(for: priceCurrency.wrappedValue)
                    )
                } else {
                    ProductPriceReadOnlyRow(
                        title: "Net price",
                        amount: effectiveNetPrice,
                        currencySymbol: currencySymbol(for: priceCurrency.wrappedValue)
                    )
                }
                ProductEditableRow(title: "VAT rate", text: $taxRateText, prompt: "20") {
                    Text("%")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                if currentPrice.priceType == .gross {
                    ProductPriceEditableRow(
                        title: "Gross price",
                        text: $grossPriceText,
                        prompt: "0,00",
                        currencySymbol: currencySymbol(for: priceCurrency.wrappedValue)
                    )
                } else {
                    ProductPriceReadOnlyRow(
                        title: "Gross price",
                        amount: effectiveGrossPrice,
                        currencySymbol: currencySymbol(for: priceCurrency.wrappedValue)
                    )
                }
            }
        }
    }

    private var commentsSection: some View {
        ProductFormSection("Internal Notes") {
            TextField("Optional notes for this saved product", text: $draft.comments, axis: .vertical)
                .lineLimit(4...6)
                .textFieldStyle(.plain)
                .padding(10)
                .frame(minHeight: 96, alignment: .topLeading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var priceCustomerCategory: Binding<String> {
        Binding(
            get: { currentPrice.customerCategory },
            set: { newValue in updatePrice { price in price.customerCategory = newValue } }
        )
    }

    private var priceType: Binding<ProductPriceType> {
        Binding(
            get: { currentPrice.priceType },
            set: { newValue in
                guard newValue != currentPrice.priceType else { return }
                switch newValue {
                case .net:
                    netPriceText = decimalText(effectiveNetPrice)
                case .gross:
                    grossPriceText = decimalText(effectiveGrossPrice)
                }
                updatePrice { price in price.priceType = newValue }
            }
        )
    }

    private var priceCurrency: Binding<String> {
        Binding(
            get: { currentPrice.currencyCode },
            set: { newValue in updatePrice { price in price.currencyCode = newValue } }
        )
    }

    private var currentPrice: ProductPrice {
        draft.prices.first ?? .empty
    }

    private var taxMultiplier: Double {
        1 + max(decimalValue(from: taxRateText), 0) / 100
    }

    private var calculatedGrossPrice: Double {
        max(decimalValue(from: netPriceText), 0) * taxMultiplier
    }

    private var calculatedNetPrice: Double {
        guard taxMultiplier > 0 else { return 0 }
        return max(decimalValue(from: grossPriceText), 0) / taxMultiplier
    }

    private var effectiveNetPrice: Double {
        switch currentPrice.priceType {
        case .net:
            max(decimalValue(from: netPriceText), 0)
        case .gross:
            calculatedNetPrice
        }
    }

    private var effectiveGrossPrice: Double {
        switch currentPrice.priceType {
        case .net:
            calculatedGrossPrice
        case .gross:
            max(decimalValue(from: grossPriceText), 0)
        }
    }

    private func updatePrice(_ transform: (inout ProductPrice) -> Void) {
        var price = currentPrice
        transform(&price)
        if draft.prices.isEmpty {
            draft.prices = [price]
        } else {
            draft.prices[0] = price
        }
    }

    private func save() {
        hasAttemptedSave = true
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        updatePrice {
            $0.quantity = max(decimalValue(from: quantityText), 0)
            $0.netPrice = effectiveNetPrice
            $0.taxRate = max(decimalValue(from: taxRateText), 0)
        }
        onSave(draft)
    }

    private func decimalValue(from text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func decimalText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}

private extension InvoiceStore {
    func newInvoiceDraft(with product: ProductItem) -> Invoice {
        var invoice = newInvoiceDraft()
        let price = product.primaryPrice
        invoice.currencyCode = price.currencyCode
        invoice.lineItems = [
            InvoiceLineItem(
                id: UUID(),
                title: product.displayName,
                description: product.description,
                quantity: max(price.quantity, 1),
                unitPrice: price.netPrice,
                vatRate: price.taxRate,
                discountPercent: 0
            )
        ]
        return invoice
    }
}

private struct ProductRow: View {
    let product: ProductItem
    var isSelected = false

    private var iconName: String {
        product.kind == .good ? "shippingbox" : "clock"
    }

    private var unitText: String {
        let trimmedUnit = product.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUnit.isEmpty ? "No unit" : trimmedUnit
    }

    private var primaryTextColor: Color {
        isSelected ? .white : .primary
    }

    private var secondaryTextColor: Color {
        isSelected ? .white.opacity(0.78) : .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .blue)
                        .frame(width: 14)

                    Text(unitText)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
                .frame(minHeight: 16, alignment: .leading)
            }

            Spacer(minLength: 12)

            Text(product.primaryPrice.netPrice.formatted(.currency(code: product.primaryPrice.currencyCode)))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProductBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct ProductFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
            content
        }
    }
}

private struct ProductFormCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ProductSegmentedRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        ProductRowContainer {
            Text(title)
                .font(.body)
            Spacer(minLength: 24)
            control
        }
    }
}

private struct ProductEditableRow<Trailing: View>: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let isMissing: Bool
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        text: Binding<String>,
        prompt: String,
        isMissing: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.isMissing = isMissing
        self.trailing = trailing()
    }

    var body: some View {
        ProductRowContainer(isMissing: isMissing) {
            Text(title)
                .font(.body.weight(isMissing ? .semibold : .regular))
                .foregroundStyle(isMissing ? .red : .primary)
            Spacer(minLength: 24)
            TextField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .font(.body)
            trailing
        }
    }
}

private struct ProductReadOnlyRow: View {
    let title: String
    let value: String

    var body: some View {
        ProductRowContainer {
            Text(title)
                .font(.body)
            Spacer(minLength: 24)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProductPriceEditableRow: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let currencySymbol: String

    var body: some View {
        ProductRowContainer {
            Text(title)
                .font(.body)
            Spacer(minLength: 24)
            HStack(spacing: 4) {
                TextField(prompt, text: $text)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .frame(width: 112, height: 28)
                    .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                Text(currencySymbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
}

private struct ProductPriceReadOnlyRow: View {
    let title: String
    let amount: Double
    let currencySymbol: String

    var body: some View {
        ProductRowContainer {
            Text(title)
                .font(.body)
            Spacer(minLength: 24)
            HStack(spacing: 4) {
                Text(amount.formatted(.number.precision(.fractionLength(2))))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 112, alignment: .trailing)
                Text(currencySymbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
}

private struct ProductMenuRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        ProductRowContainer {
            Text(title)
                .font(.body)
            Spacer(minLength: 24)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

private struct ProductRowContainer<Content: View>: View {
    var isMissing = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            content
        }
        .frame(minHeight: 38)
        .padding(.horizontal, isMissing ? 10 : 0)
        .background {
            if isMissing {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(isMissing ? 0 : 1)
        }
    }
}

private extension ProductItem {
    func matchesSearch(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return searchableFields.contains { field in
            field.localizedCaseInsensitiveContains(query)
        }
    }

    var searchableFields: [String] {
        var fields = [
            displayName,
            name,
            description,
            unit,
            category,
            kind.title,
            comments
        ]

        for price in prices {
            fields.append(contentsOf: [
                price.customerCategory,
                price.currencyCode,
                price.netPrice.formatted(.number.precision(.fractionLength(0...2))),
                price.grossPrice.formatted(.number.precision(.fractionLength(0...2))),
                price.taxRate.formatted(.number.precision(.fractionLength(0...2)))
            ])
        }

        return fields
    }
}
