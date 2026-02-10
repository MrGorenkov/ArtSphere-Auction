import SwiftUI

@main
struct NFTArtsApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var auctionService = AuctionService.shared
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                        .task {
                            await auctionService.loadFromAPI()
                        }
                } else {
                    LoginView()
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 1.05))
                        ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: authManager.isAuthenticated)
            .environmentObject(themeManager)
            .environmentObject(auctionService)
            .environmentObject(languageManager)
            .environmentObject(authManager)
            .applyTheme(themeManager.selectedTheme)
            .id(languageManager.currentLanguage)
        }
    }
}
