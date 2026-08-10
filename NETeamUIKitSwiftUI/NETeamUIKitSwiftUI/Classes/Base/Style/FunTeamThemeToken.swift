// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum FunTeamThemeToken {
  public static let `default`: NETeamThemeToken = {
    var t = NETeamThemeToken(
      styleMode: .fun,
      pageBackground: NEUIKitSwiftUIStyle.ColorToken.funBackground,
      rowBackground: Color.white,
      primaryText: NEUIKitSwiftUIStyle.ColorToken.darkText,
      secondaryText: NEUIKitSwiftUIStyle.ColorToken.greyText,
      accent: NEUIKitSwiftUIStyle.ColorToken.funTheme,
      destructive: NEUIKitSwiftUIStyle.ColorToken.redText,
      separator: NEUIKitSwiftUIStyle.ColorToken.funLineBorder,
      ownerText: NEUIKitSwiftUIStyle.ColorToken.funTheme,
      ownerBackground: NEUIKitSwiftUIStyle.ColorToken.funTheme.opacity(0.1),
      ownerBorder: NEUIKitSwiftUIStyle.ColorToken.funTheme
    )

    t.headerHeight = 188
    t.headerHorizontalMargin = 0
    t.headerCornerRadius = 0
    t.headerAvatarSize = 50
    t.headerAvatarCornerRadius = 4
    t.previewTitleHeight = 50
    t.previewListHeight = 56
    t.previewAvatarSize = 36
    t.previewAvatarCornerRadius = 4
    t.previewMemberSpacing = 16
    t.memberRowHeight = 64
    t.memberAvatarSize = 40
    t.memberAvatarCornerRadius = 4
    t.infoAvatarSize = 42
    t.infoAvatarCornerRadius = 4
    t.detailAvatarSize = 60
    t.detailAvatarCornerRadius = 4
    t.avatarEditPreviewSize = 88
    t.avatarEditPreviewCornerRadius = 4
    t.defaultAvatarSelectionSize = 56
    t.defaultAvatarIconSize = 40
    t.defaultAvatarIconCornerRadius = 4
    t.sectionHorizontalMargin = 0
    t.sectionCornerRadius = 0
    t.destructiveButtonHeight = 56
    t.destructiveButtonTopPadding = 12
    t.destructiveButtonHorizontalMargin = 0
    t.textEditContainerHeight = 60
    t.textEditContainerHorizontalMargin = 0
    t.textEditContainerTopPadding = 0
    t.textEditContainerCornerRadius = 0
    t.introduceEditContainerHeight = 142
    t.rowHeight = 56

    return t
  }()
}
