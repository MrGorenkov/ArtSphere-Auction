import Foundation
import SwiftUI

// MARK: - Language Manager

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @AppStorage("app_language") var currentLanguage: AppLanguage = .russian {
        didSet { objectWillChange.send() }
    }

    enum AppLanguage: String, CaseIterable, Identifiable {
        case russian = "ru"
        case english = "en"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .russian: return "Русский"
            case .english: return "English"
            }
        }

        var flagEmoji: String {
            switch self {
            case .russian: return "🇷🇺"
            case .english: return "🇬🇧"
            }
        }
    }

    private init() {}
}

// MARK: - Localized Strings

enum L10n {
    private static var lang: LanguageManager.AppLanguage {
        LanguageManager.shared.currentLanguage
    }

    private static var isRu: Bool { lang == .russian }

    // MARK: - Tabs
    static var tabFeed: String { isRu ? "Лента" : "Feed" }
    static var tabExplore: String { isRu ? "Поиск" : "Explore" }
    static var tabCreate: String { isRu ? "Создать" : "Create" }
    static var tabAR: String { isRu ? "AR Просмотр" : "AR View" }
    static var tabCollection: String { isRu ? "Коллекция" : "Collection" }
    static var tabProfile: String { isRu ? "Профиль" : "Profile" }

    // MARK: - Feed
    static var feedTitle: String { isRu ? "NFT Арт" : "NFT Arts" }
    static var featured: String { isRu ? "Популярное" : "Featured" }
    static var searchArtworks: String { isRu ? "Поиск произведений..." : "Search artworks..." }
    static var auctionWon: String { isRu ? "Аукцион выигран!" : "Auction Won!" }
    static var youWon: String { isRu ? "Вы выиграли" : "You won" }
    static var view: String { isRu ? "Открыть" : "View" }

    // MARK: - Categories
    static var digitalPainting: String { isRu ? "Цифровая живопись" : "Digital Painting" }
    static var generativeArt: String { isRu ? "Генеративное" : "Generative Art" }
    static var photography: String { isRu ? "Фотография" : "Photography" }
    static var abstract: String { isRu ? "Абстракция" : "Abstract" }
    static var pixelArt: String { isRu ? "Пиксель-арт" : "Pixel Art" }
    static var threeDArt: String { isRu ? "3D Арт" : "3D Art" }

    static func categoryName(_ cat: NFTArtwork.ArtworkCategory) -> String {
        switch cat {
        case .digitalPainting: return digitalPainting
        case .generativeArt: return generativeArt
        case .photography: return photography
        case .abstract: return abstract
        case .pixel: return pixelArt
        case .threeD: return threeDArt
        }
    }

    // MARK: - Auction / Bidding
    static var currentBid: String { isRu ? "Текущая ставка" : "Current Bid" }
    static var finalPrice: String { isRu ? "Итоговая цена" : "Final Price" }
    static var endsIn: String { isRu ? "До конца" : "Ends in" }
    static var ended: String { isRu ? "Завершён" : "Ended" }
    static var closed: String { isRu ? "Закрыт" : "Closed" }
    static var placeBid: String { isRu ? "Сделать ставку" : "Place Bid" }
    static var bidPlaced: String { isRu ? "Ставка сделана!" : "Bid Placed!" }
    static var bidFailed: String { isRu ? "Ошибка ставки" : "Bid Failed" }
    static var bidQueued: String { isRu ? "Ставка в очереди" : "Bid Queued" }
    static var pendingSync: String { isRu ? "Ожидает отправки" : "Pending sync" }
    static func pendingBidsCount(_ count: Int) -> String {
        isRu ? "\(count) ставок в очереди" : "\(count) bids pending"
    }
    static var yourBid: String { isRu ? "Ваша ставка" : "Your Bid" }
    static var minimumBid: String { isRu ? "Минимальная ставка" : "Minimum bid" }
    static var noBidsYet: String { isRu ? "Ставок пока нет" : "No bids yet" }
    static var auctionNotFound: String { isRu ? "Аукцион не найден" : "Auction not found" }
    static var auctionNoLongerActive: String { isRu ? "Аукцион больше не активен" : "Auction is no longer active" }
    static func bidMinimumError(_ amount: String) -> String {
        isRu ? "Ставка должна быть не менее \(amount) ETH" : "Bid must be at least \(amount) ETH"
    }
    static var insufficientBalance: String { isRu ? "Недостаточно средств" : "Insufficient balance" }
    static var bids: String { isRu ? "Ставки" : "Bids" }
    static var active: String { isRu ? "Активный" : "Active" }
    static var upcoming: String { isRu ? "Скоро" : "Upcoming" }
    static var sold: String { isRu ? "Продано" : "Sold" }

