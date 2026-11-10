platform :ios, '15.0'

# Prefer CDN; if HTTP/2 fails locally, try: export COCOAPODS_SOURCE=... or use mirror.
source 'https://cdn.cocoapods.org/'

target 'MMBrowser' do
  use_frameworks!

  # Layout (5.7+ ships PrivacyInfo.xcprivacy required by App Store)
  pod 'SnapKit', '~> 5.7.1'

  # Firebase (binary pods via CocoaPods)
  # Use /Core (no IDFA / ATT) so App Store Connect does not treat the binary as tracking-capable.
  pod 'FirebaseAnalytics/Core', '~> 11.15.0'
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

  # GoogleAdsOnDeviceConversion has no Mac Catalyst slice (FirebaseAnalytics transitive).
  # Drop it from the shared OTHER_LDFLAGS and re-add only for iOS device/simulator.
  # (Xcode concatenates OTHER_LDFLAGS + OTHER_LDFLAGS[sdk=*], so a macosx strip-line is not enough.)
  Dir.glob(File.join(installer.sandbox.root, 'Target Support Files/Pods-MMBrowser/*.xcconfig')).each do |path|
    text = File.read(path)
    next unless text =~ /^OTHER_LDFLAGS = (.*)$/
    original = Regexp.last_match(1)
    next unless original.include?('GoogleAdsOnDeviceConversion')

    without = original.gsub(/\s*-framework "GoogleAdsOnDeviceConversion"/, '')
    text = text.sub(/^OTHER_LDFLAGS = .*$/, "OTHER_LDFLAGS = #{without}")
    # Drop any previous Catalyst-only override from earlier installs.
    text = text.gsub(/\nOTHER_LDFLAGS\[sdk=macosx\*\] = .*\n?/, "\n")
    text = text.gsub(/\nOTHER_LDFLAGS\[sdk=iphoneos\*\] = .*\n?/, "\n")
    text = text.gsub(/\nOTHER_LDFLAGS\[sdk=iphonesimulator\*\] = .*\n?/, "\n")
    text = text.rstrip + "\n"
    text += "OTHER_LDFLAGS[sdk=iphoneos*] = $(inherited) -framework \"GoogleAdsOnDeviceConversion\"\n"
    text += "OTHER_LDFLAGS[sdk=iphonesimulator*] = $(inherited) -framework \"GoogleAdsOnDeviceConversion\"\n"
    File.write(path, text)
  end
end
