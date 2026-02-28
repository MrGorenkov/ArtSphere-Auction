import SwiftUI

enum AdminSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case users = "Пользователи"
    case artworks = "Артворки"
    case auctions = "Аукционы"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .users: return "person.3.fill"
        case .artworks: return "photo.artframe"
        case .auctions: return "hammer.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AdminAuthManager
    @State private var selectedSection: AdminSection = .dashboard

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 28))
                        .foregroundColor(.purple)
                    Text("ArtSphere")
                        .font(.headline)
                    Text("Admin Panel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)

                Divider()

                // Menu
                List(AdminSection.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Divider()

                // User info + logout
                VStack(spacing: 8) {
                    if let user = authManager.currentUser {
                        Text(user.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: { authManager.logout() }) {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                .padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selectedSection {
            case .dashboard:
                DashboardView()
            case .users:
                UsersListView()
            case .artworks:
                ArtworksListView()
            case .auctions:
                AuctionsListView()
            }
        }
    }
}
