import StoreKit
import SwiftUI

/// 14 Settings (pushed from Home).
struct SettingsView: View {
    @Environment(ReminderController.self) private var reminders
    @Environment(AppLock.self) private var appLock
    @State private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HeaderBar(leading: {
                        GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
                    }, center: {
                        ScreenTitle(text: "Settings")
                    })
                    .padding(.horizontal, -DS.Space.screen)
                    .enterUp(0.1)

                    preferencesGroup.padding(.top, 8).enterUp(0.3)
                    accountGroup.enterUp(0.45)

                    VStack(spacing: 0) {
                        TextLinkButton(title: viewModel.isSigningOut ? "Signing out…" : "Sign out") {
                            viewModel.isSignOutConfirmationPresented = true
                        }
                        .disabled(viewModel.isSigningOut)
                        TextLinkButton(title: "Delete account and all dreams", color: DS.Palette.destructive) {
                            viewModel.isDeleteConfirmationPresented = true
                        }
                    }
                    .padding(.top, 14)
                    .enterUp(0.6)
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .trackScreen(.settings)
        .alert("Dreamer", isPresented: lockAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appLock.alertMessage ?? "")
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            Group {
                switch sheet {
                case .reminderTime: ReminderTimeSheet(time: $viewModel.reminderTime)
                case .lens: LensPickerSheet(selection: $viewModel.preferredLens)
                case .subscription:
                    ZStack {
                        PanoramaSkyBackground.onboarding(at: .paywall)
                        PaywallView(viewModel: viewModel.makePaywallViewModel())
                    }
                }
            }
            .scrollEdgeEffectsHidden()
        }
        .manageSubscriptionsSheet(isPresented: $viewModel.isManagingSubscription)
        .sheet(isPresented: $viewModel.isDeleteConfirmationPresented, onDismiss: viewModel.cancelDelete) {
            DeleteAccountSheet(viewModel: viewModel)
        }
        .confirmationDialog("Sign out of Dreamer?", isPresented: $viewModel.isSignOutConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await viewModel.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your journal stays in your account. Sign in again to see it.")
        }
        #if DEBUG
        .onAppear { if DebugLaunch.screen == .deleteAccount { viewModel.isDeleteConfirmationPresented = true } }
        #endif
        .alert("Dreamer", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var preferencesGroup: some View {
        SettingsGroup {
            toggleRow("bell", "Morning reminder", isOn: reminderBinding)
            SettingsDivider()
            navigationRow("clock", "Reminder time", value: viewModel.reminderTimeText) { viewModel.activeSheet = .reminderTime }
                .disabled(!viewModel.morningReminder)
                .opacity(viewModel.morningReminder ? 1 : 0.5)
            SettingsDivider()
            navigationRow("sparkle", "Default lens", value: viewModel.preferredLens.title) { viewModel.activeSheet = .lens }
            SettingsDivider()
            toggleRow("moon", "Night mode after 9 PM", isOn: $viewModel.nightModeAfter9)
            SettingsDivider()
            toggleRow("lock", "Lock journal with Face ID", isOn: lockBinding)
        }
    }

    private var accountGroup: some View {
        SettingsGroup {
            navigationRow("creditcard", "Subscription", value: viewModel.subscriptionText) { viewModel.openSubscription() }
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

    /// Turning the lock on checks Face ID (or the passcode) first.
    private var lockBinding: Binding<Bool> {
        Binding(get: { viewModel.lockWithFaceID },
                set: { isOn in Task { await appLock.setEnabled(isOn) } })
    }

    private var lockAlert: Binding<Bool> {
        Binding(get: { appLock.alertMessage != nil }, set: { if !$0 { appLock.alertMessage = nil } })
    }

    /// Turning the reminder on asks for the permission when it was never asked.
    private var reminderBinding: Binding<Bool> {
        Binding(get: { viewModel.morningReminder },
                set: { isOn in
                    if isOn {
                        Task { await reminders.enable() }
                    } else {
                        viewModel.morningReminder = false
                    }
                })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } })
    }
}

// MARK: - Sheets

/// App Review 5.1.1(v): deletion inside the app, with a clear warning that the App Store
/// subscription is separate and a way to manage it first.
private struct DeleteAccountSheet: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var isManagingSubscription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Delete your account?")
                    .textStyle(.title)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    point("trash", "Your journal, notes, dream images and voice-overs are deleted for good.")
                    point("arrow.uturn.backward", "This can’t be undone.")
                    point("creditcard", "Your App Store subscription is not cancelled by this. Cancel it first so you aren’t charged again.")
                }

                if viewModel.hasSubscription {
                    PillButton(title: "Manage subscription") { isManagingSubscription = true }
                }

                if let error = viewModel.deleteError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error.title).textStyle(.bodyStrong)
                        Text(error.message).textStyle(.secondary, color: DS.Palette.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: DS.Radius.option)
                }

                VStack(spacing: 6) {
                    Button {
                        Task { await viewModel.deleteAccount() }
                    } label: {
                        ZStack {
                            Capsule().fill(DS.Palette.destructive)
                            if viewModel.isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Delete account and all dreams")
                                    .font(TextStyle.button.font)
                                    .foregroundStyle(DS.Palette.white)
                            }
                        }
                        .frame(height: DS.Size.primaryButton)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(viewModel.isDeleting)
                    TextLinkButton(title: "Keep my account") { viewModel.cancelDelete() }
                        .disabled(viewModel.isDeleting)
                }
                .padding(.top, 6)
            }
            .padding(DS.Space.screen)
        }
        .background(DS.Palette.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(DS.Radius.sheet)
        .interactiveDismissDisabled(viewModel.isDeleting)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(DS.Palette.icon)
                .frame(width: 22)
            Text(text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

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
        SettingsView(viewModel: SettingsViewModel(appState: state, purchases: MockPurchaseService(), account: MockAccountActions()))
    }
    .environment(ReminderController.preview)
    .environment(AppLock(appState: state, authenticator: MockAuthenticator()))
}
