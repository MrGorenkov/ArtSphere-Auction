import SwiftUI

struct ArtworksListView: View {
    @State private var artworks: [AdminArtwork] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var filterPublished: Bool? = nil
    @State private var selectedArtwork: AdminArtwork?

    private var filteredArtworks: [AdminArtwork] {
        var result = artworks
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artistName.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let fp = filterPublished {
            result = result.filter { $0.isPublished == fp }
        }
        return result
    }

    private var styleDistribution: [String: Int] {
        var dist: [String: Int] = [:]
        for a in artworks {
            let style = a.styleName ?? "Unknown"
            dist[style, default: 0] += 1
        }
        return dist
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Артворки")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Filter
                Picker("", selection: $filterPublished) {
                    Text("Все").tag(nil as Bool?)
                    Text("Опубликованы").tag(true as Bool?)
                    Text("Скрыты").tag(false as Bool?)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Поиск по названию или художнику...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Style chart
            if !styleDistribution.isEmpty {
                StatusBar(statuses: styleDistribution)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredArtworks) { artwork in
                            ArtworkCard(artwork: artwork, onTogglePublish: {
                                togglePublish(artwork)
                            }, onDelete: {
                                deleteArtwork(artwork)
                            })
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        do {
            artworks = try await AdminNetworkService.shared.fetchArtworks()
        } catch {}
        isLoading = false
    }

    private func togglePublish(_ artwork: AdminArtwork) {
        Task {
            do {
                let update = AdminUpdateArtwork(
                    title: nil,
                    description: nil,
                    isPublished: !artwork.isPublished,
                    isForSale: nil
                )
                let updated = try await AdminNetworkService.shared.updateArtwork(id: artwork.id, update: update)
                if let idx = artworks.firstIndex(where: { $0.id == artwork.id }) {
                    artworks[idx] = updated
                }
            } catch {}
        }
    }

    private func deleteArtwork(_ artwork: AdminArtwork) {
        Task {
            do {
                try await AdminNetworkService.shared.deleteArtwork(id: artwork.id)
                artworks.removeAll { $0.id == artwork.id }
            } catch {}
        }
    }
}

struct ArtworkCard: View {
    let artwork: AdminArtwork
    let onTogglePublish: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            AsyncImage(url: artwork.imageUrl.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.purple.opacity(0.15))
                    .overlay(
                        Image(systemName: "photo.artframe")
                            .font(.title)
                            .foregroundColor(.purple.opacity(0.5))
                    )
            }
            .frame(height: 160)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(artwork.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    Circle()
                        .fill(artwork.isPublished ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }

                Text(artwork.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack {
                    if let price = artwork.price {
                        Text(String(format: "%.2f ETH", price))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    if let style = artwork.styleName {
                        Text(style)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                HStack {
                    Text("\(artwork.blockchain)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(artwork.auctionsCount) аукц.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .contextMenu {
            Button(artwork.isPublished ? "Скрыть" : "Опубликовать") {
                onTogglePublish()
            }
            Divider()
            Button("Удалить", role: .destructive) {
                onDelete()
            }
        }
    }
}
