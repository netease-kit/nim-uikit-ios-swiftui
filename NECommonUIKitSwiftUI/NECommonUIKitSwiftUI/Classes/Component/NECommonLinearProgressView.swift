// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonLinearProgressView: View {
  @Environment(\.neCommonTheme) private var token
  private let value: Double
  private let height: CGFloat
  private let foregroundColor: Color?
  private let backgroundColor: Color?
  private let accessibilityLabel: String?

  public init(value: Double,
              height: CGFloat = 4,
              foregroundColor: Color? = nil,
              backgroundColor: Color? = nil,
              accessibilityLabel: String? = nil) {
    self.value = min(max(value, 0), 1)
    self.height = height
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
    self.accessibilityLabel = accessibilityLabel
  }

  public var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(backgroundColor ?? token.palette.disabled.opacity(0.45))
        Capsule()
          .fill(foregroundColor ?? token.palette.accent)
          .frame(width: proxy.size.width * CGFloat(value))
      }
    }
    .frame(height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel ?? NECommonUIKitSwiftUIBundle.localized("common_progress", fallback: "Progress"))
    .accessibilityValue("\(Int(value * 100))%")
  }
}
