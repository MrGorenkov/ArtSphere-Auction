import SwiftUI

struct CountdownTimerView: View {
    let endTime: Date
    var compact: Bool = false

    @State private var timeRemaining: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if compact {
                compactView
            } else {
                fullView
            }
        }
        .onAppear {
            updateTime()
        }
        .onReceive(timer) { _ in
            updateTime()
        }
    }

    private var compactView: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 10))
            Text(formattedTime)
                .font(NFTTypography.timer)
        }
        .foregroundStyle(urgencyColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .nftGlassStyle()
    }

    private var fullView: some View {
        HStack(spacing: 2) {
            if timeRemaining <= 0 {
                Text(L10n.ended)
                    .font(NFTTypography.timer)
                    .foregroundStyle(.secondary)
            } else {
                Text(formattedTime)
                    .font(NFTTypography.timer)
                    .foregroundStyle(urgencyColor)
            }
        }
    }

    private var formattedTime: String {
        guard timeRemaining > 0 else { return "00:00:00" }

        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60

        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var urgencyColor: Color {
        if timeRemaining <= 300 { return .red }
        if timeRemaining <= 3600 { return .nftOrange }
        return .nftGreen
    }

    private func updateTime() {
        timeRemaining = max(endTime.timeIntervalSince(Date()), 0)
    }
}
