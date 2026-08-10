// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonEmptyStateView: View {
  @Environment(\.neCommonTheme) private var token
  private let state: NECommonEmptyState
  private let action: (() -> Void)?

  public init(state: NECommonEmptyState = NECommonEmptyState(),
              action: (() -> Void)? = nil) {
    self.state = state
    self.action = action
  }

  public var body: some View {
    VStack(spacing: token.spacing.small) {
      Image(NECommonPlaceholderImage.emptyImageName(kind: state.imageKind, styleMode: token.styleMode),
            bundle: NECommonUIKitSwiftUIBundle.bundle)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: 122, height: 91)

      Text(localized(state.titleKey, fallback: state.fallbackTitle))
        .font(.system(size: 14))
        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.emptyTitle)
        .multilineTextAlignment(.center)

      if let messageKey = state.messageKey,
         let fallbackMessage = state.fallbackMessage {
        Text(localized(messageKey, fallback: fallbackMessage))
          .font(token.typography.footnote)
          .foregroundColor(token.palette.secondaryText)
          .multilineTextAlignment(.center)
      }

      if let action,
         let actionTitleKey = state.actionTitleKey,
         let fallbackActionTitle = state.fallbackActionTitle {
        NECommonActionButton(title: localized(actionTitleKey, fallback: fallbackActionTitle),
                             style: .secondary,
                             action: action)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, token.spacing.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 176)
    .padding(.horizontal, 20)
    .padding(.bottom, token.spacing.large)
  }

  private func localized(_ key: String, fallback: String) -> String {
    NECommonUIKitSwiftUIBundle.localized(key, fallback: fallback)
  }
}
