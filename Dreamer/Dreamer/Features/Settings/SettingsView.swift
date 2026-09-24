import SwiftUI

/// 14 Settings (pushed from Home).
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: .top)
            ScrollView {
                VStack(spacing: 16) {
                    HeaderBar(leading: {
                        GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
                    }, center: {
                        SkyTitle(text: "Settings")
                    })
                    .padding(.horizontal, -DS.Space.screen)
                    .enterUp(0.1)

                    preferencesGroup.padding(.top, 8).enterUp(0.3)
                    accountGroup.enterUp(0.45)

                    TextLinkButton(title: "Delete account and all dreams", color: DS.Palette.destructive) {
                        viewModel.isDeleteConfirmationPresented = true
                    }
                    .padding(.top, 14)
                    .enterUp(0.6)
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .reminderTime: ReminderTimeSheet(time: $viewModel.reminderTime)
            case .lens: LensPickerSheet(selection: $viewModel.preferredLens)
            case .subscription:
                ZStack {
                    SkyBackground(kind: .full)
                    PaywallView(viewModel: viewModel.makePaywallViewModel())
                }
            }
        }
        .confirmationDialog("Delete your account and all dreams?", isPresented: $viewModel.isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { viewModel.deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your journal, notes and preferences from this iPhone. It can’t be undone.")
        }
        .alert("Dreamer", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var preferencesGroup: some View {
        SettingsGroup {
            toggleRow("bell", "Morning reminder", isOn: $viewModel.morningReminder)
            SettingsDivider()
            navigationRow("clock", "Reminder time", value: viewModel.reminderTimeText) { viewModel.activeSheet = .reminderTime }
                .disabled(!viewModel.morningReminder)
                .opacity(viewModel.morningReminder ? 1 : 0.5)
            SettingsDivider()
            navigationRow("sparkle", "Default lens", value: viewModel.preferredLens.title) { viewModel.activeSheet = .lens }
            SettingsDivider()
            toggleRow("moon", "Night mode after 9 PM", isOn: $viewModel.nightModeAfter9)
            SettingsDivider()
            toggleRow("lock", "Lock journal with Face ID", isOn: $viewModel.lockWithFaceID)
        }
    }

    private var accountGroup: some View {
        SettingsGroup {
            navigationRow("creditcard", "Subscription", value: viewModel.subscriptionText) { viewModel.activeSheet = .subscription }
            SettingsDivider()
            navigationRow("arrow.clockwise", "Restore purchases", value: viewModel.isRestoring ? "Restoring…" : nil) {
                Task { await viewModel.restorePurchases() }
            }
            SettingsDivider()
            navigationRow("shield", "Privacy policy") { openURL(AppLinks.privacy) }
            SettingsDivider()
            navigationRow("doc.text", "Terms of use") { openURL(AppLinks.terms) }
            SettingsDivider()
            navigationRow("questionmark.circle", "Contact support") { openURL(AppLinks.support) }
        }
    }

    private func toggleRow(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            SettingsRowLabel(systemImage: icon, title: title)
        }
        .toggleStyle(.dreamer)
        .settingsRowFrame()
    }

    private func navigationRow(_ icon: String, _ title: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(systemImage: icon, title: title) { SettingsValue(value: value) }
        }
        .buttonStyle(.plain)
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } })
    }
}

// MARK: - Sheets

private struct ReminderTimeSheet: View {
    @Binding var time: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            SheetTitleBar(title: "Reminder time") { dismiss() }
            DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .padding(DS.Space.screen)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.Palette.background.ignoresSafeArea())
        .presentationDetents([.height(340)])
        .presentationCornerRadius(DS.Radius.sheet)
    }
}

private struct LensPickerSheet: View {
    @Binding var selection: Lens
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DS.Space.stack) {
            SheetTitleBar(title: "Default lens") { dismiss() }
                .padding(.bottom, 6)
            ForEach(Lens.allCases) { lens in
                RadioOptionCard(title: lens.title, subtitle: lens.summary, isSelected: selection == lens) {
                    selection = lens
                }
            }
        }
        .padding(DS.Space.screen)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.Palette.background.ignoresSafeArea())
        .presentationDetents([.height(380)])
        .presentationCornerRadius(DS.Radius.sheet)
    }
}

private struct SheetTitleBar: View {
    var title: String
    var onDone: () -> Void

    var body: some View {
        HStack {
            Text(title).textStyle(.heading).accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done", action: onDone)
                .font(TextStyle.bodyStrong.font)
                .foregroundStyle(DS.Palette.cta)
                .frame(minHeight: 44)
        }
    }
}

#Preview {
    let state = AppState.preview()
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(appState: state, purchases: MockPurchaseService(), store: InMemoryDreamStore()))
    }
}
