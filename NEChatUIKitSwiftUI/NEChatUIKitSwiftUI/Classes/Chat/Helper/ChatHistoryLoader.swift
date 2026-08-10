// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ChatHistoryLoadRequest: Equatable {
  public enum Direction: Equatable {
    case initial
    case older
    case newer
    case aroundAnchor
  }

  public var conversationId: String
  public var context: ChatSessionContext?
  public var anchorMessageId: String?
  public var anchorMessage: V2NIMMessage?
  public var limit: Int
  public var direction: Direction
  public var teamReadReceiptDisplayLimit: Int?
  public var imageThumbSize: Int

  public init(conversationId: String,
              context: ChatSessionContext? = nil,
              anchorMessageId: String? = nil,
              anchorMessage: V2NIMMessage? = nil,
              limit: Int = NEChatUIKitSwiftUIConstants.defaultHistoryPageSize,
              direction: Direction = .initial,
              teamReadReceiptDisplayLimit: Int? = nil,
              imageThumbSize: Int = 350) {
    self.conversationId = conversationId
    self.context = context
    self.anchorMessageId = anchorMessageId
    self.anchorMessage = anchorMessage
    self.limit = limit
    self.direction = direction
    self.teamReadReceiptDisplayLimit = teamReadReceiptDisplayLimit
    self.imageThumbSize = max(0, imageThumbSize)
  }
}

extension ChatHistoryLoadRequest {
  public static func == (lhs: ChatHistoryLoadRequest, rhs: ChatHistoryLoadRequest) -> Bool {
      lhs.conversationId == rhs.conversationId &&
      lhs.context == rhs.context &&
      lhs.anchorMessageId == rhs.anchorMessageId &&
      lhs.anchorMessage.map(ChatMessageMapper.stableMessageId(for:)) == rhs.anchorMessage.map(ChatMessageMapper.stableMessageId(for:)) &&
      lhs.limit == rhs.limit &&
      lhs.direction == rhs.direction &&
      lhs.teamReadReceiptDisplayLimit == rhs.teamReadReceiptDisplayLimit &&
      lhs.imageThumbSize == rhs.imageThumbSize
  }
}

public struct ChatHistoryLoadResult {
  public var rows: [MessageRowState]
  public var messages: [V2NIMMessage]
  public var hasMoreOlder: Bool
  public var hasMoreNewer: Bool
  public var oldestAnchorMessageId: String?
  public var newestAnchorMessageId: String?
  public var oldestAnchorMessage: V2NIMMessage?
  public var newestAnchorMessage: V2NIMMessage?
  public var loadedMessageCount: Int

  public init(rows: [MessageRowState] = [],
              messages: [V2NIMMessage] = [],
              hasMoreOlder: Bool = false,
              hasMoreNewer: Bool = false,
              oldestAnchorMessageId: String? = nil,
              newestAnchorMessageId: String? = nil,
              oldestAnchorMessage: V2NIMMessage? = nil,
              newestAnchorMessage: V2NIMMessage? = nil,
              loadedMessageCount: Int? = nil) {
    self.rows = rows
    self.messages = messages
    self.hasMoreOlder = hasMoreOlder
    self.hasMoreNewer = hasMoreNewer
    self.oldestAnchorMessageId = oldestAnchorMessageId
    self.newestAnchorMessageId = newestAnchorMessageId
    self.oldestAnchorMessage = oldestAnchorMessage
    self.newestAnchorMessage = newestAnchorMessage
    self.loadedMessageCount = loadedMessageCount ?? messages.count
  }
}

