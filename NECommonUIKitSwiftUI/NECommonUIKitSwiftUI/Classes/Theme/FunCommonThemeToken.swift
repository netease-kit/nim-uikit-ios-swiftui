// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum FunCommonThemeToken {
  public static let token: NECommonThemeToken = {
    let palette = NECommonThemePalette(
      pageBackground: NEUIKitSwiftUIStyle.ColorToken.funBackground,
      rowBackground: .white,
      elevatedBackground: .white,
      primaryText: NEUIKitSwiftUIStyle.ColorToken.darkText,
      secondaryText: NEUIKitSwiftUIStyle.ColorToken.greyText,
      tertiaryText: NEUIKitSwiftUIStyle.ColorToken.lightText,
      accent: NEUIKitSwiftUIStyle.ColorToken.funTheme,
      destructive: NEUIKitSwiftUIStyle.ColorToken.redText,
      warning: Color(red: 0.94, green: 0.53, blue: 0.12),
      separator: NEUIKitSwiftUIStyle.ColorToken.funLineBorder,
      disabled: NEUIKitSwiftUIStyle.ColorToken.dateText
    )

    let button = NECommonButtonToken(
      primaryBackground: NEUIKitSwiftUIStyle.ColorToken.funTheme,
      primaryForeground: .white,
      secondaryBackground: NEUIKitSwiftUIStyle.ColorToken.back,
      secondaryForeground: NEUIKitSwiftUIStyle.ColorToken.funTheme,
      destructiveBackground: NEUIKitSwiftUIStyle.ColorToken.redText,
      destructiveForeground: .white,
      disabledBackground: NEUIKitSwiftUIStyle.ColorToken.funLineBorder,
      disabledForeground: NEUIKitSwiftUIStyle.ColorToken.lightText
    )

    return NECommonThemeToken(
      styleMode: .fun,
      palette: palette,
      typography: NECommonTypography(
        title: NEUIKitSwiftUIStyle.FontToken.navTitle,
        headline: NEUIKitSwiftUIStyle.FontToken.settingTitle,
        body: NEUIKitSwiftUIStyle.FontToken.settingTitle,
        footnote: NEUIKitSwiftUIStyle.FontToken.pinMessage,
        caption: NEUIKitSwiftUIStyle.FontToken.settingSubtitle
      ),
      spacing: NECommonSpacing(),
      radius: NECommonRadius(small: 6, medium: 10, large: 14, avatar: 20),
      shadow: NECommonShadow(color: Color(red: 0.36, green: 0.13, blue: 0.44).opacity(0.10)),
      avatar: NECommonAvatarToken(
        background: NEUIKitSwiftUIStyle.ColorToken.avatarBackground,
        foreground: .white
      ),
      badge: NECommonBadgeToken(
        background: NEUIKitSwiftUIStyle.ColorToken.red,
        foreground: .white
      ),
      button: button,
      overlay: NECommonOverlayToken(
        toastBackground: Color.black.opacity(0.82),
        toastForeground: .white,
        scrim: Color.black.opacity(0.24)
      )
    )
  }()
}
