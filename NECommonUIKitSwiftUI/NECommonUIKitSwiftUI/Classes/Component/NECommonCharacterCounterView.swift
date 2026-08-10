// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonCharacterCounterView: View {
  @Environment(\.neCommonTheme) private var token
  private let count: Int
  private let limit: Int?
  private let isWarning: Bool
  private let font: Font?

  public init(count: Int,
              limit: Int?,
              isWarning: Bool = false,
              font: Font? = nil) {
    self.count = max(0, count)
    self.limit = limit.map { max(0, $0) }
    self.isWarning = isWarning
    self.font = font
  }

  public var body: some View {
    Text(displayText)
      .font(font ?? token.typography.caption)
      .foregroundColor(isWarning ? token.palette.warning : token.palette.secondaryText)
      .lineLimit(1)
      .truncationMode(.tail)
      .accessibilityLabel(displayText)
  }

  private var displayText: String {
    guard let limit else {
      return "\(count)"
    }
    return "\(count)/\(limit)"
  }
}
