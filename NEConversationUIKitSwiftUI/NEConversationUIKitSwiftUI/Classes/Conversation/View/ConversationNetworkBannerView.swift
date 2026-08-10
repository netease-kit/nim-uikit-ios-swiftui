// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

struct ConversationNetworkBannerView: View {
  let token: ConversationThemeToken

  var body: some View {
    HStack(spacing: 18) {
      NECommonIconView(
        imageName: "error",
        bundle: NECommonUIKitSwiftUIBundle.bundle,
        renderingMode: .original,
        size: CGSize(width: 20, height: 20),
        foregroundColor: token.networkBrokenTitleColor,
        accessibilityLabel: NEConversationUIKitSwiftUIBundle.localized("network_error", value: "Network unavailable")
      )
      .opacity(token.styleMode == .fun ? 1 : 0)

      Text(NEConversationUIKitSwiftUIBundle.localized("network_error", value: "Network unavailable"))
        .font(.system(size: 14))
        .foregroundColor(token.networkBrokenTitleColor)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
      .padding(.leading, 30)
      .padding(.trailing, 15)
      .frame(maxWidth: .infinity)
      .frame(height: token.styleMode == .fun ? 48 : 36)
      .background(token.networkBrokenBackground)
  }
}
