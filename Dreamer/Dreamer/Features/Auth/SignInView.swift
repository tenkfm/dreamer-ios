import AuthenticationServices
import SwiftUI

/// Account step of onboarding, built from the design system (the design has no account screen):
/// full sky, title, Sign in with Apple, Sign in with Google (when the build has a Google
/// client), a glass email field and the legal line.
/// After an email is sent: "Check your inbox" with the envelope orb and "Resend".
/// Draws no background: it sits on the onboarding sky.
struct SignInView: View {
    @Bindable var viewModel: SignInViewModel
    var onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var appleNonce = ""
    @FocusState private var emailFocused: Bool

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                header
                switch viewModel.phase {
                case .form:
                    form.transition(.stepChange)
                case .checkInbox(let email):
                    checkInbox(email).transition(.stepChange)
                case .verifyingLink:
                    verifying.transition(.stepChange)
                }
            }
            .padding(.horizontal, DS.Space.cta)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.soft(0.5), value: viewModel.phase)
        .animation(.soft(0.3), value: viewModel.error)
        // The link is on its way; a sign-in that failed (a cancel sets no error).
        .sensoryFeedback(.success, trigger: viewModel.phase) { _, phase in
            if case .checkInbox = phase { true } else { false }
        }
        .sensoryFeedback(.error, trigger: viewModel.error) { _, error in error != nil }
    }

    private var header: some View {
        HeaderBar(leading: {
            GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                emailFocused = false
                if viewModel.phase == .form { onBack() } else { viewModel.useAnotherEmail() }
            }
        }, center: {
            EmptyView()
        })
        // HeaderBar keeps its own screen margin; this only cancels the content's CTA margin, so the
        // header buttons stand where they do on every other screen.
        .padding(.horizontal, -DS.Space.cta)
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                Text(viewModel.title)
                    .textStyle(.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.subtitle)
                    .textStyle(.body, color: DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 28)

            VStack(spacing: 14) {
                appleButton
                if viewModel.isGoogleAvailable { googleButton }
                orDivider
                GlassTextField(systemImage: "envelope", placeholder: "Your email", text: $viewModel.email,
                               contentType: .emailAddress, keyboard: .emailAddress, submitLabel: .continue) {
                    Task { await viewModel.continueWithEmail() }
                }
                .focused($emailFocused)
                PrimaryButton(title: "Continue with email",
                              isLoading: viewModel.workingMethod == .email) {
                    emailFocused = false
                    Task { await viewModel.continueWithEmail() }
                }
                .disabled(!viewModel.isEmailValid || viewModel.isWorking)
                .opacity(viewModel.isEmailValid ? 1 : 0.6)
            }

            if let error = viewModel.error {
                errorLine(error).padding(.top, 14)
            }

            Spacer(minLength: 24)
            legalLine
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(viewModel.mode == .signUp ? .signUp : .signIn) { request in
            appleNonce = AppleSignIn.prepare(request)
            viewModel.appleSignInStarted()
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = AppleSignIn.credential(from: authorization, rawNonce: appleNonce) else {
                    viewModel.appleSignInFailed(cancelled: false)
                    return
                }
                Task { await viewModel.signInWithApple(credential) }
            case .failure(let error):
                viewModel.appleSignInFailed(cancelled: AppleSignIn.isCancellation(error))
            }
        }
        // HIG: black on light backgrounds, white on dark. The system button keeps the style it was
        // created with, so it is rebuilt when the appearance changes.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .id(colorScheme)
        .frame(height: DS.Size.primaryButton)
        .clipShape(Capsule())
        .overlay {
            if viewModel.workingMethod == .apple {
                Capsule().fill(.black.opacity(0.35))
                ProgressView().tint(.white)
            }
        }
        .disabled(viewModel.isWorking)
    }

    private var googleButton: some View {
        GoogleSignInButton(mode: viewModel.mode, isLoading: viewModel.workingMethod == .google) {
            emailFocused = false
            Task { await viewModel.signInWithGoogle() }
        }
        .disabled(viewModel.isWorking)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(DS.Palette.line.opacity(0.25)).frame(height: 1)
            Text("or").textStyle(.label, color: DS.Palette.textTertiary)
            Rectangle().fill(DS.Palette.line.opacity(0.25)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func errorLine(_ error: ErrorState) -> some View {
        VStack(spacing: 4) {
            Text(error.title).textStyle(.bodyStrong)
            Text(error.message)
                .textStyle(.secondary, color: DS.Palette.textSecondary)
            if error.action == .requestNewLink, let title = error.actionTitle {
                PillButton(title: title) { Task { await viewModel.performErrorAction() } }
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.option)
        .onTapGesture { viewModel.dismissError() }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Dismiss") { viewModel.dismissError() }
    }

    private var legalLine: some View {
        VStack(spacing: 6) {
            Text("By continuing you agree to our")
                .textStyle(.label, color: DS.Palette.textTertiary)
            HStack(spacing: 16) {
                legalLink("Terms") { openURL(AppLinks.terms) }
                legalLink("Privacy Policy") { openURL(AppLinks.privacy) }
            }
        }
        .padding(.bottom, 12)
    }

    private func legalLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .textStyle(.label)
                .underline()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Check your inbox

    private func checkInbox(_ email: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            OrbView(glyph: .envelope, size: .onboarding)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Check your inbox")
                    .textStyle(.display)
                    .accessibilityAddTraits(.isHeader)
                Text("We sent a sign-in link to \(email). It works once, for 15 minutes.")
                    .textStyle(.body, color: DS.Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 28)

            if let error = viewModel.error {
                errorLine(error).padding(.top, 18)
            }

            Spacer(minLength: 28)

            VStack(spacing: 8) {
                PrimaryButton(title: "Open Mail", systemImage: "envelope.open") {
                    if let mail = URL(string: "message://") { openURL(mail) }
                }
                ResendButton(availableAt: viewModel.resendAvailableAt, isWorking: viewModel.workingMethod == .email) {
                    Task { await viewModel.resend() }
                }
                TextLinkButton(title: "Use another email") { viewModel.useAnotherEmail() }
            }
            .padding(.bottom, 8)
        }
    }

    private var verifying: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            OrbView(glyph: .envelope, size: .onboarding).accessibilityHidden(true)
            Text("Signing you in…").textStyle(.heading)
            ProgressView().tint(DS.Palette.icon)
            Spacer(minLength: 40)
        }
    }
}

/// "Resend" with a visible countdown while the cooldown runs.
private struct ResendButton: View {
    var availableAt: Date?
    var isWorking: Bool
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((availableAt ?? .distantPast).timeIntervalSince(context.date).rounded(.up)))
            TextLinkButton(title: isWorking ? "Sending…" : remaining > 0 ? "Resend in \(remaining) s" : "Resend link",
                           color: remaining > 0 || isWorking ? DS.Palette.textTertiary : DS.Palette.textPrimary,
                           action: action)
                .disabled(remaining > 0 || isWorking)
        }
    }
}

#Preview("Sign up") {
    ZStack {
        SkyBackground(kind: .full)
        SignInView(viewModel: SignInViewModel(mode: .signUp, auth: MockAuthService(), google: MockGoogleSignIn()) { _ in }, onBack: {})
    }
}
