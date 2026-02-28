import SwiftUI

struct UserDetailView: View {
    let user: AdminUser

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Avatar + name
                HStack(spacing: 16) {
                    AsyncImage(url: user.avatarUrl.flatMap { URL(string: $0) }) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(user.displayName)
                                .font(.title3)
                                .fontWeight(.bold)
                            if user.isAdmin {
                                Text("ADMIN")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.2))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(4)
                            }
                        }
                        Text("@\(user.username)")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Info rows
                DetailRow(label: "Email", value: user.email ?? "—")
                DetailRow(label: "Wallet", value: String(user.walletAddress.prefix(12)) + "...")
                DetailRow(label: "Баланс", value: String(format: "%.2f ETH", user.balance))
                DetailRow(label: "Статус", value: user.isActive ? "Активен" : "Заблокирован")
                DetailRow(label: "Артворков", value: "\(user.artworksCount)")
                DetailRow(label: "Ставок", value: "\(user.bidsCount)")
                DetailRow(label: "Регистрация", value: formatDate(user.createdAt))

                if let bio = user.bio, !bio.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(bio)
                            .font(.body)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.body)
            Spacer()
        }
    }
}