extension ChatHistoryLoadResult: Equatable {
  public static func == (lhs: ChatHistoryLoadResult, rhs: ChatHistoryLoadResult) -> Bool {
    lhs.rows == rhs.rows &&
      lhs.messages.map(ChatMessageMapper.stableMessageId(for:)) == rhs.messages.map(ChatMessageMapper.stableMessageId(for:)) &&
      lhs.hasMoreOlder == rhs.hasMoreOlder &&
      lhs.hasMoreNewer == rhs.hasMoreNewer &&
      lhs.oldestAnchorMessageId == rhs.oldestAnchorMessageId &&
      lhs.newestAnchorMessageId == rhs.newestAnchorMessageId &&
      lhs.oldestAnchorMessage.map(ChatMessageMapper.stableMessageId(for:)) == rhs.oldestAnchorMessage.map(ChatMessageMapper.stableMessageId(for:)) &&
      lhs.newestAnchorMessage.map(ChatMessageMapper.stableMessageId(for:)) == rhs.newestAnchorMessage.map(ChatMessageMapper.stableMessageId(for:)) &&
      lhs.loadedMessageCount == rhs.loadedMessageCount
  }
}

public protocol ChatHistoryLoading {
  func load(_ request: ChatHistoryLoadRequest,
            completion: @escaping (Result<ChatHistoryLoadResult, Error>) -> Void)
}

public final class NEChatKitHistoryLoader: ChatHistoryLoading {
  private let chatRepo: ChatRepo
  private let topicRepo: TopicRepo
  private let currentAccountProvider: () -> String?
  private let readReceiptLoader: ChatReadReceiptStateLoading

