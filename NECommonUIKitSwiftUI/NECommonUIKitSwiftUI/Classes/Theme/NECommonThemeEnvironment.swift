// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

private struct NECommonThemeKey: EnvironmentKey {
  static let defaultValue = NECommonThemeToken.normal
}

private struct NECommonLocalBackActionKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
  var neCommonTheme: NECommonThemeToken {
    get { self[NECommonThemeKey.self] }
    set { self[NECommonThemeKey.self] = newValue }
  }

  var neCommonLocalBackAction: (() -> Void)? {
    get { self[NECommonLocalBackActionKey.self] }
    set { self[NECommonLocalBackActionKey.self] = newValue }
  }
}

public extension View {
  func neCommonTheme(_ token: NECommonThemeToken) -> some View {
    environment(\.neCommonTheme, token)
  }
}
