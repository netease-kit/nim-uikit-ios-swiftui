require_relative "PodConfigs/config_podspec.rb"

platform :ios, YXConfig.deployment_target

source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!

target "IMUIKitSwiftUIExample" do
  # ===== 非开源组件 (二进制分发) =====
  # NIM IM SDK (网易云信内部闭环，不开源)
  pod 'NIMSDK_LITE', '10.9.81'
  pod 'NIMSDK_LITE/FTS', '10.9.81'

  # NEChatKit (数据层，不开源，二进制 Pod)
  pod 'NEChatKit', YXConfig.imuikit_version

  # ===== 开源组件 (本地源码) =====
  # 取消注释以下行使用本地源码：
  pod 'NECommonUIKitSwiftUI', :path => 'NECommonUIKitSwiftUI/NECommonUIKitSwiftUI.podspec'
  pod 'NEChatUIKitSwiftUI', :path => 'NEChatUIKitSwiftUI/NEChatUIKitSwiftUI.podspec'
  pod 'NEConversationUIKitSwiftUI', :path => 'NEConversationUIKitSwiftUI/NEConversationUIKitSwiftUI.podspec'
  pod 'NEContactUIKitSwiftUI', :path => 'NEContactUIKitSwiftUI/NEContactUIKitSwiftUI.podspec'
  pod 'NETeamUIKitSwiftUI', :path => 'NETeamUIKitSwiftUI/NETeamUIKitSwiftUI.podspec'
  pod 'NEAISearchKitSwiftUI', :path => 'NEAISearchKitSwiftUI/NEAISearchKitSwiftUI.podspec'

  # ===== Demo 专用 =====
  # 相册选择 (ZLPhotoBrowser 为开源三方库)
  pod 'ZLPhotoBrowser'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings["ENABLE_BITCODE"] = "NO"
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = YXConfig.deployment_target
    end
  end
end
