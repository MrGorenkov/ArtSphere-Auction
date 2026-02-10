import Foundation
import SwiftUI

// MARK: - AuthManager

/// Observable singleton that manages authentication state for the app.
/// Views can inject it via `@EnvironmentObject` or reference `AuthManager.shared` directly.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: APIUser?
    @Published var isLoading = false
    @Published var error: String?

    private let network = NetworkService.shared

    private init() {
        // If a persisted token exists, mark as authenticated and fetch the profile.
        if network.authToken != nil {
            isAuthenticated = true
            Task { await loadProfile() }
        }
    }

    // MARK: - Login

    func login(walletAddress: String, password: String) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let response: APILoginResponse = try await network.request(
                endpoint: "auth/login",
                method: .post,
                body: APILoginRequest(walletAddress: walletAddress, password: password)
            )

            network.setAuthToken(response.token)

            await MainActor.run {
                currentUser = response.user
                isAuthenticated = true
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Register

    func register(
        username: String,
        displayName: String,
        walletAddress: String,
        password: String,
        email: String?
    ) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let body = APIRegisterRequest(
                username: username,
                displayName: displayName,
                walletAddress: walletAddress,
                password: password,
                email: email
            )

            let response: APILoginResponse = try await network.request(
                endpoint: "auth/register",
                method: .post,
                body: body
            )

            network.setAuthToken(response.token)

            await MainActor.run {
                currentUser = response.user
                isAuthenticated = true
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Load Profile

    /// Fetches the current user profile from the backend.
    /// If the request fails (e.g. expired token), the user is logged out automatically.
    func loadProfile() async {
        do {
            let user: APIUser = try await network.request(endpoint: "users/me")
            await MainActor.run {
                currentUser = user
            }
        } catch {
            await MainActor.run {
                // Token likely expired or invalid -- force logout.
                logout()
            }
        }
    }

    // MARK: - Update Profile

    /// Pushes profile changes to the backend and refreshes the local user object.
    func updateProfile(displayName: String?, bio: String?, avatarUrl: String?) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let updatedUser = try await network.updateProfile(
                displayName: displayName,
                bio: bio,
                avatarUrl: avatarUrl
            )
            await MainActor.run {
                currentUser = updatedUser
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Logout

    func logout() {
        network.setAuthToken(nil)
        isAuthenticated = false
        currentUser = nil
        error = nil
    }
}
