import SwiftUI

struct MyCollectionView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var gridColumns = 2
    @State private var selectedCollection: NFTCollection?
    @State private var showCreateCollection = false
    @State private var showEditCollection = false

    private let columns2 = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    private let columns1 = [
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Collections horizontal list
                    collectionsSection

                    // Owned artworks
                    if let collection = selectedCollection {
                        collectionContent(collection)
                    } else {
                        allOwnedContent
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.myCollection)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showCreateCollection = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }

                        Button {
                            withAnimation {
                                gridColumns = gridColumns == 2 ? 1 : 2
                            }
                        } label: {
                            Image(systemName: gridColumns == 2 ? "square.grid.2x2" : "list.bullet")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateCollection) {
                CreateCollectionSheet(auctionService: auctionService)
            }
            .sheet(isPresented: $showEditCollection) {
                if let collection = selectedCollection {
                    EditCollectionSheet(
                        auctionService: auctionService,
                        collection: collection
                    )
                }
            }
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.collections)
                .font(NFTTypography.title2)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // "All" chip
                    CollectionChip(
                        name: L10n.all,
                        count: auctionService.currentUser.ownedArtworks.count,
                        isSelected: selectedCollection == nil
                    ) {
                        withAnimation { selectedCollection = nil }
                    }

                    ForEach(auctionService.currentUser.collections) { collection in
                        CollectionChip(
                            name: collection.name,
                            count: collection.artworkCount,
                            isSelected: selectedCollection?.id == collection.id
                        ) {
                            withAnimation {
                                selectedCollection = selectedCollection?.id == collection.id ? nil : collection
                            }
                        }
                        .contextMenu {
                            if !collection.isDefault {
                                Button {
                                    selectedCollection = collection
                                    showEditCollection = true
                                } label: {
                                    Label(L10n.edit, systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    auctionService.deleteCollection(id: collection.id)
                                    if selectedCollection?.id == collection.id {
                                        selectedCollection = nil
                                    }
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Collection Content

    private func collectionContent(_ collection: NFTCollection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(NFTTypography.title2)
                    if !collection.description.isEmpty {
                        Text(collection.description)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !collection.isDefault {
                    Button {
                        showEditCollection = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.nftPurple)
                    }
                }
            }
            .padding(.horizontal)

            let artworks = collection.artworkIds.compactMap { artworkId in
                auctionService.auctions.first { $0.artwork.id == artworkId }
            }

            if artworks.isEmpty {
                emptyCollectionState
            } else {
                artworkGrid(auctions: artworks)
            }
        }
    }

    private var allOwnedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.allArtworks)
                .font(NFTTypography.title2)
                .padding(.horizontal)

            let ownedAuctions = auctionService.currentUser.ownedArtworks.compactMap { artworkId in
                auctionService.auctions.first { $0.artwork.id == artworkId }
            }

            if ownedAuctions.isEmpty {
                emptyState
            } else {
                artworkGrid(auctions: ownedAuctions)
            }
        }
    }

    private func artworkGrid(auctions: [Auction]) -> some View {
        LazyVGrid(columns: gridColumns == 2 ? columns2 : columns1, spacing: 12) {
            ForEach(auctions) { auction in
                NavigationLink {
                    ArtworkDetailView(auction: auction)
                } label: {
                    CollectionItem(auction: auction, isWide: gridColumns == 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text(L10n.noArtworksYet)
                    .font(NFTTypography.title2)

                Text(L10n.winOrCreateToStart)
                    .font(NFTTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 60)
        }
        .padding()
    }

    private var emptyCollectionState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(L10n.collectionEmpty)
                .font(NFTTypography.body)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Collection Chip

struct CollectionChip: View {
    let name: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name)
                    .font(NFTTypography.caption)
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(NFTTypography.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color(.quaternarySystemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.nftPurple : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Collection Item

struct CollectionItem: View {
    let auction: Auction
    var isWide: Bool = false

    var body: some View {
        if isWide {
            wideLayout
        } else {
            compactLayout
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkImageView(artwork: auction.artwork)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(auction.artwork.title)
                .font(NFTTypography.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack {
                Text(auction.formattedCurrentBid)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.nftPurple)

                Spacer()

                if auction.status == .sold {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.nftGreen)
                }
            }
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 16) {
            ArtworkImageView(artwork: auction.artwork)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(auction.artwork.title)
                    .font(NFTTypography.headline)
                    .lineLimit(1)

                Text(auction.artwork.artistName)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(auction.formattedCurrentBid)
                        .font(NFTTypography.bid)
                        .foregroundStyle(.nftPurple)

                    Spacer()

                    Text(L10n.categoryName(auction.artwork.category))
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .nftCardStyle()
    }
}

// MARK: - Create Collection Sheet

struct CreateCollectionSheet: View {
    let auctionService: AuctionService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.collectionName) {
                    TextField(L10n.enterName, text: $name)
                }
                Section(L10n.descriptionOptional) {
                    TextField(L10n.describeCollection, text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L10n.newCollection)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.create) {
                        _ = auctionService.createCollection(name: name, description: description)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Collection Sheet

struct EditCollectionSheet: View {
    let auctionService: AuctionService
    let collection: NFTCollection
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String

    init(auctionService: AuctionService, collection: NFTCollection) {
        self.auctionService = auctionService
        self.collection = collection
        _name = State(initialValue: collection.name)
        _description = State(initialValue: collection.description)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.collectionName) {
                    TextField(L10n.enterName, text: $name)
                }
                Section(L10n.description) {
                    TextField(L10n.describeCollection, text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text(L10n.containsArtworks(collection.artworkCount))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.editCollection)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        auctionService.updateCollection(id: collection.id, name: name, description: description)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
