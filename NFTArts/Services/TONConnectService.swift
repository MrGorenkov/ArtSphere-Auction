import Foundation
import Combine
import UIKit

/// Управляет подключением TON-кошелька пользователя (testnet) и периодически
/// подтягивает реальный баланс через публичный Toncenter API.
///
/// Архитектура (pragmatic, без полного TON Connect Bridge SDK):
/// 1. Юзер открывает Tonkeeper deep-link → копирует свой testnet адрес.
/// 2. Возвращается в наше приложение → вставляет адрес в шит подключения.
/// 3. Адрес валидируется по формату и сохраняется в UserDefaults.
/// 4. Сервис подписан на периодический refresh — баланс из реальной testnet-цепочки.
///
/// Для mint NFT генерируется `ton://transfer/<contract>?...` deep-link — Tonkeeper подтверждает
/// и шлёт реальную транзакцию в testnet. Видно на `testnet.tonviewer.com`.
@MainActor
final class TONConnectService: ObservableObject {
    static let shared = TONConnectService()

    // MARK: - Published state

    @Published private(set) var walletAddress: String?
    @Published private(set) var balanceTON: Double?
    @Published private(set) var isLoadingBalance: Bool = false
    @Published private(set) var lastError: String?

    var isConnected: Bool { walletAddress != nil }

    // MARK: - Storage

    private let addressKey = "ton_wallet_address_v1"
    private let defaults = UserDefaults.standard

    // MARK: - Polling

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 30

    // MARK: - Init

    private init() {
        self.walletAddress = defaults.string(forKey: addressKey)
        if walletAddress != nil {
            startBalancePolling()
        }
    }

    // MARK: - Connect / Disconnect

    /// Открывает Tonkeeper по universal link.
    func openTonkeeper() {
        if let url = URL(string: "https://app.tonkeeper.com/") {
            UIApplication.shared.open(url)
        }
    }

    /// Бесплатные тестовые TON через Telegram-бота.
    func openTestnetFaucet() {
        if let url = URL(string: "https://t.me/testgiver_ton_bot") {
            UIApplication.shared.open(url)
        }
    }

    /// Подключает кошелёк по вставленному пользователем адресу.
    @discardableResult
    func connect(address rawInput: String) -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TONAddress.isValid(trimmed) else {
            lastError = "Некорректный адрес кошелька"
            return false
        }
        lastError = nil
        walletAddress = trimmed
        defaults.set(trimmed, forKey: addressKey)
        startBalancePolling()
        Task {
            await refreshBalance()
            await syncAddressToBackend(trimmed)
        }
        return true
    }

    func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        walletAddress = nil
        balanceTON = nil
        lastError = nil
        defaults.removeObject(forKey: addressKey)
        Task { await syncAddressToBackend(nil) }
    }

    /// Сохраняет (или сбрасывает) TON-адрес в backend — нужен для payout при выигрыше.
    private func syncAddressToBackend(_ address: String?) async {
        struct Body: Encodable { let tonWalletAddress: String? }
        do {
            try await NetworkService.shared.requestVoid(
                endpoint: "users/me/ton-wallet",
                method: .put,
                body: Body(tonWalletAddress: address)
            )
        } catch {
            // Не критично — payout не сработает, но локальный balance polling продолжится.
            print("syncAddressToBackend failed: \(error)")
        }
    }

    /// Адрес задеплоенной NFT-коллекции в TON Testnet (Tact-контракт ArtSphereCollection).
    /// Backend mint'ит NFT в этот контракт от имени owner-кошелька — юзеру TON для этого не нужны.
    static let collectionAddress = "kQAOK4YRtEimfHBDRKeM0DRN_BLTh4GyiyqqaGcHArpCF7Ji"

    // MARK: - Balance

    func refreshBalance() async {
        guard let address = walletAddress else { return }
        isLoadingBalance = true
        defer { isLoadingBalance = false }

        do {
            let nano = try await ToncenterClient.fetchBalance(address: address)
            self.balanceTON = Double(nano) / 1_000_000_000.0
        } catch {
            self.lastError = "Не удалось получить баланс: \(error.localizedDescription)"
        }
    }

    private func startBalancePolling() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshBalance()
                try? await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000))
            }
        }
    }
}

// MARK: - Address validation

enum TONAddress {
    /// User-friendly формат: EQ/UQ/kQ/0Q + base64url, ровно 48 символов.
    /// CRC16 не проверяется — Toncenter всё равно вернёт ошибку на невалидный адрес.
    static func isValid(_ address: String) -> Bool {
        guard address.count == 48 else { return false }
        let prefix = address.prefix(2)
        guard ["EQ", "UQ", "kQ", "0Q"].contains(String(prefix)) else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return address.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
