// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSafeAreaBackgroundModifier: ViewModifier {
  private let color: Color

  public init(color: Color) {
    self.color = color
  }

  public func body(content: Content) -> some View {
    ZStack {
      color.ignoresSafeArea()
      content
    }
  }
}

public extension View {
  func neCommonSafeAreaBackground(_ color: Color) -> some View {
    modifier(NECommonSafeAreaBackgroundModifier(color: color))
  }
}
