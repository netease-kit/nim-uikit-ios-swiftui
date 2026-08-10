// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonLoadingView: View {
  @Environment(\.neCommonTheme) private var token
  private let title: String

  public init(title: String? = nil) {
    self.title = title ?? NECommonUIKitSwiftUIBundle.localized("common_loading", fallback: "Loading")
  }

  public var body: some View {
    VStack(spacing: token.spacing.medium) {
      ProgressView()
        .progressViewStyle(.circular)
        .tint(token.palette.accent)
      Text(title)
        .font(token.typography.footnote)
        .foregroundColor(token.palette.secondaryText)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(token.spacing.large)
  }
}
