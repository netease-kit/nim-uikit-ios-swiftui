// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonErrorStateView: View {
  @Environment(\.neCommonTheme) private var token
  private let state: NECommonErrorState
  private let retry: (() -> Void)?

  public init(state: NECommonErrorState = NECommonErrorState(),
              retry: (() -> Void)? = nil) {
    self.state = state
    self.retry = retry
  }

  public var body: some View {
    VStack(spacing: token.spacing.medium) {
      Text(NECommonUIKitSwiftUIBundle.localized(state.textKey, fallback: state.fallbackText))
        .font(token.typography.headline)
        .foregroundColor(color(for: state.severity))
        .multilineTextAlignment(.center)

      if state.retryable, let retry {
        NECommonActionButton(title: NECommonUIKitSwiftUIBundle.localized("common_retry", fallback: "Retry"),
                             style: .secondary,
                             action: retry)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, token.spacing.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(token.spacing.large)
  }

  private func color(for severity: NECommonErrorSeverity) -> Color {
    switch severity {
    case .info:
      return token.palette.secondaryText
    case .warning:
      return token.palette.warning
    case .error:
      return token.palette.destructive
    }
  }
}
