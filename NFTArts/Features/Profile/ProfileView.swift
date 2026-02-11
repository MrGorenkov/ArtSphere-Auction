import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var authManager: AuthManager
    @State private var showNotifications = false
    @State private var showEditProfile = false

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
                    if let stats = auctionService.userStats {
                        StatRow(icon: "square.grid.2x2.fill", title: L10n.ownedNFTs, value: "\(stats.ownedNFTs)")
                        StatRow(icon: "heart.fill", title: L10n.favorites, value: "\(stats.favorites)")
                        StatRow(icon: "folder.fill", title: L10n.collections, value: "\(stats.collections)")
                        StatRow(icon: "trophy.fill", title: L10n.auctionsWon, value: "\(stats.auctionsWon)")
                    } else {
                        StatRow(icon: "square.grid.2x2.fill", title: L10n.ownedNFTs, value: "\(auctionService.currentUser.ownedArtworks.count)")
                        StatRow(icon: "heart.fill", title: L10n.favorites, value: "\(auctionService.currentUser.favoritedArtworks.count)")
                        StatRow(icon: "folder.fill", title: L10n.collections, value: "\(auctionService.currentUser.collections.count)")
                        StatRow(icon: "trophy.fill", title: L10n.auctionsWon, value: "\(auctionService.wonAuctions.count)")
                    }

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

                // Account
                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                            Text(L10n.logout)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(L10n.profileTitle)
            .refreshable {
                await auctionService.refreshProfile()
                auctionService.fetchAPINotifications()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showEditProfile = true
                        } label: {
                            Image(systemName: "pencil.circle")
                        }

                        Button {
                            showNotifications = true
                        } label: {
                            Image(systemName: "bell.fill")
                                .overlay(alignment: .topTrailing) {
                                    if !auctionService.notifications.isEmpty || !auctionService.apiNotifications.isEmpty {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 4, y: -4)
                                    }
                                }
                        }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsSheet()
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet()
            }
            .onAppear {
                auctionService.fetchUserStats()
                auctionService.fetchAPINotifications()
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            AvatarView(
                avatarUrl: auctionService.currentUser.avatarUrl,
                displayName: auctionService.currentUser.displayName,
                size: 60
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(auctionService.currentUser.displayName)
                    .font(NFTTypography.headline)
                Text("@\(auctionService.currentUser.username)")
                    .font(NFTTypography.subheadline)
                    .foregroundStyle(.secondary)
                if !auctionService.currentUser.bio.isEmpty {
                    Text(auctionService.currentUser.bio)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
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

// MARK: - Avatar View

struct AvatarView: View {
    let avatarUrl: String?
    let displayName: String
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(LinearGradient.nftPrimary)
                    .overlay {
                        Text(String(displayName.prefix(1)))
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear { loadAvatar() }
        .onChange(of: avatarUrl) { _ in
            image = nil
            loadAvatar()
        }
    }

    private func loadAvatar() {
        // Try local avatar first (saved from device camera/gallery)
        if let localImage = AuctionService.loadLocalAvatarImage() {
            withAnimation(.easeIn(duration: 0.3)) { self.image = localImage }
            return
        }

        // Fall back to URL (from server/MinIO)
        guard let urlString = avatarUrl, let url = URL(string: urlString) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.3)) { self.image = uiImage }
                    }
                }
            } catch {}
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

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @EnvironmentObject var auctionService: AuctionService
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                AvatarView(
                                    avatarUrl: auctionService.currentUser.avatarUrl,
                                    displayName: auctionService.currentUser.displayName,
                                    size: 80
                                )
                            }
                            Button(L10n.changeAvatar) {
                                showImagePicker = true
                            }
                            .font(NFTTypography.caption)
                        }
                        Spacer()
                    }
                }

                Section(L10n.displayName) {
                    TextField(L10n.displayName, text: $displayName)
                }

                Section(L10n.bio) {
                    TextField(L10n.bio, text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(L10n.editProfile)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        auctionService.updateProfile(displayName: displayName, bio: bio)
                        if let image = selectedImage, let data = image.jpegData(compressionQuality: 0.8) {
                            auctionService.uploadAvatar(imageData: data)
                        }
                        dismiss()
                    }
                    .disabled(displayName.isEmpty)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onAppear {
                displayName = auctionService.currentUser.displayName
                bio = auctionService.currentUser.bio
            }
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
                let allEmpty = auctionService.notifications.isEmpty && auctionService.apiNotifications.isEmpty

                if allEmpty {
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
                    // API notifications (from server)
                    ForEach(auctionService.apiNotifications) { notification in
                        HStack(spacing: 12) {
                            Image(systemName: apiNotificationIcon(notification.type))
                                .font(.system(size: 16))
                                .foregroundStyle(apiNotificationColor(notification.type))
                                .frame(width: 32, height: 32)
                                .background(apiNotificationColor(notification.type).opacity(0.1))
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

                            if let date = ISO8601DateFormatter().date(from: notification.createdAt) {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(NFTTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .opacity(notification.isRead ? 0.6 : 1.0)
                    }

                    // Local notifications (from this session)
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

    private func apiNotificationIcon(_ type: String) -> String {
        switch type {
        case "bid": return "arrow.up.circle.fill"
        case "outbid": return "exclamationmark.arrow.circlepath"
        case "auction_won": return "trophy.fill"
        case "auction_ended": return "clock.badge.checkmark.fill"
        default: return "bell.fill"
        }
    }

    private func apiNotificationColor(_ type: String) -> Color {
        switch type {
        case "bid": return .nftBlue
        case "outbid": return .nftOrange
        case "auction_won": return .yellow
        case "auction_ended": return .gray
        default: return .nftPurple
        }
    }
}
