import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AdminAuthManager
    @State private var walletAddress = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundColor(.purple)

                Text("ArtSphere Admin")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Панель администратора")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Wallet Address", text: $walletAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { login() }
            }

            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: login) {
                if authManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Войти")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(walletAddress.isEmpty || password.isEmpty || authManager.isLoading)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 360)
    }

    private func login() {
        authManager.login(walletAddress: walletAddress, password: password)
    }
}
