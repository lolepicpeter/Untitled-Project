import SwiftUI

#if os(macOS)
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct InvoiceDocumentPreviewSheet: View {
    let invoice: Invoice
    let sellerName: String
    let sellerDetails: [String]
    let buyerName: String
    let buyerDetails: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Invoice Preview")
                    .font(.headline)
                Spacer()
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.down")
                }

                Button {
                    printInvoice()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                documentPage
                    .frame(width: 720, alignment: .top)
                    .frame(minHeight: 1018, alignment: .top)
                    .background(.white)
                    .foregroundStyle(.black)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    .padding(28)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 860)
    }

    private var documentPage: some View {
        InvoiceDocumentPage(
            invoice: invoice,
            sellerName: sellerName,
            sellerDetails: sellerDetails,
            buyerName: buyerName,
            buyerDetails: buyerDetails
        )
    }

    private func exportPDF() {
        InvoicePrintService.exportPDF(
            invoice: invoice,
            sellerName: sellerName,
            sellerDetails: sellerDetails,
            buyerName: buyerName,
            buyerDetails: buyerDetails
        )
    }

    private func printInvoice() {
        InvoicePrintService.printInvoice(
            invoice: invoice,
            sellerName: sellerName,
            sellerDetails: sellerDetails,
            buyerName: buyerName,
            buyerDetails: buyerDetails
        )
    }
}

struct InvoiceDocumentPage: View {
    let invoice: Invoice
    let sellerName: String
    let sellerDetails: [String]
    let buyerName: String
    let buyerDetails: [String]

    private let templateSettings = DocumentTemplateSettings.load()

    private var currencyCode: String {
        invoice.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "EUR" : invoice.currencyCode
    }

    private var footerText: String {
        let configuredText = templateSettings.footerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = configuredText.isEmpty ? DocumentTemplateSettings.defaultFooterText : configuredText
        return "\(baseText) - \(formattedDate(Date()))"
    }

    private var paymentMethodText: String {
        let method = invoice.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        return method.isEmpty ? InvoiceDefaults.standardPaymentMethod : method
    }

    private var paymentInstructionsText: String {
        invoice.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(sellerName)
                        .font(.title3.weight(.bold))
                    Text("Printable invoice preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Issue date")
                        .font(.caption.weight(.semibold))
                    Text(formattedDate(invoice.issueDate))
                }
                .font(.subheadline)
            }

            VStack(spacing: 5) {
                Text("Invoice")
                    .font(.headline)
                Text(invoice.displayTitle)
                    .font(.title.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.08))
            .overlay(Rectangle().stroke(.black, lineWidth: 1))

            HStack(alignment: .top, spacing: 12) {
                partyBox(title: "Seller", name: sellerName, details: sellerDetails)
                partyBox(title: "Buyer", name: buyerName, details: buyerDetails)
            }

            itemsTable

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Amount due: \(invoice.total.formatted(.currency(code: currencyCode)))")
                        .font(.title2.weight(.bold))
                    Text("Payment method: \(paymentMethodText)")
                        .font(.subheadline.weight(.semibold))
                    if !paymentInstructionsText.isEmpty {
                        Text(paymentInstructionsText)
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Payment due date: \(formattedDate(invoice.dueDate))")
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                totalsBox
            }
            .padding(.top, 10)

            Spacer(minLength: 80)

            if templateSettings.showsSignatureLines {
                HStack(spacing: 30) {
                    signatureLine("Signature of authorized recipient")
                    signatureLine("Signature of authorized issuer")
                }
            }

            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 22)
        }
        .padding(52)
    }

    private func partyBox(title: String, name: String, details: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline.weight(.bold))
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(10)
            .overlay(Rectangle().stroke(.black, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var itemsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider().overlay(.black)
            ForEach(Array(invoice.documentLineItems.enumerated()), id: \.element.id) { index, item in
                tableRow(index: index, item: item)
                Divider().overlay(.black)
            }
        }
        .font(.caption)
        .overlay(Rectangle().stroke(.black, lineWidth: 1))
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            tableCell("#", width: 28, weight: .semibold)
            tableCell("Product/service name", minWidth: 128, weight: .semibold, alignment: .leading)
            tableCell("Qty", width: 56, weight: .semibold)
            tableCell("Net", width: 76, weight: .semibold)
            tableCell("Discount", width: 70, weight: .semibold)
            tableCell("VAT", width: 58, weight: .semibold)
            tableCell("Total", width: 82, weight: .semibold)
        }
        .background(Color.black.opacity(0.08))
    }

    private func tableRow(index: Int, item: InvoiceLineItem) -> some View {
        HStack(spacing: 0) {
            tableCell("\(index + 1)", width: 28)
            tableCell(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled item" : item.title, minWidth: 128, alignment: .leading)
            tableCell(decimal(item.quantity), width: 56)
            tableCell(item.netTotal.formatted(.currency(code: currencyCode)), width: 76)
            tableCell(item.discountPercent > 0 ? "\(decimal(item.discountPercent))%" : "-", width: 70)
            tableCell("\(decimal(item.vatRate))%", width: 58)
            tableCell(item.grossTotal.formatted(.currency(code: currencyCode)), width: 82, weight: .semibold)
        }
    }

    private func tableCell(_ text: String, width: CGFloat? = nil, minWidth: CGFloat? = nil, weight: Font.Weight = .regular, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .fontWeight(weight)
            .lineLimit(2)
            .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            .frame(width: width, alignment: alignment)
            .frame(minWidth: minWidth, maxWidth: minWidth == nil ? nil : .infinity, alignment: alignment)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .border(.black.opacity(0.35), width: 0.5)
    }

    private var totalsBox: some View {
        VStack(alignment: .trailing, spacing: 6) {
            totalRow("Total net", value: invoice.netTotal.formatted(.currency(code: currencyCode)))
            totalRow("Total VAT", value: invoice.vatTotal.formatted(.currency(code: currencyCode)))
            totalRow("Total gross", value: invoice.total.formatted(.currency(code: currencyCode)), isProminent: true)
        }
        .frame(width: 240, alignment: .trailing)
    }

    private func totalRow(_ title: String, value: String, isProminent: Bool = false) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(isProminent ? .bold : .semibold)
                .monospacedDigit()
        }
        .font(isProminent ? .headline : .subheadline)
    }

    private func signatureLine(_ title: String) -> some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(.black.opacity(0.55))
                .frame(height: 1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private extension Invoice {
    var documentLineItems: [InvoiceLineItem] {
        lineItems.filter(\.hasDocumentContent)
    }
}

private extension InvoiceLineItem {
    var hasDocumentContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || unitPrice > 0
            || discountPercent > 0
    }
}

