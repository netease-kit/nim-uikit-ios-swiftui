// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonBlockingLoadingOverlay: View {
  @Environment(\.neCommonTheme) private var token
  private let state: NECommonBlockingLoadingState

  public init(state: NECommonBlockingLoadingState) {
    self.state = state
  }

  public var body: some View {
    ZStack {
      if state.showsScrim {
        token.overlay.scrim
          .ignoresSafeArea()
      }

      VStack(spacing: token.spacing.medium) {
        ProgressView()
          .progressViewStyle(.circular)
          .tint(token.palette.accent)

        if let title, !title.isEmpty {
          Text(title)
            .font(token.typography.footnote)
            .foregroundColor(token.palette.secondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
      }
      .frame(minWidth: 96)
      .padding(.horizontal, token.spacing.large)
      .padding(.vertical, token.spacing.medium)
      .background(token.palette.elevatedBackground)
      .clipShape(RoundedRectangle(cornerRadius: token.overlay.cornerRadius, style: .continuous))
      .shadow(color: token.shadow.color, radius: token.shadow.radius, x: token.shadow.x, y: token.shadow.y)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .allowsHitTesting(state.blocksInteraction)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title ?? NECommonUIKitSwiftUIBundle.localized("common_loading", fallback: "Loading"))
    .accessibilityIdentifier("neCommonBlockingLoadingOverlay")
  }

  private var title: String? {
    if let textKey = state.textKey {
      return NECommonUIKitSwiftUIBundle.localized(textKey, fallback: state.fallbackText)
    }
    return state.fallbackText
  }
}
