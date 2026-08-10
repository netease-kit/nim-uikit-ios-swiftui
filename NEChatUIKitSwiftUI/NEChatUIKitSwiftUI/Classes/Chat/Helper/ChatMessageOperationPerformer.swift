// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ChatOperationResult {
  public var row: MessageRowState?
  public var message: String?
  public var canCloseTopMessage: Bool?

  public init(row: MessageRowState? = nil,
              message: String? = nil,
              canCloseTopMessage: Bool? = nil) {
    self.row = row
    self.message = message
    self.canCloseTopMessage = canCloseTopMessage
  }
}

public protocol ChatMessageOperationPerforming {
  func deleteMessage(id: String,
                     completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func revokeMessage(id: String,
                     completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func revokeMessage(message: V2NIMMessage,
                     completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func pinMessage(id: String,
                  isPinned: Bool,
                  completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func pinMessage(message: V2NIMMessage,
                  isPinned: Bool,
                  completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func loadTopMessage(context: ChatSessionContext,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func topMessage(id: String,
                  context: ChatSessionContext,
                  completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func untopMessage(id: String?,
                    context: ChatSessionContext,
                    completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func unpinMessage(id: String,
                    completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func collectMessage(id: String,
                      conversationName: String,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func collectMessage(id: String,
                      conversationName: String,
                      displayRow: MessageRowState?,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func collectMessage(message: V2NIMMessage,
                      conversationName: String,
                      displayRow: MessageRowState?,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func voiceToText(id: String,
                   completion: @escaping (Result<String, Error>) -> Void)
  func forwardMessages(ids: [String],
                       targets: [ChatForwardTargetState],
                       comment: String?,
                       merged: Bool,
                       sourceConversationId: String,
                       sourceConversationName: String?,
                       depth: Int,
                       completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
  func forwardMessages(messages: [V2NIMMessage],
                       targets: [ChatForwardTargetState],
                       comment: String?,
                       merged: Bool,
                       sourceConversationId: String,
                       sourceConversationName: String?,
                       depth: Int,
                       completion: @escaping (Result<ChatOperationResult, Error>) -> Void)
}

public extension ChatMessageOperationPerforming {
  func revokeMessage(message: V2NIMMessage,
                     completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let id = message.messageClientId ?? message.messageServerId ?? ""
    revokeMessage(id: id, completion: completion)
  }

  func pinMessage(message: V2NIMMessage,
                  isPinned: Bool,
                  completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let id = message.messageClientId ?? message.messageServerId ?? ""
    pinMessage(id: id, isPinned: isPinned, completion: completion)
  }

  func unpinMessage(id: String,
                    completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    completion(.success(ChatOperationResult()))
  }

  func loadTopMessage(context: ChatSessionContext,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    completion(.success(ChatOperationResult()))
  }

  func topMessage(id: String,
                  context: ChatSessionContext,
                  completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    completion(.failure(Self.defaultOperationUnsupportedError()))
  }

  func untopMessage(id: String?,
                    context: ChatSessionContext,
                    completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    completion(.failure(Self.defaultOperationUnsupportedError()))
  }

  func forwardMessages(ids: [String],
                       targets: [ChatForwardTargetState],
                       comment: String?,
                       completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    forwardMessages(ids: ids,
                    targets: targets,
                    comment: comment,
                    merged: false,
                    sourceConversationId: "",
                    sourceConversationName: nil,
                    depth: 0,
                    completion: completion)
  }

  func forwardMessages(messages: [V2NIMMessage],
                       targets: [ChatForwardTargetState],
                       comment: String?,
                       merged: Bool,
                       sourceConversationId: String,
                       sourceConversationName: String?,
                       depth: Int,
                       completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let ids = messages.compactMap { message in
      if let clientId = message.messageClientId, !clientId.isEmpty {
        return clientId
      }
      if let serverId = message.messageServerId, !serverId.isEmpty {
        return serverId
      }
      return nil
    }
    forwardMessages(ids: ids,
                    targets: targets,
                    comment: comment,
                    merged: merged,
                    sourceConversationId: sourceConversationId,
                    sourceConversationName: sourceConversationName,
                    depth: depth,
                    completion: completion)
  }

  func voiceToText(id: String,
                   completion: @escaping (Result<String, Error>) -> Void) {
    completion(.failure(Self.defaultOperationUnsupportedError()))
  }

  func collectMessage(id: String,
                      conversationName: String,
                      displayRow: MessageRowState?,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    collectMessage(id: id, conversationName: conversationName, completion: completion)
  }

  func collectMessage(message: V2NIMMessage,
                      conversationName: String,
                      displayRow: MessageRowState?,
                      completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let id = message.messageClientId ?? message.messageServerId ?? ""
    collectMessage(
      id: id,
      conversationName: conversationName,
      displayRow: displayRow,
      completion: completion
    )
  }

  private static func defaultOperationUnsupportedError() -> NSError {
    NSError(
      domain: NEChatUIKitSwiftUIConstants.moduleName,
      code: -10,
      userInfo: [NSLocalizedDescriptionKey: NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")]
    )
  }
}

public final class NEChatKitMessageOperationPerformer: ChatMessageOperationPerforming {
  private let chatRepo: ChatRepo
  private let teamRepo: TeamRepo
  private let currentAccountProvider: () -> String?

  public init(chatRepo: ChatRepo = .shared,
              teamRepo: TeamRepo = .shared,
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() }) {
    self.chatRepo = chatRepo
    self.teamRepo = teamRepo
    self.currentAccountProvider = currentAccountProvider
  }

  public func deleteMessage(id: String,
                            completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    resolveMessage(id: id) { [chatRepo] result in
      switch result {
      case .success(let message):
        let onlyDeleteLocal = (message.messageServerId?.isEmpty ?? true) || message.messageServerId == "0"
        chatRepo.deleteMessage(message: message, onlyDeleteLocal: onlyDeleteLocal) { error in
          if let error {
            NEChatSwiftUILogger.log("deleteMessage failed id=\(id) error=\(error)")
            completion(.failure(error))
          } else {
            completion(.success(ChatOperationResult()))
          }
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func revokeMessage(id: String,
                            completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    resolveMessage(id: id) { [chatRepo] result in
      switch result {
      case .success(let message):
        self.revokeMessage(message: message, chatRepo: chatRepo, completion: completion)
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func revokeMessage(message: V2NIMMessage,
                            completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    revokeMessage(message: message, chatRepo: chatRepo, completion: completion)
  }

  private func revokeMessage(message: V2NIMMessage,
                             chatRepo: ChatRepo,
                             completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let revokeParams = V2NIMMessageRevokeParams()
    revokeParams.serverExtension = Self.revokeServerExtension(for: message)
    chatRepo.revokeMessage(message: message, params: revokeParams) { [currentAccountProvider = self.currentAccountProvider] error in
      if let error {
        NEChatSwiftUILogger.log("revokeMessage failed id=\(message.messageClientId ?? "") error=\(error)")
        completion(.failure(error))
      } else {
        var row = ChatMessageMapper.row(message: message, currentAccountId: currentAccountProvider())
        row.content = .revoke(NEChatUIKitSwiftUIBundle.localized("message_recalled", value: "Message recalled"))
        row.reedit = Self.reeditState(for: message)
        completion(.success(ChatOperationResult(row: row)))
      }
    }
  }

  public func pinMessage(id: String,
                         isPinned: Bool,
                         completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    resolveMessage(id: id) { result in
      switch result {
      case .success(let message):
        self.pinMessage(message: message, isPinned: isPinned, completion: completion)
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func pinMessage(message: V2NIMMessage,
                         isPinned: Bool,
                         completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let finish: (NSError?) -> Void = { error in
      if let error {
        NEChatSwiftUILogger.log("pinMessage failed isPinned=\(isPinned) error=\(error)")
        completion(.failure(error))
      } else {
        completion(.success(ChatOperationResult(
          message: isPinned
            ? NEChatUIKitSwiftUIBundle.localized("chat_pin_removed", value: "Pin removed")
            : NEChatUIKitSwiftUIBundle.localized("chat_pinned", value: "Pinned")
        )))
      }
    }

    if isPinned {
      // Match IMUIKitExample's ChatViewModel.removePinMessage: pass the
      // original SDK message as its V2NIMMessageRefer. Rebuilding a reduced
      // refer drops peer fields needed when the pinned P2P message was sent by
      // the other participant.
      chatRepo.unpinMessage(messageRefer: message, serverExtension: "", finish)
    } else {
      chatRepo.pinMessage(message, serverExt: "", completion: finish)
    }
  }

  public func unpinMessage(id: String,
                           completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    resolveMessage(id: id) { [chatRepo] result in
      switch result {
      case .success(let message):
        chatRepo.unpinMessage(message, serverExt: "") { error in
          if let error {
            completion(.failure(error))
          } else {
            completion(.success(ChatOperationResult(
              message: NEChatUIKitSwiftUIBundle.localized("chat_pin_removed", value: "Pin removed")
            )))
          }
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func loadTopMessage(context: ChatSessionContext,
                             completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    guard context.kind == .team,
          let teamId = Self.teamId(from: context) else {
      completion(.success(ChatOperationResult()))
      return
    }

    teamRepo.loadTopMessage(
      teamId: teamId,
      currentAccountId: currentAccountProvider()
    ) { [currentAccountProvider = self.currentAccountProvider] info, error in
      if let error {
        completion(.failure(error))
        return
      }
      guard let info, let message = info.message, info.isActive else {
        completion(.success(ChatOperationResult()))
        return
      }

      var row = ChatMessageMapper.row(message: message, currentAccountId: currentAccountProvider())
      row.isTopMessage = true
      completion(.success(ChatOperationResult(row: row, canCloseTopMessage: info.canUntop)))
    }
  }

  public func topMessage(id: String,
                         context: ChatSessionContext,
                         completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    guard context.kind == .team,
          let teamId = Self.teamId(from: context) else {
      completion(.failure(Self.error(
        code: -6,
        message: NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
      )))
      return
    }

    resolveMessage(id: id) { [teamRepo, currentAccountProvider = self.currentAccountProvider] result in
      switch result {
      case .success(let message):
        teamRepo.topMessage(
          message,
          teamId: teamId,
          currentAccountId: currentAccountProvider()
        ) { error in
          if let error {
            completion(.failure(error))
          } else {
            var row = ChatMessageMapper.row(message: message, currentAccountId: currentAccountProvider())
            row.isTopMessage = true
            completion(.success(ChatOperationResult(row: row, canCloseTopMessage: true)))
          }
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func untopMessage(id: String?,
                           context: ChatSessionContext,
                           completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    guard context.kind == .team,
          let teamId = Self.teamId(from: context) else {
      completion(.failure(Self.error(
        code: failedOperation,
        message: NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
      )))
      return
    }

    teamRepo.untopMessage(
      teamId: teamId,
      messageClientId: id,
      currentAccountId: currentAccountProvider()
    ) { error in
      if let error {
        completion(.failure(error))
      } else {
        completion(.success(ChatOperationResult()))
      }
    }
  }

  public func collectMessage(id: String,
                             conversationName: String,
                             completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    collectMessage(id: id, conversationName: conversationName, displayRow: nil, completion: completion)
  }

  public func collectMessage(id: String,
                             conversationName: String,
                             displayRow: MessageRowState?,
                             completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    resolveMessage(id: id) { result in
      switch result {
      case .success(let message):
        self.collectMessage(
          message: message,
          conversationName: conversationName,
          displayRow: displayRow,
          completion: completion
        )
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func collectMessage(message: V2NIMMessage,
                             conversationName: String,
                             displayRow: MessageRowState?,
                             completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let params = V2NIMAddCollectionParams()
    params.collectionType = Int32(message.messageType.rawValue + collectionTypeOffset)
    params.collectionData = Self.collectionData(
      for: message,
      conversationName: conversationName,
      displayRow: displayRow
    )
    params.uniqueId = message.messageServerId
    chatRepo.addCollection(params) { _, error in
      if let error {
        NEChatSwiftUILogger.log("collectMessage failed id=\(message.messageClientId ?? "") error=\(error)")
        completion(.failure(error))
      } else {
        completion(.success(ChatOperationResult(
          message: NEChatUIKitSwiftUIBundle.localized("chat_collected", value: "Collected")
        )))
      }
    }
  }

  public func voiceToText(id: String,
                          completion: @escaping (Result<String, Error>) -> Void) {
    resolveMessage(id: id) { [chatRepo] result in
      switch result {
      case .success(let message):
        chatRepo.voiceToText(message: message) { text, error in
          if let error {
            completion(.failure(error))
          } else if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            completion(.success(text))
          } else {
            completion(.failure(Self.error(
              code: -5,
              message: NEChatUIKitSwiftUIBundle.localized("operation_to_text_failed", value: "Voice to text failed")
            )))
          }
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  public func forwardMessages(ids: [String],
                              targets: [ChatForwardTargetState],
                              comment: String?,
                              merged: Bool = false,
                              sourceConversationId: String = "",
                              sourceConversationName: String? = nil,
                              depth: Int = 0,
                              completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let messageIds = ids.filter { !$0.isEmpty }
    let conversationIds = targets.map(\.conversationId).filter { !$0.isEmpty }
    guard !messageIds.isEmpty, !conversationIds.isEmpty else {
      completion(.failure(Self.error(
        code: -4,
        message: NEChatUIKitSwiftUIBundle.localized("chat_forward_target_missing", value: "Forward target is missing")
      )))
      return
    }

    chatRepo.getMessageListByIds(messageIds) { [chatRepo] messages, error in
      if let error {
        completion(.failure(error))
        return
      }

      let messages = (messages ?? []).sorted { left, right in
        left.createTime < right.createTime
      }
      self.forwardResolvedMessages(messages,
                                   conversationIds: conversationIds,
                                   comment: comment,
                                   merged: merged,
                                   sourceConversationId: sourceConversationId,
                                   sourceConversationName: sourceConversationName,
                                   depth: depth,
                                   chatRepo: chatRepo,
                                   completion: completion)
    }
  }

  public func forwardMessages(messages: [V2NIMMessage],
                              targets: [ChatForwardTargetState],
                              comment: String?,
                              merged: Bool = false,
                              sourceConversationId: String = "",
                              sourceConversationName: String? = nil,
                              depth: Int = 0,
                              completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    let conversationIds = targets.map(\.conversationId).filter { !$0.isEmpty }
    guard !messages.isEmpty, !conversationIds.isEmpty else {
      completion(.failure(Self.error(
        code: conversationIds.isEmpty ? -4 : -1,
        message: conversationIds.isEmpty
          ? NEChatUIKitSwiftUIBundle.localized("chat_forward_target_missing", value: "Forward target is missing")
          : NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found")
      )))
      return
    }

    forwardResolvedMessages(
      messages.sorted { $0.createTime < $1.createTime },
      conversationIds: conversationIds,
      comment: comment,
      merged: merged,
      sourceConversationId: sourceConversationId,
      sourceConversationName: sourceConversationName,
      depth: depth,
      chatRepo: chatRepo,
      completion: completion
    )
  }

  private func forwardResolvedMessages(_ messages: [V2NIMMessage],
                                       conversationIds: [String],
                                       comment: String?,
                                       merged: Bool,
                                       sourceConversationId: String,
                                       sourceConversationName: String?,
                                       depth: Int,
                                       chatRepo: ChatRepo,
                                       completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    guard !messages.isEmpty else {
      completion(.failure(Self.error(
        code: -1,
        message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found")
      )))
      return
    }

    if merged {
      let sourceId = sourceConversationId.isEmpty ? (messages.first?.conversationId ?? "") : sourceConversationId
      forwardMergedMessages(messages,
                            conversationIds: conversationIds,
                            comment: comment,
                            sourceConversationId: sourceId,
                            sourceConversationName: sourceConversationName,
                            depth: depth,
                            chatRepo: chatRepo,
                            completion: completion)
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var lastError: Error?
    let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)

    func record(_ error: Error?) {
      guard let error else {
        return
      }
      lock.lock()
      lastError = error
      lock.unlock()
    }

    for conversationId in conversationIds {
      for message in messages {
        group.enter()
        let forwardMessage = chatRepo.makeForwardMessage(message)
        sendForwardMessage(forwardMessage, conversationId: conversationId, chatRepo: chatRepo) { error in
          record(error)
          group.leave()
        }
      }

      if let trimmedComment, !trimmedComment.isEmpty {
        group.enter()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          let commentMessage = chatRepo.makeTextMessage(text: trimmedComment)
          self.sendForwardMessage(commentMessage, conversationId: conversationId, chatRepo: chatRepo) { error in
            record(error)
            group.leave()
          }
        }
      }
    }

    group.notify(queue: .main) {
      if let lastError {
        completion(.failure(lastError))
      } else {
        SettingRepo.shared.updateRecentForward(conversationIds)
        completion(.success(ChatOperationResult(
          message: NEChatUIKitSwiftUIBundle.localized("chat_forward_sent", value: "Forward sent")
        )))
      }
    }
  }

  private func forwardMergedMessages(_ messages: [V2NIMMessage],
                                     conversationIds: [String],
                                     comment: String?,
                                     sourceConversationId: String,
                                     sourceConversationName: String?,
                                     depth: Int,
                                     chatRepo: ChatRepo,
                                     completion: @escaping (Result<ChatOperationResult, Error>) -> Void) {
    chatRepo.makeMergedForwardPayload(messages: messages,
                                      fromConversationId: sourceConversationId,
                                      sessionName: sourceConversationName,
                                      depth: depth,
                                      contentLocalizer: { key, fallback in
                                        NEChatUIKitSwiftUIBundle.localized(key, value: fallback)
                                      }) { payload, error in
      if let error {
        completion(.failure(error))
        return
      }

      guard let payload else {
        completion(.failure(Self.error(
          code: -6,
          message: NEChatUIKitSwiftUIBundle.localized("chat_forward_payload_missing", value: "Forward payload is missing")
        )))
        return
      }

      let group = DispatchGroup()
      let lock = NSLock()
      var lastError: Error?
      let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)

      func record(_ error: Error?) {
        guard let error else {
          return
        }
        lock.lock()
        lastError = error
        lock.unlock()
      }

      for conversationId in conversationIds {
        group.enter()
        let message = chatRepo.makeCustomMessage(text: payload.text, rawAttachment: payload.rawAttachment)
        self.sendForwardMessage(message, conversationId: conversationId, chatRepo: chatRepo) { error in
          record(error)
          group.leave()
        }

        if let trimmedComment, !trimmedComment.isEmpty {
          group.enter()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let commentMessage = chatRepo.makeTextMessage(text: trimmedComment)
            self.sendForwardMessage(commentMessage, conversationId: conversationId, chatRepo: chatRepo) { error in
              record(error)
              group.leave()
            }
          }
        }
      }

      group.notify(queue: .main) {
        if let lastError {
          completion(.failure(lastError))
        } else {
          SettingRepo.shared.updateRecentForward(conversationIds)
          completion(.success(ChatOperationResult(
            message: NEChatUIKitSwiftUIBundle.localized("chat_forward_sent", value: "Forward sent")
          )))
        }
      }
    }
  }

  private func sendForwardMessage(_ message: V2NIMMessage,
                                  conversationId: String,
                                  chatRepo: ChatRepo,
                                  completion: @escaping (Error?) -> Void) {
    let finishLock = NSLock()
    var didFinish = false

    func finish(_ error: Error?) {
      finishLock.lock()
      let alreadyFinished = didFinish
      didFinish = true
      finishLock.unlock()

      guard !alreadyFinished else {
        return
      }
      completion(error)
    }

    let params = chatRepo.swiftUIForwardMessageParams(message: message, conversationId: conversationId)
    chatRepo.sendMessage(message: message, conversationId: conversationId, params: params) { result, error, progress in
      if let error {
        finish(error)
      } else if result != nil || progress >= 100 {
        finish(nil)
      }
    }
  }

  private func resolveMessage(id: String,
                              completion: @escaping (Result<V2NIMMessage, Error>) -> Void) {
    chatRepo.getMessageListByIds([id]) { messages, error in
      if let error {
        NEChatSwiftUILogger.log("resolveMessage failed id=\(id) error=\(error)")
        completion(.failure(error))
        return
      }

      guard let message = messages?.first else {
        completion(.failure(Self.error(
          code: -1,
          message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found")
        )))
        return
      }

      completion(.success(message))
    }
  }

  private static func teamId(from context: ChatSessionContext) -> String? {
    if let sessionId = context.sessionId, !sessionId.isEmpty {
      return sessionId
    }
    if let targetId = V2NIMConversationIdUtil.conversationTargetId(context.conversationId), !targetId.isEmpty {
      return targetId
    }
    return context.conversationId.isEmpty ? nil : context.conversationId
  }

  private static func revokeServerExtension(for message: V2NIMMessage) -> String {
    var extensionDictionary = [String: Any]()
    if let serverExtension = message.serverExtension,
       let current = NECommonUtil.getDictionaryFromJSONString(serverExtension) as? [String: Any] {
      extensionDictionary = current
    }

    if let threadReply = message.threadReply,
       threadReply.messageClientId?.isEmpty == false {
      extensionDictionary[keyReplyMsgKey] = replyDictionary(from: threadReply)
    }

    extensionDictionary[revokeLocalMessage] = true
    extensionDictionary[revokeLocalMessageTime] = Date().timeIntervalSince1970

    switch message.messageType {
    case .MESSAGE_TYPE_TEXT:
      extensionDictionary[revokeLocalMessageContent] = message.text
    case .MESSAGE_TYPE_CUSTOM:
      if let title = NECustomUtils.titleOfRichText(message.attachment), !title.isEmpty {
        extensionDictionary[revokeLocalMessageTitle] = title
      }
      if let body = NECustomUtils.bodyOfRichText(message.attachment), !body.isEmpty {
        extensionDictionary[revokeLocalMessageContent] = body
      }
    default:
      break
    }

    return NECommonUtil.getJSONStringFromDictionary(extensionDictionary)
  }

  private static func replyDictionary(from messageRefer: V2NIMMessageRefer) -> [String: Any] {
    [
      "idClient": messageRefer.messageClientId as Any,
      "scene": messageRefer.conversationType.rawValue,
      "from": messageRefer.senderId as Any,
      "receiverId": messageRefer.receiverId as Any,
      "to": messageRefer.conversationId as Any,
      "idServer": messageRefer.messageServerId as Any,
      "time": Int(messageRefer.createTime * 1000),
    ]
  }

  private static func reeditState(for message: V2NIMMessage) -> ChatReeditState? {
    switch message.messageType {
    case .MESSAGE_TYPE_TEXT:
      guard let text = message.text, !text.isEmpty else {
        return nil
      }
      return ChatReeditState(
        text: text,
        mentions: ChatMessageMapper.mentionStates(fromServerExtension: message.serverExtension, in: text),
        reply: ChatMessageMapper.replyState(for: message),
        revokeTime: Date().timeIntervalSince1970
      )
    case .MESSAGE_TYPE_CUSTOM:
      guard NECustomUtils.typeOfCustomMessage(message.attachment) == customRichTextType,
            let body = NECustomUtils.bodyOfRichText(message.attachment),
            !body.isEmpty else {
        return nil
      }
      return ChatReeditState(
        text: body,
        title: NECustomUtils.titleOfRichText(message.attachment),
        mentions: ChatMessageMapper.mentionStates(fromServerExtension: message.serverExtension, in: body),
        reply: ChatMessageMapper.replyState(for: message),
        revokeTime: Date().timeIntervalSince1970
      )
    default:
      return nil
    }
  }

  private static func collectionData(for message: V2NIMMessage,
                                     conversationName: String,
                                     displayRow: MessageRowState?) -> String {
    var collectionDictionary: [String: Any] = [
      "conversationName": conversationName,
    ]

    if let serializedMessage = serializedCollectionMessage(message) {
      collectionDictionary["message"] = serializedMessage
    }

    if let senderId = message.senderId {
      collectionDictionary["senderId"] = senderId
      let senderName = NEAIUserManager.shared.getAIUserById(senderId)?.name ??
        displayRow?.senderName ??
        ChatRepo.swiftUIDisplayName(accountId: senderId, showAlias: true)
      collectionDictionary["senderName"] = senderName.isEmpty ? senderId : senderName
    }

    if let avatar = displayRow?.avatarURL?.absoluteString, !avatar.isEmpty {
      collectionDictionary["avatar"] = avatar
    }

    if let text = message.text, !text.isEmpty {
      collectionDictionary["text"] = text
    }
    let textHighlights = collectionTextHighlights(for: message, displayRow: displayRow)
    if !textHighlights.isEmpty {
      collectionDictionary["textHighlights"] = textHighlights
    }
    if NECustomUtils.typeOfCustomMessage(message.attachment) == customRichTextType {
      collectionDictionary["richTextTitle"] = NECustomUtils.titleOfRichText(message.attachment)
      collectionDictionary["richTextBody"] = NECustomUtils.bodyOfRichText(message.attachment)
    }
    if NECustomUtils.typeOfCustomMessage(message.attachment) == customMultiForwardType,
       let data = NECustomUtils.dataOfCustomMessage(message.attachment) {
      collectionDictionary["multiForwardTitle"] = data["sessionName"]
      collectionDictionary["multiForwardURL"] = data["url"]
      collectionDictionary["multiForwardMD5"] = data["md5"]
      collectionDictionary["multiForwardDepth"] = data["depth"]
      collectionDictionary["multiForwardSessionId"] = data["sessionId"]
      collectionDictionary["multiForwardSummaries"] = data["abstracts"]
    }

    collectionDictionary["messageClientId"] = message.messageClientId
    collectionDictionary["messageServerId"] = message.messageServerId
    collectionDictionary["messageType"] = message.messageType.rawValue
    collectionDictionary["conversationType"] = message.conversationType.rawValue
    collectionDictionary["conversationId"] = message.conversationId
    collectionDictionary["createTime"] = message.createTime
    appendCollectionFallbackFields(for: message, displayRow: displayRow, to: &collectionDictionary)

    return NECommonUtil.getJSONStringFromDictionary(collectionDictionary)
  }

  private static func collectionTextHighlights(for message: V2NIMMessage,
                                               displayRow: MessageRowState?) -> [[String: Any]] {
    let rowHighlights = displayRow?.textHighlights ?? []
    let highlights: [MessageTextHighlightState]
    if !rowHighlights.isEmpty {
      highlights = rowHighlights
    } else if let text = collectionHighlightText(for: message, displayRow: displayRow) {
      highlights = ChatMessageMapper.mentionHighlights(fromServerExtension: message.serverExtension, in: text)
    } else {
      highlights = []
    }
    return collectionTextHighlights(from: highlights)
  }

  private static func collectionHighlightText(for message: V2NIMMessage,
                                              displayRow: MessageRowState?) -> String? {
    if let text = collectionHighlightText(in: displayRow?.content) {
      return text
    }
    if message.messageType == .MESSAGE_TYPE_TEXT {
      return message.text
    }
    if NECustomUtils.typeOfCustomMessage(message.attachment) == customRichTextType {
      return NECustomUtils.bodyOfRichText(message.attachment)
    }
    return nil
  }

  private static func collectionHighlightText(in content: MessageContentState?) -> String? {
    switch content {
    case let .text(text):
      return text
    case let .richText(_, body):
      return body
    case let .reply(_, boxed):
      return collectionHighlightText(in: boxed.value)
    case let .aiStream(text, _, _):
      return text
    default:
      return nil
    }
  }

  private static func collectionTextHighlights(from highlights: [MessageTextHighlightState]?) -> [[String: Any]] {
    var result = [[String: Any]]()
    for highlight in highlights ?? [] {
      switch highlight.kind {
      case .mention:
        result.append([
          "start": highlight.start,
          "end": highlight.end,
          "kind": "mention",
        ])
      case .keyword:
        continue
      }
    }
    return result
  }

  private static func appendCollectionFallbackFields(for message: V2NIMMessage,
                                                     displayRow: MessageRowState?,
                                                     to dictionary: inout [String: Any]) {
    switch message.messageType {
    case .MESSAGE_TYPE_IMAGE:
      guard let attachment = message.attachment as? V2NIMMessageImageAttachment else {
        return
      }
      dictionary["mediaURL"] = attachment.url
      dictionary["mediaLocalPath"] = attachment.path
      dictionary["mediaWidth"] = attachment.width
      dictionary["mediaHeight"] = attachment.height
      dictionary["mediaExtension"] = attachment.ext
      if let url = attachment.url, !url.isEmpty {
        let normalizedExt = attachment.ext?
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
          .lowercased()
        dictionary["mediaThumbnailURL"] = normalizedExt == "gif"
          ? url
          : V2NIMStorageUtil.imageThumbUrl(url, thumbSize: 350)
      }
    case .MESSAGE_TYPE_VIDEO:
      guard let attachment = message.attachment as? V2NIMMessageVideoAttachment else {
        return
      }
      dictionary["mediaURL"] = attachment.url
      dictionary["mediaLocalPath"] = attachment.path
      dictionary["mediaWidth"] = attachment.width
      dictionary["mediaHeight"] = attachment.height
      dictionary["mediaDuration"] = normalizedCollectionVideoDuration(attachment.duration)
      if let url = attachment.url, !url.isEmpty {
        dictionary["mediaThumbnailURL"] = V2NIMStorageUtil.videoCoverUrl(url, offset: 0)
      }
    case .MESSAGE_TYPE_AUDIO:
      guard let attachment = message.attachment as? V2NIMMessageAudioAttachment else {
        return
      }
      dictionary["audioURL"] = attachment.url
      dictionary["audioLocalPath"] = attachment.path
      dictionary["audioDuration"] = max(0, TimeInterval(attachment.duration) / 1000.0)
    case .MESSAGE_TYPE_FILE:
      guard let attachment = message.attachment as? V2NIMMessageFileAttachment else {
        return
      }
      dictionary["fileName"] = attachment.name
      dictionary["fileSize"] = attachment.size
      dictionary["fileSizeText"] = ChatUnitFormatter.fileSizeText(bytes: attachment.size)
      dictionary["fileURL"] = attachment.url
      if let displayContent = displayRow?.content,
         case let .file(file) = displayContent {
        dictionary["fileLocalPath"] = file.existingLocalPath ?? file.localPath ?? attachment.path
      } else {
        dictionary["fileLocalPath"] = attachment.path
      }
      dictionary["fileExtension"] = attachment.ext
    case .MESSAGE_TYPE_LOCATION:
      guard let attachment = message.attachment as? V2NIMMessageLocationAttachment else {
        return
      }
      dictionary["locationTitle"] = attachment.address
      dictionary["locationLatitude"] = attachment.latitude
      dictionary["locationLongitude"] = attachment.longitude
      dictionary["locationThumbnailURL"] = NEChatKitClient.instance.getMapImageUrl(lat: attachment.latitude, lng: attachment.longitude)
    default:
      return
    }
  }

  private static func normalizedCollectionVideoDuration<T: BinaryInteger>(_ rawDuration: T) -> TimeInterval {
    let duration = TimeInterval(rawDuration)
    guard duration > 0 else {
      return 0
    }
    return duration >= 1000 ? duration / 1000.0 : duration
  }

  private static func serializedCollectionMessage(_ message: V2NIMMessage) -> String? {
    guard let messageString = V2NIMMessageConverter.messageSerialization(message) else {
      return nil
    }
    guard let collectionMessage = V2NIMMessageConverter.messageDeserialization(messageString) else {
      return messageString
    }

    if var serverExtension = NECommonUtil.getDictionaryFromJSONString(collectionMessage.serverExtension ?? "") as? [String: Any] {
      serverExtension.removeValue(forKey: "yxAitMsg")
      collectionMessage.serverExtension = serverExtension.isEmpty ? "" : NECommonUtil.getJSONStringFromDictionary(serverExtension)
    }

    return V2NIMMessageConverter.messageSerialization(collectionMessage)
  }

  private static func error(code: Int, message: String) -> NSError {
    NSError(
      domain: NEChatUIKitSwiftUIConstants.moduleName,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
