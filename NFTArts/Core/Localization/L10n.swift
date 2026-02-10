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
    static var yourBid: String { isRu ? "Ваша ставка" : "Your Bid" }
    static var minimumBid: String { isRu ? "Минимальная ставка" : "Minimum bid" }
    static var noBidsYet: String { isRu ? "Ставок пока нет" : "No bids yet" }
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
    static var tapToPlace: String { isRu ? "Нажмите на поверхность для размещения" : "Tap on a surface to place artwork" }

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

    // MARK: - Theme names
    static var themeSystem: String { isRu ? "Системная" : "System" }
    static var themeLight: String { isRu ? "Светлая" : "Light" }
    static var themeDark: String { isRu ? "Тёмная" : "Dark" }
}