    static func bidsCount(_ count: Int) -> String {
        if isRu {
            let mod10 = count % 10
            let mod100 = count % 100
            if mod10 == 1 && mod100 != 11 { return "\(count) ставка" }
            if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return "\(count) ставки" }
            return "\(count) ставок"
        }
        return "\(count) bids"
    }

    // MARK: - Detail View
    static var overview: String { isRu ? "Обзор" : "Overview" }
    static var details: String { isRu ? "Детали" : "Details" }
    static var artist: String { isRu ? "Художник" : "Artist" }
    static var created: String { isRu ? "Создано" : "Created" }
    static var category: String { isRu ? "Категория" : "Category" }
    static var tokenId: String { isRu ? "Токен ID" : "Token ID" }
    static var blockchain: String { isRu ? "Блокчейн" : "Blockchain" }
    static var startingPrice: String { isRu ? "Начальная цена" : "Starting Price" }
    static var reservePrice: String { isRu ? "Резервная цена" : "Reserve Price" }
    static var started: String { isRu ? "Начало" : "Started" }
    static var ends: String { isRu ? "Окончание" : "Ends" }
    static var totalBids: String { isRu ? "Всего ставок" : "Total Bids" }
    static var minNextBid: String { isRu ? "Мин. след. ставка" : "Min Next Bid" }
    static var auctionSold: String { isRu ? "Аукцион завершён" : "Auction Sold" }
    static var auctionEnded: String { isRu ? "Аукцион завершён" : "Auction Ended" }
    static var youWonThis: String { isRu ? "Вы выиграли это произведение!" : "You won this artwork!" }
    static func wonBy(_ name: String, _ amount: String) -> String {
        isRu ? "Выиграл \(name) за \(amount)" : "Won by \(name) for \(amount)"
    }
    static var noBidsPlaced: String { isRu ? "Ставок не было" : "No bids were placed" }
    static var reserveNotMet: String { isRu ? "Резерв не достигнут" : "Not met" }
    static var addToCollection: String { isRu ? "Добавить в коллекцию" : "Add to Collection" }

    // MARK: - Explore
    static var exploreTitle: String { isRu ? "Поиск" : "Explore" }
    static var categories: String { isRu ? "Категории" : "Categories" }
    static var trending: String { isRu ? "В тренде" : "Trending" }
    static var recentActivity: String { isRu ? "Последняя активность" : "Recent Activity" }
    static var searchArtistsArtworks: String { isRu ? "Поиск произведений, художников..." : "Search artworks, artists..." }
    static func resultsCount(_ count: Int) -> String {
        isRu ? "\(count) результатов" : "\(count) results"
    }

    // MARK: - Create NFT
    static var createNFT: String { isRu ? "Создать NFT" : "Create NFT" }
    static var uploadArtwork: String { isRu ? "Загрузите произведение" : "Upload Your Artwork" }
    static var selectImageDescription: String { isRu ? "Выберите PNG или JPG для конвертации в 3D NFT" : "Select a PNG or JPG image to convert into a 3D NFT" }
    static var tapToSelect: String { isRu ? "Нажмите для выбора" : "Tap to Select Image" }
    static var changeImage: String { isRu ? "Изменить изображение" : "Change Image" }
    static var artworkDetails: String { isRu ? "Детали произведения" : "Artwork Details" }
    static var title: String { isRu ? "Название" : "Title" }
    static var enterTitle: String { isRu ? "Введите название" : "Enter artwork title" }
    static var description: String { isRu ? "Описание" : "Description" }
    static var describeArtwork: String { isRu ? "Опишите произведение" : "Describe your artwork" }
    static var startingPriceLabel: String { isRu ? "Начальная цена" : "Starting Price" }
    static func auctionDuration(_ hours: Int) -> String {
        isRu ? "Длительность аукциона: \(hours)ч" : "Auction Duration: \(hours)h"
    }
    static var preview3D: String { isRu ? "3D Превью" : "3D Preview" }
    static var convertedTo3D: String { isRu ? "Ваше произведение в формате 3D NFT" : "Your artwork converted to 3D NFT" }
    static var back: String { isRu ? "Назад" : "Back" }
    static var next: String { isRu ? "Далее" : "Next" }
    static var nftCreated: String { isRu ? "NFT создан!" : "NFT Created!" }
    static func nftLiveMessage(_ title: String) -> String {
        isRu ? "Ваше произведение \"\(title)\" выставлено на аукцион!" : "Your artwork \"\(title)\" is now live on auction!"
    }
    static var viewFeed: String { isRu ? "На ленту" : "View Feed" }
    static var cancel: String { isRu ? "Отмена" : "Cancel" }

    // MARK: - Collection
    static var myCollection: String { isRu ? "Моя коллекция" : "My Collection" }
    static var collections: String { isRu ? "Коллекции" : "Collections" }
    static var allArtworks: String { isRu ? "Все произведения" : "All Artworks" }
    static var all: String { isRu ? "Все" : "All" }
    static var noArtworksYet: String { isRu ? "Пока нет произведений" : "No Artworks Yet" }
    static var winOrCreateToStart: String { isRu ? "Выиграйте аукцион или создайте NFT,\nчтобы начать коллекцию" : "Win auctions or create your own NFTs\nto start your collection" }
    static var collectionEmpty: String { isRu ? "Эта коллекция пуста" : "This collection is empty" }
    static var newCollection: String { isRu ? "Новая коллекция" : "New Collection" }
    static var editCollection: String { isRu ? "Редактирование" : "Edit Collection" }
    static var collectionName: String { isRu ? "Название коллекции" : "Collection Name" }
    static var enterName: String { isRu ? "Введите название" : "Enter name" }
    static var descriptionOptional: String { isRu ? "Описание (необязательно)" : "Description (Optional)" }
    static var describeCollection: String { isRu ? "Опишите коллекцию" : "Describe your collection" }
    static var create: String { isRu ? "Создать" : "Create" }
    static var save: String { isRu ? "Сохранить" : "Save" }
    static var edit: String { isRu ? "Редактировать" : "Edit" }
    static var delete: String { isRu ? "Удалить" : "Delete" }
    static func containsArtworks(_ count: Int) -> String {
        isRu ? "Содержит \(count) произведений" : "Contains \(count) artworks"
    }
    static func artworksCount(_ count: Int) -> String {
        isRu ? "\(count) произведений" : "\(count) artworks"
    }

    // MARK: - AR View
    static var arTitle: String { isRu ? "AR Просмотр" : "AR View" }
    static var arViewer: String { isRu ? "AR Просмотр" : "AR Viewer" }
    static var arDescription: String { isRu ? "Просматривайте NFT в дополненной реальности.\nРазмещайте цифровое искусство в реальном мире." : "View NFT artworks in augmented reality.\nPlace digital art in your real environment." }
    static var selectArtwork: String { isRu ? "Выбрать произведение" : "Select Artwork" }
    static var launchAR: String { isRu ? "Запустить AR" : "Launch AR" }
    static var changeArtwork: String { isRu ? "Изменить произведение" : "Change Artwork" }
    static var tapToPlace: String { isRu ? "Нажмите на стену или пол для размещения" : "Tap on a wall or floor to place artwork" }
    static var rotateToInspect: String { isRu ? "Вращайте для осмотра" : "Rotate to inspect" }
    static var view3DModel: String { isRu ? "3D Модель" : "3D Model" }
    static var arShowroom: String { isRu ? "AR Шоурум" : "AR Showroom" }
    static var pinchToScale: String { isRu ? "Масштабируйте и вращайте жестами" : "Pinch to scale, rotate to turn" }
    static var tapWallOrFloor: String { isRu ? "Нажмите на стену или пол" : "Tap wall or floor to place" }
    static var placedOnWall: String { isRu ? "Размещено на стене" : "Placed on wall" }
    static var placedOnFloor: String { isRu ? "Размещено на полу" : "Placed on floor" }
    static var heatmap: String { isRu ? "Карта" : "Heatmap" }
    static var original: String { isRu ? "Оригинал" : "Original" }
    static var textureComplexity: String { isRu ? "Сложность текстуры" : "Texture Complexity" }

    // MARK: - Profile
    static var profileTitle: String { isRu ? "Профиль" : "Profile" }
    static var wallet: String { isRu ? "Кошелёк" : "Wallet" }
    static var balance: String { isRu ? "Баланс" : "Balance" }
    static var appearance: String { isRu ? "Оформление" : "Appearance" }
    static var theme: String { isRu ? "Тема" : "Theme" }
    static var language: String { isRu ? "Язык" : "Language" }
    static var statistics: String { isRu ? "Статистика" : "Statistics" }
    static var ownedNFTs: String { isRu ? "Мои NFT" : "Owned NFTs" }
    static var favorites: String { isRu ? "Избранное" : "Favorites" }
    static var auctionsWon: String { isRu ? "Выиграно аукционов" : "Auctions Won" }
    static var activeBids: String { isRu ? "Активные ставки" : "Active Bids" }
    static var about: String { isRu ? "О приложении" : "About" }
    static var version: String { isRu ? "Версия" : "Version" }
    static var network: String { isRu ? "Сеть" : "Network" }
    static var logout: String { isRu ? "Выйти" : "Logout" }

    // MARK: - Notifications
    static var notifications: String { isRu ? "Уведомления" : "Notifications" }
    static var noNotifications: String { isRu ? "Уведомлений пока нет" : "No notifications yet" }
    static var done: String { isRu ? "Готово" : "Done" }
    static var newBid: String { isRu ? "Новая ставка" : "New Bid" }
    static var ok: String { isRu ? "OK" : "OK" }
    static var you: String { isRu ? "Вы" : "You" }

    // MARK: - Wallet
    static var yourBalance: String { isRu ? "Ваш баланс:" : "Your Balance:" }

    // MARK: - Auction Status
    static func statusName(_ status: Auction.AuctionStatus) -> String {
        switch status {
        case .active: return active
        case .upcoming: return upcoming
        case .ended: return ended
        case .sold: return sold
        }
    }

    // MARK: - Profile Edit
    static var editProfile: String { isRu ? "Редактировать профиль" : "Edit Profile" }
    static var displayName: String { isRu ? "Отображаемое имя" : "Display Name" }
    static var bio: String { isRu ? "О себе" : "Bio" }
    static var changeAvatar: String { isRu ? "Изменить аватар" : "Change Avatar" }
    static var profileUpdated: String { isRu ? "Профиль обновлён" : "Profile Updated" }
    static var account: String { isRu ? "Аккаунт" : "Account" }

    // MARK: - BidButton / PlaceBidSheet
    static var currentBidLabel: String { isRu ? "Текущая: " : "Current: " }
    static var syncBids: String { isRu ? "Синхр." : "Sync" }
    static func bidConfirmation(_ amount: String, _ title: String) -> String {
        isRu ? "Ваша ставка \(amount) на \"\(title)\" размещена" : "Your bid of \(amount) has been placed on \"\(title)\""
    }

    // MARK: - CreateNFT
    static var fileFormatInfo: String { isRu ? "PNG, JPG до 50 МБ" : "PNG, JPG up to 50MB" }
    static var durationLabel: String { isRu ? "Длительность" : "Duration" }
    static func durationHoursValue(_ hours: Int) -> String {
        isRu ? "\(hours) ч." : "\(hours) hours"
    }
    static var oneHour: String { isRu ? "1 ч" : "1h" }
    static var sevenDays: String { isRu ? "7 дней" : "7 days" }

    // MARK: - AR (extended)
    static var arNotSupported: String { isRu ? "AR не поддерживается на этом устройстве" : "AR not supported on this device" }
    static var arGalleryAdd: String { isRu ? "Добавить" : "Add" }
    static var arClearAll: String { isRu ? "Очистить" : "Clear" }
    static var arTakePhoto: String { isRu ? "Фото" : "Photo" }
    static var arPhotoSaved: String { isRu ? "Сохранено в Фото" : "Saved to Photos" }
    static var arPhotoNoPermission: String { isRu ? "Нет доступа к Фото" : "No Photos access" }
    static var arDimensions: String { isRu ? "см" : "cm" }
    static var arWallMode: String { isRu ? "Стена" : "Wall" }
    static var arFloorMode: String { isRu ? "Пол" : "Floor" }
    static var arObjectSelected: String { isRu ? "Объект выбран" : "Object selected" }

    // MARK: - Notifications (AuctionService)
    static func auctionWonNotif(_ title: String, _ amount: String) -> String {
        isRu ? "Вы выиграли \"\(title)\" за \(amount)!" : "You won \"\(title)\" for \(amount)!"
    }
    static func auctionEndedSold(_ title: String, _ winner: String) -> String {
        isRu ? "\"\(title)\" продано пользователю \(winner)" : "\"\(title)\" was sold to \(winner)"
    }
    static func auctionEndedNoBids(_ title: String) -> String {
        isRu ? "\"\(title)\" — ставок не было" : "\"\(title)\" received no bids"
    }
    static func newBidNotif(_ user: String, _ amount: String, _ title: String) -> String {
        isRu ? "\(user) поставил \(amount) на \"\(title)\"" : "\(user) bid \(amount) on \"\(title)\""
    }
    static func bidPlacedNotif(_ amount: String, _ title: String) -> String {
        isRu ? "Ваша ставка \(amount) на \"\(title)\"" : "You bid \(amount) on \"\(title)\""
    }
    static func bidQueuedNotif(_ amount: String) -> String {
        isRu ? "Ставка \(amount) — синхронизируется при подключении" : "You bid \(amount) — will sync when online"
    }
    static func nftCreatedNotif(_ title: String) -> String {
        isRu ? "Ваше произведение \"\(title)\" выставлено!" : "Your artwork \"\(title)\" is now live!"
    }
    static var auctionEndedTitle: String { isRu ? "Аукцион завершён" : "Auction Ended" }
    static var nftCreatedTitle: String { isRu ? "NFT создан!" : "NFT Created!" }

    // MARK: - User Profile
    static var userArtworks: String { isRu ? "Произведения" : "Artworks" }
    static var auctionActivity: String { isRu ? "Аукционная активность" : "Auction Activity" }
    static var noRecentActivity: String { isRu ? "Нет недавней активности" : "No recent activity" }
    static var exportMetrics: String { isRu ? "Экспорт метрик" : "Export Metrics" }
    static var metricsCopied: String { isRu ? "Метрики скопированы" : "Metrics copied to clipboard" }

    // MARK: - Theme names
    static var themeSystem: String { isRu ? "Системная" : "System" }
    static var themeLight: String { isRu ? "Светлая" : "Light" }
    static var themeDark: String { isRu ? "Тёмная" : "Dark" }

    // MARK: - Messages
    static var messages: String { isRu ? "Сообщения" : "Messages" }
    static var noMessages: String { isRu ? "Нет сообщений" : "No messages yet" }
    static var typeMessage: String { isRu ? "Написать сообщение..." : "Type a message..." }
    static var send: String { isRu ? "Отправить" : "Send" }
    static var shareArtwork: String { isRu ? "Поделиться" : "Share" }
    static var sharedArtwork: String { isRu ? "Поделился произведением" : "Shared an artwork" }
    static var selectUser: String { isRu ? "Выбрать пользователя" : "Select User" }
    static var sendTo: String { isRu ? "Отправить" : "Send to" }
    static var artworkShared: String { isRu ? "Произведение отправлено!" : "Artwork shared!" }
    static var newConversation: String { isRu ? "Новый диалог" : "New Conversation" }
    static var searchUsers: String { isRu ? "Поиск пользователей..." : "Search users..." }
    static var noSearchResults: String { isRu ? "Ничего не найдено" : "No results found" }

    // MARK: - Social Interactions
    static var comments: String { isRu ? "Комментарии" : "Comments" }
    static var noComments: String { isRu ? "Пока нет комментариев" : "No comments yet" }
    static var addComment: String { isRu ? "Добавить комментарий..." : "Add a comment..." }
    static var likes: String { isRu ? "Нравится" : "Likes" }
    static var follow: String { isRu ? "Подписаться" : "Follow" }
    static var unfollow: String { isRu ? "Отписаться" : "Unfollow" }
    static var followers: String { isRu ? "Подписчики" : "Followers" }
    static var following: String { isRu ? "Подписки" : "Following" }
    static var deleteComment: String { isRu ? "Удалить комментарий" : "Delete comment" }
}
