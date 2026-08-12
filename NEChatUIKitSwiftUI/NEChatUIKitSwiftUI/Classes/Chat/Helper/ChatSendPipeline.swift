// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ChatSendTextRequest: Equatable {
  public var conversationId: String
  public var context: ChatSessionContext?
  public var text: String
  public var richTextTitle: String?
  public var replyToMessageId: String?
  public var replyToMessageServerId: String?
  public var mentionedAccountIds: Set<String>
  public var mentions: [ChatMentionState]

  public init(conversationId: String,
              context: ChatSessionContext? = nil,
              text: String,
              richTextTitle: String? = nil,
              replyToMessageId: String? = nil,
              replyToMessageServerId: String? = nil,
              mentionedAccountIds: Set<String> = [],
              mentions: [ChatMentionState] = []) {
    self.conversationId = conversationId
    self.context = context
    self.text = text
    self.richTextTitle = richTextTitle
    self.replyToMessageId = replyToMessageId
    self.replyToMessageServerId = replyToMessageServerId
    self.mentionedAccountIds = mentionedAccountIds
    self.mentions = mentions
  }
}

public struct ChatSendResultState {
  public var row: MessageRowState
  public var result: V2NIMSendMessageResult?

  public init(row: MessageRowState,
              result: V2NIMSendMessageResult? = nil) {
    self.row = row
    self.result = result
  }
}

public protocol ChatTextSending {
  func sendText(_ request: ChatSendTextRequest,
                progress: @escaping (Double) -> Void,
                completion: @escaping (Result<ChatSendResultState, Error>) -> Void)
  func sendMessage(_ message: V2NIMMessage,
                   conversationId: String,
                   context: ChatSessionContext?,
                   progress: @escaping (Double) -> Void,
                   completion: @escaping (Result<ChatSendResultState, Error>) -> Void)
}

public protocol ChatPreparedTextSending {
  func makeTextMessage(for request: ChatSendTextRequest) -> V2NIMMessage
  func sendTextMessage(_ message: V2NIMMessage,
                       request: ChatSendTextRequest,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Result<ChatSendResultState, Error>) -> Void)
}

public extension ChatTextSending {
  func sendMessage(_ message: V2NIMMessage,
                   conversationId: String,
                   progress: @escaping (Double) -> Void,
                   completion: @escaping (Result<ChatSendResultState, Error>) -> Void) {
    sendMessage(message,
                conversationId: conversationId,
                context: nil,
                progress: progress,
                completion: completion)
  }
}

public final class NEChatKitSendPipeline: ChatTextSending, ChatPreparedTextSending {
  private let chatRepo: ChatRepo
  private let topicRepo: TopicRepo
  private let currentAccountProvider: () -> String?

