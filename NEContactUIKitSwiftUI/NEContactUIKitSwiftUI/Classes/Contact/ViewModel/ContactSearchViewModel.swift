// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatUIKitSwiftUI
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

@MainActor
public final class ContactSearchViewModel: ObservableObject {
  @Published public private(set) var phase: ContactSearchPhase = .idle
  @Published public private(set) var sections: [ContactSearchSectionState] = []
  @Published public var query = ""
  @Published public var toast: NECommonToast?

  private let contactRepo: ContactRepo
  private let teamRepo: TeamRepo
  private var friends = [NEUserWithFriend]()
  private var teams = [V2NIMTeam]()
  private var didLoad = false

  public init(contactRepo: ContactRepo = .shared,
              teamRepo: TeamRepo = .shared) {
    self.contactRepo = contactRepo
    self.teamRepo = teamRepo
  }

  public func onAppear() {
    guard !didLoad else {
      rebuild()
      return
    }
    didLoad = true
    load()
  }

  public func load() {
    phase = .loading
    let group = DispatchGroup()
    var friendError: NSError?
    var teamError: NSError?

    group.enter()
    loadFriends { [weak self] friends, error in
      Task { @MainActor in
        self?.friends = friends
        friendError = error
        group.leave()
      }
    }

    group.enter()
    teamRepo.getTeamList { [weak self] teams, error in
      Task { @MainActor in
        self?.teams = teams ?? []
        teamError = error
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else {
        return
      }
      if let error = friendError ?? teamError {
        let message = NEContactErrorMessageMapper.message(for: error)
        self.phase = .failed(message)
        self.toast = NECommonToast(message: message)
      } else {
        self.rebuild()
        self.phase = .loaded
      }
    }
  }

  public func updateQuery(_ text: String) {
    query = text
    rebuild()
  }

  public func clearQuery() {
    updateQuery("")
  }

  public func select(_ row: ContactSearchRowState,
                     completion: @escaping (ContactRouteRequest) -> Void) {
    guard row.targetKind == .team else {
      completion(row.route)
      return
    }

    teamRepo.getTeamInfo(row.targetId) { [weak self] team, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          let message = NEContactErrorMessageMapper.message(
            for: error,
            fallbackMessage: NEContactUIKitSwiftUIBundle.localized(
              "leave_team_desc",
              value: "You have been removed from the group chat or the group chat has been dissolved."
            )
          )
          self.toast = NECommonToast(message: message)
          return
        }
        guard team?.isValidTeam != false else {
          self.toast = NECommonToast(
            message: NEContactUIKitSwiftUIBundle.localized(
              "leave_team_desc",
              value: "You have been removed from the group chat or the group chat has been dissolved."
            )
          )
          return
        }
        completion(row.route)
      }
    }
  }

  public func route(for row: ContactSearchRowState) -> ContactRouteRequest {
    row.route
  }

  public func consumeToast(_ toast: NECommonToast) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  private func loadFriends(_ completion: @escaping ([NEUserWithFriend], NSError?) -> Void) {
    if !NEFriendUserCache.shared.isEmpty() {
      completion(NEFriendUserCache.shared.getFriendListNotInBlocklist().map(\.value), nil)
      return
    }

    contactRepo.getContactList { friends, error in
      completion(friends ?? [], error)
    }
  }

  private func rebuild() {
    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      sections = []
      return
    }

    let friendRows = friends.compactMap { friend -> ContactSearchRowState? in
      guard let accountId = friend.user?.accountId ?? friend.friend?.accountId,
            !NEFriendUserCache.shared.isBlockAccount(accountId) else {
        return nil
      }
      let title = friend.showName(true) ?? accountId
      let titleRange = highlightRange(in: title, keyword: keyword)
      let accountRange = highlightRange(in: accountId, keyword: keyword)
      guard titleRange != nil || accountRange != nil else {
        return nil
      }
      guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
        return nil
      }
      return ContactSearchRowState(
        id: "friend.\(accountId)",
        section: .friend,
        conversationId: conversationId,
        targetId: accountId,
        targetKind: .p2p,
        title: title,
        subtitle: accountId,
        highlightedTitleRange: titleRange,
        highlightedSubtitleRange: accountRange,
        avatar: ContactSearchAvatarState(
          imageURL: NECommonAvatarDisplayResolver.url(from: friend.user?.avatar),
          initials: friend.showName(false) ?? accountId,
          hashID: accountId
        )
      )
    }
    .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

    let teamRows = teams.compactMap { team -> ContactSearchRowState? in
      let title = team.getShowName()
      let titleRange = highlightRange(in: title, keyword: keyword)
      guard titleRange != nil else {
        return nil
      }
      guard let conversationId = V2NIMConversationIdUtil.teamConversationId(team.teamId) else {
        return nil
      }
      let section: ContactSearchSectionKind = team.isDisscuss() ? .discussion : .senior
      return ContactSearchRowState(
        id: "\(section.rawValue).\(team.teamId)",
        section: section,
        conversationId: conversationId,
        targetId: team.teamId,
        targetKind: .team,
        title: title,
        highlightedTitleRange: titleRange,
        avatar: ContactSearchAvatarState(
          imageURL: NECommonAvatarDisplayResolver.url(from: team.avatar),
          initials: team.getShortName(),
          hashID: team.teamId
        )
      )
    }
    .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

    let discussionRows = teamRows.filter { $0.section == .discussion }
    let seniorRows = teamRows.filter { $0.section == .senior }
    var nextSections = [ContactSearchSectionState]()
    if !friendRows.isEmpty {
      nextSections.append(ContactSearchSectionState(
        kind: .friend,
        title: NEContactUIKitSwiftUIBundle.localized("friend", value: "Contact"),
        rows: friendRows
      ))
    }
    if !discussionRows.isEmpty {
      nextSections.append(ContactSearchSectionState(
        kind: .discussion,
        title: NEContactUIKitSwiftUIBundle.localized("discussion_group", value: "Temperature Group"),
        rows: discussionRows
      ))
    }
    if !seniorRows.isEmpty {
      nextSections.append(ContactSearchSectionState(
        kind: .senior,
        title: NEContactUIKitSwiftUIBundle.localized("senior_group", value: "Group"),
        rows: seniorRows
      ))
    }
    sections = nextSections
  }

  private func highlightRange(in text: String?,
                              keyword: String) -> Range<String.Index>? {
    guard let text, !text.isEmpty, !keyword.isEmpty else {
      return nil
    }
    return text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive])
  }
}
