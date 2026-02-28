import SwiftUI

struct UsersListView: View {
    @State private var users: [AdminUser] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var selectedUser: AdminUser?

    private var filteredUsers: [AdminUser] {
        if searchText.isEmpty { return users }
        return users.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // Users table
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Пользователи")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Text("\(filteredUsers.count) из \(users.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Поиск по имени...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredUsers, selection: $selectedUser) { user in
                        UserRow(user: user)
                            .tag(user)
                            .contextMenu {
                                Button(user.isActive ? "Заблокировать" : "Разблокировать") {
                                    toggleActive(user)
                                }
                                Divider()
                                Button("Удалить", role: .destructive) {
                                    deleteUser(user)
                                }
                                .disabled(user.isAdmin)
                            }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .frame(minWidth: 500)

            // Detail panel
            if let user = selectedUser {
                UserDetailView(user: user)
                    .frame(minWidth: 300, maxWidth: 400)
            } else {
                VStack {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Выберите пользователя")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 300, maxWidth: 400, maxHeight: .infinity)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        do {
            users = try await AdminNetworkService.shared.fetchUsers()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleActive(_ user: AdminUser) {
        Task {
            do {
                let updated = try await AdminNetworkService.shared.toggleUserActive(userId: user.id)
                if let idx = users.firstIndex(where: { $0.id == user.id }) {
                    users[idx] = updated
                }
                if selectedUser?.id == user.id { selectedUser = updated }
            } catch {}
        }
    }

    private func deleteUser(_ user: AdminUser) {
        Task {
            do {
                try await AdminNetworkService.shared.deleteUser(userId: user.id)
                users.removeAll { $0.id == user.id }
                if selectedUser?.id == user.id { selectedUser = nil }
            } catch {}
        }
    }
}

struct UserRow: View {
    let user: AdminUser

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AsyncImage(url: user.avatarUrl.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .fontWeight(.medium)
                    if user.isAdmin {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f ETH", user.balance))
                    .font(.caption)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text("\(user.artworksCount) art")
                    Text("·")
                    Text("\(user.bidsCount) bids")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Circle()
                .fill(user.isActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}

extension AdminUser: Hashable {
    static func == (lhs: AdminUser, rhs: AdminUser) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
