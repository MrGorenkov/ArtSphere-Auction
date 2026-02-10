import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var selectedTab: Tab = .feed
    @State private var showCreateNFT = false

    enum Tab: String, CaseIterable {
        case feed
        case explore
        case create
        case arView
        case collection
        case profile

        var iconName: String {
            switch self {
            case .feed: return "flame.fill"
            case .explore: return "magnifyingglass"
            case .create: return "plus.circle.fill"
            case .arView: return "arkit"
            case .collection: return "square.grid.2x2.fill"
            case .profile: return "person.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label(L10n.tabFeed, systemImage: Tab.feed.iconName)
                }
                .tag(Tab.feed)

            ExploreView()
                .tabItem {
                    Label(L10n.tabExplore, systemImage: Tab.explore.iconName)
                }
                .tag(Tab.explore)

            Color.clear
                .tabItem {
                    Label(L10n.tabCreate, systemImage: Tab.create.iconName)
                }
                .tag(Tab.create)

            ARContentView()
                .tabItem {
                    Label(L10n.tabAR, systemImage: Tab.arView.iconName)
                }
                .tag(Tab.arView)

            MyCollectionView()
                .tabItem {
                    Label(L10n.tabCollection, systemImage: Tab.collection.iconName)
                }
                .tag(Tab.collection)

            ProfileView()
                .tabItem {
                    Label(L10n.tabProfile, systemImage: Tab.profile.iconName)
                }
                .tag(Tab.profile)
        }
        .tint(.nftPurple)
        .onChange(of: selectedTab) { newTab in
            if newTab == .create {
                showCreateNFT = true
                selectedTab = .feed
            }
        }
        .sheet(isPresented: $showCreateNFT) {
            CreateNFTView()
        }
    }
}
