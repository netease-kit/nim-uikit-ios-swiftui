require_relative "../PodConfigs/config_podspec.rb"

Pod::Spec.new do |spec|
  spec.name         = 'NEChatUIKitSwiftUI'
  spec.version      = YXConfig.imuikit_version
  spec.summary      = 'Netease XKit IM UIKit - SwiftUI Chat Module'
  spec.homepage         = YXConfig.homepage
  spec.license          = YXConfig.license
  spec.author           = YXConfig.author
  spec.ios.deployment_target = YXConfig.deployment_target
  spec.swift_version = YXConfig.swift_version
  spec.source           = { :git => '', :tag => spec.version.to_s }
  spec.source_files = 'NEChatUIKitSwiftUI/Classes/**/*'
  spec.resource = 'NEChatUIKitSwiftUI/Assets/**/*'
  YXConfig.pod_target_xcconfig(spec)

  spec.dependency 'NEChatKit'
  spec.dependency 'NECommonUIKitSwiftUI'
  spec.dependency 'lottie-ios'
end
