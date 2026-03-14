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

                // Email/Password form
                VStack(spacing: 12) {
                    TextField("Email", text: .init(
                        get: { authViewModel.email },
                        set: { authViewModel.email = $0 }
                    ))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(.systemGray6))
                    .foregroundStyle(.black)
                    .cornerRadius(12)

                    SecureField("Password", text: .init(
                        get: { authViewModel.password },
                        set: { authViewModel.password = $0 }
                    ))
                    .textContentType(authViewModel.isSignUpMode ? .newPassword : .password)
                    .padding()
                    .background(Color(.systemGray6))
                    .foregroundStyle(.black)
                    .cornerRadius(12)

                    Button {
                        authViewModel.handleEmailSignIn()
                    } label: {
                        Text(authViewModel.isSignUpMode ? "Create Account" : "Sign In")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(authViewModel.isProcessing)

                    Button {
                        authViewModel.isSignUpMode.toggle()
                        authViewModel.errorMessage = nil
                    } label: {
                        Text(authViewModel.isSignUpMode
                             ? "Already have an account? Sign In"
                             : "Don't have an account? Sign Up")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                }
                .padding(.horizontal, 24)

                // Social sign-in buttons
                VStack(spacing: 12) {
                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        authViewModel.handleAppleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(12)

                    // Sign in with Google (placeholder)
                    Button {
                        authViewModel.handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Sign in with Google")
                                .font(.body.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white)
                        .foregroundStyle(.black)
                        .cornerRadius(12)
                    }
                }
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
