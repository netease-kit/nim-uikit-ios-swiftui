// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum FunConversationThemeToken {
  public static var token: ConversationThemeToken {
    var token = ConversationThemeToken(styleMode: .fun)
    token.pageBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
    token.navigationBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
    token.rowBackground = .white
    token.rowStickTopBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
    token.rowSeparatorColor = NEUIKitSwiftUIStyle.ColorToken.funListLineBorder
    token.accentColor = NEUIKitSwiftUIStyle.ColorToken.funTheme
    token.topActionColor = NEUIKitSwiftUIStyle.ColorToken.funTheme
    token.destructiveColor = Color(hex: 0xE75E58)
    token.popoverBackground = Color(hex: 0x4C4C4C)
    token.popoverTextColor = .white
    token.networkBrokenBackground = NEUIKitSwiftUIStyle.ColorToken.funNetworkBrokenBackground
    token.networkBrokenTitleColor = Color.black.opacity(0.5)
    token.avatarSize = 48
    token.avatarCornerRadius = 4
    token.rowHeight = 72
    token.titleFontSize = 17
    token.showsRowSeparator = true
    return token
  }
}
