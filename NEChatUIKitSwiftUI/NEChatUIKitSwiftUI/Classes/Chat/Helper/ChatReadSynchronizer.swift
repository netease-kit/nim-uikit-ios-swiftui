// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ChatReadSyncRequest {
  public var context: ChatSessionContext
  public var messages: [V2NIMMessage]
  public var currentAccountId: String?
  public var isP2PReadReceiptEnabled: Bool
  public var isTeamReadReceiptEnabled: Bool
  public var shouldSyncConversationRead: Bool

  public init(context: ChatSessionContext,
              messages: [V2NIMMessage] = [],
              currentAccountId: String?,
              isP2PReadReceiptEnabled: Bool = true,
              isTeamReadReceiptEnabled: Bool = true,
              shouldSyncConversationRead: Bool = true) {
    self.context = context
    self.messages = messages
    self.currentAccountId = currentAccountId
    self.isP2PReadReceiptEnabled = isP2PReadReceiptEnabled
    self.isTeamReadReceiptEnabled = isTeamReadReceiptEnabled
    self.shouldSyncConversationRead = shouldSyncConversationRead
  }
}

public struct ChatReadSyncResult: Equatable {
  public var readTime: TimeInterval?
  public var markedMessageIds: [String]
  public var didClearUnread: Bool

  public init(readTime: TimeInterval? = nil,
              markedMessageIds: [String] = [],
              didClearUnread: Bool = false) {
    self.readTime = readTime
    self.markedMessageIds = markedMessageIds
    self.didClearUnread = didClearUnread
  }
}

public protocol ChatReadSynchronizing {
  func sync(_ request: ChatReadSyncRequest,
            completion: @escaping (Result<ChatReadSyncResult, Error>) -> Void)
}

public final class NEChatKitReadSynchronizer: ChatReadSynchronizing {
  private let chatRepo: ChatRepo
  private let conversationRepo: ConversationRepo
  private let localConversationRepo: LocalConversationRepo
  private let isCloudConversationEnabled: () -> Bool

  public init(chatRepo: ChatRepo = .shared,
              conversationRepo: ConversationRepo = .shared,
              localConversationRepo: LocalConversationRepo = .shared,
              isCloudConversationEnabled: @escaping () -> Bool = { IMKitClient.instance.isV2CloudConversationEnabled }) {
    self.chatRepo = chatRepo
    self.conversationRepo = conversationRepo
    self.localConversationRepo = localConversationRepo
    self.isCloudConversationEnabled = isCloudConversationEnabled
  }

