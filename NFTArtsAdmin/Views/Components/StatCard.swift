import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct StatusBar: View {
    let statuses: [String: Int]

    private var sortedStatuses: [(String, Int)] {
        let order = ["active", "upcoming", "ended", "sold"]
        return statuses.sorted { a, b in
            let ia = order.firstIndex(of: a.key) ?? 99
            let ib = order.firstIndex(of: b.key) ?? 99
            return ia < ib
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "active": return .green
        case "upcoming": return .blue
        case "ended": return .orange
        case "sold": return .purple
        default: return .gray
        }
    }

    private var total: Int {
        statuses.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(sortedStatuses, id: \.0) { status, count in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color(for: status))
                            .frame(width: max(geo.size.width * CGFloat(count) / max(CGFloat(total), 1) - 2, 4))
                    }
                }
            }
            .frame(height: 24)

            HStack(spacing: 16) {
                ForEach(sortedStatuses, id: \.0) { status, count in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color(for: status))
                            .frame(width: 8, height: 8)
                        Text("\(status): \(count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status {
        case "active": return .green
        case "upcoming": return .blue
        case "ended": return .orange
        case "sold": return .purple
        default: return .gray
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}
