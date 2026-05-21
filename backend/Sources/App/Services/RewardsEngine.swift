import Foundation
import Fluent

/// Единая точка для всех бонусов: buyer-уровни (volume tier), creator (mint milestones),
/// daily, royalty при finalize. Хуки вызываются из BidController / NFTTokenController /
/// AdminController.finalizeAuction.
enum RewardsEngine {

    // MARK: - Buyer tiers (volume-based)

    enum UserLevel: String, CaseIterable {
        case bronze, silver, gold, diamond, legend

        /// Минимальный объём для уровня.
        var threshold: Double {
            switch self {
            case .bronze:  return 0
            case .silver:  return 50
            case .gold:    return 200
            case .diamond: return 500
            case .legend:  return 1000
            }
        }
        /// Бонус при достижении (one-time).
        var rewardOnReach: Double {
            switch self {
            case .bronze:  return 0
            case .silver:  return 15
            case .gold:    return 40
            case .diamond: return 80
            case .legend:  return 200
            }
        }
        /// Cashback при placeBid: % от amount возвращается на balance мгновенно.
        var cashbackPct: Double {
            switch self {
            case .bronze:  return 0
            case .silver:  return 0.01
            case .gold:    return 0.02
            case .diamond: return 0.03
            case .legend:  return 0.05
            }
        }

        static func from(volume: Double) -> UserLevel {
            allCases.reversed().first { volume >= $0.threshold } ?? .bronze
        }
        var next: UserLevel? {
            guard let i = Self.allCases.firstIndex(of: self), i + 1 < Self.allCases.count else { return nil }
            return Self.allCases[i + 1]
        }
    }

    // MARK: - Creator milestones (mint-based)

    /// Возвращает бонус за конкретный новый mint:
    /// - 1й mint = +20 (welcome)
    /// - последующие = +10
    /// - milestone-достижения (5/15/30) — отдельным бонусом сверху
    static func mintReward(newTotalMints: Int) -> Double {
        var reward: Double = (newTotalMints == 1) ? 20 : 10
        switch newTotalMints {
        case 5:  reward += 30
        case 15: reward += 100
        case 30: reward += 250
        default: break
        }
        return reward
    }

    // MARK: - Hooks

    /// Обновляет volume и применяет cashback + level-up бонус.
    /// Возвращает суммарную сумму, добавленную к balance (для логов/UI).
    @discardableResult
    static func onBidPlaced(user: UserModel, amount: Double, on db: Database) async throws -> Double {
        let prevLevel = UserLevel.from(volume: user.totalVolumeTraded)
        user.totalVolumeTraded += amount

        let cashback = amount * prevLevel.cashbackPct
        user.balance += cashback

        // Level-up?
        let newLevel = UserLevel.from(volume: user.totalVolumeTraded)
        var levelUpBonus: Double = 0
        if newLevel != prevLevel {
            // Может перескочить через несколько уровней одной ставкой — суммируем все.
            for lvl in UserLevel.allCases where lvl.threshold > prevLevel.threshold && lvl.threshold <= newLevel.threshold {
                levelUpBonus += lvl.rewardOnReach
            }
            user.balance += levelUpBonus
        }
        try await user.save(on: db)
        return cashback + levelUpBonus
    }

    /// Начисляет creator-бонус за mint. Вызывается из NFTTokenController после успешного minter.
    @discardableResult
    static func onMint(user: UserModel, on db: Database) async throws -> Double {
        user.totalMints += 1
        let bonus = mintReward(newTotalMints: user.totalMints)
        user.balance += bonus
        try await user.save(on: db)
        return bonus
    }

    /// 5% royalty продавцу сверху winning bid. Вызывается из finalizeAuction.
    static func onSaleRoyalty(seller: UserModel, winningBid: Double, on db: Database) async throws -> Double {
        let royalty = winningBid * 0.05
        seller.balance += royalty
        try await seller.save(on: db)
        return royalty
    }

    // MARK: - Daily

    /// Возвращает true если бонус начислен (бонус +5 за каждый календарный день).
    @discardableResult
    static func tryClaimDaily(user: UserModel, on db: Database) async throws -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        if let last = user.lastDailyClaim, calendar.isDate(last, inSameDayAs: now) {
            return false
        }
        user.balance += 5
        user.lastDailyClaim = now
        try await user.save(on: db)
        return true
    }
}
