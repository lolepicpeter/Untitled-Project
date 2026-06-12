import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct InvoiceFlowBackup: Codable {
    private enum CodingKeys: String, CodingKey {
        case exportedAt
        case invoices
        case clients
        case products
        case sellerProfiles
        case selectedSellerProfileID
        case invoiceDefaults
        case invoiceNumbering
        case documentTemplate
        case clientCommunication
        case allegroConnection
    }

    static var empty: InvoiceFlowBackup {
        InvoiceFlowBackup(
            exportedAt: Date(),
            invoices: [],
            clients: [],
            products: [],
            sellerProfiles: [],
            selectedSellerProfileID: nil,
            invoiceDefaults: InvoiceDefaults.load(),
            invoiceNumbering: InvoiceNumberingSettings.load(),
            documentTemplate: DocumentTemplateSettings.load(),
            clientCommunication: ClientCommunicationSettings.load(),
            allegroConnection: AllegroConnectionSettings.load()
        )
    }

    var exportedAt: Date
    var invoices: [Invoice]
    var clients: [Client]
    var products: [ProductItem]
    var sellerProfiles: [MyCompanySellerProfile]
    var selectedSellerProfileID: UUID?
    var invoiceDefaults: InvoiceDefaults
    var invoiceNumbering: InvoiceNumberingSettings
    var documentTemplate: DocumentTemplateSettings
    var clientCommunication: ClientCommunicationSettings
    var allegroConnection: AllegroConnectionSettings

    init(
        exportedAt: Date,
        invoices: [Invoice],
        clients: [Client],
        products: [ProductItem],
        sellerProfiles: [MyCompanySellerProfile],
        selectedSellerProfileID: UUID?,
        invoiceDefaults: InvoiceDefaults,
        invoiceNumbering: InvoiceNumberingSettings,
        documentTemplate: DocumentTemplateSettings,
        clientCommunication: ClientCommunicationSettings,
        allegroConnection: AllegroConnectionSettings
    ) {
        self.exportedAt = exportedAt
        self.invoices = invoices
        self.clients = clients
        self.products = products
        self.sellerProfiles = sellerProfiles
        self.selectedSellerProfileID = selectedSellerProfileID
        self.invoiceDefaults = invoiceDefaults
        self.invoiceNumbering = invoiceNumbering
        self.documentTemplate = documentTemplate
        self.clientCommunication = clientCommunication
        self.allegroConnection = allegroConnection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        invoices = try container.decode([Invoice].self, forKey: .invoices)
        clients = try container.decode([Client].self, forKey: .clients)
        products = try container.decode([ProductItem].self, forKey: .products)
        sellerProfiles = try container.decode([MyCompanySellerProfile].self, forKey: .sellerProfiles)
        selectedSellerProfileID = try container.decodeIfPresent(UUID.self, forKey: .selectedSellerProfileID)
        invoiceDefaults = try container.decode(InvoiceDefaults.self, forKey: .invoiceDefaults)
        invoiceNumbering = try container.decode(InvoiceNumberingSettings.self, forKey: .invoiceNumbering)
        documentTemplate = try container.decode(DocumentTemplateSettings.self, forKey: .documentTemplate)
        clientCommunication = try container.decode(ClientCommunicationSettings.self, forKey: .clientCommunication)
        allegroConnection = try container.decodeIfPresent(AllegroConnectionSettings.self, forKey: .allegroConnection) ?? .load()
    }
}

struct InvoiceFlowBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
enum AppBackupService {
    static func makeBackup() -> InvoiceFlowBackup {
        let invoiceStore = InvoiceStore()
        let clientStore = ClientStore()
        let productStore = ProductStore()
        let profileStore = MyCompanyProfileStore()

        return InvoiceFlowBackup(
            exportedAt: Date(),
            invoices: invoiceStore.invoices,
            clients: clientStore.clients,
            products: productStore.products,
            sellerProfiles: profileStore.profiles,
            selectedSellerProfileID: profileStore.selectedProfileID,
            invoiceDefaults: InvoiceDefaults.load(),
            invoiceNumbering: InvoiceNumberingSettings.load(),
            documentTemplate: DocumentTemplateSettings.load(),
            clientCommunication: ClientCommunicationSettings.load(),
            allegroConnection: AllegroConnectionSettings.load()
        )
    }

    static func makeBackupData() throws -> Data {
        try JSONEncoder.invoiceFlow.encode(makeBackup())
    }

    static func decodeBackup(from data: Data) throws -> InvoiceFlowBackup {
        try JSONDecoder.invoiceFlow.decode(InvoiceFlowBackup.self, from: data)
    }

    static func restore(_ backup: InvoiceFlowBackup) {
        InvoiceStore().replaceAll(backup.invoices)
        ClientStore().replaceAll(backup.clients)
        ProductStore().replaceAll(backup.products)
        MyCompanyProfileStore().replaceAll(
            profiles: backup.sellerProfiles,
            selectedProfileID: backup.selectedSellerProfileID
        )
        backup.invoiceDefaults.save()
        backup.invoiceNumbering.save()
        backup.documentTemplate.save()
        backup.clientCommunication.save()
        backup.allegroConnection.save()
    }
}

private extension JSONEncoder {
    static var invoiceFlow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var invoiceFlow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
