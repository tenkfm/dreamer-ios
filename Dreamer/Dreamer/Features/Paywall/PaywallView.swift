import SwiftUI

/// 06 Paywall. Draws no background: it sits on the sky of whoever presents it.
struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    @Environment(\.openURL) private var openURL

    init(viewModel: PaywallViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                perksCard.enterUp(0.4)
                plans.padding(.top, 30)
                Spacer(minLength: 24)
                PrimaryButton(title: viewModel.ctaTitle, isLoading: viewModel.isPurchasing) {
                    Task { await viewModel.purchase() }
                }
                .padding(.horizontal, DS.Space.cta - DS.Space.screen)
                .enterUp(0.9)
                footer.enterUp(1)
            }
            .padding(.horizontal, DS.Space.screen)
        }
        .overlay(alignment: .topTrailing) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") { viewModel.close() }
                .padding(.trailing, DS.Space.screen)
                .padding(.top, DS.Space.headerTop)
                .enterUp(0.1)
        }
        .alert("Dreamer", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Logo(large: true)
            Text("Wake up to meaning")
                .textStyle(.display, color: DS.Palette.white)
                .skyTextShadow()
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 60)
        .enterUp(0.2)
    }

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.perks, id: \.self) { perk in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.icon)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(DS.Palette.surface))
                    Text(perk).textStyle(.link)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.cardPaddingLarge)
        .padding(.vertical, 18)
        .glassCard(radius: DS.Radius.cardLarge)
    }

    private var plans: some View {
        VStack(spacing: DS.Space.stack) {
            ForEach(Array(Plan.allCases.enumerated()), id: \.element) { index, plan in
                PlanCard(title: plan.title, subtitle: plan.billingDescription, price: plan.displayPrice,
                         badge: plan.badge, isSelected: viewModel.selectedPlan == plan) {
                    viewModel.selectedPlan = plan
                }
                .enterUp(0.55 + Double(index) * 0.15)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(viewModel.termsText)
                .textStyle(.label, color: DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.soft(0.3), value: viewModel.selectedPlan)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                footerLink(viewModel.isRestoring ? "Restoring…" : "Restore") {
                    Task { await viewModel.restore() }
                }
                footerLink("Terms") { openURL(AppLinks.terms) }
                footerLink("Privacy") { openURL(AppLinks.privacy) }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .textStyle(.label, color: DS.Palette.textPrimary)
                .underline()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } })
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full)
        PaywallView(viewModel: PaywallViewModel(purchases: MockPurchaseService(), appState: .preview(onboardingCompleted: false)))
    }
}
