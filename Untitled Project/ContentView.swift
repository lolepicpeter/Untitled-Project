import SwiftUI

#if os(macOS)
import AppKit

extension View {
    func onMacKeyDown(perform handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(MacKeyDownHandler(handler: handler))
    }
}

private struct MacKeyDownHandler: ViewModifier {
    let handler: (NSEvent) -> Bool

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handler(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }
    }
}
#endif

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            AppRootView()
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

private struct AppRootView: View {
    var body: some View {
        #if os(macOS)
        MacMainView()
        #else
        MainTabView()
        #endif
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case invoices
    case clients
    case items
    case integrations
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .invoices: "Invoices"
        case .clients: "Clients"
        case .items: "Products"
        case .integrations: "Integrations"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar"
        case .invoices: "doc.text"
        case .clients: "person.2"
        case .items: "shippingbox"
        case .integrations: "link.badge.plus"
        case .settings: "gearshape"
        }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label(AppSection.dashboard.title, systemImage: AppSection.dashboard.systemImage) }

            InvoicesView()
                .tabItem { Label(AppSection.invoices.title, systemImage: AppSection.invoices.systemImage) }

            ClientsView()
                .tabItem { Label(AppSection.clients.title, systemImage: AppSection.clients.systemImage) }

            ItemsView()
                .tabItem { Label(AppSection.items.title, systemImage: AppSection.items.systemImage) }

            IntegrationsView()
                .tabItem { Label(AppSection.integrations.title, systemImage: AppSection.integrations.systemImage) }

            SettingsView()
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
        }
    }
}

#if os(macOS)
private struct MacMainView: View {
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("InvoiceFlow")
            .frame(minWidth: 220)
        } detail: {
            MacDetailHost(selection: selection ?? .dashboard)
        }
    }
}

private struct MacDetailHost: View {
    let selection: AppSection

    var body: some View {
        destination
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    @ViewBuilder
    private var destination: some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .invoices:
            InvoicesView()
        case .clients:
            ClientsView()
        case .items:
            ItemsView()
        case .integrations:
            IntegrationsView()
        case .settings:
            SettingsView()
        }
    }

    private var section: AppSection {
        selection
    }
}

private struct MacAppSidebarNavigation: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.body.weight(selection == section ? .semibold : .regular))
                        .foregroundStyle(selection == section ? .white : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .background(
                    selection == section ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ActiveSellerSidebarControl: View {
    @Bindable var profileStore: MyCompanyProfileStore
    let onAddSeller: () -> Void

    private var selectedSellerBinding: Binding<UUID?> {
        Binding(
            get: { profileStore.selectedProfileID },
            set: { newValue in
                guard let newValue else { return }
                profileStore.selectProfile(id: newValue)
            }
        )
    }

    private var activeSellerName: String {
        profileStore.selectedProfile?.displayName ?? "No seller selected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Operating as", systemImage: "building.2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if profileStore.profiles.count > 1 {
                Picker("Active seller", selection: selectedSellerBinding) {
                    ForEach(profileStore.profiles) { profile in
                        Text(profile.displayName).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(activeSellerName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(profileStore.hasSavedProfile ? .primary : .secondary)
            }

            if profileStore.hasSavedProfile {
                Button(action: onAddSeller) {
                    Label("Manage Sellers", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            } else {
                Button(action: onAddSeller) {
                    Label("Set Up Seller", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 2)
            }

            Text("Used for new invoices")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
#endif

#Preview {
    ContentView()
}
