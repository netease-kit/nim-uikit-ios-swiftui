// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public struct ChatForwardTargetState: Equatable, Identifiable {
  public var id: String
  public var conversationId: String
  public var title: String?
  public var avatarName: String?
  public var avatarURL: URL?

  public init(conversationId: String,
              title: String? = nil,
              avatarName: String? = nil,
              avatarURL: URL? = nil) {
    id = conversationId
    self.conversationId = conversationId
    self.title = title
    self.avatarName = avatarName
    self.avatarURL = avatarURL
  }

  public var avatarDisplayName: String? {
    switch V2NIMConversationIdUtil.conversationType(conversationId) {
    case .CONVERSATION_TYPE_P2P:
      return avatarName
    default:
      return avatarName ?? title
    }
  }

  public var avatarHashID: String {
    V2NIMConversationIdUtil.conversationTargetId(conversationId) ?? conversationId
  }
}

public protocol ChatRecentForwardProviding {
  func recentForwardTargets(for request: ChatForwardRequest) -> [ChatForwardTargetState]
}

public struct ChatRecentForwardProvider: ChatRecentForwardProviding {
  private let provider: (ChatForwardRequest) -> [ChatForwardTargetState]

  public init(_ provider: @escaping (ChatForwardRequest) -> [ChatForwardTargetState]) {
    self.provider = provider
  }

  public func recentForwardTargets(for request: ChatForwardRequest) -> [ChatForwardTargetState] {
    provider(request)
  }

  public static let chatKitDefault = ChatRecentForwardProvider { request in
    let currentConversationId = request.context.conversationId
    var seen = Set<String>()

    return (SettingRepo.shared.getRecentForward() ?? [])
      .filter { !$0.isEmpty }
      .filter { $0 != currentConversationId }
      .filter { conversationId in
        seen.insert(conversationId).inserted
      }
      .prefix(max(0, IMKitConfigCenter.shared.recentForwardListMaxCount))
      .map { conversationId in
        ChatForwardTargetState(
          conversationId: conversationId,
          title: ChatForwardTargetState.cachedDisplayTitle(for: conversationId)
        )
      }
  }
}

public struct ChatForwardRequest: Equatable {
  public var context: ChatSessionContext
  public var messageIds: [String]
  public var merged: Bool
  public var depth: Int
  public var isFromMessageMultiSelect: Bool

  public init(context: ChatSessionContext,
              messageIds: [String],
              merged: Bool,
              depth: Int = 0,
              isFromMessageMultiSelect: Bool = false) {
    self.context = context
    self.messageIds = messageIds
    self.merged = merged
    self.depth = merged ? max(0, depth) : 0
    self.isFromMessageMultiSelect = isFromMessageMultiSelect
  }
}

public struct ChatForwardSelectionResult: Equatable {
  public var targets: [ChatForwardTargetState]
  public var comment: String?

  public init(targets: [ChatForwardTargetState],
              comment: String? = nil) {
    self.targets = targets
    self.comment = comment
  }
}

public protocol ChatForwardSelectionHandling {
  func selectForwardTargets(_ request: ChatForwardRequest,
                            completion: @escaping (Result<ChatForwardSelectionResult, Error>) -> Void)
}

public struct ChatForwardSelectionHandler: ChatForwardSelectionHandling {
  private let handler: (ChatForwardRequest, @escaping (Result<ChatForwardSelectionResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatForwardRequest, @escaping (Result<ChatForwardSelectionResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func selectForwardTargets(_ request: ChatForwardRequest,
                                   completion: @escaping (Result<ChatForwardSelectionResult, Error>) -> Void) {
    handler(request, completion)
  }
}

private extension ChatForwardTargetState {
  static func cachedDisplayTitle(for conversationId: String) -> String? {
    guard let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId),
          !targetId.isEmpty else {
      return nil
    }
    switch V2NIMConversationIdUtil.conversationType(conversationId) {
    case .CONVERSATION_TYPE_P2P:
      let title = ChatRepo.cachedSwiftUIDisplayUser(accountId: targetId)?
        .showName(true)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return title?.isEmpty == false && title != targetId ? title : nil
    case .CONVERSATION_TYPE_TEAM:
      var error: NSError?
      let title = TeamRepo.shared
        .getTeamInfoLocal(teamId: targetId, teamType: .TEAM_TYPE_NORMAL, error: &error)?
        .name
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return title?.isEmpty == false && title != targetId ? title : nil
    default:
      return nil
    }
  }
}
