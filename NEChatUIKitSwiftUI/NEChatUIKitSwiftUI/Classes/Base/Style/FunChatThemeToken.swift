// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public enum FunChatThemeToken {
    public static let token: ChatThemeToken = {
        var t = ChatThemeToken(styleMode: .fun)

        // funChatBackgroundColor: #EDEDED
        t.pageBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
        t.groupedPageBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground
        t.messageListBackground = Color.clear
        // funChatNavigationBg = funChatBackgroundColor: #EDEDED
        t.navigationBackground = NEUIKitSwiftUIStyle.ColorToken.funBackground

        // funChatInputViewBg: #F5F5F5
        t.inputBackground = NEUIKitSwiftUIStyle.ColorToken.funInputBackground
        // funChatInputBg: white
        t.inputFieldBackground = .white
        t.searchFieldBackground = NEUIKitSwiftUIStyle.ColorToken.searchBackground
        t.panelItemBackground = .white
        t.floatingPanelBackground = .white
        t.incomingBubbleBackground = .white

        // ne_darkText: #333333
        t.incomingTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
        t.outgoingTextColor = NEUIKitSwiftUIStyle.ColorToken.darkText
        // ne_greyText: #666666
        t.secondaryTextColor = NEUIKitSwiftUIStyle.ColorToken.greyText

        // ne_funTheme: #58BE6B (green — matches UIKit exactly)
        t.accentColor = NEUIKitSwiftUIStyle.ColorToken.funTheme
        // UIKit @ highlight stays ne_normalTheme in both NormalUI and FunUI.
        t.mentionTextColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
        // ne_redText: #E6605C
        t.warningColor = NEUIKitSwiftUIStyle.ColorToken.redText

        // funChatNavigationDivideBg: #D5D5D5 at 40%
        t.dividerColor = Color(hex: 0xD5D5D5).opacity(0.4)

        // Fun control radius
        t.controlCornerRadius = 8

        // Fun avatar: rectangular style, default corner radius = 4.
        t.avatarSize = 42
        t.avatarCornerRadius = 4

        // funMargin: 5.2
        t.funMargin = 5.2

        // chat_timeCellH: 22
        t.timeCellHeight = 22
        // fun_chat_reply_height: 44
        t.replyHeight = 44
        // chat_content_maxW: kScreenWidth - 156 (aligned with UIKit ChatCellConstantValue)
        t.messageContentMaxWidth = NEChatUIKitSwiftUIConstants.defaultMessageContentMaxWidth
        // chat_pin_height: 16
        t.pinHeight = 16
        // chat_full_name_height: 16
        t.fullNameHeight = 16
        // fun_chat_min_h: 42
        t.minBubbleHeight = 42
        t.mediaThumbnailMinHeight = 42

        // funChatNetworkBrokenViewBg: #FCEEEE
        t.networkBrokenBackground = NEUIKitSwiftUIStyle.ColorToken.funNetworkBrokenBackground
        // funChatNetworkBrokenTitleColor: UIColor(white: 0, alpha: 0.5)
        t.networkBrokenTitleColor = Color.black.opacity(0.5)
        // funChatReplyViewBg: #E1E1E1
        t.replyBackground = Color(hex: 0xE1E1E1)
        // funChatInputMuteBg: #E0E0E0
        t.mutedInputBackground = Color(hex: 0xE0E0E0)

        // funChatTranslationTagColor: #656A72
        t.translationTagColor = NEUIKitSwiftUIStyle.ColorToken.teamOwnerText
        t.translationDividerColor = Color.black.opacity(0.08)

        // chat_file_size: (254, 56)
        t.fileBubbleWidth = 254
        t.fileBubbleHeight = 56
        return t
    }()
}