  public init(chatRepo: ChatRepo = .shared,
              topicRepo: TopicRepo = .shared,
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() }) {
    self.chatRepo = chatRepo
    self.topicRepo = topicRepo
    self.currentAccountProvider = currentAccountProvider
  }

  public func sendText(_ request: ChatSendTextRequest,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Result<ChatSendResultState, Error>) -> Void) {
    sendTextMessage(
      makeTextMessage(for: request),
      request: request,
      progress: progress,
      completion: completion
    )
  }

  public func makeTextMessage(for request: ChatSendTextRequest) -> V2NIMMessage {
    let richTextTitle = request.richTextTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !richTextTitle.isEmpty {
      var data: [String: Any] = ["title": richTextTitle]
      if !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        data["body"] = request.text
      }
      let rawAttachment = NECommonUtil.getJSONStringFromDictionary([
        "type": customRichTextType,
        "data": data,
      ])
      let message = chatRepo.makeCustomMessage(text: request.text, rawAttachment: rawAttachment)
      message.text = richTextTitle
      chatRepo.applyMentions(mentionInfos(from: request, text: request.text), to: message)
      return message
    }

    return chatRepo.makeTextMessage(
      text: request.text,
      mentions: mentionInfos(from: request, text: request.text)
    )
  }

  public func sendTextMessage(_ message: V2NIMMessage,
                              request: ChatSendTextRequest,
                              progress: @escaping (Double) -> Void,
                              completion: @escaping (Result<ChatSendResultState, Error>) -> Void) {
    let trimmed = request.text.trimmingCharacters(in: .whitespaces)
    let richTextTitle = request.richTextTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty || !richTextTitle.isEmpty else {
      completion(.failure(Self.error(
        code: -1,
        message: NEChatUIKitSwiftUIBundle.localized("chat_input_empty", value: "Message is empty")
      )))
      return
    }

    let aiUserAccountId = mentionedAIAccountId(from: request)
    let completionLock = NSLock()
    var didComplete = false

    let sendCompletion: (V2NIMSendMessageResult?, NSError?, UInt) -> Void = { [currentAccountProvider] result, error, sendProgress in
      let shouldTreatNilZeroAsInterception = result == nil &&
        sendProgress == 0 &&
        Self.shouldTreatNilZeroProgressAsInterception(message)
      completionLock.lock()
      let alreadyCompleted = didComplete
      if error != nil || result != nil || shouldTreatNilZeroAsInterception {
        didComplete = true
      }
      completionLock.unlock()

      guard !alreadyCompleted else {
        return
      }

      if let error {
        NEChatSwiftUILogger.log("sendPipeline send error=\(error)")
        completion(.failure(error))
        return
      }

      if shouldTreatNilZeroAsInterception {
        NEChatSwiftUILogger.log("sendPipeline send intercepted conversationId=\(message.conversationId ?? "")")
        completion(.failure(Self.error(
          code: -2,
          message: NEChatUIKitSwiftUIBundle.localized("chat_send_intercepted", value: "Message was not sent")
        )))
        return
      }

      progress(Double(sendProgress) / 100.0)
      guard result != nil else {
        return
      }

      let sentMessage = result?.message ?? message
      let row = ChatMessageMapper.row(message: sentMessage, currentAccountId: currentAccountProvider())
      completion(.success(ChatSendResultState(row: row, result: result)))
    }

    if let replyToMessageId = request.replyToMessageId, !replyToMessageId.isEmpty {
      chatRepo.getMessageListByIds([replyToMessageId]) { [chatRepo] messages, error in
        if let error {
          NEChatSwiftUILogger.log("sendPipeline resolveReply error=\(error) replyToMessageId=\(replyToMessageId)")
          completion(.failure(error))
          return
        }

        if let replyMessage = messages?.first {
          self.sendReplyMessage(message,
                                replyMessage: replyMessage,
                                request: request,
                                aiUserAccountId: aiUserAccountId,
                                sendCompletion: sendCompletion)
          return
        }

        // Fallback: the reply target may have been recalled and the SDK removed
        // or transformed the original message, causing getMessageListByIds to
        // return empty. Build a complete reply reference and try findReplyMessage.
        let reference = NEChatReplyReference(
          messageClientId: replyToMessageId,
          messageServerId: request.replyToMessageServerId,
          conversationId: request.conversationId,
          conversationType: V2NIMConversationIdUtil.conversationType(request.conversationId)
        )
        chatRepo.findReplyMessage(reference: reference) { [chatRepo] fallbackMessage, fallbackError in
          if let fallbackError {
            NEChatSwiftUILogger.log("sendPipeline findReplyMessage error=\(fallbackError) replyToMessageId=\(replyToMessageId)")
            completion(.failure(fallbackError))
            return
          }

          if let fallbackMessage {
            self.sendReplyMessage(message,
                                  replyMessage: fallbackMessage,
                                  request: request,
                                  aiUserAccountId: aiUserAccountId,
                                  sendCompletion: sendCompletion)
            return
          }

          // Last resort: the reply target message cannot be found (e.g. it was
          // recalled and fully removed). Fall back to the legacy approach that
          // stores reply metadata in serverExtension, matching the UIKit
          // replyMessageWithoutThread behaviour.
          self.sendReplyMessageWithoutThread(
            message,
            reference: reference,
            request: request,
            aiUserAccountId: aiUserAccountId,
            sendCompletion: sendCompletion
          )
        }
      }
    } else {
      let params = chatRepo.swiftUISendMessageParams(
        message: message,
        conversationId: request.conversationId,
        aiUserAccountId: aiUserAccountId
      )
      sendMessage(message,
                  conversationId: request.conversationId,
                  context: request.context,
                  params: params,
                  progress: progress,
                  completion: completion)
    }
  }

  private func sendReplyMessage(_ message: V2NIMMessage,
                                replyMessage: V2NIMMessage,
                                request: ChatSendTextRequest,
                                aiUserAccountId: String?,
                                sendCompletion: @escaping (V2NIMSendMessageResult?, NSError?, UInt) -> Void) {
    let contextMessages = chatRepo.swiftUIAIContextText(for: replyMessage).map { [$0] } ?? []
    let replyParams = chatRepo.swiftUISendMessageParams(
      message: message,
      conversationId: request.conversationId,
      aiUserAccountId: aiUserAccountId,
      contextMessages: contextMessages
    )

    if let context = request.context, context.usesTopicHistory, let topic = context.topic {
      topicRepo.replyTopicMessage(
        message: message,
        replyMessage: replyMessage,
        topic: topic,
        params: replyParams,
        sendCompletion
      )
    } else {
      chatRepo.replyMessage(
        message: message,
        replyMessage: replyMessage,
        params: replyParams,
        sendCompletion
      )
    }
  }

  /// Sends a reply message when the original reply target cannot be found (e.g.
  /// it was recalled and removed from the local database). Encodes reply metadata
  /// into serverExtension (like the UIKit replyMessageWithoutThread) and sends
  /// as a regular message, preserving the reply reference for receivers.
  private func sendReplyMessageWithoutThread(_ message: V2NIMMessage,
                                             reference: NEChatReplyReference,
                                             request: ChatSendTextRequest,
                                             aiUserAccountId: String?,
                                             sendCompletion: @escaping (V2NIMSendMessageResult?, NSError?, UInt) -> Void) {
    let replyDictionary: [String: Any] = [
      "idClient": reference.messageClientId as Any,
      "scene": reference.conversationType.rawValue,
      "from": reference.senderId as Any,
      "receiverId": reference.receiverId as Any,
      "to": reference.conversationId as Any,
      "idServer": reference.messageServerId as Any,
      "time": Int(reference.createTime * 1000),
    ]
    var serverExtension = NECommonUtil.getDictionaryFromJSONString(message.serverExtension ?? "") as? [String: Any] ?? [:]
    serverExtension["yxReplyMsg"] = replyDictionary
    message.serverExtension = NECommonUtil.getJSONStringFromDictionary(serverExtension)

    let params = chatRepo.swiftUISendMessageParams(
      message: message,
      conversationId: request.conversationId,
      aiUserAccountId: aiUserAccountId
    )

    if let context = request.context, context.usesTopicHistory {
      var topicParams = V2NIMSendTopicMessageParams()
      topicParams.sendMessageParams = params
      if context.topic == nil {
        topicParams.createTopicParams = V2NIMCreateTopicParams()
      }
      topicRepo.sendTopicMessage(
        message: message,
        conversationId: request.conversationId,
        topic: context.topic,
        params: topicParams,
        sendCompletion
      )
    } else {
      chatRepo.sendMessage(
        message: message,
        conversationId: request.conversationId,
        params: params,
        sendCompletion
      )
    }
  }

  public func sendMessage(_ message: V2NIMMessage,
                          conversationId: String,
                          context: ChatSessionContext?,
                          progress: @escaping (Double) -> Void,
                          completion: @escaping (Result<ChatSendResultState, Error>) -> Void) {
    sendMessage(message,
                conversationId: conversationId,
                context: context,
                params: chatRepo.swiftUISendMessageParams(message: message, conversationId: conversationId),
                progress: progress,
                completion: completion)
  }

  private func sendMessage(_ message: V2NIMMessage,
                           conversationId: String,
                           context: ChatSessionContext?,
                           params: V2NIMSendMessageParams,
                           progress: @escaping (Double) -> Void,
                           completion: @escaping (Result<ChatSendResultState, Error>) -> Void) {
    let completionLock = NSLock()
    var didComplete = false

    let sendCompletion: (V2NIMSendMessageResult?, NSError?, UInt) -> Void = { [currentAccountProvider] result, error, sendProgress in
      let shouldTreatNilZeroAsInterception = result == nil &&
        sendProgress == 0 &&
        Self.shouldTreatNilZeroProgressAsInterception(message)
      completionLock.lock()
      let alreadyCompleted = didComplete
      if error != nil || result != nil || shouldTreatNilZeroAsInterception {
        didComplete = true
      }
      completionLock.unlock()

      guard !alreadyCompleted else {
        return
      }

      if let error {
        NEChatSwiftUILogger.log("sendPipeline sendMessage error=\(error)")
        completion(.failure(error))
        return
      }

      if shouldTreatNilZeroAsInterception {
        NEChatSwiftUILogger.log("sendPipeline sendMessage intercepted conversationId=\(conversationId)")
        completion(.failure(Self.error(
          code: -2,
          message: NEChatUIKitSwiftUIBundle.localized("chat_send_intercepted", value: "Message was not sent")
        )))
        return
      }

      progress(Double(sendProgress) / 100.0)
      guard result != nil else {
        return
      }

      let sentMessage = result?.message ?? message
      let row = ChatMessageMapper.row(message: sentMessage, currentAccountId: currentAccountProvider())
      completion(.success(ChatSendResultState(row: row, result: result)))
    }

    if let context, context.usesTopicHistory {
      let topicParams = V2NIMSendTopicMessageParams()
      topicParams.sendMessageParams = params
      if context.topic == nil {
        topicParams.createTopicParams = V2NIMCreateTopicParams()
      }
      topicRepo.sendTopicMessage(
        message: message,
        conversationId: conversationId,
        topic: context.topic,
        params: topicParams,
        sendCompletion
      )
      return
    }

    chatRepo.sendMessage(message: message, conversationId: conversationId, params: params, sendCompletion)
  }

  private static func error(code: Int, message: String) -> NSError {
    NSError(
      domain: NEChatUIKitSwiftUIConstants.moduleName,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private static func shouldTreatNilZeroProgressAsInterception(_ message: V2NIMMessage) -> Bool {
    switch message.messageType {
    case .MESSAGE_TYPE_AUDIO,
         .MESSAGE_TYPE_FILE,
         .MESSAGE_TYPE_IMAGE,
         .MESSAGE_TYPE_VIDEO:
      return false
    default:
      return true
    }
  }

  private func mentionedAIAccountId(from request: ChatSendTextRequest) -> String? {
    let orderedMentions = request.mentions.enumerated().sorted { lhs, rhs in
      if lhs.element.start == rhs.element.start {
        return lhs.offset < rhs.offset
      }
      return lhs.element.start < rhs.element.start
    }.map { $0.element }

    for mention in orderedMentions {
      let accountId = mention.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !accountId.isEmpty,
            mentionSegment(for: mention, in: request.text) != nil,
            NEAIUserManager.shared.isAIUser(accountId) else {
        continue
      }
      return accountId
    }

    let fallbackMentions = request.mentionedAccountIds.compactMap {
      rawAccountId -> (accountId: String, location: Int)? in
      let accountId = rawAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !accountId.isEmpty,
            NEAIUserManager.shared.isAIUser(accountId),
            let range = request.text.range(of: "@\(accountId)") else {
        return nil
      }
      return (accountId, request.text.distance(from: request.text.startIndex, to: range.lowerBound))
    }
    return fallbackMentions.min { $0.location < $1.location }?.accountId
  }

  private func mentionInfos(from request: ChatSendTextRequest,
                            text: String) -> [NEChatMentionInfo] {
    let explicitMentions = request.mentions.compactMap { mention -> (mention: ChatMentionState, segment: NEChatMentionSegment)? in
      guard let segment = mentionSegment(for: mention, in: text) else {
        return nil
      }
      return (mention, segment)
    }
    if !explicitMentions.isEmpty {
      var grouped = [String: (displayText: String, segments: [NEChatMentionSegment])]()
      for item in explicitMentions {
        let mention = item.mention
        let accountId = mention.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountId.isEmpty else {
          continue
        }
        let current = grouped[accountId]
        grouped[accountId] = (
          displayText: current?.displayText ?? mention.displayText,
          segments: (current?.segments ?? []) + [item.segment]
        )
      }
      return grouped.map { accountId, value in
        NEChatMentionInfo(accountId: accountId, text: value.displayText, segments: value.segments)
      }
    }

    return request.mentionedAccountIds.compactMap { accountId in
      let normalizedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalizedAccountId.isEmpty,
            let range = text.range(of: "@\(normalizedAccountId)") else {
        return nil
      }

      let segmentRange = mentionSegmentRange(displayRange: range, in: text)
      return NEChatMentionInfo(
        accountId: normalizedAccountId,
        text: "@\(normalizedAccountId)",
        segments: [NEChatMentionSegment(start: segmentRange.start, end: segmentRange.end)]
      )
    }
  }

  private func mentionSegment(for mention: ChatMentionState,
                              in text: String) -> NEChatMentionSegment? {
    if mention.start >= 0,
       mention.end >= mention.start,
       mention.end < text.utf16.count {
      let range = NSRange(
        location: mention.start,
        length: mention.end - mention.start + 1
      )
      if (text as NSString).substring(with: range) == mention.displayText {
        return NEChatMentionSegment(start: mention.start, end: mention.end + 1)
      }
    }

    guard let range = text.range(of: mention.displayText) else {
      return nil
    }
    let segmentRange = mentionSegmentRange(displayRange: range, in: text)
    return NEChatMentionSegment(start: segmentRange.start, end: segmentRange.end)
  }

  private func mentionSegmentRange(displayRange: Range<String.Index>,
                                   in text: String) -> (start: Int, end: Int) {
    let nsRange = NSRange(displayRange, in: text)
    return (nsRange.location, nsRange.location + nsRange.length)
  }
}
