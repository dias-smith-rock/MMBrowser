platform :ios, '15.0'

# Prefer CDN; if HTTP/2 fails locally, try: export COCOAPODS_SOURCE=... or use mirror.
source 'https://cdn.cocoapods.org/'

target 'MMBrowser' do
  use_frameworks!

  # Layout (5.7+ ships PrivacyInfo.xcprivacy required by App Store)
  pod 'SnapKit', '~> 5.7.1'

  # Firebase (Analytics includes GoogleAppMeasurement / IDFA paths; gated by ATT + shareDiagnostics)
  pod 'FirebaseAnalytics', '~> 11.15.0'
  pod 'FirebaseRemoteConfig', '~> 11.15.0'
  pod 'FirebaseCrashlytics', '~> 11.15.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
      # Mac Catalyst builds share the iOS pods as a UIKit Mac app.
      config.build_settings['SUPPORTS_MACCATALYST'] = 'YES'
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
