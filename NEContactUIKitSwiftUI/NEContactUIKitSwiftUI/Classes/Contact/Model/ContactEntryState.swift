// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

public enum ContactEntryKind: String, Equatable {
  case header
  case friend
  case aiUser
  case aiRobot
  case team
  case blackList
  case validation
}

public struct ContactEntryState: Identifiable, Equatable {
  public var id: String
  public var kind: ContactEntryKind
  public var accountId: String?
  public var title: String
  public var subtitle: String?
  public var avatarURL: String?
  public var avatarName: String?
  public var imageName: String?
  public var unreadCount: Int
  public var isOnline: Bool
  public var isSelected: Bool
  public var isDisabled: Bool
  public var user: NEUserWithFriend?
  public var aiUser: V2NIMAIUser?
  public var team: V2NIMTeam?

  public init(id: String,
              kind: ContactEntryKind,
              accountId: String? = nil,
              title: String,
              subtitle: String? = nil,
              avatarURL: String? = nil,
              avatarName: String? = nil,
              imageName: String? = nil,
              unreadCount: Int = 0,
              isOnline: Bool = false,
              isSelected: Bool = false,
              isDisabled: Bool = false,
              user: NEUserWithFriend? = nil,
              aiUser: V2NIMAIUser? = nil,
              team: V2NIMTeam? = nil) {
    self.id = id
    self.kind = kind
    self.accountId = accountId
    self.title = title
    self.subtitle = subtitle
    self.avatarURL = avatarURL
    self.avatarName = avatarName
    self.imageName = imageName
    self.unreadCount = unreadCount
    self.isOnline = isOnline
    self.isSelected = isSelected
    self.isDisabled = isDisabled
    self.user = user
    self.aiUser = aiUser
    self.team = team
  }

  public static func == (lhs: ContactEntryState, rhs: ContactEntryState) -> Bool {
    lhs.id == rhs.id &&
      lhs.kind == rhs.kind &&
      lhs.accountId == rhs.accountId &&
      lhs.title == rhs.title &&
      lhs.subtitle == rhs.subtitle &&
      lhs.avatarURL == rhs.avatarURL &&
      lhs.avatarName == rhs.avatarName &&
      lhs.imageName == rhs.imageName &&
      lhs.unreadCount == rhs.unreadCount &&
      lhs.isOnline == rhs.isOnline &&
      lhs.isSelected == rhs.isSelected &&
      lhs.isDisabled == rhs.isDisabled
  }
}

public struct ContactSectionState: Identifiable, Equatable {
  public var id: String { title.isEmpty ? "header" : title }
  public var title: String
  public var entries: [ContactEntryState]

  public init(title: String, entries: [ContactEntryState]) {
    self.title = title
    self.entries = entries
  }
}

public enum ContactListPhase: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}

public struct ContactListState: Equatable {
  public var phase: ContactListPhase
  public var sections: [ContactSectionState]
  public var indexTitles: [String]
  public var searchText: String
  public var unreadValidationCount: Int
  public var pendingRoute: ContactRouteRequest?
  public var toast: NECommonToast?

  public init(phase: ContactListPhase = .idle,
              sections: [ContactSectionState] = [],
              indexTitles: [String] = [],
              searchText: String = "",
              unreadValidationCount: Int = 0,
              pendingRoute: ContactRouteRequest? = nil,
              toast: NECommonToast? = nil) {
    self.phase = phase
    self.sections = sections
    self.indexTitles = indexTitles
    self.searchText = searchText
    self.unreadValidationCount = unreadValidationCount
    self.pendingRoute = pendingRoute
    self.toast = toast
  }

  public var visibleSections: [ContactSectionState] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else {
      return sections
    }
    return sections.compactMap { section in
      let entries = section.entries.filter { entry in
        entry.title.lowercased().contains(query) ||
          (entry.accountId?.lowercased().contains(query) ?? false) ||
          (entry.subtitle?.lowercased().contains(query) ?? false)
      }
      guard !entries.isEmpty else {
        return nil
      }
      return ContactSectionState(title: section.title, entries: entries)
    }
  }

  public var shouldShowEmpty: Bool {
    if case .loaded = phase {
      return visibleSections.allSatisfy { $0.entries.isEmpty }
    }
    return false
  }

  public var shouldShowFriendEmptyOverlay: Bool {
    if case .loaded = phase {
      return !visibleSections.contains { section in
        section.entries.contains { $0.kind == .friend }
      }
    }
    return false
  }
}

public struct NECommonToast: Identifiable, Equatable {
  public var id: String
  public var message: String

  public init(id: String = UUID().uuidString, message: String) {
    self.id = id
    self.message = message
  }
}
