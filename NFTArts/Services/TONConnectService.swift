import Foundation
import Combine

final class TONConnectService: ObservableObject {
    static let shared = TONConnectService()
    
    @Published var isConnected: Bool = false
    @Published var walletAddress: String?
    
    // Временный ID сессии для TON Connect
    private let clientId = UUID().uuidString.lowercased()
    
    // URL, где лежит наш манифест (генерируется Vapor-бэкендом)
    private var manifestUrl: String {
        return "\(APIConfig.baseURL)/tonconnect-manifest.json"
    }

    /// Генерирует универсальную ссылку для открытия Tonkeeper
    func generateConnectDeepLink() -> URL? {
        // Формируем payload запроса на подключение
        let requestDict: [String: Any] = [
            "manifestUrl": manifestUrl,
            "items": [
                [
                    "name": "ton_addr"
                ]
            ]
        ]
        
        guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict),
              let requestJson = String(data: requestData, encoding: .utf8),
              let encodedRequest = requestJson.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Deep-link схема для Tonkeeper с протоколом TON Connect (v=2)
        let urlString = "tonkeeper://tc?v=2&id=\(clientId)&r=\(encodedRequest)"
        return URL(string: urlString)
    }
    
    /// Имитация обработки ответа от Tonkeeper (т.к. для полного цикла нужно поднимать SSE-соединение или Bridge)
    /// Для тестового стенда мы мокаем успешное подключение тестового кошелька после возврата из Tonkeeper
    func handleDeepLinkCallback(address: String) {
        DispatchQueue.main.async {
            self.walletAddress = address
            self.isConnected = true
        }
    }
    
    func disconnect() {
        DispatchQueue.main.async {
            self.walletAddress = nil
            self.isConnected = false
        }
    }
}