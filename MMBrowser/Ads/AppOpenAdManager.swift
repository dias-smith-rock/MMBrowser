import GoogleMobileAds
import UIKit

@MainActor
final class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()

    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?
    private var isShowingAd = false
    private var isLoadingAd = false

    func loadAd() {
        guard AdMobConfig.adsEnabled, AdMobConfig.coldStartEnabled, AdConsentManager.canRequestAds else { return }
        guard !isLoadingAd, !isShowingAd else { return }
        isLoadingAd = true

        AppOpenAd.load(with: AdMobConfig.appOpenAdUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAd = false
                if let error {
                    #if DEBUG
                    print("[AppOpen] load failed: \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let ad else { return }
                self.appOpenAd = ad
                self.loadTime = Date()
                ad.fullScreenContentDelegate = self
            }
        }
    }

    func showAdIfAvailable(from root: UIViewController? = nil) {
        guard AdMobConfig.adsEnabled, AdMobConfig.coldStartEnabled, AdConsentManager.canRequestAds else { return }
        guard !isShowingAd else { return }
        guard let ad = appOpenAd, !isAdExpired else {
            loadAd()
            return
        }
        guard let presenter = root ?? UIApplication.shared.mmb_topViewController else { return }
        isShowingAd = true
        AppAnalytics.logAdImpression(format: "app_open")
        ad.present(from: presenter)
    }

    private var isAdExpired: Bool {
        guard let loadTime else { return true }
        return Date().timeIntervalSince(loadTime) > AdMobConfig.appOpenAdTimeout
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        appOpenAd = nil
        isShowingAd = false
        loadAd()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("[AppOpen] present failed: \(error.localizedDescription)")
        #endif
        appOpenAd = nil
        isShowingAd = false
        loadAd()
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        AppAnalytics.logAdClick(format: "app_open")
    }
}
