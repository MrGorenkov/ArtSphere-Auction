import SwiftUI

struct ArtworkDetailView: View {
    let initialAuction: Auction
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager

    init(auction: Auction) {
        self.initialAuction = auction
    }

    /// Always read the live auction (with up-to-date bids + currentBid) from the service
    /// so that new bids appear instantly in the bids tab after placement.
    private var auction: Auction {
        auctionService.auctions.first(where: { $0.id == initialAuction.id }) ?? initialAuction
    }
    @State private var selectedTab: DetailTab = .overview
    @State private var show3DView = false
    @State private var showFullscreen3D = false
    @State private var isFavorited = false
    @State private var showAddToCollection = false
    @State private var showComplexityOverlay = false
    @State private var heatmapBlend: Double = 0.6
    @State private var algorithm: NormalMapGenerator.FilterAlgorithm = NormalMapGenerator.defaultAlgorithm
    @State private var likeCount = 0
    @State private var isLikedByMe = false
    @State private var isLikeLoading = false
    @State private var comments: [APICommentDTO] = []
    @State private var newComment = ""
    @State private var showShareArtwork = false
    @State private var showBuyNowConfirm = false
    @State private var showBuyNowSuccess = false
    @State private var showAutoBrokerSheet = false

    enum DetailTab: CaseIterable {
        case overview
        case bids
        case comments
        case details

