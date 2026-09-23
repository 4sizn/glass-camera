import GoogleMobileAds

/// Shows a full-screen AdMob ad before the recent capture sheet, when one is loaded.
@MainActor final class RecentCaptureAd: NSObject, FullScreenContentDelegate {
    #if DEBUG
    private let unitID = "ca-app-pub-3940256099942544/4411468910" // Google's test interstitial
    #else
    private let unitID = "ca-app-pub-4045474417631564/7164798781"
    #endif
    private let enabled = !ProcessInfo.processInfo.arguments.contains("--no-ads")
    private var ad: InterstitialAd?
    private var onDismiss: (() -> Void)?

    override init() {
        super.init()
        guard enabled else { return }
        MobileAds.shared.start()
        load()
    }

    private func load() {
        Task {
            ad = try? await InterstitialAd.load(with: unitID, request: Request())
            ad?.fullScreenContentDelegate = self
        }
    }

    /// Runs `then` right away when no ad is ready, so the sheet never waits on the network.
    func show(then: @escaping () -> Void) {
        guard let ad else { then(); load(); return }
        self.ad = nil
        onDismiss = then
        ad.present(from: nil)
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in finish() }
    }

    private func finish() {
        onDismiss?(); onDismiss = nil
        load()
    }
}