  public init(chatRepo: ChatRepo = .shared,
              topicRepo: TopicRepo = .shared,
              readReceiptLoader: ChatReadReceiptStateLoading? = nil,
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() }) {
    self.chatRepo = chatRepo
    self.topicRepo = topicRepo
    self.readReceiptLoader = readReceiptLoader ?? NEChatKitReadReceiptStateLoader(chatRepo: chatRepo)
    self.currentAccountProvider = currentAccountProvider
  }

  public func load(_ request: ChatHistoryLoadRequest,
                   completion: @escaping (Result<ChatHistoryLoadResult, Error>) -> Void) {
    if request.context?.usesTopicHistory == true {
      loadTopicHistory(request, completion: completion)
      return
    }

    resolveAnchorMessage(for: request) { [weak self] result in
      guard let self else {
        return
      }

      switch result {
      case .success(let anchorMessage):
        self.loadHistory(request, anchorMessage: anchorMessage, completion: completion)
      case .failure(let error):
        NEChatSwiftUILogger.log("historyLoader resolveAnchor failed error=\(error)")
        completion(.failure(error))
      }
    }
  }

  private func loadTopicHistory(_ request: ChatHistoryLoadRequest,
                                completion: @escaping (Result<ChatHistoryLoadResult, Error>) -> Void) {
    guard let topic = request.context?.topic else {
      completion(.success(ChatHistoryLoadResult()))
      return
    }

    resolveAnchorMessage(for: request) { [weak self] result in
      guard let self else {
        return
      }

      switch result {
      case .success(let anchorMessage):
        self.loadTopicHistory(request, topic: topic, anchorMessage: anchorMessage, completion: completion)
      case .failure(let error):
        NEChatSwiftUILogger.log("historyLoader resolveAnchor topic failed error=\(error)")
        completion(.failure(error))
      }
    }
  }

  private func loadTopicHistory(_ request: ChatHistoryLoadRequest,
                                topic: V2NIMTopic,
                                anchorMessage: V2NIMMessage?,
                                completion: @escaping (Result<ChatHistoryLoadResult, Error>) -> Void) {
    let option = V2NIMTopicMessageListOption()
    option.topic = topic
    option.limit = 100
    option.anchorMessage = anchorMessage
    option.direction = queryDirection(for: request.direction)
    option.sortOrder = .SORT_ORDER_ASC
    option.beginTime = 0
    option.endTime = 0

    topicRepo.getTopicMessageList(option) { [currentAccountProvider] result, error in
      if let error {
        NEChatSwiftUILogger.log("historyLoader topicMessageList failed error=\(error)")
        completion(.failure(error))
        return
      }

      let currentAccountId = currentAccountProvider()
      let messages = Self.uniqueTopicMessages(result?.replyList ?? [])
        .sorted { $0.createTime < $1.createTime }
      let rows = messages.map {
        ChatMessageMapper.row(
          message: $0,
          currentAccountId: currentAccountId,
          imageThumbSize: request.imageThumbSize
        )
      }
      let nextOlderAnchorMessage = result?.anchorMessage ?? messages.first
      let nextNewerAnchorMessage = messages.max(by: Self.isEarlierMessage) ?? result?.anchorMessage
      let canAdvanceOlderAnchor = Self.canAdvanceOlderAnchor(
        from: request.anchorMessageId,
        to: nextOlderAnchorMessage
      )
      let hasMoreOlder = option.direction == .QUERY_DIRECTION_DESC ? !messages.isEmpty && canAdvanceOlderAnchor : false
      let hasMoreNewer = option.direction == .QUERY_DIRECTION_ASC
        ? Self.hasMoreTopicHistory(result: result, loadedCount: messages.count, limit: option.limit, nextAnchorMessage: nextNewerAnchorMessage)
        : false
      completion(.success(ChatHistoryLoadResult(
        rows: rows,
        messages: messages,
        hasMoreOlder: hasMoreOlder,
        hasMoreNewer: hasMoreNewer,
        oldestAnchorMessageId: Self.stableMessageId(for: nextOlderAnchorMessage) ?? rows.first?.id ?? request.anchorMessageId,
        newestAnchorMessageId: Self.stableMessageId(for: nextNewerAnchorMessage) ?? rows.last?.id ?? request.anchorMessageId,
        oldestAnchorMessage: nextOlderAnchorMessage,
        newestAnchorMessage: nextNewerAnchorMessage,
        loadedMessageCount: messages.count
      )))
    }
  }

  private func resolveAnchorMessage(for request: ChatHistoryLoadRequest,
                                    completion: @escaping (Result<V2NIMMessage?, Error>) -> Void) {
    if let anchorMessage = request.anchorMessage {
      completion(.success(anchorMessage))
      return
    }

    guard let anchorMessageId = request.anchorMessageId, !anchorMessageId.isEmpty else {
      completion(.success(nil))
      return
    }

    chatRepo.getMessageListByIds([anchorMessageId]) { messages, error in
      if let error {
        NEChatSwiftUILogger.log("historyLoader getMessageListByIds failed anchorId=\(anchorMessageId) error=\(error)")
        completion(.failure(error))
        return
      }

      completion(.success(messages?.first))
    }
  }

  private func loadHistory(_ request: ChatHistoryLoadRequest,
                           anchorMessage: V2NIMMessage?,
                           completion: @escaping (Result<ChatHistoryLoadResult, Error>) -> Void) {
    let option = V2NIMMessageListOption()
    option.conversationId = request.conversationId
    option.limit = max(1, min(request.limit, NEChatUIKitSwiftUIConstants.defaultHistoryPageSize))
    option.anchorMessage = anchorMessage
    option.direction = queryDirection(for: request.direction)

    if let anchorMessage {
      if option.direction == .QUERY_DIRECTION_DESC {
        option.endTime = anchorMessage.createTime
      } else {
        option.beginTime = anchorMessage.createTime
      }
    }

    chatRepo.getMessageList(option: option) { [currentAccountProvider] messages, error in
      if let error {
        NEChatSwiftUILogger.log("historyLoader getMessageList failed conversationId=\(request.conversationId) error=\(error)")
        completion(.failure(error))
        return
      }

      let currentAccountId = currentAccountProvider()
      let rawMessages = messages ?? []
      let sortedMessages = rawMessages
        .sorted { $0.createTime < $1.createTime }
      let rows = sortedMessages
        .map {
          ChatMessageMapper.row(
            message: $0,
            currentAccountId: currentAccountId,
            imageThumbSize: request.imageThumbSize
          )
      }
      let currentAnchorId = request.anchorMessageId ?? Self.stableMessageId(for: anchorMessage)
      let nextOlderAnchorMessage = rawMessages.min(by: Self.isEarlierMessage)
      let nextNewerAnchorMessage = rawMessages.max(by: Self.isEarlierMessage)
      let canAdvanceOlderAnchor = Self.canAdvanceOlderAnchor(
        from: currentAnchorId,
        to: nextOlderAnchorMessage
      )
      let hasMoreOlder = request.direction == .newer
        ? false
        : !rawMessages.isEmpty && canAdvanceOlderAnchor
      let hasMoreNewer = request.direction == .newer
        ? Self.hasMoreMessageHistory(loadedCount: rawMessages.count, nextAnchorMessage: nextNewerAnchorMessage)
        : false

      completion(.success(ChatHistoryLoadResult(
        rows: rows,
        messages: rawMessages,
        hasMoreOlder: hasMoreOlder,
        hasMoreNewer: hasMoreNewer,
        oldestAnchorMessageId: Self.stableMessageId(for: request.direction == .newer ? nil : nextOlderAnchorMessage) ?? rows.first?.id ?? request.anchorMessageId,
        newestAnchorMessageId: Self.stableMessageId(for: request.direction == .newer ? nextNewerAnchorMessage : nil) ?? rows.last?.id ?? request.anchorMessageId,
        oldestAnchorMessage: request.direction == .newer ? nil : nextOlderAnchorMessage,
        newestAnchorMessage: request.direction == .newer ? nextNewerAnchorMessage : nil,
        loadedMessageCount: rawMessages.count
      )))
    }
  }

  private static func nextAnchorMessage(result: V2NIMTopicMessageListResult?,
                                        fallback: V2NIMMessage?,
                                        currentAnchorId: String?) -> V2NIMMessage? {
    nextAnchorMessage(
      resultAnchor: result?.anchorMessage,
      fallback: fallback,
      currentAnchorId: currentAnchorId
    )
  }

  private static func nextAnchorMessage(resultAnchor: V2NIMMessage?,
                                        fallback: V2NIMMessage?,
                                        currentAnchorId: String?) -> V2NIMMessage? {
    if let resultAnchor,
       !message(resultAnchor, matches: currentAnchorId) {
      return resultAnchor
    }
    if let fallback,
       !message(fallback, matches: currentAnchorId) {
      return fallback
    }
    return currentAnchorId == nil ? (resultAnchor ?? fallback) : nil
  }

  private static func canAdvanceOlderAnchor(from currentAnchorId: String?,
                                            to nextAnchorMessage: V2NIMMessage?) -> Bool {
    guard let nextAnchorMessage else {
      return false
    }
    return !message(nextAnchorMessage, matches: currentAnchorId)
  }

  private static func isEarlierMessage(_ lhs: V2NIMMessage,
                                       _ rhs: V2NIMMessage) -> Bool {
    if lhs.createTime != rhs.createTime {
      return lhs.createTime < rhs.createTime
    }
    return (stableMessageId(for: lhs) ?? "") < (stableMessageId(for: rhs) ?? "")
  }

  private static func hasMoreMessageHistory(loadedCount: Int,
                                            nextAnchorMessage: V2NIMMessage?) -> Bool {
    guard nextAnchorMessage != nil else {
      return false
    }
    return loadedCount > 0
  }

  private static func hasMoreTopicHistory(result: V2NIMTopicMessageListResult?,
                                          loadedCount: Int,
                                          limit: Int,
                                          nextAnchorMessage: V2NIMMessage?) -> Bool {
    guard nextAnchorMessage != nil else {
      return false
    }
    if let result {
      return result.hasMore
    }
    return loadedCount >= limit
  }

  private static func message(_ message: V2NIMMessage?,
                              matches id: String?) -> Bool {
    guard let message,
          let id,
          !id.isEmpty else {
      return false
    }
    return message.messageClientId == id ||
      message.messageServerId == id ||
      stableMessageId(for: message) == id
  }

  private func queryDirection(for direction: ChatHistoryLoadRequest.Direction) -> V2NIMQueryDirection {
    switch direction {
    case .newer:
      return .QUERY_DIRECTION_ASC
    case .initial, .older, .aroundAnchor:
      return .QUERY_DIRECTION_DESC
    }
  }

  private static func uniqueTopicMessages(_ messages: [V2NIMMessage]) -> [V2NIMMessage] {
    var result = [V2NIMMessage]()
    var keys = Set<String>()
    for message in messages {
      let key = topicMessageKey(message)
      guard !keys.contains(key) else {
        continue
      }
      keys.insert(key)
      result.append(message)
    }
    return result
  }

  private static func topicMessageKey(_ message: V2NIMMessage) -> String {
    if let clientId = message.messageClientId, !clientId.isEmpty {
      return "client:\(clientId)"
    }
    if let serverId = message.messageServerId, !serverId.isEmpty {
      return "server:\(serverId)"
    }
    return "time:\(message.createTime)-type:\(String(describing: message.messageType))"
  }

  private static func stableMessageId(for message: V2NIMMessage?) -> String? {
    guard let message else {
      return nil
    }
    return ChatMessageMapper.stableMessageId(for: message)
  }

  private func loadReadReceiptsIfNeeded(request: ChatHistoryLoadRequest,
                                        messages: [V2NIMMessage],
                                        result: ChatHistoryLoadResult,
                                        currentAccountId: String?,
                                        completion: @escaping (Result<ChatHistoryLoadResult, Error>) -> Void) {
    let receiptRequest = ChatReadReceiptStateLoadRequest(
      conversationId: request.conversationId,
      kind: ChatSessionKind(conversationId: request.conversationId),
      messages: messages,
      rows: result.rows,
      currentAccountId: currentAccountId,
      teamReadReceiptDisplayLimit: request.teamReadReceiptDisplayLimit
    )
    guard receiptRequest.shouldLoad else {
      completion(.success(result))
      return
    }

    readReceiptLoader.load(receiptRequest) { receiptResult in
      switch receiptResult {
      case .success(let rows):
        var next = result
        next.rows = rows
        completion(.success(next))
      case .failure:
        completion(.success(result))
      }
    }
  }
}