enum InvoicePrintService {
    private static let pageSize = NSSize(width: 720, height: 1018)

    static func pdfData(
        invoice: Invoice,
        sellerName: String,
        sellerDetails: [String],
        buyerName: String,
        buyerDetails: [String]
    ) -> Data {
        let documentPage = InvoiceDocumentPage(
            invoice: invoice,
            sellerName: sellerName,
            sellerDetails: sellerDetails,
            buyerName: buyerName,
            buyerDetails: buyerDetails
        )
        .frame(width: pageSize.width, height: pageSize.height, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)

        return renderedPDFData(from: documentPage)
    }

    static func exportPDF(
        invoice: Invoice,
        sellerName: String,
        sellerDetails: [String],
        buyerName: String,
        buyerDetails: [String]
    ) {
        let data = pdfData(
            invoice: invoice,
            sellerName: sellerName,
            sellerDetails: sellerDetails,
            buyerName: buyerName,
            buyerDetails: buyerDetails
        )
        guard !data.isEmpty else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(sanitizedFilename(invoice.displayTitle)).pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    static func printInvoice(
        invoice: Invoice,
        sellerName: String,
        sellerDetails: [String],
        buyerName: String,
        buyerDetails: [String]
    ) {
        let pdfData = pdfData(
            invoice: invoice,
            sellerName: sellerName,
            sellerDetails: sellerDetails,
            buyerName: buyerName,
            buyerDetails: buyerDetails
        )
        guard let document = PDFDocument(data: pdfData),
              let operation = document.printOperation(
                for: configuredPrintInfo(),
                scalingMode: .pageScaleToFit,
                autoRotate: true
              ) else {
            return
        }

        operation.jobTitle = invoice.displayTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>")
        let components = value.components(separatedBy: invalidCharacters)
        let filename = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? "Invoice" : filename
    }

    private static func configuredPrintInfo() -> NSPrintInfo {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        return printInfo
    }

    private static func renderedPDFData<Content: View>(from content: Content) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: pageSize.height)
        pdfContext.beginPDFPage(nil)
        renderer.render { _, render in
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fill(mediaBox)
            render(pdfContext)
        }
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return data as Data
    }
}
#endif
