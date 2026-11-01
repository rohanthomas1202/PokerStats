import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    let authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fades the error and the progress row in and out instead of popping
    /// (#332); off with Reduce Motion, since the rows below them move.
    private var rowAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App branding
                VStack(spacing: 12) {
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)

                    Text("PokerStats")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("Sign in to back up your data\nand sync across devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Optional. Your stats stay on this iPhone either way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    authViewModel.configureAppleRequest(request)
                } onCompletion: { result in
                    authViewModel.handleAppleSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.white)
                .disabled(authViewModel.isProcessing)
                .frame(height: 50)
                .cornerRadius(12)
                .padding(.horizontal, 24)

                // Error message
                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        authViewModel.retrySignIn()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .disabled(authViewModel.isProcessing)
                }

                // Always in the layout so the sheet doesn't shift when
                // sign-in starts or ends (#228); hidden while idle.
                ProgressView("Signing in…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .opacity(authViewModel.isProcessing ? 1 : 0)
                    .accessibilityHidden(!authViewModel.isProcessing)

                Spacer()
                    .frame(height: 40)
            }
            .animation(rowAnimation, value: authViewModel.errorMessage)
            .animation(rowAnimation, value: authViewModel.isProcessing)
            .background(Color.pokerBackground)
            .onChange(of: authViewModel.errorMessage) { _, message in
                guard let message else { return }
                AccessibilityNotification.Announcement(message).post()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authViewModel.isShowingSignIn = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}