public struct ChatReadReceiptStateLoadRequest {
  public var conversationId: String
  public var kind: ChatSessionKind
  public var messages: [V2NIMMessage]
  public var rows: [MessageRowState]
  public var currentAccountId: String?
  public var teamReadReceiptDisplayLimit: Int?

  public init(conversationId: String,
              kind: ChatSessionKind,
              messages: [V2NIMMessage],
              rows: [MessageRowState],
              currentAccountId: String?,
              teamReadReceiptDisplayLimit: Int? = nil) {
    self.conversationId = conversationId
    self.kind = kind
    self.messages = messages
    self.rows = rows
    self.currentAccountId = currentAccountId
    self.teamReadReceiptDisplayLimit = teamReadReceiptDisplayLimit
  }

  public var shouldLoad: Bool {
    switch kind {
    case .p2p, .team:
      return rows.contains { $0.direction == .outgoing && $0.isReadReceiptEnabled }
    case .botSubSession, .topic, .history:
      return false
    }
  }
}

public protocol ChatReadReceiptStateLoading {
  func load(_ request: ChatReadReceiptStateLoadRequest,
            completion: @escaping (Result<[MessageRowState], Error>) -> Void)
}

public final class NEChatKitReadReceiptStateLoader: ChatReadReceiptStateLoading {
  private let chatRepo: ChatRepo

