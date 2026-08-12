// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatUIKitSwiftUI
import SwiftUI

public enum ConversationSearchSectionKind: String, Equatable {
  case friend
  case discussion
  case senior
}

public struct ConversationSearchRowState: Identifiable, Equatable {
  public var id: String
  public var section: ConversationSearchSectionKind
  public var conversationId: String
  public var targetId: String
  public var targetKind: ConversationTargetKind
  public var title: String
  public var subtitle: String?
  public var highlightedTitleRange: Range<String.Index>?
  public var highlightedSubtitleRange: Range<String.Index>?
  public var avatar: ConversationAvatarState

  public init(id: String,
              section: ConversationSearchSectionKind,
              conversationId: String,
              targetId: String,
              targetKind: ConversationTargetKind,
              title: String,
              subtitle: String? = nil,
              highlightedTitleRange: Range<String.Index>? = nil,
              highlightedSubtitleRange: Range<String.Index>? = nil,
              avatar: ConversationAvatarState) {
    self.id = id
    self.section = section
    self.conversationId = conversationId
    self.targetId = targetId
    self.targetKind = targetKind
    self.title = title
    self.subtitle = subtitle
    self.highlightedTitleRange = highlightedTitleRange
    self.highlightedSubtitleRange = highlightedSubtitleRange
    self.avatar = avatar
  }

  public var routeContext: ConversationRouteContext {
    ConversationRouteContext(
      conversationId: conversationId,
      targetId: targetId,
      kind: targetKind == .team ? .team : .p2p,
      title: title
    )
  }
}

public struct ConversationSearchSectionState: Identifiable, Equatable {
  public var kind: ConversationSearchSectionKind
  public var title: String
  public var rows: [ConversationSearchRowState]

  public init(kind: ConversationSearchSectionKind,
              title: String,
              rows: [ConversationSearchRowState]) {
    self.kind = kind
    self.title = title
    self.rows = rows
  }

  public var id: String { kind.rawValue }
}

public struct ConversationSearchAlertState: Identifiable, Equatable {
  public var id: String
  public var title: String
  public var message: String

  public init(id: String = UUID().uuidString,
              title: String,
              message: String) {
    self.id = id
    self.title = title
    self.message = message
  }
}

public enum ConversationSearchPhase: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}
