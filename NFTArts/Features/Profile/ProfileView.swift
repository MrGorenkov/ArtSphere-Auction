import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var languageManager: LanguageManager
    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    profileHeader
                }

                // Wallet
                Section(L10n.wallet) {
                    HStack {
                        Image(systemName: "wallet.pass.fill")
                            .foregroundStyle(.nftPurple)
                        Text(auctionService.currentUser.formattedWallet)
                            .font(NFTTypography.subheadline)
                            .monospaced()
                        Spacer()
                        Button {
                            UIPasteboard.general.string = auctionService.currentUser.walletAddress
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                        }
                    }

                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.nftGreen)
                        Text(L10n.balance)
                            .font(NFTTypography.subheadline)
                        Spacer()
                        Text(auctionService.currentUser.formattedBalance)
                            .font(NFTTypography.bid)
                            .foregroundStyle(.nftGreen)
                    }
                }

                // Appearance
                Section(L10n.appearance) {
                    Picker(L10n.theme, selection: $themeManager.selectedTheme) {
                        ForEach(ThemeManager.AppTheme.allCases) { theme in
                            Label(themeDisplayName(theme), systemImage: theme.iconName).tag(theme)
                        }
                    }
                    Picker(L10n.language, selection: $languageManager.currentLanguage) {
                        ForEach(LanguageManager.AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                }

                // Stats
                Section(L10n.statistics) {
                    StatRow(icon: "square.grid.2x2.fill", title: L10n.ownedNFTs, value: "\(auctionService.currentUser.ownedArtworks.count)")
                    StatRow(icon: "heart.fill", title: L10n.favorites, value: "\(auctionService.currentUser.favoritedArtworks.count)")
                    StatRow(icon: "folder.fill", title: L10n.collections, value: "\(auctionService.currentUser.collections.count)")
                    StatRow(icon: "trophy.fill", title: L10n.auctionsWon, value: "\(auctionService.wonAuctions.count)")

                    let activeBids = auctionService.auctions.filter { auction in
                        auction.isActive && auction.bids.contains { $0.userId == auctionService.currentUser.id }
                    }.count
                    StatRow(icon: "gavel.fill", title: L10n.activeBids, value: "\(activeBids)")
                }

                // About
                Section(L10n.about) {
                    HStack {
                        Text(L10n.version)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(L10n.network)
                        Spacer()
                        Text("Polygon (Testnet)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.profileTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        Image(systemName: "bell.fill")
                            .overlay(alignment: .topTrailing) {
                                if !auctionService.notifications.isEmpty {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsSheet()
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(LinearGradient.nftPrimary)
                .frame(width: 60, height: 60)
                .overlay {
                    Text(String(auctionService.currentUser.displayName.prefix(1)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(auctionService.currentUser.displayName)
                    .font(NFTTypography.headline)
                Text("@\(auctionService.currentUser.username)")
                    .font(NFTTypography.subheadline)
                    .foregroundStyle(.secondary)
                Text(auctionService.currentUser.bio)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func themeDisplayName(_ theme: ThemeManager.AppTheme) -> String {
        switch theme {
        case .system: return L10n.themeSystem
        case .light: return L10n.themeLight
        case .dark: return L10n.themeDark
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.nftPurple)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @EnvironmentObject var auctionService: AuctionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if auctionService.notifications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(L10n.noNotifications)
                            .font(NFTTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(auctionService.notifications) { notification in
                        HStack(spacing: 12) {
                            Image(systemName: notification.iconName)
                                .font(.system(size: 16))
                                .foregroundStyle(notificationColor(notification))
                                .frame(width: 32, height: 32)
                                .background(notificationColor(notification).opacity(0.1))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(notification.title)
                                    .font(NFTTypography.subheadline)
                                    .fontWeight(.medium)
                                Text(notification.message)
                                    .font(NFTTypography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(notification.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(NFTTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.notifications)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
    }

    private func notificationColor(_ n: AuctionNotification) -> Color {
        switch n.type {
        case .newBid: return .nftBlue
        case .bidPlaced: return .nftPurple
        case .auctionWon: return .nftOrange
        case .auctionEnded: return .gray
        case .nftCreated: return .nftGreen
        }
    }
}
