import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        #if os(macOS)
        DesktopOnboardingLayout(onComplete: onComplete)
        #elseif os(visionOS)
        DesktopOnboardingLayout(onComplete: onComplete)
        #else
        MobileOnboardingLayout(onComplete: onComplete)
        #endif
    }
}

private struct MobileOnboardingLayout: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.42, blue: 0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BrandMark(color: .white)
                        .padding(.top, 34)
                        .padding(.horizontal, 28)

                    Spacer(minLength: 40)

                    VStack(spacing: 28) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 112, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)

                        Text("Invoices, clients, and payments in one place.")
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 40)
                }

                OnboardingSetupPanel(onComplete: onComplete)
                    .background(alignment: .bottom) {
                        UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                            .fill(.background)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
        }
    }
}

private struct DesktopOnboardingLayout: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.97, blue: 1.0)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 32) {
                    BrandMark(color: Color(red: 0.04, green: 0.32, blue: 0.72))

                    Spacer()

                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 118, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(red: 0.04, green: 0.32, blue: 0.72))

                    Text("Run invoices from a focused workspace.")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    Text("Prepare business details, clients, documents, and payment settings without forcing a phone layout onto larger screens.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(48)

                OnboardingSetupPanel(onComplete: onComplete)
                    .frame(width: 460)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
                    .padding(48)
            }
            .frame(minWidth: 780, minHeight: 560)
        }
    }
}

private struct BrandMark: View {
    let color: Color

    var body: some View {
        Label("InvoiceFlow", systemImage: "square.grid.2x2.fill")
            .font(.system(size: 30, weight: .bold, design: .default))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
    }
}

private struct OnboardingSetupPanel: View {
    let onComplete: () -> Void

    @State private var company = CompanyFormData.empty
    @State private var profileStore = MyCompanyProfileStore()
    @State private var defaults = InvoiceDefaults.load()
    @State private var numbering = InvoiceNumberingSettings.load()
    @State private var selectedCountry = CompanyLookupCountry.slovakia
    @State private var selectedStep: OnboardingStep = .seller

