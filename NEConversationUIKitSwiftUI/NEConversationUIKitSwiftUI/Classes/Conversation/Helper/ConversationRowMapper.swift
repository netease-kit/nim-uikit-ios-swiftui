// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

enum ConversationRowMapper {
  static func row(from snapshot: ConversationItemSnapshot,
                  onlineStatus: [String: Bool]) -> ConversationRowState {
    let targetKind = kind(for: snapshot.type)
    let targetId = snapshot.targetId
    let identity = resolvedIdentity(snapshot: snapshot, targetKind: targetKind, targetId: targetId)
    let title = identity.title
    let timestamp = snapshot.lastMessage?.messageRefer.createTime ?? snapshot.updateTime
    let isAt = snapshot.unreadCount > 0 &&
      NEConversationAtMessageStore.shared.isAtCurrentUser(conversationId: snapshot.conversationId)
    let robot = targetKind == .p2p && (targetId.map { NEAIRobotManager.shared.isRobot($0) } ?? false)
    let subtitle = subtitle(snapshot: snapshot, isAt: isAt, isRobot: robot)
    let online = IMKitConfigCenter.shared.enableOnlineStatus
      ? onlineStatus[snapshot.conversationId] ?? false
      : nil
    let unreadText: String?
    if snapshot.unreadCount <= 0 || snapshot.mute {
      unreadText = nil
    } else if snapshot.unreadCount > 99 {
      unreadText = "99+"
    } else {
      unreadText = "\(snapshot.unreadCount)"
    }

    return ConversationRowState(
      id: snapshot.conversationId,
      conversationId: snapshot.conversationId,
      targetId: targetId,
      targetKind: targetKind,
      title: title,
      subtitle: subtitle,
      timeText: ConversationTimeFormatter.string(from: timestamp),
      avatar: ConversationAvatarState(
        imageURL: NECommonAvatarDisplayResolver.url(from: identity.avatarURLString),
        initials: identity.avatarName ?? targetId ?? snapshot.conversationId,
        hashID: targetId ?? snapshot.conversationId
      ),
      unreadText: unreadText,
      unreadCount: snapshot.unreadCount,
      isStickTop: snapshot.stickTop,
      isMuted: snapshot.mute,
      isAtCurrentUser: isAt,
      isOnline: targetKind == .p2p && !NEAIUserManager.shared.isAIUser(targetId ?? "") ? online : nil,
      isRobot: robot,
      sortOrder: snapshot.sortOrder
    )
  }

  static func aiUserRows(from aiUsers: [V2NIMAIUser]) -> [ConversationAIUserState] {
    aiUsers.compactMap { aiUser in
      guard NEAIUserPinManager.shared.checkoutUnPinAIUser(aiUser) == true,
            let accountId = aiUser.accountId,
            let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
        return nil
      }
      let name = aiUser.name?.isEmpty == false ? aiUser.name ?? accountId : accountId
      return ConversationAIUserState(
        id: accountId,
        title: name,
        avatar: ConversationAvatarState(
          imageURL: NECommonAvatarDisplayResolver.url(from: aiUser.avatar),
          initials: name,
          hashID: accountId
        ),
        conversationId: conversationId
      )
    }
  }

  private static func kind(for type: V2NIMConversationType) -> ConversationTargetKind {
    switch type {
    case .CONVERSATION_TYPE_P2P:
      return .p2p
    case .CONVERSATION_TYPE_TEAM:
      return .team
    default:
      return .unknown
    }
  }

  private static func resolvedTitle(snapshot: ConversationItemSnapshot,
                                    targetId: String?) -> String {
    if let title = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines),
       !title.isEmpty {
      return title
    }
    if let targetId, !targetId.isEmpty {
      return targetId
    }
    return snapshot.conversationId
  }

  private static func resolvedIdentity(snapshot: ConversationItemSnapshot,
                                       targetKind: ConversationTargetKind,
                                       targetId: String?) -> (title: String, avatarName: String?, avatarURLString: String?) {
    let fallbackTitle = resolvedTitle(snapshot: snapshot, targetId: targetId)
    guard targetKind == .p2p, let targetId else {
      return (fallbackTitle, snapshot.shortName, snapshot.avatarURLString)
    }
    guard let user = ChatRepo.cachedSwiftUIDisplayUser(accountId: targetId) else {
      return (fallbackTitle, targetId, snapshot.avatarURLString)
    }

    let cachedTitle = user.showName()?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = cachedTitle?.isEmpty == false ? cachedTitle ?? fallbackTitle : fallbackTitle
    return (
      title,
      user.showName(false) ?? targetId,
      user.user?.avatar ?? snapshot.avatarURLString
    )
  }

  private static func subtitle(snapshot: ConversationItemSnapshot,
                               isAt: Bool,
                               isRobot: Bool) -> String {
    var pieces = [String]()
    if isAt {
      pieces.append(NEConversationUIKitSwiftUIBundle.localized("you_were_mentioned", value: "[You were mentioned]"))
    }
    if isRobot {
      pieces.append(NEConversationUIKitSwiftUIBundle.localized("bot_sub_session_prefix", value: "[Sub-session]"))
    }
    let content = ConversationMessageContentFormatter.content(for: snapshot.lastMessage)
    if !content.isEmpty {
      pieces.append(content)
    }
    return pieces.joined()
  }
}
