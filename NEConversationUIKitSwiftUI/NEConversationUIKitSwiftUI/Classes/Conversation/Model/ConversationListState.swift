// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import SwiftUI
import NEChatUIKitSwiftUI

public enum ConversationLoadPhase: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}

public enum ConversationTargetKind: String, Equatable {
  case p2p
  case team
  case unknown

  public var chatKind: ChatSessionKind? {
    switch self {
    case .p2p: return .p2p
    case .team: return .team
    case .unknown: return nil
    }
  }
}

public struct ConversationAvatarState: Equatable {
  public var imageURL: URL?
  public var initials: String
  public var hashID: String?

  public init(imageURL: URL? = nil,
              initials: String,
              hashID: String? = nil) {
    self.imageURL = imageURL
    self.initials = initials
    self.hashID = hashID
  }
}

public struct ConversationRowState: Identifiable, Equatable {
  public var id: String
  public var conversationId: String
  public var targetId: String?
  public var targetKind: ConversationTargetKind
  public var title: String
  public var subtitle: String
  public var timeText: String
  public var avatar: ConversationAvatarState
  public var unreadText: String?
  public var unreadCount: Int
  public var isStickTop: Bool
  public var isMuted: Bool
  public var isAtCurrentUser: Bool
  public var isOnline: Bool?
  public var isRobot: Bool
  public var sortOrder: Int64

  public init(id: String,
              conversationId: String,
              targetId: String?,
              targetKind: ConversationTargetKind,
              title: String,
              subtitle: String,
              timeText: String,
              avatar: ConversationAvatarState,
              unreadText: String?,
              unreadCount: Int,
              isStickTop: Bool,
              isMuted: Bool,
              isAtCurrentUser: Bool,
              isOnline: Bool?,
              isRobot: Bool = false,
              sortOrder: Int64) {
    self.id = id
    self.conversationId = conversationId
    self.targetId = targetId
    self.targetKind = targetKind
    self.title = title
    self.subtitle = subtitle
    self.timeText = timeText
    self.avatar = avatar
    self.unreadText = unreadText
    self.unreadCount = unreadCount
    self.isStickTop = isStickTop
    self.isMuted = isMuted
    self.isAtCurrentUser = isAtCurrentUser
    self.isOnline = isOnline
    self.isRobot = isRobot
    self.sortOrder = sortOrder
  }

  public var routeContext: ConversationRouteContext? {
    guard let kind = targetKind.chatKind else {
      return nil
    }
    return ConversationRouteContext(
      conversationId: conversationId,
      targetId: targetId,
      kind: kind,
      title: title,
      isRobot: isRobot
    )
  }
}

public struct ConversationAIUserState: Identifiable, Equatable {
  public var id: String
  public var title: String
  public var avatar: ConversationAvatarState
  public var conversationId: String

  public init(id: String,
              title: String,
              avatar: ConversationAvatarState,
              conversationId: String) {
    self.id = id
    self.title = title
    self.avatar = avatar
    self.conversationId = conversationId
  }
}

public struct ConversationToastState: Identifiable, Equatable {
  public var id: String
  public var message: String

  public init(id: String = UUID().uuidString,
              message: String) {
    self.id = id
    self.message = message
  }
}

public struct ConversationListState: Equatable {
  public var phase: ConversationLoadPhase
  public var rows: [ConversationRowState]
  public var aiUsers: [ConversationAIUserState]
  public var isLoadingMore: Bool
  public var hasMore: Bool
  public var networkBroken: Bool
  public var searchText: String
  public var toast: ConversationToastState?
  public var isActionMenuPresented: Bool
  public var pendingRoute: ConversationRouteContext?
  public var listReloadRevision: Int

  public init(phase: ConversationLoadPhase = .idle,
              rows: [ConversationRowState] = [],
              aiUsers: [ConversationAIUserState] = [],
              isLoadingMore: Bool = false,
              hasMore: Bool = true,
              networkBroken: Bool = false,
              searchText: String = "",
              toast: ConversationToastState? = nil,
              isActionMenuPresented: Bool = false,
              pendingRoute: ConversationRouteContext? = nil,
              listReloadRevision: Int = 0) {
    self.phase = phase
    self.rows = rows
    self.aiUsers = aiUsers
    self.isLoadingMore = isLoadingMore
    self.hasMore = hasMore
    self.networkBroken = networkBroken
    self.searchText = searchText
    self.toast = toast
    self.isActionMenuPresented = isActionMenuPresented
    self.pendingRoute = pendingRoute
    self.listReloadRevision = listReloadRevision
  }

  public var filteredRows: [ConversationRowState] {
    let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      return rows
    }
    return rows.filter {
      $0.title.localizedCaseInsensitiveContains(keyword) ||
        $0.subtitle.localizedCaseInsensitiveContains(keyword) ||
        $0.conversationId.localizedCaseInsensitiveContains(keyword) ||
        ($0.targetId?.localizedCaseInsensitiveContains(keyword) ?? false)
    }
  }

  public var shouldShowEmpty: Bool {
    switch phase {
    case .loaded:
      return rows.isEmpty
    default:
      return false
    }
  }
}
