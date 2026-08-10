// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

struct NEChatLocalIconLabel: View {
  var title: String
  var imageName: String
  var token: ChatThemeToken
  var renderingMode: NECommonImageRenderingMode = .template
  var iconSize: CGSize = CGSize(width: 16, height: 16)
  var foregroundColor: Color? = nil

  var body: some View {
    HStack(spacing: 6) {
      NEChatCommonPresentation.iconView(
        imageName: imageName,
        token: token,
        renderingMode: renderingMode,
        size: iconSize,
        foregroundColor: foregroundColor,
        accessibilityLabel: title
      )
      Text(title)
    }
  }
}
