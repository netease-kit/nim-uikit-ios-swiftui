# NIM UIKit SwiftUI

网易云信 IM UIKit 的 SwiftUI 实现，提供会话列表、聊天、通讯录、群组管理等 IM 核心功能的 SwiftUI 组件。

## 目录结构

```
nim-uikit-ios-swiftui/
├── app/                          # Demo 应用源码
│   ├── App/                      # 入口 (AppDelegate, AppKey)
│   ├── Bootstrap/                # 启动引导与服务注入
│   ├── Login/                    # 登录页面
│   ├── Main/                     # 各 Tab 的根视图与路由
│   ├── Root/                     # 根容器与 TabBar
│   ├── State/                    # 全局状态管理
│   ├── Support/                  # 原生能力桥接 (相册/相机/录音/定位等)
│   └── Resources/                # 资源文件
├── NECommonUIKitSwiftUI/         # 通用 UI 组件 (基础层)
├── NEChatUIKitSwiftUI/           # 聊天 UI 组件
├── NEConversationUIKitSwiftUI/   # 会话列表 UI 组件
├── NEContactUIKitSwiftUI/        # 通讯录 UI 组件
├── NETeamUIKitSwiftUI/           # 群组管理 UI 组件
├── NEAISearchKitSwiftUI/         # AI 搜索 UI 组件
├── PodConfigs/                   # CocoaPods 共享配置
└── Podfile                       # 依赖声明
```

## 模块依赖关系

```
NECommonUIKitSwiftUI  ──→  (无内部依赖)
NEChatUIKitSwiftUI    ──→  NEChatKit + NECommonUIKitSwiftUI + lottie-ios
NETeamUIKitSwiftUI    ──→  NEChatKit + NECommonUIKitSwiftUI
NEConversationUIKitSwiftUI ──→ NEChatKit + NEChatUIKitSwiftUI + NECommonUIKitSwiftUI
NEContactUIKitSwiftUI ──→ NEChatKit + NEChatUIKitSwiftUI + NETeamUIKitSwiftUI + NECommonUIKitSwiftUI
NEAISearchKitSwiftUI  ──→  NEChatKit
```

注: `NEChatKit` 为数据层组件，以二进制 Pod 形式分发，不在本仓库开源。

## 快速开始

### 环境要求

- Xcode 16+
- iOS 16.0+
- Swift 5.0+
- CocoaPods 1.10+

### 运行 Demo

```bash
# 1. 安装依赖
pod install

# 2. 打开 workspace
open app.xcworkspace

# 3. 在 Xcode 中选择 IMUIKitSwiftUIExample target 运行
```

### 使用组件

在你的 `Podfile` 中添加:

```ruby
# 通过 CocoaPods 引用
pod 'NEChatUIKitSwiftUI', '~> 10.9.0'
pod 'NEConversationUIKitSwiftUI', '~> 10.9.0'
# ... 其他模块
```

### 本地开发

取消 `Podfile` 中开源组件的 `:path` 引用注释，即可使用本地源码进行开发和调试。

## 许可证

MIT License - Copyright (c) 2022 NetEase, Inc.
