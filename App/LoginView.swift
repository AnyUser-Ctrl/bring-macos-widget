import SwiftUI

struct LoginView: View {
    let onLoginSuccess: () -> Void

    @State private var email: String = BringStore.shared.email ?? ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bring! Widget")
                    .font(.system(size: 28, weight: .bold))
                Text("Sign in with your Bring! account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .disableAutocorrection(true)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit(performLogin)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(action: performLogin) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In")
                            .frame(minWidth: 100)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
            }

            Spacer()

            Text("Email and password are stored in plain text in the App Group container so the app and the widget can sign in again automatically when tokens expire. Intended for personal use on your own Mac only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func performLogin() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                _ = try await BringAPI.shared.login(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    onLoginSuccess()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    LoginView(onLoginSuccess: {})
        .padding()
        .frame(width: 420, height: 520)
}
