platform :ios, '15.0'

# Prefer CDN; if HTTP/2 fails locally, try: export COCOAPODS_SOURCE=... or use mirror.
source 'https://cdn.cocoapods.org/'

target 'MMBrowser' do
  use_frameworks!

  # Existing
  pod 'lottie-ios', '~> 2.5.3'
  pod 'SnapKit', '5.0.1'
  pod 'KakaJSON', '1.1.2'
  pod 'RxSwift', '5.1.1'
  pod 'RxCocoa', '5.1.1'
  pod 'Kingfisher', '~>6.3.1'

  # Firebase (binary pods via CocoaPods)
  pod 'FirebaseAnalytics', '~> 11.15.0'
  pod 'FirebaseRemoteConfig', '~> 11.15.0'
  pod 'FirebaseCrashlytics', '~> 11.15.0'

  # AdMob (+ UMP)
  pod 'Google-Mobile-Ads-SDK', '~> 12.2.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
    end
  end
end
