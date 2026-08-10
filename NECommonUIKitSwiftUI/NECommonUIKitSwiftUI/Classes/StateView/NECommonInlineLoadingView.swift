// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonInlineLoadingView: View {
  @Environment(\.neCommonTheme) private var token
  private let title: String?

  public init(title: String? = nil) {
    self.title = title
  }

  public var body: some View {
    HStack(spacing: token.spacing.small) {
      ProgressView()
        .progressViewStyle(.circular)
        .controlSize(.small)
        .tint(token.palette.accent)

      if let title, !title.isEmpty {
        Text(title)
          .font(token.typography.footnote)
          .foregroundColor(token.palette.secondaryText)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title ?? NECommonUIKitSwiftUIBundle.localized("common_loading", fallback: "Loading"))
  }
}
