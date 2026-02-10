import SwiftUI

@main
struct NFTArtsApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var auctionService = AuctionService.shared
    @StateObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(themeManager)
                .environmentObject(auctionService)
                .environmentObject(languageManager)
                .applyTheme(themeManager.selectedTheme)
                .id(languageManager.currentLanguage)
        }
    }
}
