import SwiftUI

// MARK: - Conversations List

struct MessagesView: View {
    @EnvironmentObject var auctionService: AuctionService
    @State private var conversations: [APIConversation] = []
    @State private var isLoading = false
    @State private var showNewConversation = false
    @State private var selectedChatUser: APIUser?
    @State private var navigateToChat = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && conversations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(L10n.noMessages)
                            .font(NFTTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(conversations) { conv in
                        NavigationLink {
                            ChatView(userId: conv.userId, userName: conv.userName, avatarUrl: conv.avatarUrl)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(avatarUrl: conv.avatarUrl, displayName: conv.userName, size: 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(conv.userName)
                                            .font(NFTTypography.subheadline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        if let date = ISO8601DateFormatter().date(from: conv.lastMessageDate) {
                                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                                .font(NFTTypography.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    HStack {
                                        Text(conv.lastMessage)
                                            .font(NFTTypography.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        if conv.unreadCount > 0 {
                                            Text("\(conv.unreadCount)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.nftPurple)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.messages)
            .refreshable { await loadConversations() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showNewConversation) {
                NewConversationSheet(onSelectUser: { user in
                    selectedChatUser = user
                    showNewConversation = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigateToChat = true
                    }
                })
            }
            .navigationDestination(isPresented: $navigateToChat) {
                if let user = selectedChatUser {
                    ChatView(userId: user.id, userName: user.displayName, avatarUrl: user.avatarUrl)
                }
            }
            .task { await loadConversations() }
        }
    }

    private func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await NetworkService.shared.fetchConversations()
        } catch {}
    }
}

// MARK: - Chat View

struct ChatView: View {
    let userId: String
    let userName: String
    let avatarUrl: String?

    @EnvironmentObject var auctionService: AuctionService
    @State private var messages: [APIMessage] = []
    @State private var messageText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            MessageBubble(
                                message: msg,
                                isMe: msg.senderId == auctionService.currentUser.id.uuidString
                            )
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField(L10n.typeMessage, text: $messageText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.nftPurple)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle(userName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMessages() }
    }

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await NetworkService.shared.fetchMessages(userId: userId)
        } catch {}
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        Task {
            do {
                let sent = try await NetworkService.shared.sendMessage(
                    request: APISendMessageRequest(receiverId: userId, artworkId: nil, text: text)
                )
                await MainActor.run { messages.append(sent) }
            } catch {}
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: APIMessage
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                // Shared artwork card
                if let artworkTitle = message.artworkTitle {
                    SharedArtworkCard(
                        title: artworkTitle,
                        imageUrl: message.artworkImageUrl
                    )
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(NFTTypography.body)
                        .foregroundStyle(isMe ? .white : .primary)
                }

                if let date = ISO8601DateFormatter().date(from: message.createdAt) {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(isMe ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isMe ? Color.nftPurple : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isMe { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Shared Artwork Card

struct SharedArtworkCard: View {
    let title: String
    let imageUrl: String?

    var body: some View {
        HStack(spacing: 10) {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.tertiarySystemFill)
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.sharedArtwork)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - New Conversation Sheet

struct NewConversationSheet: View {
    var onSelectUser: (APIUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var following: [APIUser] = []
    @State private var searchResults: [APIUser] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var displayedUsers: [APIUser] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? following : searchResults
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.searchUsers, text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                // User list
                if isLoading && following.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if isSearching {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if displayedUsers.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "person.2.slash" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? L10n.noRecentActivity : L10n.noSearchResults)
                            .font(NFTTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(displayedUsers, id: \.id) { user in
                        Button {
                            onSelectUser(user)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(avatarUrl: user.avatarUrl, displayName: user.displayName, size: 40)
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                        .font(NFTTypography.subheadline)
                                        .fontWeight(.medium)
                                    Text("@\(user.username)")
                                        .font(NFTTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L10n.newConversation)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
            .task {
                isLoading = true
                defer { isLoading = false }
                do { following = try await NetworkService.shared.fetchFollowing() } catch {}
            }
            .onChange(of: searchText) { newValue in
                searchTask?.cancel()
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    searchResults = []
                    isSearching = false
                    return
                }
                isSearching = true
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard !Task.isCancelled else { return }
                    do {
                        let results = try await NetworkService.shared.searchUsers(query: query)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            searchResults = results
                            isSearching = false
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        await MainActor.run { isSearching = false }
                    }
                }
            }
        }
    }
}

// MARK: - Share Artwork Sheet

struct ShareArtworkSheet: View {
    let artwork: NFTArtwork
    @Environment(\.dismiss) private var dismiss
    @State private var following: [APIUser] = []
    @State private var searchResults: [APIUser] = []
    @State private var searchText = ""
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var searchTask: Task<Void, Never>?

    private var displayedUsers: [APIUser] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? following : searchResults
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Artwork preview (NFT card)
                HStack(spacing: 12) {
                    ArtworkImageView(artwork: artwork)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(artwork.title)
                            .font(NFTTypography.subheadline)
                            .fontWeight(.semibold)
                        Text(artwork.artistName)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()

                TextField(L10n.typeMessage, text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.searchUsers, text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Users list
                if isLoading || isSearching {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if displayedUsers.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "person.2.slash" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? L10n.noRecentActivity : L10n.noSearchResults)
                            .font(NFTTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(displayedUsers, id: \.id) { user in
                        Button {
                            shareToUser(user)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(avatarUrl: user.avatarUrl, displayName: user.displayName, size: 36)
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                        .font(NFTTypography.subheadline)
                                        .fontWeight(.medium)
                                    Text("@\(user.username)")
                                        .font(NFTTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(.nftPurple)
                            }
                        }
                        .tint(.primary)
                        .disabled(isSending)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L10n.shareArtwork)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
            .alert(L10n.artworkShared, isPresented: $showSuccess) {
                Button(L10n.ok) { dismiss() }
            }
            .task {
                isLoading = true
                defer { isLoading = false }
                do { following = try await NetworkService.shared.fetchFollowing() } catch {}
            }
            .onChange(of: searchText) { newValue in
                searchTask?.cancel()
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    searchResults = []
                    isSearching = false
                    return
                }
                isSearching = true
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    do {
                        let results = try await NetworkService.shared.searchUsers(query: query)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            searchResults = results
                            isSearching = false
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        await MainActor.run { isSearching = false }
                    }
                }
            }
        }
    }

    private func shareToUser(_ user: APIUser) {
        isSending = true
        Task {
            do {
                _ = try await NetworkService.shared.sendMessage(
                    request: APISendMessageRequest(
                        receiverId: user.id,
                        artworkId: artwork.id.uuidString,
                        text: messageText
                    )
                )
                await MainActor.run {
                    isSending = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run { isSending = false }
            }
        }
    }
}