  public init(chatRepo: ChatRepo = .shared) {
    self.chatRepo = chatRepo
  }

  public func load(_ request: ChatReadReceiptStateLoadRequest,
                   completion: @escaping (Result<[MessageRowState], Error>) -> Void) {
    switch request.kind {
    case .p2p:
      loadP2PReadReceipt(request, completion: completion)
    case .team:
      loadTeamReadReceipts(request, completion: completion)
    case .botSubSession, .topic, .history:
      completion(.success(request.rows))
    }
  }

  private func loadP2PReadReceipt(_ request: ChatReadReceiptStateLoadRequest,
                                  completion: @escaping (Result<[MessageRowState], Error>) -> Void) {
    chatRepo.getP2PMessageReceipt(conversationId: request.conversationId) { readReceipt, error in
      if let error {
        completion(.failure(error))
        return
      }
      guard let readReceipt else {
        completion(.success(request.rows))
        return
      }

      let rows = request.rows.map { row in
        guard Self.shouldApplyLoadedReceipt(to: row),
              let createTime = row.timestamp,
              createTime <= readReceipt.timestamp else {
          return row
        }
        var next = row
        next.deliveryState = .read
        next.readReceipt = MessageReadReceiptState(
          readCount: 1,
          unreadCount: 0,
          isP2PRead: true,
          timestamp: readReceipt.timestamp
        )
        return next
      }
      completion(.success(rows))
    }
  }

