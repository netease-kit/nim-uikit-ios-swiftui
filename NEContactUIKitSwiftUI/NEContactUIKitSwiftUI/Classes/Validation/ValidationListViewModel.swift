// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

public enum ValidationRowKind: Equatable {
  case friend
  case team
}

public enum ValidationListTab: String, CaseIterable, Identifiable {
  case friend
  case team

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .friend:
      return NEContactUIKitSwiftUIBundle.localized("contact_friend", value: "Friend")
    case .team:
      return NECommonUIKitSwiftUIBundle.localized("team_group", fallback: "Team")
    }
  }
}

private var contactTeamJoinActionReadTime: TimeInterval {
  UserDefaults.standard.double(forKey: keyTeamJoinActionReadTime)
}

public struct ValidationRowState: Identifiable, Equatable {
  public var id: String
  public var kind: ValidationRowKind
  public var title: String
  public var subtitle: String
  public var avatarURL: String?
  public var avatarName: String?
  public var accountId: String
  public var unreadCount: Int
  public var statusText: String?
  public var canHandle: Bool
  public var showsResult: Bool
  public var friendApplication: V2NIMFriendAddApplication?
  public var teamAction: V2NIMTeamJoinActionInfo?

  public static func == (lhs: ValidationRowState, rhs: ValidationRowState) -> Bool {
    lhs.id == rhs.id &&
      lhs.kind == rhs.kind &&
      lhs.title == rhs.title &&
      lhs.subtitle == rhs.subtitle &&
      lhs.avatarURL == rhs.avatarURL &&
      lhs.avatarName == rhs.avatarName &&
      lhs.accountId == rhs.accountId &&
      lhs.unreadCount == rhs.unreadCount &&
      lhs.statusText == rhs.statusText &&
      lhs.canHandle == rhs.canHandle &&
      lhs.showsResult == rhs.showsResult
  }
}

@MainActor
public final class ValidationListViewModel: ObservableObject {
  @Published public private(set) var phase: ContactListPhase = .idle
  @Published public private(set) var rows: [ValidationRowState] = []
  @Published public var toast: NECommonToast?
  @Published public var selectedTab: ValidationListTab = .friend {
    didSet {
      updateRowsForSelectedTab()
    }
  }

  private let contactRepo: ContactRepo
  private let teamRepo: TeamRepo
  private var contactToken: NEChatKitListenerToken?
  private var teamToken: NEChatKitListenerToken?
  private var friendRows: [ValidationRowState] = []
  private var teamRows: [ValidationRowState] = []

  public init(contactRepo: ContactRepo = .shared,
              teamRepo: TeamRepo = .shared) {
    self.contactRepo = contactRepo
    self.teamRepo = teamRepo
  }

  deinit {
    contactToken?.cancel()
    teamToken?.cancel()
  }

  public func onAppear() {
    installListenersIfNeeded()
    load()
  }

  public func onDisappear() {
    markRead()
  }

