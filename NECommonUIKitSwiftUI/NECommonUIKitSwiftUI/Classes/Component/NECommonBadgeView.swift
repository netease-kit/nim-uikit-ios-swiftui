// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonBadgeView: View {
  @Environment(\.neCommonTheme) private var token
  private let content: Content
  private let showZero: Bool
  private let minSize: CGFloat?
  private let horizontalPadding: CGFloat?
  private let verticalPadding: CGFloat
  private let background: Color?
  private let foreground: Color?

  public init(count: Int,
              showZero: Bool = false,
              minSize: CGFloat? = nil,
              horizontalPadding: CGFloat? = nil,
              verticalPadding: CGFloat = 0,
              background: Color? = nil,
              foreground: Color? = nil) {
    content = .count(count)
    self.showZero = showZero
    self.minSize = minSize
    self.horizontalPadding = horizontalPadding
    self.verticalPadding = verticalPadding
    self.background = background
    self.foreground = foreground
  }

  public init(text: String,
              minSize: CGFloat? = nil,
              horizontalPadding: CGFloat? = nil,
              verticalPadding: CGFloat = 0,
              background: Color? = nil,
              foreground: Color? = nil) {
    content = .text(text)
    showZero = true
    self.minSize = minSize
    self.horizontalPadding = horizontalPadding
    self.verticalPadding = verticalPadding
    self.background = background
    self.foreground = foreground
  }

  public var body: some View {
    if shouldShow {
      Text(displayText)
        .font(token.typography.caption)
        .foregroundColor(foreground ?? token.badge.foreground)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, horizontalPadding ?? token.spacing.xsmall)
        .padding(.vertical, verticalPadding)
        .frame(minWidth: minSize ?? token.badge.minSize, minHeight: minSize ?? token.badge.minSize)
        .background(background ?? token.badge.background)
        .clipShape(Capsule())
        .accessibilityLabel(displayText)
    }
  }

  private var shouldShow: Bool {
    switch content {
    case .count(let count):
      return count > 0 || showZero
    case .text(let text):
      return !text.isEmpty
    }
  }

  private var displayText: String {
    switch content {
    case .count(let count):
      return count > token.badge.maxCount ? "\(token.badge.maxCount)+" : "\(max(count, 0))"
    case .text(let text):
      return text
    }
  }

  private enum Content {
    case count(Int)
    case text(String)
  }
}
