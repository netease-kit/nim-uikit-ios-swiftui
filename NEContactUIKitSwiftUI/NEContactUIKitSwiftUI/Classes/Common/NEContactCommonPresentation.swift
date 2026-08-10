// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum NEContactCommonPresentation {
  public static func commonTheme(for token: ContactThemeToken) -> NECommonThemeToken {
    var common = token.styleMode == .fun ? NECommonThemeToken.fun : NECommonThemeToken.normal
    common.palette.pageBackground = token.pageBackground
    common.palette.rowBackground = token.rowBackground
    common.palette.elevatedBackground = token.rowBackground
    common.palette.primaryText = token.primaryTextColor
    common.palette.secondaryText = token.secondaryTextColor
    common.palette.tertiaryText = token.tertiaryTextColor
    common.palette.accent = token.accentColor
    common.palette.destructive = token.destructiveColor
    common.palette.separator = token.rowSeparatorColor
    common.badge.background = token.unreadBackgroundColor
    common.badge.foreground = token.unreadTextColor
    common.button.primaryBackground = token.accentColor
    return common
  }

  public static func searchTheme(for token: ContactThemeToken) -> NECommonThemeToken {
    var common = commonTheme(for: token)
    common.palette.rowBackground = token.searchBackground
    common.palette.elevatedBackground = token.searchBackground
    return common
  }
}
