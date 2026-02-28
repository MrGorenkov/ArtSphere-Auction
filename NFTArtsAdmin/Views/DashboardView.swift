import SwiftUI

struct DashboardView: View {
    @State private var stats: DashboardStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if isLoading {
                    ProgressView("Загрузка статистики...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let stats {
                    // Stat cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(
                            title: "Пользователи",
                            value: "\(stats.totalUsers)",
                            subtitle: "Активных: \(stats.activeUsers)",
                            icon: "person.3.fill",
                            color: .blue
                        )

                        StatCard(
                            title: "Артворки",
                            value: "\(stats.totalArtworks)",
                            subtitle: "Опубликовано: \(stats.publishedArtworks)",
                            icon: "photo.artframe",
                            color: .purple
                        )

                        StatCard(
                            title: "Аукционы",
                            value: "\(stats.totalAuctions)",
                            subtitle: "Активных: \(stats.activeAuctions)",
                            icon: "hammer.fill",
                            color: .green
                        )

                        StatCard(
                            title: "Оборот",
                            value: String(format: "%.2f ETH", stats.totalRevenue),
                            subtitle: "Всего ставок: \(stats.totalBids)",
                            icon: "chart.line.uptrend.xyaxis",
                            color: .orange
                        )
                    }

                    // Auction status chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Статусы аукционов")
                            .font(.headline)

                        StatusBar(statuses: stats.auctionsByStatus)
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await loadData() }
        .refreshable { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        do {
            stats = try await AdminNetworkService.shared.fetchDashboard()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