        var title: String {
            switch self {
            case .overview: return L10n.overview
            case .bids: return L10n.bids
            case .comments: return L10n.comments
            case .details: return L10n.details
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artworkSection
                VStack(spacing: 20) {
                    headerSection
                    socialBar
                    auctionStatusBanner
                    bidSection
                    tabSection
                    selectedTabContent
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showShareArtwork = true
                    } label: {
                        Image(systemName: "paperplane")
                    }

                    Button {
                        showAddToCollection = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }

                    Button {
                        auctionService.toggleFavorite(artworkId: auction.artwork.id)
                        isFavorited.toggle()
                    } label: {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorited ? .red : .primary)
                    }
                }
            }
        }
        .onAppear {
            isFavorited = auctionService.isFavorited(auction.artwork.id)
            auctionService.fetchBidsForAuction(auction.id)
            loadLikeStatus()
            loadComments()
        }
        .sheet(isPresented: $showAddToCollection) {
            AddToCollectionSheet(artworkId: auction.artwork.id)
        }
        .sheet(isPresented: $showShareArtwork) {
            ShareArtworkSheet(artwork: auction.artwork)
        }
        .fullScreenCover(isPresented: $showFullscreen3D) {
            FullScreen3DViewer(artwork: auction.artwork)
        }
        .alert(L10n.buyNowConfirm, isPresented: $showBuyNowConfirm) {
            Button(L10n.buyNow) {
                let result = auctionService.buyNow(auctionId: auction.id)
                if case .success = result {
                    showBuyNowSuccess = true
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.buyNowConfirmMessage(auction.artwork.title, auction.formattedBuyNowPrice ?? ""))
        }
        .alert(L10n.buyNowSuccess, isPresented: $showBuyNowSuccess) {
            Button(L10n.ok) {}
        }
        .sheet(isPresented: $showAutoBrokerSheet) {
            AutoBrokerSheet(auction: auction)
        }
    }

    // MARK: - Artwork Section

    private var artworkSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if show3DView {
                Artwork3DView(
                    artwork: auction.artwork,
                    showComplexityOverlay: showComplexityOverlay,
                    heatmapBlend: heatmapBlend,
                    algorithm: algorithm
                )
                .frame(height: 400)
                .transition(.opacity)
                .overlay(alignment: .topLeading) {
                    if showComplexityOverlay {
                        heatmapLegend
                            .padding(12)
                    }
                }
                .overlay(alignment: .bottom) {
                    if showComplexityOverlay {
                        heatmapSlider
                            .padding(.horizontal, 16)
                            .padding(.bottom, 60)
                    }
                }
            } else {
                ArtworkImageView(artwork: auction.artwork)
                    .frame(height: 400)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                // 3D toggle button
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        if show3DView {
                            show3DView = false
                            showComplexityOverlay = false
                        } else {
                            AnalyticsService.shared.track3D(artworkId: auction.artwork.id.uuidString, artworkTitle: auction.artwork.title)
                            show3DView = true
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: show3DView ? "photo" : "cube.fill")
                            .font(.system(size: 14))
                        Text(show3DView ? "2D" : "3D")
                            .font(NFTTypography.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }

                if show3DView {
                    // Heatmap toggle
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            showComplexityOverlay.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showComplexityOverlay ? "waveform.path" : "waveform.path.ecg")
                                .font(.system(size: 14))
                            Text(showComplexityOverlay ? L10n.original : L10n.heatmap)
                                .font(NFTTypography.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(showComplexityOverlay ? AnyShapeStyle(Color.red.opacity(0.6)) : AnyShapeStyle(.ultraThinMaterial))
                        .clipShape(Capsule())
                    }

                    // Algorithm picker — lets the user compare Sobel / Laplacian /
                    // Depth Anything hybrid pipelines side by side.
                    algorithmMenu
                }

            }
            .padding(16)
        }
    }

    /// Vertical color bar — explains what the heatmap colours mean. Pinned to the
    /// top-left of the 3D view while overlay is active.
    private var heatmapLegend: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [.red, .yellow, .blue],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 14, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.7), lineWidth: 0.5)
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.complexityHigh)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(L10n.complexityMid)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(L10n.complexityLow)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(height: 110)
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Bottom slider — fades between original and heatmap. Lets users dial the
    /// overlay strength instead of a binary on/off swap.
    private var heatmapSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Slider(value: $heatmapBlend, in: 0.1...1.0)
                .tint(.nftPurple)
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var algorithmMenu: some View {
        Menu {
            Picker(L10n.algorithmPicker, selection: $algorithm) {
                Text(L10n.algorithmSobel).tag(NormalMapGenerator.FilterAlgorithm.sobel)
                Text(L10n.algorithmHybrid).tag(NormalMapGenerator.FilterAlgorithm.hybrid)
                Text(L10n.algorithmPointCloud).tag(NormalMapGenerator.FilterAlgorithm.pointCloud)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 14))
                Text(algorithm.shortLabel)
                    .font(NFTTypography.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    // MARK: - Social Bar (Like + Comment count + Share)

    private var socialBar: some View {
        HStack(spacing: 20) {
            // Like button
            Button {
                toggleLike()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLikedByMe ? "heart.fill" : "heart")
                        .foregroundStyle(isLikedByMe ? .red : .secondary)
                        .font(.system(size: 18))
                    Text("\(likeCount)")
                        .font(NFTTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isLikeLoading)

            // Comment count
            Button {
                withAnimation { selectedTab = .comments }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                    Text("\(comments.count)")
                        .font(NFTTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Share button
            Button {
                showShareArtwork = true
            } label: {
                Image(systemName: "paperplane")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))
            }

            Spacer()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(auction.artwork.title)
                        .font(NFTTypography.title)

                    if let creatorId = auction.creatorId {
                        NavigationLink(destination: UserProfileView(userId: creatorId, userName: auction.artwork.artistName, avatarUrl: nil).environmentObject(auctionService)) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(.nftPurple)
                                Text(auction.artwork.artistName)
                                    .font(NFTTypography.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.nftPurple)
                            Text(auction.artwork.artistName)
                                .font(NFTTypography.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(auction.artwork.blockchain.rawValue)
                        .font(NFTTypography.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: auction.artwork.category.iconName)
                            .font(.system(size: 12))
                        Text(L10n.categoryName(auction.artwork.category))
                            .font(NFTTypography.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Text(auction.artwork.description)
                .font(NFTTypography.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: - Auction Status Banner

    @ViewBuilder
    private var auctionStatusBanner: some View {
        if auction.hasEnded {
            HStack(spacing: 12) {
                Image(systemName: auction.status == .sold ? "trophy.fill" : "clock.badge.checkmark.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(auction.status == .sold ? .yellow : .gray)

                VStack(alignment: .leading, spacing: 2) {
                    Text(auction.status == .sold ? L10n.auctionSold : L10n.auctionEnded)
                        .font(NFTTypography.headline)

                    if let winner = auction.highestBid {
                        if winner.userId == auctionService.currentUser.id {
                            Text(L10n.youWonThis)
                                .font(NFTTypography.subheadline)
                                .foregroundStyle(.nftGreen)
                        } else {
                            Text(L10n.wonBy(winner.userName, winner.formattedAmount))
                                .font(NFTTypography.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(L10n.noBidsPlaced)
                            .font(NFTTypography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(auction.status == .sold ? Color.nftOrange.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Bid Section

    private var bidSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(auction.hasEnded ? L10n.finalPrice : L10n.currentBid)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(auction.formattedCurrentBid)
                        .font(NFTTypography.price)
                        .foregroundStyle(.nftPurple)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(auction.hasEnded ? L10n.ended : L10n.endsIn)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                    if auction.hasEnded {
                        Text(L10n.closed)
                            .font(NFTTypography.timer)
                            .foregroundStyle(.secondary)
                    } else {
                        CountdownTimerView(endTime: auction.endTime)
                    }
                }

                Spacer()

                if !auction.hasEnded {
                    BidButton(auction: auction)
                }
            }

            // Buy Now button
            if auction.hasBuyNow, let price = auction.formattedBuyNowPrice {
                Button {
                    showBuyNowConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14))
                        Text("\(L10n.buyNow) — \(price)")
                            .font(NFTTypography.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [.nftOrange, .nftOrange.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Auto-broker indicator
            if !auction.hasEnded {
                if auctionService.isAutoBrokerActive(for: auction.id) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(.nftGreen)
                        Text(L10n.autoBrokerActive)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.nftGreen)
                        if let max = auctionService.autoBrokerSettings[auctionService.currentUser.id]?[auction.id] {
                            Text(String(format: "— %.2f TON", max))
                                .font(NFTTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.autoBrokerDisable) {
                            auctionService.removeAutoBroker(auctionId: auction.id)
                        }
                        .font(NFTTypography.caption)
                        .foregroundStyle(.red)
                    }
                    .padding(10)
                    .background(Color.nftGreen.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Button {
                        showAutoBrokerSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.circle")
                                .font(.system(size: 14))
                            Text(L10n.autoBrokerEnable)
                                .font(NFTTypography.caption)
                        }
                        .foregroundStyle(.nftPurple)
                    }
                }
            }
        }
        .padding(16)
        .nftCardStyle()
    }

    // MARK: - Tab Section

    private var tabSection: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(NFTTypography.caption)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? Color.nftPurple.opacity(0.1)
                                : Color.clear
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .overview:
            overviewContent
        case .bids:
            bidsContent
        case .comments:
            commentsContent
        case .details:
            detailsContent
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoRow(icon: "person.fill", title: L10n.artist, value: auction.artwork.artistName)
            InfoRow(icon: "calendar", title: L10n.created, value: auction.artwork.createdAt.formatted(date: .abbreviated, time: .omitted))
            InfoRow(icon: "tag.fill", title: L10n.category, value: L10n.categoryName(auction.artwork.category))
            // On-chain token: либо реальный ID + ссылка на эксплорер, либо "minting…"
            if let tokenId = auction.artwork.tokenId, let contract = auction.artwork.contractAddress {
                Button {
                    // Если minter дал hash mint-транзакции — открываем её напрямую,
                    // иначе fallback на адрес коллекции (вкладка Transactions в эксплорере).
                    let target = auction.artwork.explorerUrl ?? "https://testnet.tonviewer.com/\(contract)"
                    if let url = URL(string: target) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cube.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tokenId)
                                .font(NFTTypography.caption)
                                .foregroundStyle(.secondary)
                            Text("#\(tokenId) · TON Testnet")
                                .font(NFTTypography.subheadline)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            } else {
                InfoRow(icon: "cube.fill", title: L10n.tokenId, value: "—")
            }
            InfoRow(icon: "link", title: L10n.blockchain, value: auction.artwork.blockchain.rawValue)
            if !auction.isReserveMet {
                InfoRow(icon: "exclamationmark.triangle", title: L10n.reservePrice, value: L10n.reserveNotMet)
            }
        }
    }

    private var bidsContent: some View {
        VStack(spacing: 12) {
            if auction.bids.isEmpty {
                Text(L10n.noBidsYet)
                    .font(NFTTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            } else {
                // Live bid count
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.nftGreen)
                    Text(L10n.bidsCount(auction.bidCount))
                        .font(NFTTypography.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.bottom, 4)

                ForEach(auction.bids.sorted(by: { $0.timestamp > $1.timestamp })) { bid in
                    NavigationLink(destination: UserProfileView(userId: bid.userId, userName: bid.userName, avatarUrl: nil).environmentObject(auctionService)) {
                        HStack {
                            Circle()
                                .fill(bid.userId == auctionService.currentUser.id ? Color.nftPurple : Color(.tertiarySystemFill))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(String(bid.userName.prefix(1)))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(bid.userId == auctionService.currentUser.id ? .white : .primary)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(bid.userName)
                                        .font(NFTTypography.subheadline)
                                        .fontWeight(.medium)
                                    if bid.userId == auctionService.currentUser.id {
                                        Text(L10n.you)
                                            .font(NFTTypography.caption)
                                            .foregroundStyle(.nftPurple)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.nftPurple.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(bid.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(NFTTypography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(bid.formattedAmount)
                                .font(NFTTypography.bid)
                                .foregroundStyle(.nftPurple)
                        }
                    }
                    .tint(.primary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Comments Content

    private var commentsContent: some View {
        VStack(spacing: 12) {
            // Add comment input
            HStack(spacing: 10) {
                TextField(L10n.addComment, text: $newComment)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())

                Button {
                    submitComment()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.nftPurple)
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if comments.isEmpty {
                Text(L10n.noComments)
                    .font(NFTTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 30)
            } else {
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        AvatarView(avatarUrl: comment.avatarUrl, displayName: comment.userName, size: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.userName)
                                    .font(NFTTypography.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                if let date = ISO8601DateFormatter().date(from: comment.createdAt) {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(comment.text)
                                .font(NFTTypography.body)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoRow(icon: "dollarsign.circle", title: L10n.startingPrice, value: String(format: "%.2f TON", auction.startingPrice))
            if let reserve = auction.reservePrice {
                InfoRow(icon: "lock.fill", title: L10n.reservePrice, value: String(format: "%.2f TON", reserve))
            }
            if let buyNow = auction.buyNowPrice {
                InfoRow(icon: "bolt.fill", title: L10n.buyNowPrice, value: String(format: "%.2f TON", buyNow))
            }
            InfoRow(icon: "clock.fill", title: L10n.started, value: auction.startTime.formatted(date: .abbreviated, time: .shortened))
            InfoRow(icon: "clock.badge.checkmark.fill", title: L10n.ends, value: auction.endTime.formatted(date: .abbreviated, time: .shortened))
            InfoRow(icon: "number", title: L10n.totalBids, value: "\(auction.bidCount)")
            InfoRow(icon: "arrow.up.right", title: L10n.minNextBid, value: String(format: "%.2f TON", auction.minimumNextBid))
            if let score = auction.artwork.textureComplexityScore {
                InfoRow(icon: "waveform.path.ecg", title: L10n.textureComplexity, value: String(format: "%.0f%%", score * 100))
            }
        }
    }

    // MARK: - Like / Comment Actions

    private func loadLikeStatus() {
        Task {
            do {
                let status = try await NetworkService.shared.fetchLikeStatus(artworkId: auction.artwork.id.uuidString)
                await MainActor.run {
                    likeCount = status.likeCount
                    isLikedByMe = status.isLikedByMe
                }
            } catch {}
        }
    }

    private func toggleLike() {
        isLikeLoading = true
        Task {
            do {
                let status = try await NetworkService.shared.toggleLike(artworkId: auction.artwork.id.uuidString)
                await MainActor.run {
                    likeCount = status.likeCount
                    isLikedByMe = status.isLikedByMe
                    isLikeLoading = false
                }
            } catch {
                await MainActor.run { isLikeLoading = false }
            }
        }
    }

    private func loadComments() {
        Task {
            do {
                let result = try await NetworkService.shared.fetchComments(artworkId: auction.artwork.id.uuidString)
                await MainActor.run { comments = result }
            } catch {}
        }
    }

    private func submitComment() {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newComment = ""

        Task {
            do {
                let comment = try await NetworkService.shared.addComment(artworkId: auction.artwork.id.uuidString, text: text)
                await MainActor.run { comments.insert(comment, at: 0) }
            } catch {}
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.nftPurple)
                .frame(width: 24)

            Text(title)
                .font(NFTTypography.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(NFTTypography.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Auto-Broker Sheet

struct AutoBrokerSheet: View {
    let auction: Auction
    @EnvironmentObject var auctionService: AuctionService
    @Environment(\.dismiss) private var dismiss
    @State private var maxAmount = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Info
                HStack(spacing: 16) {
                    ArtworkImageView(artwork: auction.artwork)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(auction.artwork.title)
                            .font(NFTTypography.headline)
                        Text(L10n.currentBidLabel + auction.formattedCurrentBid)
                            .font(NFTTypography.subheadline)
                            .foregroundStyle(.nftPurple)
                    }
                    Spacer()
                }
                .padding()
                .nftCardStyle()

                // Explanation
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.nftPurple)
                    Text(L10n.autoBrokerDescription)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Max amount input
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.autoBrokerMaxAmount)
                        .font(NFTTypography.headline)

                    HStack {
                        TextField(String(format: "%.2f", auction.minimumNextBid * 2), text: $maxAmount)
                            .font(NFTTypography.price)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.plain)

                        Text("TON")
                            .font(NFTTypography.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(L10n.minimumBid + ": \(String(format: "%.2f TON", auction.minimumNextBid))")
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    guard let amount = Double(maxAmount), amount >= auction.minimumNextBid else { return }
                    auctionService.setAutoBroker(auctionId: auction.id, maxAmount: amount)
                    dismiss()
                } label: {
                    Text(L10n.autoBrokerEnable)
                        .font(NFTTypography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.nftPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(maxAmount.isEmpty || (Double(maxAmount) ?? 0) < auction.minimumNextBid)
            }
            .padding()
            .navigationTitle(L10n.autoBrokerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add to Collection Sheet

struct AddToCollectionSheet: View {
    let artworkId: UUID
    @EnvironmentObject var auctionService: AuctionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(auctionService.currentUser.collections) { collection in
                    let isInCollection = collection.artworkIds.contains(artworkId)
                    Button {
                        if isInCollection {
                            auctionService.removeFromCollection(collectionId: collection.id, artworkId: artworkId)
                        } else {
                            auctionService.addToCollection(collectionId: collection.id, artworkId: artworkId)
                        }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name)
                                    .font(NFTTypography.subheadline)
                                    .fontWeight(.medium)
                                Text("\(collection.artworkCount) artworks")
                                    .font(NFTTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isInCollection {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.nftGreen)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle(L10n.addToCollection)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
    }
}
