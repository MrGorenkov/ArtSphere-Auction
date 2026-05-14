import SwiftUI

@main
struct NFTArtsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var themeManager = ThemeManager()
    @ObservedObject private var auctionService = AuctionService.shared
    @StateObject private var languageManager = LanguageManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @State private var showOnboarding: Bool = !OnboardingView.hasSeenOnboarding

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                        .id(authManager.currentUser?.id ?? "none")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                        .task(id: authManager.currentUser?.id) {
                            await auctionService.loadFromAPI()
                        }
                        .onAppear {
                            // Request push notification permission after login
                            PushNotificationService.shared.requestPermission()
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
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
                    .applyTheme(themeManager.selectedTheme)
                    .id(languageManager.currentLanguage)
            }
        }
    }
}
