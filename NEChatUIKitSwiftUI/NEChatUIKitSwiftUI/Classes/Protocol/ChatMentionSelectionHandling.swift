// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum ChatMentionSelectionSource: Equatable {
  case teamMembers
  case aiUsers
}

public enum ChatMentionSelectionTrigger: Equatable {
  case inputAt
  case reply
  case avatarTap
  case programmatic
}

public struct ChatMentionTargetState: Equatable, Identifiable {
  public static let allMembersAccountId = "ait_all"

  public var accountId: String
  public var displayName: String?
  public var isAllMembers: Bool

  public init(accountId: String,
              displayName: String? = nil,
              isAllMembers: Bool = false) {
    let normalizedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.accountId = isAllMembers && normalizedAccountId.isEmpty ? Self.allMembersAccountId : normalizedAccountId
    self.displayName = displayName
    self.isAllMembers = isAllMembers
  }

  public var id: String {
    "\(accountId):\(isAllMembers)"
  }

  public var mentionAccountId: String {
    isAllMembers ? Self.allMembersAccountId : accountId
  }

  public var mentionDisplayName: String {
    if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !displayName.isEmpty {
      return displayName
    }
    if isAllMembers {
      return NEChatUIKitSwiftUIBundle.localized("user_select_all", value: "All")
    }
    return accountId
  }
}

public struct ChatMentionSelectionRequest: Equatable {
  public var context: ChatSessionContext
  public var source: ChatMentionSelectionSource
  public var allowsAllMembers: Bool
  public var trigger: ChatMentionSelectionTrigger

  public init(context: ChatSessionContext,
              source: ChatMentionSelectionSource,
              allowsAllMembers: Bool,
              trigger: ChatMentionSelectionTrigger) {
    self.context = context
    self.source = source
    self.allowsAllMembers = allowsAllMembers
    self.trigger = trigger
  }
}

public struct ChatMentionSelectionResult: Equatable {
  public var targets: [ChatMentionTargetState]

  public init(targets: [ChatMentionTargetState]) {
    self.targets = targets
  }
}

public protocol ChatMentionSelectionHandling {
  func selectMentionTargets(_ request: ChatMentionSelectionRequest,
                            completion: @escaping (Result<ChatMentionSelectionResult, Error>) -> Void)
}

public struct ChatMentionSelectionHandler: ChatMentionSelectionHandling {
  private let handler: (ChatMentionSelectionRequest, @escaping (Result<ChatMentionSelectionResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (ChatMentionSelectionRequest, @escaping (Result<ChatMentionSelectionResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func selectMentionTargets(_ request: ChatMentionSelectionRequest,
                                   completion: @escaping (Result<ChatMentionSelectionResult, Error>) -> Void) {
    handler(request, completion)
  }
}
