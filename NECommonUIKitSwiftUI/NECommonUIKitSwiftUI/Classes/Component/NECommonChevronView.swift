// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonChevronView: View {
  @Environment(\.neCommonTheme) private var token
  private let isEnabled: Bool
  private let font: Font?

  public init(isEnabled: Bool = true,
              font: Font? = nil) {
    self.isEnabled = isEnabled
    self.font = font
  }

  public var body: some View {
    Image("arrow_right", bundle: NECommonUIKitSwiftUIBundle.bundle)
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: 12, height: 12)
      .opacity(isEnabled ? 1 : 0.45)
      .accessibilityHidden(true)
  }
}
