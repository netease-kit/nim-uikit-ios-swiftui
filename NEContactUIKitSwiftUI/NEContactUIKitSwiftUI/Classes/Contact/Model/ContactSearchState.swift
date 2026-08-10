// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatUIKitSwiftUI

public enum ContactSearchSectionKind: String, Equatable {
  case friend
  case discussion
  case senior
}

public struct ContactSearchAvatarState: Equatable {
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

public struct ContactSearchRowState: Identifiable, Equatable {
  public var id: String
  public var section: ContactSearchSectionKind
  public var conversationId: String
  public var targetId: String
  public var targetKind: ChatSessionKind
  public var title: String
  public var subtitle: String?
  public var highlightedTitleRange: Range<String.Index>?
  public var highlightedSubtitleRange: Range<String.Index>?
  public var avatar: ContactSearchAvatarState

  public init(id: String,
              section: ContactSearchSectionKind,
              conversationId: String,
              targetId: String,
              targetKind: ChatSessionKind,
              title: String,
              subtitle: String? = nil,
              highlightedTitleRange: Range<String.Index>? = nil,
              highlightedSubtitleRange: Range<String.Index>? = nil,
              avatar: ContactSearchAvatarState) {
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

  public var route: ContactRouteRequest {
    switch targetKind {
    case .team:
      return ContactRouteRequest(kind: .teamChat(teamId: targetId, title: title))
    default:
      return ContactRouteRequest(kind: .chat(accountId: targetId, title: title))
    }
  }
}

public struct ContactSearchSectionState: Identifiable, Equatable {
  public var kind: ContactSearchSectionKind
  public var title: String
  public var rows: [ContactSearchRowState]

  public init(kind: ContactSearchSectionKind,
              title: String,
              rows: [ContactSearchRowState]) {
    self.kind = kind
    self.title = title
    self.rows = rows
  }

  public var id: String { kind.rawValue }
}

public enum ContactSearchPhase: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}