  private func loadTeamReadReceipts(_ request: ChatReadReceiptStateLoadRequest,
                                    completion: @escaping (Result<[MessageRowState], Error>) -> Void) {
    let targetMessages = request.messages.filter { message in
      message.messageServerId != nil &&
        message.senderId == request.currentAccountId &&
        message.messageType != .MESSAGE_TYPE_NOTIFICATION &&
        message.messageType != .MESSAGE_TYPE_TIP &&
        message.messageConfig?.readReceiptEnabled != false
    }
    guard !targetMessages.isEmpty else {
      completion(.success(request.rows))
      return
    }

    let chunks = Self.chunk(targetMessages, size: 50)
    let group = DispatchGroup()
    let lock = NSLock()
    var firstError: Error?
    var receipts = [V2NIMTeamMessageReadReceipt]()

    for chunk in chunks {
      group.enter()
      chatRepo.getTeamMessageReceipts(messages: chunk) { readReceipts, error in
        lock.lock()
        if let error, firstError == nil {
          firstError = error
        }
        if let readReceipts {
          receipts.append(contentsOf: readReceipts)
        }
        lock.unlock()
        group.leave()
      }
    }

    group.notify(queue: .main) {
      if let firstError, receipts.isEmpty {
        completion(.failure(firstError))
        return
      }

      var receiptMap = [String: V2NIMTeamMessageReadReceipt]()
      for receipt in receipts {
        guard let messageId = receipt.messageClientId, !messageId.isEmpty else {
          continue
        }
        receiptMap[messageId] = receipt
      }
      let rows = request.rows.map { row in
        guard Self.shouldApplyLoadedReceipt(to: row),
              let receipt = receiptMap[row.id] else {
          return row
        }
        var next = row
        next.deliveryState = .read
        next.readReceipt = MessageReadReceiptState(
          readCount: Int(receipt.readCount),
          unreadCount: Int(receipt.unreadCount),
          isP2PRead: false,
          displayLimit: request.teamReadReceiptDisplayLimit
        )
        return next
      }
      completion(.success(rows))
    }
  }

  private static func shouldApplyLoadedReceipt(to row: MessageRowState) -> Bool {
    guard row.direction == .outgoing,
          row.isReadReceiptEnabled else {
      return false
    }
    switch row.deliveryState {
    case .sent, .read:
      return true
    default:
      return false
    }
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

private extension ChatSessionKind {
  init(conversationId: String) {
    switch V2NIMConversationIdUtil.conversationType(conversationId) {
    case .CONVERSATION_TYPE_P2P:
      self = .p2p
    case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
      self = .team
    default:
      self = .history
    }
  }
}
