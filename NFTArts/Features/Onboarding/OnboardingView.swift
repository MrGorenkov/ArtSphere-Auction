import SwiftUI

/// Three-screen first-launch tour: Feed → 3D viewer → Showroom.
/// Gated by `UserDefaults.standard.bool(forKey: "onboarding_completed")`.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page: Int = 0

    private let pages: [Page] = [
        Page(
            icon: "rectangle.stack.fill",
            iconColor: .nftPurple,
            title: L10n.onboardingTitle1,
            description: L10n.onboardingDesc1
        ),
        Page(
            icon: "cube.transparent",
            iconColor: .nftBlue,
            title: L10n.onboardingTitle2,
            description: L10n.onboardingDesc2
        ),
        Page(
            icon: "building.columns.fill",
            iconColor: .nftOrange,
            title: L10n.onboardingTitle3,
            description: L10n.onboardingDesc3
        )
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.nftPurple.opacity(0.15), Color.nftBlue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        PageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    HapticService.tap()
                    if page < pages.count - 1 {
                        withAnimation(.spring(response: 0.4)) { page += 1 }
                    } else {
                        complete()
                    }
                } label: {
                    Text(page < pages.count - 1 ? L10n.onboardingNext : L10n.onboardingStart)
                        .font(NFTTypography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.nftPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

            Button(L10n.onboardingSkip) {
                complete()
            }
            .font(NFTTypography.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completedKey)
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
    }

    static let completedKey = "onboarding_completed"
    static var hasSeenOnboarding: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }
}

private struct Page {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

private struct PageView: View {
    let page: Page

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.15))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(page.iconColor.opacity(0.25))
                    .frame(width: 130, height: 130)
                Image(systemName: page.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(page.iconColor)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(NFTTypography.largeTitle)
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(NFTTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
