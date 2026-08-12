// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonTabBarHiddenPreferenceKey: PreferenceKey {
  public static var defaultValue = false

  public static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

public extension View {
  func neCommonRequestsTabBarHidden() -> some View {
    toolbar(.hidden, for: .tabBar)
      .preference(key: NECommonTabBarHiddenPreferenceKey.self, value: true)
  }
}
