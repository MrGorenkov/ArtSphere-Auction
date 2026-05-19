import SwiftUI

/// Компактная карточка подключения TON-кошелька в Profile.
/// Отключённое состояние — кнопка «Подключить». Подключённое — адрес + реальный testnet баланс.
struct TONConnectButton: View {
    @ObservedObject private var tonConnect = TONConnectService.shared
    @State private var showConnectSheet = false
    @State private var showDisconnectConfirm = false

    var body: some View {
        Group {
            if let address = tonConnect.walletAddress {
                connectedCard(address: address)
            } else {
                connectButton
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectWalletSheet()
        }
        .confirmationDialog(
            "Отключить кошелёк?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Отключить", role: .destructive) {
                tonConnect.disconnect()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Disconnected

    private var connectButton: some View {
        Button {
            showConnectSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                Text("Подключить Tonkeeper")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color.blue, Color(red: 0.0, green: 0.5, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(14)
        }
    }

    // MARK: - Connected

    private func connectedCard(address: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.blue)
                Text("Tonkeeper подключен")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showDisconnectConfirm = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Адрес")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(address.prefix(6))…\(address.suffix(6))")
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Баланс (testnet)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if tonConnect.isLoadingBalance && tonConnect.balanceTON == nil {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(balanceText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Button {
                        Task { await tonConnect.refreshBalance() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    tonConnect.openTestnetFaucet()
                } label: {
                    Label("Получить TON", systemImage: "drop.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
                Button {
                    openExplorer(address: address)
                } label: {
                    Label("В эксплорере", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var balanceText: String {
        guard let value = tonConnect.balanceTON else { return "—" }
        return String(format: "%.3f TON", value)
    }

    private func openExplorer(address: String) {
        if let url = URL(string: "https://testnet.tonviewer.com/\(address)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Connect sheet

private struct ConnectWalletSheet: View {
    @ObservedObject private var tonConnect = TONConnectService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var showError: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    instructions
                    inputField
                    if showError, let err = tonConnect.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    connectAction
                    faucetHint
                }
                .padding(20)
            }
            .navigationTitle("Подключить кошелёк")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Используется testnet — реальных денег нет.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            stepRow(num: 1, text: "Откройте Tonkeeper и переключите сеть на Testnet (Настройки → Активные сети)")
            stepRow(num: 2, text: "Скопируйте адрес своего кошелька")
            stepRow(num: 3, text: "Вставьте его в поле ниже")
            Button {
                tonConnect.openTonkeeper()
            } label: {
                Label("Открыть Tonkeeper", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 4)
        }
    }

    private func stepRow(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num).")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.blue)
            Text(text)
                .font(.subheadline)
        }
    }

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Адрес кошелька")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                TextField("EQ... или UQ...", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.subheadline, design: .monospaced))
                Button {
                    if let str = UIPasteboard.general.string {
                        input = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var connectAction: some View {
        Button {
            showError = false
            let ok = tonConnect.connect(address: input)
            if ok {
                dismiss()
            } else {
                showError = true
            }
        } label: {
            Text("Подключить")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(input.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
        }
        .disabled(input.isEmpty)
    }

    private var faucetHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нужны тестовые TON?")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Button {
                tonConnect.openTestnetFaucet()
            } label: {
                Label("Telegram-бот @testgiver_ton_bot", systemImage: "paperplane.fill")
                    .font(.caption)
            }
        }
        .padding(.top, 12)
    }
}
