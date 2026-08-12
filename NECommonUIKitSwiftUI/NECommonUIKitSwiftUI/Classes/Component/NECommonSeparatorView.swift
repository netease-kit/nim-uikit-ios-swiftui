// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSeparatorView: View {
  @Environment(\.neCommonTheme) private var token
  private let height: CGFloat
  private let opacity: Double

  public init(height: CGFloat = 0.5,
              opacity: Double = 1) {
    self.height = height
    self.opacity = opacity
  }

  public var body: some View {
    Rectangle()
      .fill(token.palette.separator.opacity(opacity))
      .frame(height: height)
  }
}
