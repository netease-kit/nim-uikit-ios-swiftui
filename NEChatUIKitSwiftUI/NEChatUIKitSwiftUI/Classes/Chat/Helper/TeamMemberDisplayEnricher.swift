// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public enum TeamMemberDisplayEnricher {
  public static func enrich(rows: [MessageRowState],
                            conversationId: String,
                            extraAccountIds: [String] = [],
                            completion: @escaping ([MessageRowState]) -> Void) {
    let conversationType = V2NIMConversationIdUtil.conversationType(conversationId)
    guard conversationType == .CONVERSATION_TYPE_TEAM ||
      conversationType == .CONVERSATION_TYPE_SUPER_TEAM else {
      completion(rows)
      return
    }

    let teamId = teamId(from: conversationId)
    guard !teamId.isEmpty else {
      completion(rows)
      return
    }

    let accountIds = accountIds(from: rows, extraAccountIds: extraAccountIds)
    guard !accountIds.isEmpty else {
      completion(rows)
      return
    }

    let cachedRows = rows.map { applyingCachedInfo(to: $0) }
    TeamRepo.shared.swiftUITeamMemberDisplayInfos(teamId: teamId, accountIds: accountIds) { infos, _ in
      let infoMap = Dictionary(uniqueKeysWithValues: infos.map { ($0.accountId, $0) })
      let enrichedRows = cachedRows.map { applying(infoMap, to: $0) }
      completion(enrichedRows)
    }
  }

  private static func teamId(from conversationId: String) -> String {
    if let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId), !targetId.isEmpty {
      return targetId
    }
    return conversationId
  }

  private static func accountIds(from rows: [MessageRowState],
                                 extraAccountIds: [String]) -> [String] {
    var orderedAccountIds = [String]()

    func append(_ accountId: String?) {
      let trimmedId = accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !trimmedId.isEmpty,
            !orderedAccountIds.contains(trimmedId) else {
        return
      }
      orderedAccountIds.append(trimmedId)
    }

    extraAccountIds.forEach { append($0) }
    for row in rows {
      append(row.senderId)
      append(row.reply?.senderId)
      append(row.pinOperatorId)
    }
    return orderedAccountIds
  }

  private static func applyingCachedInfo(to row: MessageRowState) -> MessageRowState {
    var next = row
    if let senderId = row.senderId {
      let cached = ChatAvatarDisplayResolver.info(
        accountId: senderId,
        fallbackName: next.senderName,
        fallbackAvatarURL: next.avatarURL
      )
      next.senderName = cached.displayName ?? next.senderName
      next.avatarURL = cached.avatarURL ?? next.avatarURL
      let avatarDisplay = ChatAvatarDisplayResolver.info(
        accountId: senderId,
        fallbackName: next.avatarName,
        showAlias: false
      )
      next.avatarName = avatarDisplay.displayName ?? next.avatarName
    }
    if var reply = row.reply,
       let senderId = reply.senderId {
      let cached = ChatAvatarDisplayResolver.info(
        accountId: senderId,
        fallbackName: reply.senderName
      )
      reply.senderName = cached.displayName ?? reply.senderName
      next.reply = reply
      if case let .reply(_, content) = next.content {
        next.content = .reply(preview: reply.displayPreview, content: content)
      }
    }
    if let operatorId = row.pinOperatorId {
      let fallbackName = ChatAvatarDisplayResolver.info(
        accountId: operatorId,
        fallbackName: next.pinOperatorName
      ).displayName
      next.pinOperatorName = operatorDisplayName(operatorId, fallbackName: fallbackName)
    }
    return next
  }

  private static func applying(_ infoMap: [String: NETeamMemberDisplayInfo],
                               to row: MessageRowState) -> MessageRowState {
    var next = row
    if let senderId = row.senderId,
       let info = infoMap[senderId] {
      next.senderName = info.displayName
      next.avatarName = info.avatarName ?? senderId
      if let avatarURL = ChatAvatarURLResolver.url(from: info.avatarURL) {
        next.avatarURL = avatarURL
      }
    }
    if let senderId = row.senderId,
       next.avatarURL == nil {
      let cached = ChatAvatarDisplayResolver.info(
        accountId: senderId,
        fallbackName: next.senderName,
        fallbackAvatarURL: next.avatarURL
      )
      next.senderName = cached.displayName ?? next.senderName
      next.avatarURL = cached.avatarURL
    }

    if var reply = row.reply,
       let senderId = reply.senderId,
       let info = infoMap[senderId] {
      reply.senderName = info.displayName
      next.reply = reply
      if case let .reply(_, content) = next.content {
        next.content = .reply(preview: reply.displayPreview, content: content)
      }
    }
    if let operatorId = row.pinOperatorId,
       let info = infoMap[operatorId] {
      next.pinOperatorName = operatorDisplayName(operatorId, fallbackName: info.displayName)
    }
    if let operatorId = row.pinOperatorId,
       next.pinOperatorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      let fallbackName = ChatAvatarDisplayResolver.info(accountId: operatorId).displayName
      next.pinOperatorName = operatorDisplayName(operatorId, fallbackName: fallbackName)
    }
    return next
  }

  private static func operatorDisplayName(_ accountId: String,
                                          fallbackName: String?) -> String? {
    if accountId == IMKitClient.instance.account() {
      return NEChatUIKitSwiftUIBundle.localized("You", value: "you")
    }
    return fallbackName
  }
}
