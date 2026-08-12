// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

private struct ChatThemeTokenKey: EnvironmentKey {
  static let defaultValue = ChatThemeToken.normal
}

private struct ChatSwiftUIConfigKey: EnvironmentKey {
  static let defaultValue = ChatSwiftUIConfig()
}

public extension EnvironmentValues {
  var chatThemeToken: ChatThemeToken {
    get { self[ChatThemeTokenKey.self] }
    set { self[ChatThemeTokenKey.self] = newValue }
  }

  var chatSwiftUIConfig: ChatSwiftUIConfig {
    get { self[ChatSwiftUIConfigKey.self] }
    set { self[ChatSwiftUIConfigKey.self] = newValue }
  }
}

public extension View {
  func chatTheme(_ token: ChatThemeToken) -> some View {
    environment(\.chatThemeToken, token)
  }

  func chatSwiftUIConfig(_ config: ChatSwiftUIConfig) -> some View {
    environment(\.chatSwiftUIConfig, config)
  }
}