  public func sync(_ request: ChatReadSyncRequest,
                   completion: @escaping (Result<ChatReadSyncResult, Error>) -> Void) {
    guard shouldSyncConversation(request.context) else {
      completion(.success(ChatReadSyncResult()))
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var readTime: TimeInterval?
    var firstError: Error?
    var markedMessageIds = [String]()
    var didClearUnread = false

    if request.shouldSyncConversationRead {
      group.enter()
      clearUnreadAndMarkConversationRead(conversationId: request.context.conversationId) { result in
        lock.lock()
        switch result {
        case .success(let time):
          readTime = time
          didClearUnread = true
        case .failure(let error):
          firstError = firstError ?? error
        }
        lock.unlock()
        group.leave()
      }
    }

    let messagesToMark = messagesNeedingReadReceipt(from: request)
    switch request.context.kind {
    case .p2p:
      if let message = newestP2PMessage(from: messagesToMark) {
        group.enter()
        chatRepo.markP2PMessageRead(message: message) { error in
          lock.lock()
          if let error {
            firstError = firstError ?? error
          } else {
            markedMessageIds.append(Self.stableMessageId(for: message))
          }
          lock.unlock()
          group.leave()
        }
      }
    case .team:
      let chunks = Self.chunk(messagesToMark, size: 50)
      for chunk in chunks {
        group.enter()
        chatRepo.markTeamMessagesRead(messages: chunk) { error in
          lock.lock()
          if let error {
            firstError = firstError ?? error
          } else {
            markedMessageIds.append(contentsOf: chunk.map(Self.stableMessageId(for:)))
          }
          lock.unlock()
          group.leave()
        }
      }
    case .botSubSession, .topic, .history:
      break
    }

    group.notify(queue: .main) {
      let result = ChatReadSyncResult(
        readTime: readTime,
        markedMessageIds: markedMessageIds,
        didClearUnread: didClearUnread
      )
      if let firstError, !didClearUnread, markedMessageIds.isEmpty {
        completion(.failure(firstError))
      } else {
        completion(.success(result))
      }
    }
  }

  private func clearUnreadAndMarkConversationRead(conversationId: String,
                                                  completion: @escaping (Result<TimeInterval?, Error>) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var readTime: TimeInterval?
    var firstError: Error?

    if isCloudConversationEnabled() == false {
      group.enter()
      localConversationRepo.clearUnreadCountByIds([conversationId]) { _, error in
        lock.lock()
        if let error {
          firstError = firstError ?? error
        }
        lock.unlock()
        group.leave()
      }

      group.enter()
      localConversationRepo.markConversationRead(conversationId) { time, error in
        lock.lock()
        readTime = time ?? readTime
        if let error {
          firstError = firstError ?? error
        }
        lock.unlock()
        group.leave()
      }
    } else {
      group.enter()
      conversationRepo.clearUnreadCountByIds([conversationId]) { _, error in
        lock.lock()
        if let error {
          firstError = firstError ?? error
        }
        lock.unlock()
        group.leave()
      }

      group.enter()
      conversationRepo.markConversationRead(conversationId) { time, error in
        lock.lock()
        readTime = time ?? readTime
        if let error {
          firstError = firstError ?? error
        }
        lock.unlock()
        group.leave()
      }
    }

    group.notify(queue: .main) {
      if let firstError {
        completion(.failure(firstError))
      } else {
        completion(.success(readTime))
      }
    }
  }

  private func messagesNeedingReadReceipt(from request: ChatReadSyncRequest) -> [V2NIMMessage] {
    request.messages.filter { message in
      message.conversationId == request.context.conversationId &&
        message.senderId != request.currentAccountId &&
        message.messageType != .MESSAGE_TYPE_NOTIFICATION &&
        message.messageType != .MESSAGE_TYPE_TIP &&
        message.messageStatus.readReceiptSent == false &&
        shouldMarkReadReceipt(for: message, request: request)
    }
  }

  private func shouldMarkReadReceipt(for message: V2NIMMessage,
                                     request: ChatReadSyncRequest) -> Bool {
    switch request.context.kind {
    case .p2p:
      return request.isP2PReadReceiptEnabled
    case .team:
      return request.isTeamReadReceiptEnabled &&
        message.messageServerId != nil &&
        message.messageConfig?.readReceiptEnabled == true
    case .botSubSession, .topic, .history:
      return false
    }
  }

  private func newestP2PMessage(from messages: [V2NIMMessage]) -> V2NIMMessage? {
    messages.sorted { $0.createTime > $1.createTime }.first
  }

  private func shouldSyncConversation(_ context: ChatSessionContext) -> Bool {
    switch context.kind {
    case .p2p, .team, .botSubSession, .topic:
      return !context.conversationId.isEmpty
    case .history:
      return false
    }
  }

  private static func stableMessageId(for message: V2NIMMessage) -> String {
    ChatMessageMapper.stableMessageId(for: message)
  }

  private static func chunk(_ messages: [V2NIMMessage], size: Int) -> [[V2NIMMessage]] {
    guard size > 0, !messages.isEmpty else {
      return []
    }
    return stride(from: 0, to: messages.count, by: size).map { start in
      Array(messages[start..<min(start + size, messages.count)])
    }
  }
}
