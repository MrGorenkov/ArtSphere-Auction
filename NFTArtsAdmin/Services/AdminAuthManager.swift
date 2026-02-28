import SwiftUI

class AdminAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AdminUserBasic?
    @Published var errorMessage: String?
    @Published var isLoading = false

    func login(walletAddress: String, password: String) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await AdminNetworkService.shared.login(
                    walletAddress: walletAddress,
                    password: password
                )
                await MainActor.run {
                    self.currentUser = response.user
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func logout() {
        AdminNetworkService.shared.token = nil
        isAuthenticated = false
        currentUser = nil
    }
}
