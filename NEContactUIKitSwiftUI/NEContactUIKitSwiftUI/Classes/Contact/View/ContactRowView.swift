// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NEChatKit
import SwiftUI

public struct ContactRowView: View {
  var entry: ContactEntryState
  var token: ContactThemeToken
  var showsSelection: Bool
  var showsOnlineStatus: Bool

  public init(entry: ContactEntryState,
              token: ContactThemeToken,
              showsSelection: Bool = false,
              showsOnlineStatus: Bool = true) {
    self.entry = entry
    self.token = token
    self.showsSelection = showsSelection
    self.showsOnlineStatus = showsOnlineStatus
  }

  public var body: some View {
    HStack(spacing: 12) {
      if showsSelection {
        NECommonSelectionIndicatorView(
          isSelected: entry.isSelected,
          isEnabled: !entry.isDisabled
        )
        .frame(width: 24, height: 24)
      }

      avatar

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.title)
          .font(.system(size: token.titleFontSize))
          .foregroundColor(entry.isDisabled ? token.tertiaryTextColor : token.primaryTextColor)
          .lineLimit(1)
          .truncationMode(.tail)

        if let subtitle = entry.subtitle, !subtitle.isEmpty, entry.kind != .friend {
          Text(subtitle)
            .font(.system(size: token.subtitleFontSize))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }

      Spacer(minLength: 8)

      if entry.unreadCount > 0 {
        ContactUnreadBadge(count: entry.unreadCount, token: token)
      }
    }
    .frame(height: entry.kind == .friend ? token.rowHeight : token.headerRowHeight)
    .padding(.leading, token.rowHorizontalPadding)
    .padding(.trailing, 16)
    .background(token.rowBackground)
    .contentShape(Rectangle())
    .opacity(entry.isDisabled ? 0.45 : 1)
    .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
  }

  @ViewBuilder
  private var avatar: some View {
    ZStack(alignment: .bottomTrailing) {
      if let imageName = entry.imageName {
        ContactImageResource(name: imageName, size: token.avatarSize)
      } else if entry.kind == .team {
        NECommonAvatarView(
          imageURL: resolvedAvatarURL,
          initials: initials,
          size: token.avatarSize,
          cornerRadius: token.avatarCornerRadius,
          hashID: entry.accountId
        )
      } else {
        NECommonAvatarView(
          imageURL: resolvedAvatarURL,
          initials: initials,
          size: token.avatarSize,
          cornerRadius: token.avatarCornerRadius,
          hashID: entry.accountId
        )
      }

      if showsOnlineStatus, entry.kind == .friend {
        Circle()
          .fill(entry.isOnline ? token.onlineColor : token.offlineColor)
          .frame(width: 9, height: 9)
          .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
          .offset(x: 1, y: 1)
      }
    }
  }

  private var initials: String {
    NECommonAvatarDisplayResolver.initials(
      displayName: entry.avatarName,
      fallbackID: entry.accountId,
      defaultText: "#"
    )
  }

  private var resolvedAvatarURL: URL? {
    let entryURL = NECommonAvatarDisplayResolver.url(from: entry.avatarURL)
    guard entry.kind == .friend else {
      return entryURL
    }
    return entryURL ??
      entry.accountId
      .flatMap { NEFriendUserCache.shared.getFriendInfo($0)?.user?.avatar }
      .flatMap { NECommonAvatarDisplayResolver.url(from: $0) }
  }
}

private struct ContactUnreadBadge: View {
  var count: Int
  var token: ContactThemeToken

  var body: some View {
    Text(count > 99 ? "99+" : "\(count)")
      .font(.system(size: 12))
      .foregroundColor(token.unreadTextColor)
      .padding(.horizontal, token.badgeHorizontalPadding)
      .frame(minHeight: token.badgeMinHeight)
      .background(token.unreadBackgroundColor, in: Capsule())
  }
}
