网易云信即时通讯界面组件（IM UIKit）的 SwiftUI 实现，基于 [NIM SDK](https://doc.yunxin.163.com/messaging2/concept/DI0Nzc2NzA?platform=client) 开发，包括聊天、会话、通讯录、群管理、AI 搜索等组件。通过 IM UIKit SwiftUI，您可快速集成包含 UI 界面的即时通讯应用。

## 与 UIKit 版本的关系

本仓库是 [nim-uikit-ios](https://github.com/netease-kit/nim-uikit-ios) (UIKit 版本) 的 SwiftUI 实现，提供相同的 IM 功能但使用 SwiftUI 框架构建。组件命名使用 `SwiftUI` 后缀以区分。

## 适用客群

IM UIKit SwiftUI 适合使用 SwiftUI 框架开发 iOS 应用的团队，最低支持 iOS 16.0。

## 组件架构

```
NECommonUIKitSwiftUI   ──→  基础层（无内部依赖）
NEChatUIKitSwiftUI     ──→  NEChatKit + NECommonUIKitSwiftUI + lottie-ios
NETeamUIKitSwiftUI     ──→  NEChatKit + NECommonUIKitSwiftUI
NEConversationUIKitSwiftUI ──→ NEChatKit + NEChatUIKitSwiftUI + NECommonUIKitSwiftUI
NEContactUIKitSwiftUI  ──→  NEChatKit + NEChatUIKitSwiftUI + NETeamUIKitSwiftUI + NECommonUIKitSwiftUI
NEAISearchKitSwiftUI   ──→  NEChatKit
```

注：`NEChatKit` 为数据层组件，以二进制 Pod 形式分发，源码不在此仓库开源。

## 快速开始

### 环境要求

- Xcode 16+
- iOS 16.0+
- Swift 5.0+
- CocoaPods 1.10+

### 运行 Demo

```bash
git clone git@github.com:netease-kit/nim-uikit-ios-swiftui.git
cd nim-uikit-ios-swiftui
pod install
open app.xcworkspace
```

### 使用组件

在 Podfile 中添加：

```ruby
pod 'NEChatUIKitSwiftUI', '10.9.30-beta'
pod 'NEConversationUIKitSwiftUI', '10.9.30-beta'
```

### 查看源码

Demo 的 Podfile 默认使用线上 SwiftUI UI 组件。需要源码模式开发调试时，先注释 SwiftUI UI 组件的线上依赖，再取消对应本地 `:path` 依赖的注释，然后执行 `pod install`。

## 相关文档

- [IM UIKit 功能概览](https://doc.yunxin.163.com/messaging-uikit/concept/zMzMDQ2MTg)
- [集成开发文档](https://doc.yunxin.163.com/messaging-uikit/guide/DU4NzAzNzQ)
- [NIM UIKit iOS (UIKit 版本)](https://github.com/netease-kit/nim-uikit-ios)
