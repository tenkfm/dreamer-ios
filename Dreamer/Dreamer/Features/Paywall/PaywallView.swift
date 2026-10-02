import SwiftUI

/// 06 Paywall. Draws no background: it sits on the sky of whoever presents it.
struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    @Environment(\.openURL) private var openURL

    /// The full-screen modal (Settings, the limit, Analysis): a picture on top, a title, perks with
    /// a line each, a white CTA and a light footer on the dark gradient. Otherwise (onboarding, the
    /// root paywall) the layout on the sky.
    private let onDark: Bool

    init(viewModel: PaywallViewModel, onDark: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.onDark = onDark
    }

    var body: some View {
        ZStack {
            if onDark { modalLayout } else { skyLayout }
        }
        // On the ZStack, which keeps to the safe area: the button clears the status bar even though
        // the modal's picture runs under it.
        .overlay(alignment: .topTrailing) {
            if viewModel.showsCloseButton {
                GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") { viewModel.close() }
                .padding(.trailing, DS.Space.screen)
                .padding(.top, DS.Space.headerTop)
            }
        }
        .haptic(viewModel.haptic)
        .task { await viewModel.loadProducts() }
        .onAppear { viewModel.viewed() }
        .trackScreen(.paywall)
        .alert("Dreamer", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var skyLayout: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                perksCard
                plans.padding(.top, 30)
                Spacer(minLength: 24)
                cta.padding(.horizontal, DS.Space.cta - DS.Space.screen)
                footer
            }
            .padding(.horizontal, DS.Space.screen)
        }
    }

    /// Fits one iPhone screen without scrolling (it scrolls only where it cannot fit, an SE).
    private var modalLayout: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                hero
                VStack(spacing: 0) {
                    Text("What your dreams reveal")
                        .textStyle(.display, color: DS.Palette.white)
                        .skyTextShadow()
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    perkList.padding(.top, 22)
                    plans.padding(.top, 24)
                    Spacer(minLength: 20)
                    cta.padding(.horizontal, DS.Space.cta - DS.Space.screen)
                    footer
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, -30)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    /// The modal's picture: Home's sky (day or night), fading into the gradient below it.
    private var hero: some View {
        // The screen sets the width: a filled image on its own would widen the whole column.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .overlay { Image(.skyTop).resizable().scaledToFill() }
            .clipped()
            // Fades out rather than into a colour, so no seam shows on the gradient behind it.
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }

    /// Each benefit: an icon, its name (larger than the old one-liners) and one line of how.
    private var perkList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.perks, id: \.self) { perk in
                HStack(spacing: 14) {
                    Image(systemName: perk.systemImage)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(DS.Palette.icon)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(DS.Palette.surface))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(perk.title).textStyle(.heading, color: DS.Palette.white)
                        Text(perk.subtitle)
                            .textStyle(.secondary, color: DS.Palette.white.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var cta: some View {
        PrimaryButton(title: viewModel.ctaTitle, isLoading: viewModel.isPurchasing, light: onDark) {
            Task { await viewModel.purchase() }
        }
        .disabled(viewModel.selectedProduct == nil)
        .opacity(viewModel.selectedProduct == nil ? 0.6 : 1)
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
                    Text(perk.title).textStyle(.link)
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
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // The plans' terms differ in length (a trial adds a sentence). The hidden copies hold the
            // height of the longest one, so picking a plan swaps the text without moving the screen.
            ZStack(alignment: .top) {
                ForEach(viewModel.allTermsTexts, id: \.self) { terms in
                    termsLabel(terms).hidden()
                }
                termsLabel(viewModel.termsText)
                    .contentTransition(.opacity)
                    .animation(.soft(0.3), value: viewModel.selectedPlan)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.termsText)
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

    private func termsLabel(_ text: String) -> some View {
        Text(text)
            .textStyle(.label, color: onDark ? DS.Palette.white.opacity(0.8) : DS.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .textStyle(.label, color: onDark ? DS.Palette.white : DS.Palette.textPrimary)
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

/// The paywall as a full-screen modal inside the app (Settings, the limit, Analysis): on its own
/// gradient, darker than the screens behind it.
struct PaywallSheet: View {
    let viewModel: PaywallViewModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Palette.paywallTop, DS.Palette.paywallBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            PaywallView(viewModel: viewModel, onDark: true)
        }
        .scrollEdgeEffectsHidden()
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full)
        PaywallView(viewModel: PaywallViewModel(purchases: MockPurchaseService(), appState: .preview(onboardingCompleted: false)))
    }
}
