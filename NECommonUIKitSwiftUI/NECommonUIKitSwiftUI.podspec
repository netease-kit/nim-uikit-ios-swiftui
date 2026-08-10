require_relative "../PodConfigs/config_podspec.rb"

Pod::Spec.new do |spec|
  spec.name         = 'NECommonUIKitSwiftUI'
  spec.version      = YXConfig.imuikit_version
  spec.summary      = 'Netease XKit IM UIKit - SwiftUI Common Module'
  spec.homepage         = YXConfig.homepage
  spec.license          = YXConfig.license
  spec.author           = YXConfig.author
  spec.ios.deployment_target = YXConfig.deployment_target
  spec.swift_version = YXConfig.swift_version
  spec.source           = { :git => '', :tag => spec.version.to_s }
  spec.source_files = 'NECommonUIKitSwiftUI/Classes/**/*'
  spec.resource = 'NECommonUIKitSwiftUI/Assets/**/*'
  YXConfig.pod_target_xcconfig(spec)
end
