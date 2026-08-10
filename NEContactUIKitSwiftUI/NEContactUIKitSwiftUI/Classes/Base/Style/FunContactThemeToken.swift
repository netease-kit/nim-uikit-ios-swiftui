// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum FunContactThemeToken {
  public static let token: ContactThemeToken = {
    var token = ContactThemeToken(styleMode: .fun)
    token.pageBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
    token.navigationBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
    token.sectionBackground = .white
    token.rowBackground = .white
    token.rowSeparatorColor = Color(hex: 0xE4E9F2)
    token.searchBackground = .white
    token.sectionTitleColor = NEUIKitSwiftUIStyle.ColorToken.emptyTitle
    token.primaryTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    token.secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.greyText
    token.tertiaryTextColor = NEUIKitSwiftUIStyle.ColorToken.lightText
    token.accentColor = NEUIKitSwiftUIStyle.ColorToken.funTheme
    token.selectionTintColor = token.accentColor
    token.titleFontSize = 17
    token.avatarCornerRadius = 4
    return token
  }()
}
