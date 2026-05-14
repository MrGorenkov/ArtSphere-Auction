import SwiftUI

/// App-wide non-blocking error banner. Services post a `BannerError`; the banner shows
/// at the top of the main hierarchy and auto-dismisses after the timeout (or stays until
/// the user taps "Retry"/"Dismiss").
struct BannerError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    var retryHandler: ErrorRetryHandler?
    var autoDismissAfter: TimeInterval? = 4.0

    static func == (lhs: BannerError, rhs: BannerError) -> Bool { lhs.id == rhs.id }
}

/// Wrapper so closures can be stored in an Equatable struct.
final class ErrorRetryHandler {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

@MainActor
final class ErrorBannerService: ObservableObject {
    static let shared = ErrorBannerService()
    @Published var current: BannerError?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ error: BannerError) {
        current = error
        dismissTask?.cancel()
        if let timeout = error.autoDismissAfter {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.dismiss() }
            }
        }
    }

    func showOffline(retry: @escaping () -> Void) {
        show(BannerError(
            title: L10n.errorOffline,
            message: L10n.errorGeneric,
            retryHandler: ErrorRetryHandler(retry),
            autoDismissAfter: nil
        ))
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

/// SwiftUI overlay component. Attach with `.errorBanner()` to whichever container should host it.
struct ErrorBannerOverlay: ViewModifier {
    @ObservedObject private var service = ErrorBannerService.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let err = service.current {
                bannerView(err)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: err.id)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
    }

    private func bannerView(_ err: BannerError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(err.title)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.semibold)
                Text(err.message)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let retry = err.retryHandler {
                Button {
                    HapticService.tap()
                    retry.action()
                    ErrorBannerService.shared.dismiss()
                } label: {
                    Text(L10n.errorRetry)
                        .font(NFTTypography.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.nftPurple, in: Capsule())
                        .foregroundStyle(.white)
                }
            } else {
                Button {
                    ErrorBannerService.shared.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func errorBanner() -> some View {
        modifier(ErrorBannerOverlay())
    }
}
