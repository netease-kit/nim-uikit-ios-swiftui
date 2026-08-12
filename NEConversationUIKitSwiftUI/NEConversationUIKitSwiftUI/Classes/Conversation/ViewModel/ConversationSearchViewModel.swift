// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

@MainActor
public final class ConversationSearchViewModel: ObservableObject {
  @Published public private(set) var phase: ConversationSearchPhase = .idle
  @Published public private(set) var sections: [ConversationSearchSectionState] = []
  @Published public var query = ""
  @Published public var toast: ConversationToastState?
  @Published public var alert: ConversationSearchAlertState?
  public let showsAllWhenQueryEmpty: Bool

  private let contactRepo: ContactRepo
  private let teamRepo: TeamRepo
  private var friends = [NEUserWithFriend]()
  private var teams = [V2NIMTeam]()
  private var didLoad = false

  public init(showsAllWhenQueryEmpty: Bool = false,
              contactRepo: ContactRepo = .shared,
              teamRepo: TeamRepo = .shared) {
    self.showsAllWhenQueryEmpty = showsAllWhenQueryEmpty
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
        let message = NEConversationErrorMessageMapper.message(for: error)
        self.phase = .failed(message)
        self.toast = ConversationToastState(message: message)
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

  public func select(_ row: ConversationSearchRowState,
                     completion: @escaping (ConversationRouteContext) -> Void) {
    if row.targetKind == .team {
      teamRepo.getTeamInfo(row.targetId) { [weak self] team, error in
        Task { @MainActor in
          guard let self else {
            return
          }
          if let error {
            let message = NEConversationErrorMessageMapper.message(
              for: error,
              fallbackMessage: NEConversationUIKitSwiftUIBundle.localized(
                "leave_team_desc",
                value: "You have been removed from the group chat or the group chat has been dissolved."
              )
            )
            if (error as NSError).code == protocolSendFailed {
              self.toast = ConversationToastState(message: message)
            } else {
              self.showLeaveTeamAlert()
            }
            return
          }
          guard team?.isValidTeam != false else {
            self.showLeaveTeamAlert()
            return
          }
          completion(row.routeContext)
        }
      }
    } else {
      completion(row.routeContext)
    }
  }

  public func consumeToast(_ toast: ConversationToastState) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  public func dismissAlert() {
    alert = nil
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
    guard showsAllWhenQueryEmpty || !keyword.isEmpty else {
      sections = []
      return
    }

    let friendRows = friends.compactMap { friend -> ConversationSearchRowState? in
      guard let accountId = friend.user?.accountId ?? friend.friend?.accountId,
            !NEFriendUserCache.shared.isBlockAccount(accountId) else {
        return nil
      }
      let title = friend.showName(true) ?? accountId
      let titleRange = highlightRange(in: title, keyword: keyword)
      let accountRange = highlightRange(in: accountId, keyword: keyword)
      if !keyword.isEmpty {
        guard titleRange != nil || accountRange != nil else {
          return nil
        }
      }
      guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
        return nil
      }
      return ConversationSearchRowState(
        id: "friend.\(accountId)",
        section: .friend,
        conversationId: conversationId,
        targetId: accountId,
        targetKind: .p2p,
        title: title,
        subtitle: accountId,
        highlightedTitleRange: titleRange,
        highlightedSubtitleRange: accountRange,
        avatar: ConversationAvatarState(
          imageURL: NECommonAvatarDisplayResolver.url(from: friend.user?.avatar),
          initials: friend.showName(false) ?? accountId,
          hashID: accountId
        )
      )
    }
    .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

    let teamRows = teams.compactMap { team -> ConversationSearchRowState? in
      let title = team.getShowName()
      let titleRange = highlightRange(in: title, keyword: keyword)
      if !keyword.isEmpty {
        guard titleRange != nil else {
          return nil
        }
      }
      guard let conversationId = V2NIMConversationIdUtil.teamConversationId(team.teamId) else {
        return nil
      }
      let section: ConversationSearchSectionKind = team.isDisscuss() ? .discussion : .senior
      return ConversationSearchRowState(
        id: "\(section.rawValue).\(team.teamId)",
        section: section,
        conversationId: conversationId,
        targetId: team.teamId,
        targetKind: .team,
        title: title,
        subtitle: nil,
        highlightedTitleRange: titleRange,
        highlightedSubtitleRange: nil,
        avatar: ConversationAvatarState(
          imageURL: NECommonAvatarDisplayResolver.url(from: team.avatar),
          initials: team.getShortName(),
          hashID: team.teamId
        )
      )
    }
    .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

    let discussionRows = teamRows.filter { $0.section == .discussion }
    let seniorRows = teamRows.filter { $0.section == .senior }
    var nextSections = [ConversationSearchSectionState]()
    if !friendRows.isEmpty {
      nextSections.append(ConversationSearchSectionState(
        kind: .friend,
        title: NEConversationUIKitSwiftUIBundle.localized("friend", value: "Contact"),
        rows: friendRows
      ))
    }
    if !discussionRows.isEmpty {
      nextSections.append(ConversationSearchSectionState(
        kind: .discussion,
        title: NEConversationUIKitSwiftUIBundle.localized("discussion_group", value: "Temperature Group"),
        rows: discussionRows
      ))
    }
    if !seniorRows.isEmpty {
      nextSections.append(ConversationSearchSectionState(
        kind: .senior,
        title: NEConversationUIKitSwiftUIBundle.localized("senior_group", value: "Group"),
        rows: seniorRows
      ))
    }
    sections = nextSections
  }

  private func showLeaveTeamAlert() {
    alert = ConversationSearchAlertState(
      title: NEConversationUIKitSwiftUIBundle.localized("leave_team", value: "Leave group chat"),
      message: NEConversationUIKitSwiftUIBundle.localized("leave_team_desc", value: "You have been removed from the group chat or the group chat has been dissolved.")
    )
  }

  private func highlightRange(in text: String?,
                              keyword: String) -> Range<String.Index>? {
    guard let text, !text.isEmpty, !keyword.isEmpty else {
      return nil
    }
    return text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive])
  }
}