  public func load() {
    phase = .loading
    loadFriendApplications { [weak self] friendRows, error in
      guard let self else {
        return
      }
      if let error {
        let message = NEContactErrorMessageMapper.message(for: error)
        self.phase = .failed(message)
        self.toast = NECommonToast(message: message)
        return
      }

      guard self.teamValidationEnabled else {
        self.selectedTab = .friend
        self.friendRows = friendRows
        self.teamRows = []
        self.updateRowsForSelectedTab()
        self.phase = .loaded
        return
      }

      self.loadTeamActions { teamRows, teamError in
        if let teamError {
          self.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: teamError))
        }
        self.friendRows = friendRows
        self.teamRows = teamRows
        self.updateRowsForSelectedTab()
        self.phase = .loaded
      }
    }
  }

  public func accept(_ row: ValidationRowState) {
    guard ensureNetworkForMutation() else {
      return
    }
    switch row.kind {
    case .friend:
      guard let application = row.friendApplication else {
        return
      }
      contactRepo.acceptAddApplication(application: application) { [weak self] error in
        Task { @MainActor in
          guard let self else {
            return
          }
          if let error {
            self.handleFriendOperationError(error, row: row)
          } else {
            if let accountId = application.applicantAccountId,
               let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) {
              Router.shared.use(
                ChatAddFriendRouter,
                parameters: [
                  "text": NEContactUIKitSwiftUIBundle.localized(
                    "let_us_chat",
                    value: "I have accepted your request. Let's chat!"
                  ),
                  "conversationId": conversationId,
                ]
              )
            }
            self.replaceFriendGroup(row: row, status: .FRIEND_ADD_APPLICATION_STATUS_AGREED)
            self.refreshFriendApplicationsSilently()
          }
        }
      }
    case .team:
      guard let action = row.teamAction else {
        return
      }
      if action.actionType == .TEAM_JOIN_ACTION_TYPE_APPLICATION {
        teamRepo.acceptJoinApplication(action) { [weak self] error in
          Task { @MainActor in self?.finishTeamHandle(row: row, error: error, accepted: true) }
        }
      } else {
        teamRepo.acceptInvitation(invitationInfo: action) { [weak self] _, error in
          Task { @MainActor in self?.finishTeamHandle(row: row, error: error, accepted: true) }
        }
      }
    }
  }

  public func reject(_ row: ValidationRowState) {
    guard ensureNetworkForMutation() else {
      return
    }
    switch row.kind {
    case .friend:
      guard let application = row.friendApplication else {
        return
      }
      contactRepo.rejectAddApplication(application: application) { [weak self] error in
        Task { @MainActor in
          guard let self else {
            return
          }
          if let error {
            self.handleFriendOperationError(error, row: row)
          } else {
            self.replaceFriendGroup(row: row, status: .FRIEND_ADD_APPLICATION_STATUS_REJECED)
            self.refreshFriendApplicationsSilently()
          }
        }
      }
    case .team:
      guard let action = row.teamAction else {
        return
      }
      if action.actionType == .TEAM_JOIN_ACTION_TYPE_APPLICATION {
        teamRepo.rejectJoinApplication(action, nil) { [weak self] error in
          Task { @MainActor in self?.finishTeamHandle(row: row, error: error, accepted: false) }
        }
      } else {
        teamRepo.rejectInvitation(invitationInfo: action, postscript: nil) { [weak self] error in
          Task { @MainActor in self?.finishTeamHandle(row: row, error: error, accepted: false) }
        }
      }
    }
  }

  public func clearAll() {
    switch selectedTab {
    case .friend:
      clearFriendRows()
    case .team:
      clearTeamRows()
    }
  }

  public var showsTabs: Bool {
    teamValidationEnabled
  }

  public var tabs: [ValidationListTab] {
    teamValidationEnabled ? [.friend, .team] : [.friend]
  }

  public func consumeToast(_ toast: NECommonToast) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  private func clearFriendRows() {
    contactRepo.clearNotification { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
        }
        self.friendRows.removeAll()
        self.updateRowsForSelectedTab()
        self.notifyValidationUnreadClearedIfNeeded()
      }
    }
  }

  private func clearTeamRows() {
    teamRepo.clearAllTeamJoinActionInfo { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
        }
        self.teamRows.removeAll()
        self.updateRowsForSelectedTab()
        self.notifyValidationUnreadClearedIfNeeded()
      }
    }
  }

  private func installListenersIfNeeded() {
    guard contactToken == nil, teamToken == nil else {
      return
    }
    contactToken = contactRepo.addContactEventListener(
      NEContactEvent(
        friendAddApplication: { [weak self] _ in Task { @MainActor in self?.load() } },
        friendAddRejected: { [weak self] rejection in
          Task { @MainActor in self?.applyFriendRejection(rejection) }
        }
      )
    )
    if teamValidationEnabled {
      teamToken = teamRepo.addTeamEventListener(
        NETeamEvent(receiveJoinAction: { [weak self] _ in Task { @MainActor in self?.load() } })
      )
    }
  }

  public func markRead() {
    contactRepo.setAddApplicationRead { _, _ in }
    if teamValidationEnabled {
      teamRepo.setTeamJoinActionInfoRead(applicationInfo: nil) { _ in }
      UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: keyTeamJoinActionReadTime)
    }
    friendRows = friendRows.map { row in
      var updated = row
      updated.unreadCount = 0
      return updated
    }
    teamRows = teamRows.map { row in
      var updated = row
      updated.unreadCount = 0
      return updated
    }
    updateRowsForSelectedTab()
    notifyValidationUnreadClearedIfNeeded()
  }

  private var teamValidationEnabled: Bool {
    IMKitConfigCenter.shared.enableTeam &&
      IMKitConfigCenter.shared.enableTeamJoinAgreeModelAuth
  }

  private func notifyValidationUnreadClearedIfNeeded() {
    NotificationCenter.default.post(name: NENotificationName.clearValidationMessageUnreadCount, object: nil)
  }

  private func loadFriendApplications(completion: @escaping ([ValidationRowState], NSError?) -> Void) {
    loadFriendApplicationsPage(offset: 0, applications: [], completion: completion)
  }

  private func loadFriendApplicationsPage(
    offset: UInt,
    applications: [V2NIMFriendAddApplication],
    completion: @escaping ([ValidationRowState], NSError?) -> Void
  ) {
    let option = V2NIMFriendAddApplicationQueryOption()
    option.offset = offset
    option.limit = 100
    contactRepo.getAddApplicationList(option: option) { [weak self] result, error in
      guard let self else {
        completion([], error)
        return
      }
      guard let result else {
        completion([], error)
        return
      }

      let infos = applications + (result.infos ?? [])
      if !result.finished {
        self.loadFriendApplicationsPage(
          offset: result.offset,
          applications: infos,
          completion: completion
        )
        return
      }

      var rows = self.makeFriendRows(infos, users: [:])
      let ids = Set(infos.compactMap { self.displayAccountId(for: $0) })
      guard !ids.isEmpty else {
        completion(rows, nil)
        return
      }

      self.contactRepo.getUserWithFriend(accountIds: Array(ids)) { users, userError in
        let map = Dictionary(uniqueKeysWithValues: (users ?? []).compactMap { user -> (String, NEUserWithFriend)? in
          guard let accountId = user.user?.accountId ?? user.friend?.accountId else {
            return nil
          }
          return (accountId, user)
        })
        rows = self.makeFriendRows(infos, users: map)
        completion(rows, error ?? userError)
      }
    }
  }

  private func loadTeamActions(completion: @escaping ([ValidationRowState], NSError?) -> Void) {
    let option = V2NIMTeamJoinActionInfoQueryOption()
    option.offset = 0
    option.limit = 100
    teamRepo.getTeamJoinActionInfoList(option) { [weak self] result, error in
      guard let self else {
        completion([], error)
        return
      }
      let infos = result?.infos ?? []
      guard !infos.isEmpty else {
        completion([], error)
        return
      }
      let accountIds = Array(Set(infos.map(\.operatorAccountId).filter { !$0.isEmpty }))
      let teamIds = Array(Set(infos.map(\.teamId).filter { !$0.isEmpty }))
      var users = [String: NEUserWithFriend]()
      var teams = [String: V2NIMTeam]()
      let group = DispatchGroup()
      var mergedError: NSError?

      if !accountIds.isEmpty {
        group.enter()
        self.contactRepo.getUserWithFriend(accountIds: accountIds) { loaded, error in
          if let error { mergedError = error }
          users = Dictionary(uniqueKeysWithValues: (loaded ?? []).compactMap { user in
            guard let accountId = user.user?.accountId ?? user.friend?.accountId else {
              return nil
            }
            return (accountId, user)
          })
          group.leave()
        }
      }

      if !teamIds.isEmpty {
        for teamId in Set(teamIds) {
          group.enter()
          self.teamRepo.getTeamInfo(teamId, .TEAM_TYPE_NORMAL) { team, error in
            if let error { mergedError = error }
            if let team {
              teams[team.teamId] = team
            }
            group.leave()
          }
        }
      }

      group.notify(queue: .main) {
        completion(self.makeTeamRows(infos, users: users, teams: teams), error ?? mergedError)
      }
    }
  }

  private func makeFriendRows(_ applications: [V2NIMFriendAddApplication],
                              users: [String: NEUserWithFriend]) -> [ValidationRowState] {
    var rows = [ValidationRowState]()
    for application in applications {
      let accountId = displayAccountId(for: application) ?? application.operatorAccountId ?? ""
      let user = users[accountId]
      let contributesUnread = application.status == .FRIEND_ADD_APPLICATION_STATUS_INIT && !application.read
      if let index = rows.firstIndex(where: { friendRowsAreEqual($0.friendApplication, application) }) {
        let unreadCount = rows[index].unreadCount + (contributesUnread ? 1 : 0)
        if application.timestamp > (rows[index].friendApplication?.timestamp ?? 0) {
          rows[index] = makeFriendRow(application, user: user, unreadCount: unreadCount)
        } else {
          rows[index].unreadCount = unreadCount
        }
      } else {
        rows.append(makeFriendRow(application, user: user, unreadCount: contributesUnread ? 1 : 0))
      }
    }
    return rows.sorted { ($0.friendApplication?.timestamp ?? 0) > ($1.friendApplication?.timestamp ?? 0) }
  }

  private func makeTeamRows(_ actions: [V2NIMTeamJoinActionInfo],
                            users: [String: NEUserWithFriend],
                            teams: [String: V2NIMTeam]) -> [ValidationRowState] {
    var rows = [ValidationRowState]()
    for action in actions {
      let contributesUnread = action.actionStatus == .TEAM_JOIN_ACTION_STATUS_INIT &&
        action.timestamp > contactTeamJoinActionReadTime
      if let index = rows.firstIndex(where: { teamRowsAreEqual($0.teamAction, action) }) {
        let unreadCount = rows[index].unreadCount + (contributesUnread ? 1 : 0)
        if action.timestamp > (rows[index].teamAction?.timestamp ?? 0) {
          rows[index] = makeTeamRow(
            action,
            user: users[action.operatorAccountId],
            team: teams[action.teamId],
            unreadCount: unreadCount
          )
        } else {
          rows[index].unreadCount = unreadCount
        }
      } else {
        rows.append(
          makeTeamRow(
            action,
            user: users[action.operatorAccountId],
            team: teams[action.teamId],
            unreadCount: contributesUnread ? 1 : 0
          )
        )
      }
    }
    return rows.sorted { ($0.teamAction?.timestamp ?? 0) > ($1.teamAction?.timestamp ?? 0) }
  }

  private func displayAccountId(for application: V2NIMFriendAddApplication) -> String? {
    if application.applicantAccountId == IMKitClient.instance.account() {
      return application.recipientAccountId
    }
    return application.applicantAccountId
  }

  private func makeFriendRow(_ application: V2NIMFriendAddApplication,
                             user: NEUserWithFriend?,
                             unreadCount: Int) -> ValidationRowState {
    let accountId = displayAccountId(for: application) ?? application.operatorAccountId ?? ""
    let title = user.map(ContactSectionBuilder.displayName(for:)) ?? accountId
    let status = friendStatusText(application.status)
    return ValidationRowState(
      id: friendRowId(application, accountId: accountId),
      kind: .friend,
      title: title,
      subtitle: friendDetail(application),
      avatarURL: user?.user?.avatar,
      avatarName: user?.showName(false),
      accountId: accountId,
      unreadCount: unreadCount,
      statusText: status,
      canHandle: application.status == .FRIEND_ADD_APPLICATION_STATUS_INIT && application.applicantAccountId != IMKitClient.instance.account(),
      showsResult: application.status != .FRIEND_ADD_APPLICATION_STATUS_INIT && application.applicantAccountId != IMKitClient.instance.account(),
      friendApplication: application,
      teamAction: nil
    )
  }

  private func makeTeamRow(_ action: V2NIMTeamJoinActionInfo,
                           user: NEUserWithFriend?,
                           team: V2NIMTeam?,
                           unreadCount: Int) -> ValidationRowState {
    let title = user.map(ContactSectionBuilder.displayName(for:)) ?? action.operatorAccountId
    let teamName = team?.name ?? action.teamId
    return ValidationRowState(
      id: teamRowId(action),
      kind: .team,
      title: title,
      subtitle: teamDetail(action, teamName: teamName),
      avatarURL: user?.user?.avatar,
      avatarName: user?.showName(false),
      accountId: action.operatorAccountId,
      unreadCount: unreadCount,
      statusText: teamStatusText(action.actionStatus),
      canHandle: action.actionStatus == .TEAM_JOIN_ACTION_STATUS_INIT &&
        (action.actionType == .TEAM_JOIN_ACTION_TYPE_APPLICATION || action.actionType == .TEAM_JOIN_ACTION_TYPE_INVITATION),
      showsResult: action.actionStatus != .TEAM_JOIN_ACTION_STATUS_INIT,
      friendApplication: nil,
      teamAction: action
    )
  }

  private func friendRowId(_ application: V2NIMFriendAddApplication, accountId: String) -> String {
    "friend.\(accountId).\(application.applicantAccountId ?? "").\(application.recipientAccountId ?? "").\(application.status.rawValue)"
  }

  private func teamRowId(_ action: V2NIMTeamJoinActionInfo) -> String {
    "team.\(action.operatorAccountId).\(action.teamId).\(action.actionType.rawValue).\(action.actionStatus.rawValue)"
  }

  private func friendRowsAreEqual(_ lhs: V2NIMFriendAddApplication?, _ rhs: V2NIMFriendAddApplication) -> Bool {
    guard let lhs else {
      return false
    }
    return lhs.applicantAccountId == rhs.applicantAccountId &&
      lhs.recipientAccountId == rhs.recipientAccountId &&
      lhs.status == rhs.status
  }

  private func teamRowsAreEqual(_ lhs: V2NIMTeamJoinActionInfo?, _ rhs: V2NIMTeamJoinActionInfo) -> Bool {
    guard let lhs else {
      return false
    }
    return lhs.operatorAccountId == rhs.operatorAccountId &&
      lhs.teamId == rhs.teamId &&
      lhs.actionType == rhs.actionType &&
      lhs.actionStatus == rhs.actionStatus
  }

  private func friendDetail(_ application: V2NIMFriendAddApplication) -> String {
    if application.applicantAccountId == IMKitClient.instance.account() {
      if application.status == .FRIEND_ADD_APPLICATION_STATUS_AGREED {
        return NEContactUIKitSwiftUIBundle.localized("agreed_request", value: "Approved your apply")
      }
      if application.status == .FRIEND_ADD_APPLICATION_STATUS_REJECED {
        return NEContactUIKitSwiftUIBundle.localized("refused_request", value: "Reject your apply")
      }
    }
    return NEContactUIKitSwiftUIBundle.localized("add_request", value: "Friend Request")
  }

  private func teamDetail(_ action: V2NIMTeamJoinActionInfo, teamName: String) -> String {
    switch action.actionType {
    case .TEAM_JOIN_ACTION_TYPE_APPLICATION:
      return NEContactUIKitSwiftUIBundle.localized("apply_to_the_team_of", value: "Apply to the group of") + " \(teamName)"
    case .TEAM_JOIN_ACTION_TYPE_INVITATION:
      return NEContactUIKitSwiftUIBundle.localized("invite_to_join_the_team_of", value: "Invite to join the group of") + " \(teamName)"
    case .TEAM_JOIN_ACTION_TYPE_REJECT_APPLICATION:
      return NEContactUIKitSwiftUIBundle.localized("rejected_the_apply", value: "Rejected the apply") + " \(teamName)"
    case .TEAM_JOIN_ACTION_TYPE_REJECT_INVITATION:
      return NEContactUIKitSwiftUIBundle.localized("refused_the_invitation", value: "Refused the invitation") + " \(teamName)"
    default:
      return ""
    }
  }

  private func friendStatusText(_ status: V2NIMFriendAddApplicationStatus) -> String? {
    switch status {
    case .FRIEND_ADD_APPLICATION_STATUS_AGREED:
      return NEContactUIKitSwiftUIBundle.localized("valid_agreed", value: "Added")
    case .FRIEND_ADD_APPLICATION_STATUS_REJECED:
      return NEContactUIKitSwiftUIBundle.localized("valid_refused", value: "Declined")
    case .FRIEND_ADD_APPLICATION_STATUS_EXPIRED:
      return NEContactUIKitSwiftUIBundle.localized("expired", value: "Expired")
    default:
      return nil
    }
  }

  private func teamStatusText(_ status: V2NIMTeamJoinActionStatus) -> String? {
    switch status {
    case .TEAM_JOIN_ACTION_STATUS_AGREED:
      return NEContactUIKitSwiftUIBundle.localized("valid_agreed", value: "Added")
    case .TEAM_JOIN_ACTION_STATUS_REJECTED:
      return NEContactUIKitSwiftUIBundle.localized("valid_refused", value: "Declined")
    case .TEAM_JOIN_ACTION_STATUS_EXPIRED:
      return NEContactUIKitSwiftUIBundle.localized("expired", value: "Expired")
    default:
      return nil
    }
  }

  private func finishTeamHandle(row: ValidationRowState, error: NSError?, accepted: Bool) {
    if let error {
      handleTeamOperationError(error, row: row)
    } else {
      replaceTeamGroup(
        row: row,
        status: accepted ? .TEAM_JOIN_ACTION_STATUS_AGREED : .TEAM_JOIN_ACTION_STATUS_REJECTED
      )
    }
  }

  private func replaceFriendGroup(row: ValidationRowState, status: V2NIMFriendAddApplicationStatus) {
    guard let application = row.friendApplication,
          let index = friendRows.firstIndex(where: { friendRowsAreEqualIgnoringStatus($0.friendApplication, application) }) else {
      return
    }
    friendRows[index].statusText = friendStatusText(status)
    friendRows[index].canHandle = false
    friendRows[index].showsResult = application.applicantAccountId != IMKitClient.instance.account()
    friendRows[index].unreadCount = 0
    let keptId = friendRows[index].id
    friendRows.removeAll { candidate in
      candidate.id != keptId &&
        candidate.friendApplication?.status == status &&
        friendRowsAreEqualIgnoringStatus(candidate.friendApplication, application)
    }
    updateRowsForSelectedTab()
  }

  private func refreshFriendApplicationsSilently() {
    loadFriendApplications { [weak self] rows, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
          return
        }
        self.friendRows = rows
        self.updateRowsForSelectedTab()
        self.notifyValidationUnreadClearedIfNeeded()
      }
    }
  }

  private func applyFriendRejection(_ rejection: V2NIMFriendAddApplication) {
    let currentAccountId = IMKitClient.instance.account()
    let matchingIndex = friendRows.firstIndex { row in
      guard let application = row.friendApplication else {
        return false
      }
      let isSameApplication = friendRowsAreEqualIgnoringStatus(application, rejection)
      let isOutgoingApplication = application.applicantAccountId == currentAccountId &&
        application.recipientAccountId == rejection.operatorAccountId
      return isSameApplication || isOutgoingApplication
    }
    guard let matchingIndex,
          let application = friendRows[matchingIndex].friendApplication else {
      return
    }
    friendRows[matchingIndex].statusText = friendStatusText(.FRIEND_ADD_APPLICATION_STATUS_REJECED)
    friendRows[matchingIndex].canHandle = false
    friendRows[matchingIndex].showsResult = application.applicantAccountId != currentAccountId
    friendRows[matchingIndex].unreadCount = 0
    let keptId = friendRows[matchingIndex].id
    friendRows.removeAll { candidate in
      candidate.id != keptId &&
        candidate.friendApplication?.status == .FRIEND_ADD_APPLICATION_STATUS_REJECED &&
        friendRowsAreEqualIgnoringStatus(candidate.friendApplication, application)
    }
    updateRowsForSelectedTab()
    notifyValidationUnreadClearedIfNeeded()
    refreshFriendApplicationsSilently()
  }

  private func replaceTeamGroup(row: ValidationRowState, status: V2NIMTeamJoinActionStatus) {
    guard let action = row.teamAction,
          let index = teamRows.firstIndex(where: { teamRowsAreEqualIgnoringStatus($0.teamAction, action) }) else {
      return
    }
    teamRows[index].statusText = teamStatusText(status)
    teamRows[index].canHandle = false
    teamRows[index].showsResult = true
    teamRows[index].unreadCount = 0
    let keptId = teamRows[index].id
    teamRows.removeAll { candidate in
      candidate.id != keptId && teamRowsAreEqualIgnoringStatus(candidate.teamAction, action)
    }
    updateRowsForSelectedTab()
  }

  private func friendRowsAreEqualIgnoringStatus(_ lhs: V2NIMFriendAddApplication?, _ rhs: V2NIMFriendAddApplication) -> Bool {
    guard let lhs else {
      return false
    }
    return lhs.applicantAccountId == rhs.applicantAccountId &&
      lhs.recipientAccountId == rhs.recipientAccountId
  }

  private func teamRowsAreEqualIgnoringStatus(_ lhs: V2NIMTeamJoinActionInfo?, _ rhs: V2NIMTeamJoinActionInfo) -> Bool {
    guard let lhs else {
      return false
    }
    return lhs.operatorAccountId == rhs.operatorAccountId &&
      lhs.teamId == rhs.teamId &&
      lhs.actionType == rhs.actionType
  }

  private func handleFriendOperationError(_ error: Error, row: ValidationRowState) {
    let code = (error as NSError).code
    if code == friendAlreadyExist {
      replaceFriendGroup(row: row, status: .FRIEND_ADD_APPLICATION_STATUS_AGREED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("verification_processed", value: "The verification message has been processed."))
      return
    }
    toast = NECommonToast(message: NEContactOperationErrorMapper.message(for: error))
  }

  private func handleTeamOperationError(_ error: Error, row: ValidationRowState) {
    let code = (error as NSError).code
    switch code {
    case protocolSendFailed, protocolTimeout:
      toast = NECommonToast(message: NEContactErrorMessageMapper.networkMessage())
    case teamNotExistCode:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("team_does_not_exist", value: "Team does not exist"))
    case teamMemberNotExist:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("verification_processed", value: "The verification message has been processed."))
    case alreadyInTeamCode:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("already_in_the_team", value: "Already in the team"))
    case invitationExpiredCode:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("invitation_expired", value: "Invitation expired"))
    case noPermissionOperationCode:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("no_permission_tip", value: "No Permission"))
    case teamMemberLimitExceededCode:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("team_member_limit_exceeded", value: "Team member limit exceeded"))
    case joinedTeamLimitExceededCode:
      replaceTeamGroup(row: row, status: .TEAM_JOIN_ACTION_STATUS_EXPIRED)
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("joined_team_limit_exceeded", value: "Joined team limit exceeded"))
    default:
      toast = NECommonToast(message: NEContactOperationErrorMapper.message(for: error))
    }
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NEContactNetworkGuard.allowsNetworkOperation else {
      toast = NECommonToast(message: NEContactErrorMessageMapper.networkMessage())
      return false
    }
    return true
  }

  private func updateRowsForSelectedTab() {
    switch selectedTab {
    case .friend:
      rows = friendRows
    case .team:
      rows = teamRows
    }
  }
}
