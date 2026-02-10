import Foundation
import SwiftUI
import Combine

final class FeedViewModel: ObservableObject {
    @Published var filteredAuctions: [Auction] = []
    @Published var selectedCategory: NFTArtwork.ArtworkCategory?
    @Published var isLoading = false
    @Published var searchText = ""

    private var cancellables = Set<AnyCancellable>()

    func bind(to auctionService: AuctionService) {
        // React to auction changes + local filters
        auctionService.$auctions
            .combineLatest($selectedCategory, $searchText)
            .map { auctions, category, search in
                var result = auctions
                if let category = category {
                    result = result.filter { $0.artwork.category == category }
                }
                if !search.isEmpty {
                    result = result.filter {
                        $0.artwork.title.localizedCaseInsensitiveContains(search) ||
                        $0.artwork.artistName.localizedCaseInsensitiveContains(search)
                    }
                }
                return result
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredAuctions)
    }

    func selectCategory(_ category: NFTArtwork.ArtworkCategory?) {
        if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
        }
    }
}
