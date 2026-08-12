// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSkeletonView: View {
  @Environment(\.neCommonTheme) private var token
  private let rows: Int

  public init(rows: Int = 3) {
    self.rows = max(rows, 1)
  }

  public var body: some View {
    VStack(spacing: token.spacing.medium) {
      ForEach(0..<rows, id: \.self) { _ in
        RoundedRectangle(cornerRadius: token.radius.medium)
          .fill(token.palette.separator.opacity(0.55))
          .frame(height: 48)
      }
    }
    .padding(token.spacing.large)
  }
}
