// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

enum NEConversationCommonPresentation {
  static func commonTheme(for token: ConversationThemeToken) -> NECommonThemeToken {
    var commonToken = token.styleMode == .fun ? NECommonThemeToken.fun : NECommonThemeToken.normal
    commonToken.palette = NECommonThemePalette(
      pageBackground: token.pageBackground,
      rowBackground: token.rowBackground,
      elevatedBackground: token.rowBackground,
      primaryText: token.primaryTextColor,
      secondaryText: token.secondaryTextColor,
      tertiaryText: token.tertiaryTextColor,
      accent: token.accentColor,
      destructive: token.destructiveColor,
      warning: token.destructiveColor,
      separator: token.rowSeparatorColor,
      disabled: token.rowSeparatorColor.opacity(0.72)
    )
    commonToken.badge = NECommonBadgeToken(
      background: token.unreadBackgroundColor,
      foreground: token.unreadTextColor,
      minSize: token.unreadMinHeight
    )
    commonToken.avatar = NECommonAvatarToken(
      size: token.avatarSize,
      cornerRadius: token.avatarCornerRadius,
      background: token.accentColor,
      foreground: .white
    )
    commonToken.overlay = NECommonOverlayToken(
      toastBackground: Color.black.opacity(0.78),
      toastForeground: .white,
      scrim: Color.black.opacity(0.18),
      cornerRadius: 8
    )
    return commonToken
  }

  static func searchTheme(for token: ConversationThemeToken) -> NECommonThemeToken {
    var commonToken = commonTheme(for: token)
    commonToken.palette.rowBackground = token.searchBackground
    commonToken.palette.elevatedBackground = token.searchBackground
    return commonToken
  }
}