    private var canSaveSeller: Bool {
        !company.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewInvoiceNumber: String {
        numbering.formattedNumber(sequence: numbering.normalizedNextNumber)
    }

    private var fieldLabels: CompanyFieldLabels {
        selectedCountry.fieldLabels
    }

    private var primaryButtonFill: Color {
        canContinue ? .black : .secondary.opacity(0.35)
    }

    private var canContinue: Bool {
        selectedStep != .seller || canSaveSeller
    }

    private var primaryActionTitle: String {
        selectedStep == .numbering ? "Start Invoicing" : "Continue"
    }

    private var primaryActionSystemImage: String {
        selectedStep == .numbering ? "checkmark.circle" : "arrow.right.circle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set Up Invoicing")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("These defaults are applied to new invoices and can be changed later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OnboardingStepHeader(selectedStep: selectedStep)

            ScrollView {
                stepContent
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 430)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    if let previousStep = selectedStep.previous {
                        Button {
                            selectedStep = previousStep
                        } label: {
                            Label("Back", systemImage: "arrow.left.circle")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: continueSetup) {
                        Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(primaryButtonFill))
                    .disabled(!canContinue)
                }

                if !canSaveSeller && selectedStep == .seller {
                    Label("Business name is required to issue invoices.", systemImage: "building.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 34)
        .safeAreaPadding(.bottom, 12)
        .onAppear(perform: loadExistingSettings)
        .onChange(of: selectedCountry) { _, newCountry in
            company.country = newCountry.rawValue
        }
    }

    private var dueDescription: String {
        switch defaults.dueDays {
        case 0:
            "Same day"
        case 1:
            "1 day"
        default:
            "\(defaults.dueDays) days"
        }
    }

    private var formattedVATRate: String {
        if defaults.vatRate.rounded() == defaults.vatRate {
            return "\(Int(defaults.vatRate))%"
        }
        return "\(defaults.vatRate.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    @ViewBuilder
    private var stepContent: some View {
        switch selectedStep {
        case .seller:
            OnboardingSetupSection(title: "Seller") {
                OnboardingTextField(fieldLabels.companyName, text: $company.name)
                OnboardingTextField(fieldLabels.companyId, text: $company.ico)
                OnboardingTextField(fieldLabels.taxId, text: $company.taxId)
                OnboardingTextField(fieldLabels.vatId, text: $company.vatId)
                OnboardingTextField(fieldLabels.street, text: $company.street)
                OnboardingTextField(fieldLabels.city, text: $company.city)
                OnboardingTextField(fieldLabels.postalCode, text: $company.postalCode)
                CountrySearchField(selectedCountry: $selectedCountry)
            }
        case .defaults:
            OnboardingSetupSection(title: "Invoice Defaults") {
                Stepper(value: $defaults.dueDays, in: 0...120) {
                    OnboardingSettingValue(title: "Payment due", value: dueDescription)
                }

                Stepper(value: $defaults.vatRate, in: 0...100, step: 1) {
                    OnboardingSettingValue(title: "Default VAT", value: formattedVATRate)
                }

                Picker("Default currency", selection: $defaults.currencyCode) {
                    ForEach(InvoiceDefaults.supportedCurrencyCodes, id: \.self) { currencyCode in
                        Text(currencyCode).tag(currencyCode)
                    }
                }
            }
        case .payment:
            OnboardingSetupSection(title: "Payment") {
                Picker("Default method", selection: $defaults.paymentMethod) {
                    ForEach(InvoiceDefaults.supportedPaymentMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }

                OnboardingTextField("Payment note", text: $defaults.paymentInstructions)
            }
        case .numbering:
            OnboardingSetupSection(title: "Numbering") {
                OnboardingTextField("Prefix", text: $numbering.prefix)
                Toggle("Include year", isOn: $numbering.includesYear)
                Stepper(value: $numbering.nextNumber, in: 1...999_999) {
                    OnboardingSettingValue(title: "Next number", value: "\(numbering.normalizedNextNumber)")
                }
                LabeledContent("Preview", value: previewInvoiceNumber)
                    .font(.subheadline)
            }
        }
    }

    private func loadExistingSettings() {
        profileStore.load()
        if profileStore.hasSavedProfile {
            company = profileStore.company
            selectedCountry = profileStore.country
        } else if company.country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedCountry = .slovakia
            company.country = selectedCountry.rawValue
        } else {
            selectedCountry = CompanyLookupCountry.allCountries.first { $0.rawValue == company.country } ?? .slovakia
        }
        defaults = InvoiceDefaults.load()
        numbering = InvoiceNumberingSettings.load()
    }

    private func finishSetup() {
        guard canSaveSeller else { return }
        defaults.save()
        numbering.save()
        company.country = selectedCountry.rawValue
        profileStore.save(company: company, country: selectedCountry)
        onComplete()
    }

    private func continueSetup() {
        guard canContinue else { return }
        if let nextStep = selectedStep.next {
            selectedStep = nextStep
        } else {
            finishSetup()
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case seller
    case defaults
    case payment
    case numbering

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .seller: "Seller"
        case .defaults: "Defaults"
        case .payment: "Payment"
        case .numbering: "Numbering"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

private struct OnboardingStepHeader: View {
    let selectedStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases) { step in
                VStack(spacing: 6) {
                    Circle()
                        .fill(step.rawValue <= selectedStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                    Text(step.title)
                        .font(.caption2.weight(step == selectedStep ? .semibold : .regular))
                        .foregroundStyle(step == selectedStep ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup step \(selectedStep.rawValue + 1) of \(OnboardingStep.allCases.count): \(selectedStep.title)")
    }
}

private struct OnboardingSetupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingTextField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}

private struct OnboardingSettingValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}


#Preview {
    OnboardingView(onComplete: {})
}
