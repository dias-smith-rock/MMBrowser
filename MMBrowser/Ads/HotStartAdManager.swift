import GoogleMobileAds
import UIKit

@MainActor
final class HotStartAdManager: NSObject {
    static let shared = HotStartAdManager()

    private var interstitial: InterstitialAd?
    private var isShowingAd = false
    private var isLoadingAd = false

    func loadAd() {
        guard AdMobConfig.adsEnabled, AdMobConfig.hotStartEnabled, AdConsentManager.canRequestAds else { return }
        guard !isLoadingAd, !isShowingAd else { return }
        isLoadingAd = true

        InterstitialAd.load(with: AdMobConfig.interstitialAdUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAd = false
                if let error {
                    #if DEBUG
                    print("[Interstitial] load failed: \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let ad else { return }
                self.interstitial = ad
                ad.fullScreenContentDelegate = self
            }
        }
    }

    func showAdIfAvailable(from root: UIViewController? = nil) {
        guard AdMobConfig.adsEnabled, AdMobConfig.hotStartEnabled, AdConsentManager.canRequestAds else { return }
        guard !isShowingAd else { return }
        guard let ad = interstitial else {
            loadAd()
            return
        }
        guard let presenter = root ?? UIApplication.shared.mmb_topViewController else { return }
        isShowingAd = true
        AppAnalytics.logAdImpression(format: "interstitial")
        ad.present(from: presenter)
    }
}

extension HotStartAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        isShowingAd = false
        loadAd()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("[Interstitial] present failed: \(error.localizedDescription)")
        #endif
        interstitial = nil
        isShowingAd = false
        loadAd()
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        AppAnalytics.logAdClick(format: "interstitial")
    }
}
