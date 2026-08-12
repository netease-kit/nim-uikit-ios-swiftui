// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ConversationThemeToken {
  public var styleMode: ConversationStyleMode
  public var pageBackground: Color
  public var navigationBackground: Color
  public var rowBackground: Color
  public var rowStickTopBackground: Color
  public var rowSeparatorColor: Color
  public var primaryTextColor: Color
  public var secondaryTextColor: Color
  public var tertiaryTextColor: Color
  public var accentColor: Color
  public var destructiveColor: Color
  public var topActionColor: Color
  public var muteIconColor: Color
  public var unreadBackgroundColor: Color
  public var unreadTextColor: Color
  public var atTextColor: Color
  public var onlineColor: Color
  public var offlineColor: Color
  public var networkBrokenBackground: Color
  public var networkBrokenTitleColor: Color
  public var popoverBackground: Color
  public var popoverTextColor: Color
  public var searchBackground: Color
  public var searchTextColor: Color
  public var rowHeight: CGFloat
  public var rowHorizontalPadding: CGFloat
  public var avatarSize: CGFloat
  public var avatarCornerRadius: CGFloat
  public var titleFontSize: CGFloat
  public var subtitleFontSize: CGFloat
  public var timeFontSize: CGFloat
  public var unreadMinHeight: CGFloat
  public var unreadHorizontalPadding: CGFloat
  public var onlineIndicatorSize: CGFloat
  public var popoverItemHeight: CGFloat
  public var searchRowHeight: CGFloat
  public var showsRowSeparator: Bool

  public init(styleMode: ConversationStyleMode) {
    self.styleMode = styleMode
    pageBackground = .white
    navigationBackground = .white
    rowBackground = .white
    rowStickTopBackground = NEUIKitSwiftUIStyle.ColorToken.back
    rowSeparatorColor = NEUIKitSwiftUIStyle.ColorToken.navLine
    primaryTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.lightText
    tertiaryTextColor = NEUIKitSwiftUIStyle.ColorToken.dateText
    accentColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    destructiveColor = Color(hex: 0xA8ABB6)
    topActionColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    muteIconColor = NEUIKitSwiftUIStyle.ColorToken.lightText
    unreadBackgroundColor = NEUIKitSwiftUIStyle.ColorToken.red
    unreadTextColor = .white
    atTextColor = NEUIKitSwiftUIStyle.ColorToken.red
    onlineColor = Color(red: 0.518, green: 0.929, blue: 0.522)
    offlineColor = Color(red: 0.831, green: 0.851, blue: 0.855)
    networkBrokenBackground = NEUIKitSwiftUIStyle.ColorToken.normalNetworkBrokenBackground
    networkBrokenTitleColor = NEUIKitSwiftUIStyle.ColorToken.normalNetworkBrokenTitle
    popoverBackground = .white
    popoverTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    searchBackground = NEUIKitSwiftUIStyle.ColorToken.searchBackground
    searchTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    rowHeight = 62
    rowHorizontalPadding = 16
    avatarSize = 42
    avatarCornerRadius = 21
    titleFontSize = 16
    subtitleFontSize = 13
    timeFontSize = 12
    unreadMinHeight = 18
    unreadHorizontalPadding = 6
    onlineIndicatorSize = 12
    popoverItemHeight = 32
    searchRowHeight = 60
    showsRowSeparator = false
  }

  public static let normal = NormalConversationThemeToken.token
  public static let fun = FunConversationThemeToken.token
}
