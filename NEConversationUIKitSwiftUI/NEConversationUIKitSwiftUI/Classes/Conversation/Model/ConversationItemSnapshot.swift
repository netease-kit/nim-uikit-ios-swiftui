// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NIMSDK

struct ConversationItemSnapshot: Identifiable, Equatable {
  var id: String { conversationId }
  var conversationId: String
  var targetId: String?
  var type: V2NIMConversationType
  var title: String?
  var shortName: String?
  var avatarURLString: String?
  var mute: Bool
  var stickTop: Bool
  var unreadCount: Int
  var sortOrder: Int64
  var updateTime: TimeInterval?
  var lastMessage: V2NIMLastMessage?

  init(conversationId: String,
       targetId: String?,
       type: V2NIMConversationType,
       title: String?,
       shortName: String?,
       avatarURLString: String?,
       mute: Bool,
       stickTop: Bool,
       unreadCount: Int,
       sortOrder: Int64,
       updateTime: TimeInterval?,
       lastMessage: V2NIMLastMessage?) {
    self.conversationId = conversationId
    self.targetId = targetId
    self.type = type
    self.title = title
    self.shortName = shortName
    self.avatarURLString = avatarURLString
    self.mute = mute
    self.stickTop = stickTop
    self.unreadCount = unreadCount
    self.sortOrder = sortOrder
    self.updateTime = updateTime
    self.lastMessage = lastMessage
  }
}

extension ConversationItemSnapshot {
  init(_ conversation: V2NIMConversation) {
    self.init(
      conversationId: conversation.conversationId,
      targetId: V2NIMConversationIdUtil.conversationTargetId(conversation.conversationId),
      type: conversation.type,
      title: conversation.name,
      shortName: conversation.shortName(),
      avatarURLString: conversation.avatar,
      mute: conversation.mute,
      stickTop: conversation.stickTop,
      unreadCount: conversation.unreadCount,
      sortOrder: conversation.sortOrder,
      updateTime: conversation.updateTime,
      lastMessage: conversation.lastMessage
    )
  }

  init(_ conversation: V2NIMLocalConversation) {
    self.init(
      conversationId: conversation.conversationId,
      targetId: V2NIMConversationIdUtil.conversationTargetId(conversation.conversationId),
      type: conversation.type,
      title: conversation.name,
      shortName: conversation.shortName(),
      avatarURLString: conversation.avatar,
      mute: conversation.mute,
      stickTop: conversation.stickTop,
      unreadCount: conversation.unreadCount,
      sortOrder: conversation.sortOrder,
      updateTime: conversation.updateTime,
      lastMessage: conversation.lastMessage
    )
  }
}
