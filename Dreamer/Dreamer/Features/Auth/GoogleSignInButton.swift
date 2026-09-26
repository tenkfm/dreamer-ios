import SwiftUI

/// Google's sign-in button as its branding guidelines draw it: the four-color "G" on a white pill
/// with a gray outline by day, on a near-black one at night, and only the approved wording.
/// Sized like the Sign in with Apple button above it.
struct GoogleSignInButton: View {
    var mode: SignInViewModel.Mode
    var isLoading = false
    var action: () -> Void

    private var title: String {
        mode == .signUp ? String(localized: "Sign up with Google") : String(localized: "Sign in with Google")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("GoogleG")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Brand.signInFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(DS.Brand.googleText)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.primaryButton)
            .background(Capsule().fill(DS.Brand.googleFill))
            .overlay(Capsule().strokeBorder(DS.Brand.googleStroke, lineWidth: 1))
            .overlay {
                if isLoading {
                    Capsule().fill(.black.opacity(0.35))
                    ProgressView().tint(.white)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: 14) {
        GoogleSignInButton(mode: .signUp) {}
        GoogleSignInButton(mode: .signIn, isLoading: true) {}
    }
    .padding()
}
