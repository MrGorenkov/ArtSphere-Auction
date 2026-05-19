import Foundation

/// Сериализует выполнение авто-брокера на уровне отдельного аукциона.
/// Несколько одновременных placeBid/setAutoBroker могут породить параллельные Task,
/// которые без сериализации читают одно и то же значение currentBid и сохраняют
/// дубликаты ставок. Используется chain-pattern: каждая новая работа ждёт окончания
/// предыдущей цепочки для того же auctionId, поэтому в любой момент по конкретному
/// аукциону выполняется не более одного прохода.
actor AutoBrokerSerializer {
    static let shared = AutoBrokerSerializer()

    private var chains: [UUID: Task<Void, Never>] = [:]

    /// Поставить проход авто-брокера в очередь и дождаться его завершения.
    func run(auctionId: UUID, work: @escaping @Sendable () async -> Void) async {
        let previous = chains[auctionId]
        let task = Task { @Sendable in
            await previous?.value
            await work()
        }
        chains[auctionId] = task
        await task.value
    }
}
