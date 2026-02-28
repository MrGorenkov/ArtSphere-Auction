import SwiftUI

@main
struct NFTArtsAdminApp: App {
    @StateObject private var authManager = AdminAuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(authManager)
                    .frame(minWidth: 1000, minHeight: 650)
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .frame(width: 420, height: 380)
            }
        }
        .windowStyle(.titleBar)
    }
}
