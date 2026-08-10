// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum NormalContactThemeToken {
  public static let token: ContactThemeToken = {
    var token = ContactThemeToken(styleMode: .normal)
    token.pageBackground = .white
    token.navigationBackground = .white
    token.sectionBackground = .white
    token.rowBackground = .white
    token.rowSeparatorColor = NEUIKitSwiftUIStyle.ColorToken.greyLine
    token.sectionTitleColor = NEUIKitSwiftUIStyle.ColorToken.emptyTitle
    token.primaryTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    token.secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.greyText
    token.tertiaryTextColor = NEUIKitSwiftUIStyle.ColorToken.lightText
    token.accentColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    token.selectionTintColor = token.accentColor
    token.titleFontSize = 14
    token.avatarCornerRadius = 18
    return token
  }()
}
