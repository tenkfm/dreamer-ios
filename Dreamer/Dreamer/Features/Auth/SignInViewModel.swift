import Foundation
import Observation

/// Account step: Sign in with Apple, with Google or an email link.
@MainActor
@Observable
final class SignInViewModel {
    enum Mode: Equatable, Sendable {
        /// New user after the quiz: "Save your dreams".
        case signUp
        /// "I already have an account" or a returning, signed-out user: "Welcome back".
        case signIn
    }

    enum Phase: Equatable {
        case form
        /// The email with the link is on its way.
        case checkInbox(email: String)
        /// A link from an email was opened and is being checked.
        case verifyingLink
    }

    var mode: Mode
    var email = ""
    private(set) var phase: Phase = .form
    private(set) var isWorking = false
    private(set) var workingMethod: SignInMethod?
    private(set) var error: ErrorState?
    /// "Resend" stays off until then, so a tap-happy user does not burn the 5 emails an hour.
    private(set) var resendAvailableAt: Date?

    private let auth: any AuthService
    private let google: (any GoogleSignInProvider)?
    private let analytics: any Analytics
    private let onSignedIn: (AuthSession) -> Void
    private let now: () -> Date

    static let resendCooldown: TimeInterval = 30

    init(mode: Mode, auth: any AuthService, google: (any GoogleSignInProvider)? = nil,
         analytics: any Analytics = NoopAnalytics(),
         now: @escaping () -> Date = Date.init, onSignedIn: @escaping (AuthSession) -> Void) {
        self.mode = mode
        self.auth = auth
        self.google = google
        self.analytics = analytics
        self.now = now
        self.onSignedIn = onSignedIn
    }

    // MARK: Copy

    var title: String { mode == .signUp ? String(localized: "Save your dreams") : String(localized: "Welcome back") }

    var subtitle: String {
        mode == .signUp ? String(localized: "Create your account to keep your journal.") : String(localized: "Sign in to open your journal.")
    }

    // MARK: Email

    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Deliberately loose: the server validates; this only catches obvious typos before a round trip.
    var isEmailValid: Bool {
        let value = trimmedEmail
        guard let at = value.firstIndex(of: "@"), value.count <= 254 else { return false }
        let domain = value[value.index(after: at)...]
        return at != value.startIndex && domain.contains(".") && !domain.hasSuffix(".") && !value.contains(" ")
    }

    func continueWithEmail() async {
        guard isEmailValid, !isWorking else { return }
        analytics.track(.signInStarted(method: .email))
        await perform(.email) { [auth, trimmedEmail] () throws(APIError) in
            try await auth.requestEmailLink(email: trimmedEmail)
        }
        if error == nil {
            phase = .checkInbox(email: trimmedEmail)
            resendAvailableAt = now().addingTimeInterval(Self.resendCooldown)
        }
    }

    var canResend: Bool {
        guard case .checkInbox = phase, !isWorking else { return false }
        return resendAvailableAt.map { now() >= $0 } ?? true
    }

    func resend() async {
        guard case .checkInbox(let address) = phase, canResend else { return }
        await perform(.email) { [auth] () throws(APIError) in
            try await auth.requestEmailLink(email: address)
        }
        if error == nil { resendAvailableAt = now().addingTimeInterval(Self.resendCooldown) }
    }

    func useAnotherEmail() {
        phase = .form
        error = nil
    }

    /// A sign-in link was opened (universal link, IOS-02.3).
    func verifyLink(token: String) async {
        phase = .verifyingLink
        let previousPhase = phase
        await perform(.email) { [auth, onSignedIn] () throws(APIError) in
            let session = try await auth.verifyEmailLink(token: token)
            onSignedIn(session)
        }
        if error != nil, phase == previousPhase { phase = .form }
    }

    // MARK: Apple

    func appleSignInStarted() {
        analytics.track(.signInStarted(method: .apple))
        error = nil
        workingMethod = .apple
        isWorking = true
    }

    func signInWithApple(_ credential: AppleCredential) async {
        await perform(.apple) { [auth, onSignedIn] () throws(APIError) in
            let session = try await auth.signInWithApple(credential)
            onSignedIn(session)
        }
    }

    /// The Apple sheet failed or was cancelled (a cancel shows nothing).
    func appleSignInFailed(cancelled: Bool) {
        isWorking = false
        workingMethod = nil
        if !cancelled {
            error = ErrorState(kind: .serverError, title: String(localized: "Sign in with Apple didn’t work"),
                               message: String(localized: "Please try again, or continue with your email."), action: .dismiss)
        }
    }

    // MARK: Google

    var isGoogleAvailable: Bool { google != nil }

    func signInWithGoogle() async {
        guard let google, !isWorking else { return }
        analytics.track(.signInStarted(method: .google))
        error = nil
        workingMethod = .google
        isWorking = true
        let credential: GoogleCredential
        do {
            credential = try await google.signIn()
        } catch {
            isWorking = false
            workingMethod = nil
            switch error {
            case .cancelled:
                break
            case .offline:
                self.error = ErrorState(APIError.offline)
            case .failed:
                self.error = ErrorState(kind: .serverError, title: String(localized: "Sign in with Google didn’t work"),
                                        message: String(localized: "Please try again, or use another way to sign in."),
                                        action: .dismiss)
            }
            return
        }
        await perform(.google) { [auth, onSignedIn] () throws(APIError) in
            let session = try await auth.signInWithGoogle(credential)
            onSignedIn(session)
        }
    }

    func dismissError() {
        error = nil
    }

    /// The action of the current error ("Send a new link" after an expired one).
    func performErrorAction() async {
        guard let error else { return }
        switch error.action {
        case .requestNewLink:
            phase = .form
            self.error = nil
            // The address is known when the email was requested on this device.
            if isEmailValid { await continueWithEmail() }
        default:
            self.error = nil
        }
    }

    // MARK: -

    private func perform(_ method: SignInMethod, _ work: () async throws(APIError) -> Void) async {
        error = nil
        workingMethod = method
        isWorking = true
        defer {
            isWorking = false
            workingMethod = nil
        }
        do {
            try await work()
        } catch {
            self.error = ErrorState(error)
        }
    }
}
