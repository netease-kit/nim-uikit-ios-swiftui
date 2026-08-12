// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NIMSDK

public enum ChatSessionKind: String, CaseIterable, Identifiable, Equatable {
  case p2p
  case team
  case botSubSession
  case topic
  case history

  public var id: String {
    rawValue
  }
}

public struct ChatSessionContext: Equatable, Identifiable {
  public var kind: ChatSessionKind
  public var conversationId: String
  public var title: String?
  public var sessionId: String?
  public var sessionName: String?
  public var anchorMessage: V2NIMMessage?
  public var pendingMessages: [V2NIMMessage]
  public var topic: V2NIMTopic?

  public init(kind: ChatSessionKind,
              conversationId: String,
              title: String? = nil,
              sessionId: String? = nil,
              sessionName: String? = nil,
              anchorMessage: V2NIMMessage? = nil,
              pendingMessages: [V2NIMMessage] = [],
              topic: V2NIMTopic? = nil) {
    self.kind = kind
    self.conversationId = conversationId
    self.title = title
    self.sessionId = sessionId
    self.sessionName = sessionName
    self.anchorMessage = anchorMessage
    self.pendingMessages = pendingMessages
    self.topic = topic
  }

  public var id: String {
    switch kind {
    case .botSubSession, .topic:
      return [kind.rawValue, conversationId, sessionId ?? ""].joined(separator: ":")
    default:
      return [kind.rawValue, conversationId].joined(separator: ":")
    }
  }

  public static func == (lhs: ChatSessionContext, rhs: ChatSessionContext) -> Bool {
    lhs.kind == rhs.kind &&
      lhs.conversationId == rhs.conversationId &&
      lhs.title == rhs.title &&
      lhs.sessionId == rhs.sessionId &&
      lhs.sessionName == rhs.sessionName &&
      lhs.anchorMessage?.messageClientId == rhs.anchorMessage?.messageClientId &&
      lhs.pendingMessages.map(\.messageClientId) == rhs.pendingMessages.map(\.messageClientId) &&
      lhs.topic?.topicId == rhs.topic?.topicId
  }
}

public extension ChatSessionContext {
  var usesTopicHistory: Bool {
    kind == .topic || kind == .botSubSession
  }

  func replacingTopic(_ topic: V2NIMTopic?) -> ChatSessionContext {
    var next = self
    next.topic = topic
    if let topicName = topic?.topicName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !topicName.isEmpty {
      next.title = topicName
    }
    return next
  }
}
