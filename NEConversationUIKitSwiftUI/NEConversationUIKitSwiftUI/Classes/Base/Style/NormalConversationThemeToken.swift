// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum NormalConversationThemeToken {
  public static var token: ConversationThemeToken {
    var token = ConversationThemeToken(styleMode: .normal)
    token.pageBackground = .white
    token.navigationBackground = .white
    token.rowBackground = .white
    token.rowStickTopBackground = NEUIKitSwiftUIStyle.ColorToken.back
    token.destructiveColor = Color(hex: 0xA8ABB6)
    token.popoverBackground = .white
    token.popoverTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    token.networkBrokenBackground = NEUIKitSwiftUIStyle.ColorToken.normalNetworkBrokenBackground
    token.networkBrokenTitleColor = NEUIKitSwiftUIStyle.ColorToken.normalNetworkBrokenTitle
    token.avatarSize = 42
    token.avatarCornerRadius = 21
    token.rowHeight = 62
    token.titleFontSize = 16
    token.showsRowSeparator = false
    return token
  }
}
