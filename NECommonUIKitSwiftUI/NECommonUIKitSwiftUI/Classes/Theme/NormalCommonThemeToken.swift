// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum NormalCommonThemeToken {
  public static let token = NECommonThemeToken(
    styleMode: .normal,
    palette: NECommonThemePalette(
      pageBackground: NEUIKitSwiftUIStyle.ColorToken.lightBackground,
      rowBackground: .white,
      elevatedBackground: .white,
      primaryText: NEUIKitSwiftUIStyle.ColorToken.darkText,
      secondaryText: NEUIKitSwiftUIStyle.ColorToken.greyText,
      tertiaryText: NEUIKitSwiftUIStyle.ColorToken.lightText,
      accent: NEUIKitSwiftUIStyle.ColorToken.normalTheme,
      destructive: NEUIKitSwiftUIStyle.ColorToken.redText,
      warning: Color(red: 0.93, green: 0.56, blue: 0.13),
      separator: NEUIKitSwiftUIStyle.ColorToken.border,
      disabled: NEUIKitSwiftUIStyle.ColorToken.dateText
    ),
    typography: NECommonTypography(
      title: NEUIKitSwiftUIStyle.FontToken.navTitle,
      headline: NEUIKitSwiftUIStyle.FontToken.settingTitle,
      body: NEUIKitSwiftUIStyle.FontToken.settingTitle,
      footnote: NEUIKitSwiftUIStyle.FontToken.pinMessage,
      caption: NEUIKitSwiftUIStyle.FontToken.settingSubtitle
    ),
    spacing: NECommonSpacing(),
    radius: NECommonRadius(),
    shadow: NECommonShadow(),
    avatar: NECommonAvatarToken(
      background: NEUIKitSwiftUIStyle.ColorToken.avatarBackground,
      foreground: .white
    ),
    badge: NECommonBadgeToken(
      background: NEUIKitSwiftUIStyle.ColorToken.red,
      foreground: .white
    ),
    button: NECommonButtonToken(
      primaryBackground: NEUIKitSwiftUIStyle.ColorToken.normalTheme,
      primaryForeground: .white,
      secondaryBackground: NEUIKitSwiftUIStyle.ColorToken.lightBackground,
      secondaryForeground: NEUIKitSwiftUIStyle.ColorToken.normalTheme,
      destructiveBackground: NEUIKitSwiftUIStyle.ColorToken.redText,
      destructiveForeground: .white,
      disabledBackground: NEUIKitSwiftUIStyle.ColorToken.border,
      disabledForeground: NEUIKitSwiftUIStyle.ColorToken.lightText
    ),
    overlay: NECommonOverlayToken(
      toastBackground: Color.black.opacity(0.82),
      toastForeground: .white,
      scrim: Color.black.opacity(0.28)
    )
  )
}
