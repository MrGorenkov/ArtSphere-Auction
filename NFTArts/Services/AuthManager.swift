import Foundation
import SwiftUI

// MARK: - AuthManager

/// Observable singleton that manages authentication state for the app.
/// Views can inject it via `@EnvironmentObject` or reference `AuthManager.shared` directly.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private var _isAuthenticated = false
    var isAuthenticated: Bool {
        _isAuthenticated && currentUser != nil
    }
    @Published var currentUser: APIUser?
    @Published var isLoading = false
    @Published var error: String?

    private let network = NetworkService.shared
    private let analytics = AnalyticsService.shared

    private init() {
        // If a persisted token exists, fetch the profile (which will set authenticated state)
        if network.authToken != nil {
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
                _isAuthenticated = true
                isLoading = false
                analytics.setUserId(response.user.id)
                analytics.track(.login, parameters: ["wallet": walletAddress])
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
                _isAuthenticated = true
                isLoading = false
                analytics.setUserId(response.user.id)
                analytics.track(.register, parameters: ["username": username])
            }
        } catch {
            await MainActor.run {
                // Provide user-friendly localized error messages
                let errorMessage: String
                let description = error.localizedDescription.lowercased()

                if description.contains("username") && description.contains("already") {
                    errorMessage = LanguageManager.shared.currentLanguage == .russian
                        ? "Это имя пользователя уже занято"
                        : "This username is already taken"
                } else if description.contains("wallet") && description.contains("already") {
                    errorMessage = LanguageManager.shared.currentLanguage == .russian
                        ? "Этот адрес кошелька уже зарегистрирован"
                        : "This wallet address is already registered"
                } else if description.contains("username or wallet") && description.contains("already") {
                    errorMessage = LanguageManager.shared.currentLanguage == .russian
                        ? "Имя пользователя или адрес кошелька уже зарегистрированы"
                        : "Username or wallet address is already registered"
                } else {
                    errorMessage = error.localizedDescription
                }

                self.error = errorMessage
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
                _isAuthenticated = true
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
        analytics.track(.logout)
        network.setAuthToken(nil)
        _isAuthenticated = false
        currentUser = nil
        error = nil
    }
}
