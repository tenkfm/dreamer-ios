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
                .disabled(viewModel.selectedProduct == nil)
                .opacity(viewModel.selectedProduct == nil ? 0.6 : 1)
                .padding(.horizontal, DS.Space.cta - DS.Space.screen)
                .enterUp(0.9)
                footer.enterUp(1)
            }
            .padding(.horizontal, DS.Space.screen)
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.showsCloseButton {
                GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") { viewModel.close() }
                .padding(.trailing, DS.Space.screen)
                .padding(.top, DS.Space.headerTop)
                .enterUp(0.1)
            }
        }
        .task { await viewModel.loadProducts() }
        .onAppear { viewModel.viewed() }
        .trackScreen(.paywall)
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

    @ViewBuilder private var plans: some View {
        switch viewModel.productsState {
        case .loading:
            VStack(spacing: DS.Space.stack) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.option, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                        .frame(height: 72)
                        .glassCard(radius: DS.Radius.option, style: .option)
                        .overlay { ProgressView().tint(DS.Palette.icon) }
                }
            }
            .accessibilityLabel("Loading plans")
        case .failed:
            ErrorStateCard(systemImage: "wifi.slash", title: "Plans didn’t load",
                           message: "We couldn’t reach the App Store. Check your connection.",
                           actionTitle: "Try again") {
                Task { await viewModel.reloadProducts() }
            }
        case .loaded(let products):
            VStack(spacing: DS.Space.stack) {
                ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                    PlanCard(title: product.plan.title, subtitle: viewModel.subtitle(for: product),
                             price: product.displayPrice, badge: viewModel.badge(for: product),
                             isSelected: viewModel.selectedPlan == product.plan) {
                        viewModel.select(product.plan)
                    }
                    .enterUp(0.55 + Double(index) * 0.15)
                }
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
