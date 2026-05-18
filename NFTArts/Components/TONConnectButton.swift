import SwiftUI

struct TONConnectButton: View {
    @ObservedObject var tonConnect = TONConnectService.shared
    
    var body: some View {
        Group {
            if tonConnect.isConnected, let address = tonConnect.walletAddress {
                // Состояние: Подключено
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text("Tonkeeper подключен")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(address.prefix(4))...\(address.suffix(4))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        tonConnect.disconnect()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            } else {
                // Состояние: Отключено
                Button(action: {
                    if let url = tonConnect.generateConnectDeepLink() {
                        // Открываем приложение Tonkeeper
                        UIApplication.shared.open(url)
                        
                        // ИМИТАЦИЯ успешного возврата для демо (т.к. у нас нет моста SSE)
                        // В реальном приложении это ловится через .onOpenURL в App-файле
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            tonConnect.handleDeepLinkCallback(address: "EQD4_testnet_demo_address_92xP")
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "link")
                        Text("Подключить Tonkeeper")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
        }
    }
}