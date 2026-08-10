// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

struct ChatNetworkBrokenBannerView: View {
  let token: ChatThemeToken

  var body: some View {
    HStack(spacing: 18) {
      NEChatCommonPresentation.commonIconView(
        imageName: "error",
        token: token,
        renderingMode: .original,
        size: CGSize(width: 20, height: 20),
        foregroundColor: token.networkBrokenTitleColor,
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
      )
      .opacity(token.styleMode == .fun ? 1 : 0)

      Text(NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"))
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
