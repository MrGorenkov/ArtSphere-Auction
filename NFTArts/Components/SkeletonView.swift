import SwiftUI

/// Lightweight skeleton placeholder with built-in shimmer. Use as a stand-in for
/// content while it loads. Width/height pass through `frame` modifiers as usual.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.tertiarySystemBackground))
            .shimmer()
    }
}

/// Skeleton mimicking an AuctionCardView: a square image area with two text rows below.
struct SkeletonAuctionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(height: 16)
                    .frame(maxWidth: 180, alignment: .leading)
                SkeletonBlock(cornerRadius: 4)
                    .frame(height: 12)
                    .frame(maxWidth: 110, alignment: .leading)
                HStack {
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 90, height: 18)
                    Spacer()
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 60, height: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A vertical stack of skeleton cards used as a loading placeholder for Feed/Explore.
struct SkeletonFeedList: View {
    var count: Int = 4

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonAuctionCard()
            }
        }
        .padding(.horizontal)
    }
}
