platform :ios, '13.0'

target 'MMBrowser' do
  use_frameworks!

  # Pods for MMBrowser
  pod 'lottie-ios', '~> 2.5.3'
  pod 'SnapKit', '5.0.1'
  pod 'KakaJSON', '1.1.2'
  pod 'RxSwift', '5.1.1'
  pod 'RxCocoa', '5.1.1'
  pod 'Kingfisher', '~>6.3.1'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 13.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
    end
  end
end
