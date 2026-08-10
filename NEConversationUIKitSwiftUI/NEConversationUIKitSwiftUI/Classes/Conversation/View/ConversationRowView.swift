// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import SwiftUI

struct ConversationRowView: View {
  let row: ConversationRowState
  let token: ConversationThemeToken

  var body: some View {
    HStack(spacing: 12) {
      avatar

      VStack(alignment: .leading, spacing: token.styleMode == .fun ? 8 : 6) {
        HStack(spacing: 8) {
          Text(row.title)
            .font(.system(size: token.titleFontSize))
            .foregroundColor(token.primaryTextColor)
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: 8)

          Text(row.timeText)
            .font(.system(size: token.timeFontSize))
            .foregroundColor(token.tertiaryTextColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }

        HStack(alignment: .top, spacing: 6) {
          subtitleText
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: 8)

          if row.isMuted {
            Image("noNeed_notify", bundle: NEConversationUIKitSwiftUIBundle.bundle)
              .renderingMode(.original)
              .resizable()
              .scaledToFit()
              .frame(width: token.styleMode == .fun ? 14 : 13,
                     height: token.styleMode == .fun ? 14 : 13)
          }
        }
      }
      .padding(.trailing, 16)
    }
    .padding(.leading, token.rowHorizontalPadding)
    .frame(maxWidth: .infinity)
    .frame(height: token.rowHeight)
    .background(row.isStickTop ? token.rowStickTopBackground : token.rowBackground)
    .overlay(alignment: .bottom) {
      if token.showsRowSeparator {
        Rectangle()
          .fill(token.rowSeparatorColor)
          .frame(height: 0.5)
          .padding(.leading, token.rowHorizontalPadding + token.avatarSize + 12)
      }
    }
    .contentShape(Rectangle())
  }

  private var avatar: some View {
    ZStack(alignment: .topTrailing) {
      ZStack(alignment: .bottomTrailing) {
        NECommonAvatarView(
          imageURL: row.avatar.imageURL,
          initials: row.avatar.initials,
          size: token.avatarSize,
          cornerRadius: token.avatarCornerRadius,
          hashID: row.avatar.hashID
        )
        .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))

        if let online = row.isOnline {
          Circle()
            .fill(online ? token.onlineColor : token.offlineColor)
            .frame(width: token.onlineIndicatorSize, height: token.onlineIndicatorSize)
            .overlay(Circle().stroke(token.rowBackground, lineWidth: 1))
        }
      }

      if let unreadText = row.unreadText {
        Text(unreadText)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(token.unreadTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
          .padding(.horizontal, token.unreadHorizontalPadding)
          .frame(minWidth: token.unreadMinHeight, minHeight: token.unreadMinHeight)
          .background(token.unreadBackgroundColor, in: Capsule())
          .offset(x: 8, y: -8)
      }
    }
    .frame(width: token.avatarSize, height: token.avatarSize)
  }

  @ViewBuilder
  private var subtitleText: some View {
    let atPrefix = NEConversationUIKitSwiftUIBundle.localized("you_were_mentioned", value: "[You were mentioned]")
    if row.subtitle.hasPrefix(atPrefix) {
      Text(atPrefix)
        .foregroundColor(token.atTextColor)
        .font(.system(size: token.subtitleFontSize))
      + MessageEmoticonTextView.text(for: String(row.subtitle.dropFirst(atPrefix.count)))
        .foregroundColor(token.secondaryTextColor)
        .font(.system(size: token.subtitleFontSize))
    } else {
      MessageEmoticonTextView.text(for: row.subtitle)
        .foregroundColor(token.secondaryTextColor)
        .font(.system(size: token.subtitleFontSize))
    }
  }
}
