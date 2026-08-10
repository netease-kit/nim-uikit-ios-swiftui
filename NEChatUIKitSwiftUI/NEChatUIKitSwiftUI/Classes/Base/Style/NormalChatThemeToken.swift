// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum NormalChatThemeToken {
  public static let token: ChatThemeToken = {
    var t = ChatThemeToken(styleMode: .normal)

    // normalChatNavigationBg / normalChatTableViewBg: white by default
    t.pageBackground = .white
    t.groupedPageBackground = NEUIKitSwiftUIStyle.ColorToken.lightBackground
    t.navigationBackground = .white
    t.inputFieldBackground = .white
    t.panelItemBackground = .white
    t.floatingPanelBackground = .white
    t.incomingBubbleBackground = .white

    // normalChatTableViewBg: white by default
    t.messageListBackground = .white

    // normalChatInputViewBg: #EFF1F3
    t.inputBackground = NEUIKitSwiftUIStyle.ColorToken.normalInputBackground
    // UIKit search fields use ne_backcolor: #F2F4F5
    t.searchFieldBackground = NEUIKitSwiftUIStyle.ColorToken.searchBackground

    // ne_normalTheme: #337EFF
    t.accentColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
    t.mentionTextColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme

    // ne_redText: #E6605C
    t.warningColor = NEUIKitSwiftUIStyle.ColorToken.redText

    // normalChatNavigationDivideBg: #E9EFF5
    t.dividerColor = NEUIKitSwiftUIStyle.ColorToken.navLine

    // ne_greyText: #666666
    t.secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.greyText

    // ne_darkText: #333333 (UIKit uses same color for both incoming and outgoing)
    t.incomingTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
    t.outgoingTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText

    // normalChatControlCornerRadius: 6
    t.controlCornerRadius = 6

    // chat_headWH: 32
    t.avatarSize = 32
    t.avatarCornerRadius = 16

    // chat_timeCellH: 22
    t.timeCellHeight = 22
    // chat_reply_height: 16
    t.replyHeight = 16
    // chat_pin_height: 16
    t.pinHeight = 16
    // chat_full_name_height: 16
    t.fullNameHeight = 16
    // chat_min_h: 40
    t.minBubbleHeight = 40

    // chat_content_maxW: kScreenWidth - 156 (aligned with UIKit ChatCellConstantValue)
    t.messageContentMaxWidth = NEChatUIKitSwiftUIConstants.defaultMessageContentMaxWidth

    // normalChatNetworkBrokenViewBg: #FEE3E6
    t.networkBrokenBackground = NEUIKitSwiftUIStyle.ColorToken.normalNetworkBrokenBackground
    // normalChatNetworkBrokenTitleColor: #FC596A
    t.networkBrokenTitleColor = NEUIKitSwiftUIStyle.ColorToken.normalNetworkBrokenTitle
    // normalChatReplyViewBg: #EFF1F2
    t.replyBackground = Color(hex: 0xEFF1F2)
    // normalChatInputMuteBg: #E3E4E4
    t.mutedInputBackground = Color(hex: 0xE3E4E4)
    // normalSearchMessageCellBg: #F9F9F9
    t.searchResultBackground = Color(hex: 0xF9F9F9)
    // normalChatTranslationDividerColor: #000000 at 8%
    t.translationDividerColor = Color.black.opacity(0.08)
    // normalChatTranslationTagColor: #656A72
    t.translationTagColor = NEUIKitSwiftUIStyle.ColorToken.teamOwnerText

    // chat_file_size: (254, 56)
    t.fileBubbleWidth = 254
    t.fileBubbleHeight = 56
    return t
  }()
}
