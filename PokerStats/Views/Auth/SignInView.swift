import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    let authViewModel: AuthViewModel

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
                }

                Spacer()

                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    authViewModel.handleAppleSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.white)
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
                }

                // Loading overlay
                if authViewModel.isProcessing {
                    ProgressView()
                        .tint(.white)
                }

                Spacer()
                    .frame(height: 40)
            }
            .background(Color.pokerBackground)
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
