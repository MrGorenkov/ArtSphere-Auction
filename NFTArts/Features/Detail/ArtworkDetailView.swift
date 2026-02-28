import SwiftUI

struct ArtworkDetailView: View {
    let auction: Auction
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var selectedTab: DetailTab = .overview
    @State private var show3DView = false
    @State private var showARViewer = false
    @State private var showFullscreen3D = false
    @State private var isFavorited = false
    @State private var showAddToCollection = false
    @State private var showComplexityOverlay = false
    @State private var likeCount = 0
    @State private var isLikedByMe = false
    @State private var isLikeLoading = false
    @State private var comments: [APICommentDTO] = []
    @State private var newComment = ""
    @State private var showShareArtwork = false

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
        .fullScreenCover(isPresented: $showARViewer) {
            ARShowroomView(artwork: auction.artwork)
                .environmentObject(auctionService)
        }
    }

    // MARK: - Artwork Section

    private var artworkSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if show3DView {
                Artwork3DView(artwork: auction.artwork, showComplexityOverlay: showComplexityOverlay)
                    .frame(height: 400)
                    .transition(.opacity)
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
                }

                // AR button
                Button {
                    AnalyticsService.shared.trackAR(artworkId: auction.artwork.id.uuidString, artworkTitle: auction.artwork.title)
                    showARViewer = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arkit")
                            .font(.system(size: 14))
                        Text("AR")
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
            .padding(16)
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
                        NavigationLink(destination: UserProfileView(userId: creatorId, userName: auction.artwork.artistName, avatarUrl: nil)) {
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
                        .font(NFTTypography.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
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
            InfoRow(icon: "cube.fill", title: L10n.tokenId, value: auction.artwork.tokenId ?? "N/A")
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
                    NavigationLink(destination: UserProfileView(userId: bid.userId, userName: bid.userName, avatarUrl: nil)) {
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
            InfoRow(icon: "dollarsign.circle", title: L10n.startingPrice, value: String(format: "%.2f ETH", auction.startingPrice))
            if let reserve = auction.reservePrice {
                InfoRow(icon: "lock.fill", title: L10n.reservePrice, value: String(format: "%.2f ETH", reserve))
            }
            InfoRow(icon: "clock.fill", title: L10n.started, value: auction.startTime.formatted(date: .abbreviated, time: .shortened))
            InfoRow(icon: "clock.badge.checkmark.fill", title: L10n.ends, value: auction.endTime.formatted(date: .abbreviated, time: .shortened))
            InfoRow(icon: "number", title: L10n.totalBids, value: "\(auction.bidCount)")
            InfoRow(icon: "arrow.up.right", title: L10n.minNextBid, value: String(format: "%.2f ETH", auction.minimumNextBid))
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
