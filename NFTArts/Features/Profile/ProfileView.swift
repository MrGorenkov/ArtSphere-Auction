import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var authManager: AuthManager
    @State private var showNotifications = false
    @State private var showEditProfile = false
    @State private var progress: APIUserProgress?

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Игровой баланс")
                                .font(NFTTypography.subheadline)
                            Text("используется для ставок в аукционе")
                                .font(NFTTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(auctionService.currentUser.formattedBalance)
                            .font(NFTTypography.bid)
                            .foregroundStyle(.nftGreen)
                    }

                    // Реальный кошелёк (testnet) — отдельно, с реальным балансом из Toncenter.
                    // При выигрыше аукциона на этот адрес уходит реальная TON-транзакция.
                    TONConnectButton()
                        .padding(.vertical, 4)
                }

                // Rewards / Progress
                Section("Прогресс") {
                    if let p = progress {
                        RewardsCard(progress: p, onClaim: { Task { await claimDaily() } })
                    } else {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("Загрузка прогресса…")
                                .font(NFTTypography.caption)
                                .foregroundStyle(.secondary)
                        }
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

                    NavigationLink {
                        AuctionHistoryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.nftPurple)
                                .frame(width: 24)
                            Text(L10n.auctionHistory)
                                .font(NFTTypography.subheadline)
                        }
                    }
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
                        Text("TON Testnet")
                            .foregroundStyle(.secondary)
                    }
                }

                // Quick Account Switcher (for testing)
                Section(L10n.switchAccount) {
                    ForEach(Self.testAccounts, id: \.wallet) { account in
                        let isCurrent = authManager.currentUser?.walletAddress == account.wallet
                        Button {
                            if !isCurrent {
                                switchAccount(wallet: account.wallet)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(isCurrent ? Color.nftPurple : Color(.tertiarySystemFill))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Text(String(account.name.prefix(1)))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isCurrent ? .white : .primary)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(NFTTypography.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(String(account.wallet.prefix(10)) + "...")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.nftPurple)
                                }
                            }
                        }
                        .disabled(isCurrent)
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
                await loadProgress()
            }
            .task { await loadProgress() }
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
                size: 60,
                isCurrentUser: true,
                userId: auctionService.currentUser.id
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

    private static let testAccounts: [(name: String, wallet: String)] = [
        ("Алексей Горенков", "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD01"),
        ("Иван Артов", "0x8ba1f109551bD432803012645Ac136ddd64DBA72"),
        ("Анна Крипто", "0x2546BcD3c84621e976D8185a91A922aE77ECEc30"),
        ("Сергей Блокчейнов", "0xbDA5747bFD65F08deb54cb465eB87D40e51B197E"),
        ("Мария Пиксель", "0xdD2FD4581271e230360230F9337D5c0430Bf44C0"),
        ("Дмитрий Фотонов", "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"),
        ("Елена Абстрактная", "0xde9be858da4a475276426320D5e9262eCfc3d0CB"),
    ]

    private func switchAccount(wallet: String) {
        Task {
            await authManager.login(walletAddress: wallet, password: "password123")
        }
    }

    // MARK: - Rewards loading

    private func loadProgress() async {
        do {
            progress = try await NetworkService.shared.fetchProgress()
        } catch {
            print("loadProgress failed: \(error)")
        }
    }

    private func claimDaily() async {
        do {
            progress = try await NetworkService.shared.claimDaily()
            HapticService.medium()
            await auctionService.refreshProfile() // обновить balance в шапке
        } catch {
            HapticService.warning()
        }
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
    var isCurrentUser: Bool = false
    var userId: UUID? = nil

    @State private var image: UIImage?
    @State private var loadedForUserId: UUID?

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
        .onChange(of: userId) { _ in
            image = nil
            loadAvatar()
        }
    }

    private func loadAvatar() {
        let currentUserId = userId ?? (isCurrentUser ? AuctionService.shared.currentUser.id : nil)

        // Only load local avatar for the current user
        if isCurrentUser, let uid = currentUserId {
            let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("user_avatar_\(uid.uuidString).jpg")
            if FileManager.default.fileExists(atPath: path.path),
               let data = try? Data(contentsOf: path),
               let localImage = UIImage(data: data) {
                loadedForUserId = uid
                withAnimation(.easeIn(duration: 0.3)) { self.image = localImage }
                return
            }
        }

        // Load from URL: либо реальная аватарка из MinIO, либо сгенерированный identicon
        // по displayName (DiceBear) — даёт уникальную картинку каждому юзеру без аплоада.
        let urlString = avatarUrl ?? Self.defaultIdenticonURL(for: displayName)
        guard let url = URL(string: urlString) else { return }
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

    /// Детерминированная аватарка по seed. DiceBear identicon — генерирует геометрический
    /// аватар уникальный для каждого имени. Хешированный URL гарантирует кэш на CDN.
    static func defaultIdenticonURL(for seed: String) -> String {
        let escaped = seed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? seed
        return "https://api.dicebear.com/7.x/identicon/png?seed=\(escaped)&size=256"
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
                                    size: 80,
                                    isCurrentUser: true,
                                    userId: auctionService.currentUser.id
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
// MARK: - Rewards card

/// Карточка прогресса: уровень + объём + прогресс-бар до следующего уровня,
/// кнопка daily-bonus + строка про creator-милстоуны.
struct RewardsCard: View {
    let progress: APIUserProgress
    let onClaim: () -> Void

    private var levelIcon: String {
        switch progress.level {
        case "silver":   return "medal.fill"
        case "gold":     return "trophy.fill"
        case "diamond":  return "diamond.fill"
        case "legend":   return "crown.fill"
        default:         return "shield.fill"
        }
    }
    private var levelTitle: String {
        switch progress.level {
        case "silver":   return "Silver"
        case "gold":     return "Gold"
        case "diamond":  return "Diamond"
        case "legend":   return "Legend"
        default:         return "Bronze"
        }
    }
    private var levelColor: Color {
        switch progress.level {
        case "silver":   return Color(red: 0.75, green: 0.75, blue: 0.78)
        case "gold":     return Color(red: 0.95, green: 0.78, blue: 0.20)
        case "diamond":  return Color(red: 0.45, green: 0.85, blue: 0.95)
        case "legend":   return Color(red: 0.80, green: 0.35, blue: 0.95)
        default:         return Color(red: 0.70, green: 0.45, blue: 0.20)
        }
    }
    private var progressFraction: Double {
        guard let nextAt = progress.nextLevelAt, nextAt > 0 else { return 1.0 }
        return min(progress.totalVolumeTraded / nextAt, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Уровень
            HStack(spacing: 10) {
                Image(systemName: levelIcon).font(.title3).foregroundStyle(levelColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(levelTitle)
                        .font(NFTTypography.headline).foregroundStyle(levelColor)
                    Text(String(format: "Cashback %.0f%% с каждой ставки", progress.cashbackPct * 100))
                        .font(NFTTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Volume + прогресс
            if let nextAt = progress.nextLevelAt, let nextLevel = progress.nextLevel, let reward = progress.nextLevelReward {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: "%.1f / %.0f TON", progress.totalVolumeTraded, nextAt))
                            .font(NFTTypography.caption)
                        Spacer()
                        Text("до \(nextLevel.capitalized) (+\(Int(reward)) TON)")
                            .font(NFTTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progressFraction)
                        .tint(levelColor)
                }
            } else {
                Text("Максимальный уровень 🏆")
                    .font(NFTTypography.caption).foregroundStyle(.secondary)
            }

            Divider()

            // Daily bonus
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(.nftGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ежедневный бонус").font(NFTTypography.subheadline)
                    Text("+5 TON / день").font(NFTTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClaim) {
                    Text(progress.dailyAvailable ? "Забрать" : "Получено")
                        .font(NFTTypography.caption).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(progress.dailyAvailable ? Color.nftGreen : Color.gray.opacity(0.4), in: Capsule())
                }
                .buttonStyle(.borderless)
                .disabled(!progress.dailyAvailable)
            }

            Divider()

            // Creator milestones
            HStack {
                Image(systemName: "paintpalette.fill").foregroundStyle(.nftOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Создано работ: \(progress.totalMints)").font(NFTTypography.subheadline)
                    if let milestone = progress.nextMilestone {
                        Text("До \(milestone) — \(milestone - progress.totalMints) работ").font(NFTTypography.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Все milestone выполнены 🎨").font(NFTTypography.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}
