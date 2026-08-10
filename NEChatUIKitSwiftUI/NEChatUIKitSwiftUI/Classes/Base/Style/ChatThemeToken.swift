// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ChatThemeToken {
  public var styleMode: ChatStyleMode
  public var pageBackground: Color
  public var groupedPageBackground: Color
  public var messageListBackground: Color
  public var navigationBackground: Color
  public var inputBackground: Color
  public var inputFieldBackground: Color
  public var searchFieldBackground: Color
  public var panelItemBackground: Color
  public var floatingPanelBackground: Color
  public var incomingBubbleBackground: Color
  public var outgoingBubbleBackground: Color
  public var incomingTextColor: Color
  public var outgoingTextColor: Color
  public var primaryButtonTextColor: Color
  public var secondaryTextColor: Color
  public var dividerColor: Color
  public var accentColor: Color
  public var mentionTextColor: Color
  public var warningColor: Color
  public var bubbleCornerRadius: CGFloat
  public var controlCornerRadius: CGFloat
  public var floatingPanelCornerRadius: CGFloat
  public var floatingPillCornerRadius: CGFloat
  public var avatarSize: CGFloat
  public var avatarCornerRadius: CGFloat
  public var incomingMessageFontSize: CGFloat
  public var outgoingMessageFontSize: CGFloat
  public var senderNameFontSize: CGFloat
  public var timeDividerFontSize: CGFloat
  public var deliveryStatusFontSize: CGFloat
  public var messageContentMaxWidth: CGFloat
  public var messageMaxWidthRatio: CGFloat
  public var messageRowHorizontalPadding: CGFloat
  public var messageRowVerticalPadding: CGFloat
  public var rowVerticalSpacing: CGFloat
  public var bubbleHorizontalPadding: CGFloat
  public var bubbleVerticalPadding: CGFloat
  public var selectionBorderWidth: CGFloat
  public var panelMaxHeight: CGFloat
  public var mediaThumbnailWidth: CGFloat
  public var mediaThumbnailMinHeight: CGFloat
  public var mediaThumbnailMaxHeight: CGFloat
  public var funMargin: CGFloat

  public var networkBrokenBackground: Color = .clear
  public var networkBrokenTitleColor: Color = .black
  public var replyBackground: Color = .clear
  public var mutedInputBackground: Color = .clear
  public var searchResultBackground: Color = .clear
  public var translationDividerColor: Color = .clear
  public var translationTagColor: Color = .clear
  /// 置顶/Pin 消息高亮背景色 — UIKit: ne_yellowBackgroundColor = #FFFBEA
  public var signalBackgroundColor: Color = Color(red: 1.0, green: 0.984, blue: 0.918)
  /// 置顶/Pin 指示符颜色 — UIKit: ne_greenText = #3EAF96
  public var pinIndicatorColor: Color = Color(red: 0.243, green: 0.686, blue: 0.588)
  /// 安全提醒文字颜色 — UIKit IMUIKitExample: #EB9718
  public var securityWarningColor: Color = Color(hex: 0xEB9718)
  /// 合并转发内容分割线颜色 — UIKit: multiForwardLineColor = #F0F1F5
  public var multiForwardLineColor: Color = Color(red: 0.941, green: 0.945, blue: 0.961)
  /// 默认头像背景色 — UIKit: ne_defautAvatarColor = #537FF4
  public var avatarBackgroundColor: Color = Color(red: 0.325, green: 0.498, blue: 0.957)
  /// 默认头像文字/图标前景色 — UIKit: white on colored background
  public var avatarForegroundColor: Color = .white

  public var timeCellHeight: CGFloat = 22
  public var replyHeight: CGFloat = 16
  public var pinHeight: CGFloat = 16
  public var fullNameHeight: CGFloat = 16
  public var minBubbleHeight: CGFloat = 40
  public var audioMaxWidth: CGFloat = 265
  public var fileBubbleWidth: CGFloat = 254
  public var fileBubbleHeight: CGFloat = 56

  public init(styleMode: ChatStyleMode) {
    self.styleMode = styleMode
    self.pageBackground = .white
    self.groupedPageBackground = NEUIKitSwiftUIStyle.ColorToken.lightBackground
    self.messageListBackground = .white
    self.navigationBackground = .white
    self.inputBackground = NEUIKitSwiftUIStyle.ColorToken.normalInputBackground
    self.inputFieldBackground = .white
    self.searchFieldBackground = NEUIKitSwiftUIStyle.ColorToken.searchBackground
    self.panelItemBackground = .white
    self.floatingPanelBackground = .white
    self.incomingBubbleBackground = .white
    self.outgoingBubbleBackground = .clear
    self.incomingTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    self.outgoingTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    self.primaryButtonTextColor = .white
    self.secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.greyText
    self.dividerColor = NEUIKitSwiftUIStyle.ColorToken.navLine
    self.accentColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    self.mentionTextColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    self.warningColor = NEUIKitSwiftUIStyle.ColorToken.redText
    self.bubbleCornerRadius = 8
    self.controlCornerRadius = 6
    self.floatingPanelCornerRadius = 8
    self.floatingPillCornerRadius = 20
    self.avatarSize = 32
    self.avatarCornerRadius = 16
    self.incomingMessageFontSize = 16
    self.outgoingMessageFontSize = 16
    self.senderNameFontSize = 12
    self.timeDividerFontSize = 11
    self.deliveryStatusFontSize = 11
    self.messageContentMaxWidth = 300
    self.messageMaxWidthRatio = 0.72
    self.messageRowHorizontalPadding = 16
    self.messageRowVerticalPadding = 2
    self.rowVerticalSpacing = 8
    self.bubbleHorizontalPadding = 8
    self.bubbleVerticalPadding = 8
    self.selectionBorderWidth = 2
    self.panelMaxHeight = 204
    self.mediaThumbnailWidth = 150
    self.mediaThumbnailMinHeight = 40
    self.mediaThumbnailMaxHeight = 200
    self.funMargin = 0
  }

  public static let normal = NormalChatThemeToken.token
  public static let fun = FunChatThemeToken.token
}
