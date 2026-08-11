# 配置内容详见：PodConfigs/config_podspec.rb
require_relative "PodConfigs/config_podspec.rb"

platform :ios, YXConfig.deployment_target
source 'https://github.com/CocoaPods/Specs.git'
source 'ssh://git@g.hz.netease.com:22222/yunxin-app/specs.git'
source 'ssh://git@g.hz.netease.com:22222/nim_ios/Specs.git'

target 'app' do
  use_frameworks!

  # 基础库 - 闭源二进制 Pod
  pod 'NEChatKit', YXConfig.imuikit_version

  # SwiftUI UI 组件
  pod 'NECommonUIKitSwiftUI', YXConfig.imuikit_version         # 通用 UI 组件（基础层）
  pod 'NEChatUIKitSwiftUI', YXConfig.imuikit_version           # 聊天组件
  pod 'NEConversationUIKitSwiftUI', YXConfig.imuikit_version   # 会话列表组件
  pod 'NEContactUIKitSwiftUI', YXConfig.imuikit_version        # 通讯录组件
  pod 'NETeamUIKitSwiftUI', YXConfig.imuikit_version           # 群组管理组件

  # 扩展库 - AI 划词搜索
  pod 'NEAISearchKitSwiftUI', YXConfig.imuikit_version

  # 扩展库 - 呼叫组件（与 UIKit Demo 保持一致）
  pod 'NERtcSDK/RtcBasic'
  pod 'NERtcSDK/Nenn'
  pod 'NERtcSDK/Segment'
  pod 'NERtcCallKit/NOS_Special', '4.1.0'
  pod 'NERtcCallUIKit/NOS_Special', '4.1.0'

  # Demo 专用
  pod 'ZLPhotoBrowser'

  # 如果需要查看 UI 部分源码，请注释掉以上 SwiftUI UI 组件在线依赖，打开下面的本地依赖
#  pod 'NECommonUIKitSwiftUI', :path => 'NECommonUIKitSwiftUI/NECommonUIKitSwiftUI.podspec'
#  pod 'NEChatUIKitSwiftUI', :path => 'NEChatUIKitSwiftUI/NEChatUIKitSwiftUI.podspec'
#  pod 'NEConversationUIKitSwiftUI', :path => 'NEConversationUIKitSwiftUI/NEConversationUIKitSwiftUI.podspec'
#  pod 'NEContactUIKitSwiftUI', :path => 'NEContactUIKitSwiftUI/NEContactUIKitSwiftUI.podspec'
#  pod 'NETeamUIKitSwiftUI', :path => 'NETeamUIKitSwiftUI/NETeamUIKitSwiftUI.podspec'
#  pod 'NEAISearchKitSwiftUI', :path => 'NEAISearchKitSwiftUI/NEAISearchKitSwiftUI.podspec'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = YXConfig.deployment_target
    end
  end
end
