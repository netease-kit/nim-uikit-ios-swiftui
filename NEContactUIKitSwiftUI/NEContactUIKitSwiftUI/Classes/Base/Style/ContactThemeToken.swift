// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ContactThemeToken {
  public var styleMode: ContactStyleMode
  public var pageBackground: Color
  public var navigationBackground: Color
  public var rowBackground: Color
  public var rowSeparatorColor: Color
  public var sectionBackground: Color
  public var sectionTitleColor: Color
  public var primaryTextColor: Color
  public var secondaryTextColor: Color
  public var tertiaryTextColor: Color
  public var accentColor: Color
  public var destructiveColor: Color
  public var unreadBackgroundColor: Color
  public var unreadTextColor: Color
  public var searchBackground: Color
  public var onlineColor: Color
  public var offlineColor: Color
  public var selectionTintColor: Color
  public var rowHeight: CGFloat
  public var headerRowHeight: CGFloat
  public var sectionHeaderHeight: CGFloat
  public var rowHorizontalPadding: CGFloat
  public var avatarSize: CGFloat
  public var avatarCornerRadius: CGFloat
  public var titleFontSize: CGFloat
  public var subtitleFontSize: CGFloat
  public var indexFontSize: CGFloat
  public var badgeMinHeight: CGFloat
  public var badgeHorizontalPadding: CGFloat

  public init(styleMode: ContactStyleMode) {
    self.styleMode = styleMode
    pageBackground = .white
    navigationBackground = .white
    rowBackground = .white
    rowSeparatorColor = NEUIKitSwiftUIStyle.ColorToken.border
    sectionBackground = .white
    sectionTitleColor = NEUIKitSwiftUIStyle.ColorToken.emptyTitle
    primaryTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.greyText
    tertiaryTextColor = NEUIKitSwiftUIStyle.ColorToken.lightText
    accentColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    destructiveColor = NEUIKitSwiftUIStyle.ColorToken.redText
    unreadBackgroundColor = NEUIKitSwiftUIStyle.ColorToken.red
    unreadTextColor = .white
    searchBackground = NEUIKitSwiftUIStyle.ColorToken.searchBackground
    onlineColor = Color(red: 0.518, green: 0.929, blue: 0.522)
    offlineColor = Color(red: 0.831, green: 0.851, blue: 0.855)
    selectionTintColor = accentColor
    rowHeight = 56
    headerRowHeight = 56
    sectionHeaderHeight = 30
    rowHorizontalPadding = 20
    avatarSize = 36
    avatarCornerRadius = 18
    titleFontSize = 14
    subtitleFontSize = 12
    indexFontSize = 11
    badgeMinHeight = 18
    badgeHorizontalPadding = 7
  }

  public static let normal = NormalContactThemeToken.token
  public static let fun = FunContactThemeToken.token
}
