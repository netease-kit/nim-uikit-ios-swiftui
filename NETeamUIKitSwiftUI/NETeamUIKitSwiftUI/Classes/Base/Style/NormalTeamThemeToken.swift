// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum NormalTeamThemeToken {
  public static let `default` = NETeamThemeToken(
    pageBackground: NEUIKitSwiftUIStyle.ColorToken.lightBackground,
    rowBackground: Color.white,
    primaryText: NEUIKitSwiftUIStyle.ColorToken.darkText,
    secondaryText: NEUIKitSwiftUIStyle.ColorToken.greyText,
    accent: NEUIKitSwiftUIStyle.ColorToken.normalTheme,
    destructive: NEUIKitSwiftUIStyle.ColorToken.redText,
    separator: NEUIKitSwiftUIStyle.ColorToken.border,
    headerHorizontalMargin: 20,
    headerCornerRadius: 8,
    avatarEditPreviewCornerRadius: 44,
    sectionHorizontalMargin: 20,
    sectionCornerRadius: 8
  )
}
