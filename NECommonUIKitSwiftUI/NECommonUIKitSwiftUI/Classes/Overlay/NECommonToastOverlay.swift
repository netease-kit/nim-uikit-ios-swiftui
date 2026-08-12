// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonToastOverlay: View {
  @Environment(\.neCommonTheme) private var token
  private let toast: NECommonToastState

  public init(toast: NECommonToastState) {
    self.toast = toast
  }

  public var body: some View {
    Text(text)
      .font(token.typography.footnote)
      .foregroundColor(token.overlay.toastForeground)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .padding(.horizontal, token.spacing.large)
      .padding(.vertical, token.spacing.medium)
      .background(token.overlay.toastBackground)
      .clipShape(RoundedRectangle(cornerRadius: token.overlay.cornerRadius))
      .shadow(color: token.shadow.color, radius: token.shadow.radius, x: token.shadow.x, y: token.shadow.y)
      .padding(.horizontal, token.spacing.xlarge)
      .accessibilityLabel(text)
  }

  private var text: String {
    if let textKey = toast.textKey {
      return NECommonUIKitSwiftUIBundle.localized(textKey, fallback: toast.fallbackText)
    }
    return toast.fallbackText
  }
}
