// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamMemberListViewModel: ObservableObject {
  @Published public private(set) var state = TeamMemberListState()

  public let teamId: String
  public let scope: NETeamSwiftUIMemberListScope
  public let teamType: NETeamSwiftUITeamType

  private let teamRepo: TeamRepo
  private let client: NETeamUIKitSwiftUIClient
  private var listenerToken: NEChatKitListenerToken?
  private var profileListenerToken: NEChatKitListenerToken?
  private var clientListenerToken: NEChatKitListenerToken?
  private static var memberDisplayCache = [String: [String: NETeamSwiftUIMemberState]]()
  private var loadGeneration = UUID()
  private var refreshGeneration = UUID()
  private var updateGeneration = UUID()
  private var inviteSelectionGeneration = UUID()
  private var inviteGeneration = UUID()
  // SDK member events and list queries can complete out of order. Keep members removed
  // during this page lifetime out of delayed snapshots until an explicit join restores them.
  private var suppressedMemberAccountIds = Set<String>()
  private var hasLoadedSnapshot = false
  private var networkWasBroken = !IMKitClient.instance.swiftUICurrentNetworkAvailable
  private static let loadTimeout: TimeInterval = 10

  public init(teamId: String,
              scope: NETeamSwiftUIMemberListScope = .all,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared,
              client: NETeamUIKitSwiftUIClient = .shared) {
    self.teamId = teamId
    self.scope = scope
    self.teamType = teamType
    self.teamRepo = teamRepo
    self.client = client
    state.teamId = teamId
    restoreCachedMembersIfNeeded()
    bindTeamEvents()
    bindProfileEvents()
    bindClientEvents()
  }

  deinit {
    listenerToken?.cancel()
    profileListenerToken?.cancel()
    clientListenerToken?.cancel()
  }

  public func load(forceRefresh: Bool = true) {
    let generation = UUID()
    loadGeneration = generation
    let hasLoadedMembers = !state.members.isEmpty
    if !hasLoadedMembers {
      state.phase = .loading
    }
    trace("load begin teamId=\(teamId) scope=\(scope) cached=\(hasLoadedMembers) generation=\(generation)")
    scheduleLoadTimeout(generation: generation, hasLoadedMembers: hasLoadedMembers)

    teamRepo.loadSwiftUIMemberList(
      teamId: teamId,
      teamType: teamType,
      scope: scope,
      fetchUserInfo: false,
      forceRefresh: forceRefresh
    ) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.loadGeneration == generation else {
          return
        }
        self.trace("load callback teamId=\(self.teamId) members=\(snapshot?.members.count ?? -1) hasError=\(error != nil) generation=\(generation)")
        if let error {
          if !hasLoadedMembers {
            self.state.phase = .failed(self.message(for: error))
          }
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
          return
        }
        self.apply(snapshot, phase: .loaded)
        self.trace("load loaded teamId=\(self.teamId) members=\(self.state.members.count)")
      }
    }
  }

  public func refreshIfNeeded() {
    guard state.phase == .idle || !hasLoadedSnapshot else {
      return
    }
    load()
  }

  public func updateSearchText(_ text: String) {
    let nextFilteredMembers = filteredMembers(in: state.members, searchText: text)
    guard state.searchText != text || state.filteredMembers != nextFilteredMembers else {
      return
    }
    var nextState = state
    nextState.searchText = text
    nextState.filteredMembers = nextFilteredMembers
    state = nextState
  }

  public func openManagerSelection() {
    guard scope == .managers else {
      return
    }
    guard state.canManageManagers else {
      noPermissionToast()
      return
    }
    state.route = .memberSelect(teamId: teamId, teamType: teamType)
  }

  public func openMemberInviteSelection() {
    guard scope == .all else {
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }
    guard state.canInviteMembers else {
      if state.remainingInviteCount <= 0 {
        state.toast = NETeamToastState(
          message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberLimitExceeded, value: "Team member limit exceeded"),
          style: .warning
        )
      } else {
        noPermissionToast()
      }
      return
    }
    guard let handler = client.memberInviteSelectionHandler else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.inviteMemberUnavailable, value: "Member invitation requires a host selection handler"),
        style: .info
      )
      return
    }

    let generation = UUID()
    inviteSelectionGeneration = generation
    teamRepo.loadSwiftUIMemberList(teamId: teamId, teamType: teamType, scope: .all) { [weak self] memberSnapshot, error in
      Task { @MainActor in
        guard let self, self.inviteSelectionGeneration == generation else {
          return
        }
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
          return
        }
        self.apply(memberSnapshot)
        let request = TeamMemberInviteSelectionRequest(
          teamId: self.teamId,
          memberLimit: self.state.memberLimit,
          remainingInviteCount: self.state.remainingInviteCount,
          existingAccountIds: self.state.existingAccountIds,
          allowsAIUserInvite: self.state.allowsAIUserInvite
        )
        handler.selectTeamMembersToInvite(request: request) { [weak self] result in
          Task { @MainActor in
            guard let self, self.inviteSelectionGeneration == generation else {
              return
            }
            switch result {
            case let .success(.selected(accountIds)):
              self.inviteMembers(accountIds)
            case .success(.cancelled):
              break
            case let .failure(error):
              self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
            }
          }
        }
      }
    }
  }

  public func dismissRoute(reload: Bool = false) {
    state.route = nil
    if reload {
      load()
    }
  }

  public func managerSelectionDidComplete() {
    state.route = nil
    // The add-manager request completed successfully. Its following snapshot is
    // authoritative and may legitimately restore a member demoted on this page.
    suppressedMemberAccountIds.removeAll()
    load()
  }

  public func openMemberProfile(_ member: NETeamSwiftUIMemberState) {
    let request = TeamMemberProfileRequest(
      teamId: teamId,
      accountId: member.accountId,
      isCurrentUser: member.isCurrentUser,
      source: scope == .managers ? .managerList : .memberList,
      teamType: teamType
    )
    client.openTeamMemberProfile(request)
  }

  public func requestRemoveManager(_ member: NETeamSwiftUIMemberState) {
    guard scope == .managers else {
      return
    }
    guard state.canManageManagers else {
      noPermissionToast()
      return
    }
    state.pendingRemoveManager = member
  }

  public func requestRemoveMember(_ member: NETeamSwiftUIMemberState) {
    guard scope == .all else {
      return
    }
    guard state.canRemove(member) else {
      noPermissionToast()
      return
    }
    state.pendingRemoveMember = member
  }

  public func dismissRemoveManager() {
    state.pendingRemoveManager = nil
  }

  public func dismissRemoveMember() {
    state.pendingRemoveMember = nil
  }

  public func confirmRemoveManager() {
    guard let member = state.pendingRemoveManager else {
      return
    }
    guard ensureNetworkForMutation() else {
      state.pendingRemoveManager = nil
      return
    }
    state.pendingRemoveManager = nil
    let previousMembers = state.members
    suppressMembers([member.accountId], removesTeamMembership: false)
    state.isUpdating = true

    let generation = UUID()
    updateGeneration = generation
    teamRepo.removeSwiftUIManagers(teamId: teamId, teamType: teamType, accountIds: [member.accountId]) { [weak self] error in
      Task { @MainActor in
        guard let self, self.updateGeneration == generation else {
          return
        }
        self.state.isUpdating = false
        if let error {
          self.restoreSuppressedMember(member.accountId, members: previousMembers)
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        } else {
          self.load()
        }
      }
    }
  }

  public func confirmRemoveMember() {
    guard let member = state.pendingRemoveMember else {
      return
    }
    guard ensureNetworkForMutation() else {
      state.pendingRemoveMember = nil
      return
    }
    state.pendingRemoveMember = nil
    let previousMembers = state.members
    let previousExistingAccountIds = state.existingAccountIds
    suppressMembers([member.accountId], removesTeamMembership: true)
    state.isUpdating = true

    let generation = UUID()
    updateGeneration = generation
    teamRepo.removeSwiftUITeamMembers(teamId: teamId, teamType: teamType, accountIds: [member.accountId]) { [weak self] error in
      Task { @MainActor in
        guard let self, self.updateGeneration == generation else {
          return
        }
        self.state.isUpdating = false
        if let error {
          self.restoreSuppressedMember(
            member.accountId,
            members: previousMembers,
            existingAccountIds: previousExistingAccountIds
          )
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        } else {
          self.load()
        }
      }
    }
  }

  public func consumeToast() {
    state.toast = nil
  }

  private func inviteMembers(_ accountIds: [String]) {
    guard ensureNetworkForMutation() else {
      return
    }
    let existingAccountIds = Set(state.existingAccountIds)
    var seen = Set<String>()
    let inviteeAccountIds = accountIds.compactMap { accountId -> String? in
      let value = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty,
            !existingAccountIds.contains(value),
            !seen.contains(value) else {
        return nil
      }
      seen.insert(value)
      return value
    }

    guard !inviteeAccountIds.isEmpty else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.memberEmptyTip, value: "Select Member"),
        style: .warning
      )
      return
    }
    guard inviteeAccountIds.count <= state.remainingInviteCount else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberLimitExceeded, value: "Team member limit exceeded"),
        style: .warning
      )
      return
    }

    state.isInviting = true
    let generation = UUID()
    inviteGeneration = generation
    teamRepo.inviteSwiftUITeamMembers(teamId: teamId, teamType: teamType, accountIds: inviteeAccountIds) { [weak self] _, error in
      Task { @MainActor in
        guard let self, self.inviteGeneration == generation else {
          return
        }
        self.state.isInviting = false
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        } else {
          self.suppressedMemberAccountIds.subtract(inviteeAccountIds)
          self.load()
        }
      }
    }
  }

  private func bindTeamEvents() {
    listenerToken = teamRepo.addTeamEventListener(
      NETeamEvent(
        teamDismissed: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.failForMissingTeam()
          }
        },
        teamLeft: { [weak self] team, _ in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.failForMissingTeam()
          }
        },
        teamMemberJoined: { [weak self] members in
          Task { @MainActor in
            guard let self else {
              return
            }
            let accountIds = Set(members.lazy.filter { $0.teamId == self.teamId }.map(\.accountId))
            guard !accountIds.isEmpty else {
              return
            }
            self.suppressedMemberAccountIds.subtract(accountIds)
            self.refreshMemberListSilently()
          }
        },
        teamMemberKicked: { [weak self] _, members in
          Task { @MainActor in
            guard let self else {
              return
            }
            let accountIds = Set(members.lazy.filter { $0.teamId == self.teamId }.map(\.accountId))
            guard !accountIds.isEmpty else {
              return
            }
            self.suppressMembers(accountIds, removesTeamMembership: true)
            self.refreshMemberListSilently()
          }
        },
        teamMemberLeft: { [weak self] members in
          Task { @MainActor in
            guard let self else {
              return
            }
            let accountIds = Set(members.lazy.filter { $0.teamId == self.teamId }.map(\.accountId))
            guard !accountIds.isEmpty else {
              return
            }
            self.suppressMembers(accountIds, removesTeamMembership: true)
            self.refreshMemberListSilently()
          }
        },
        teamMemberInfoUpdated: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshMemberListSilently()
          }
        }
      )
    )
  }

  private func bindProfileEvents() {
    profileListenerToken = teamRepo.addSwiftUITeamMemberProfileListener { [weak self] changedAccountIds in
      Task { @MainActor in
        guard let self else {
          return
        }
        let changed = Set(changedAccountIds)
        guard self.state.members.contains(where: { changed.contains($0.accountId) }) else {
          return
        }
        self.refreshMemberListSilently()
      }
    }
  }

  private func bindClientEvents() {
    clientListenerToken = IMKitClient.instance.addClientEventListener(
      NEIMKitClientEvent(connectionAvailable: { [weak self] isAvailable in
        Task { @MainActor in
          self?.handleConnectionAvailability(isAvailable)
        }
      })
    )
  }

  private func handleConnectionAvailability(_ isAvailable: Bool) {
    guard isAvailable else {
      networkWasBroken = true
      return
    }
    guard networkWasBroken else {
      return
    }
    networkWasBroken = false
    suppressedMemberAccountIds.removeAll()
    load()
  }

  private func refreshMemberListSilently() {
    guard state.phase == .loaded, !state.isUpdating, !state.isInviting else {
      return
    }
    let generation = UUID()
    refreshGeneration = generation

    teamRepo.loadSwiftUIMemberList(
      teamId: teamId,
      teamType: teamType,
      scope: scope,
      fetchUserInfo: false,
      forceRefresh: true
    ) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.refreshGeneration == generation else {
          return
        }
        if let error {
          if error.code == teamNotExistCode {
            self.failForMissingTeam()
          }
          return
        }
        self.apply(snapshot)
      }
    }
  }

  private func scheduleLoadTimeout(generation: UUID, hasLoadedMembers: Bool) {
    guard !hasLoadedMembers else {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout) { [weak self] in
      guard let self,
            self.loadGeneration == generation,
            self.state.phase == .loading else {
        return
      }
      self.trace("load timeout teamId=\(self.teamId) generation=\(generation)")
      self.state.phase = .failed(
        NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.failedOperation, value: "Operation failed")
      )
    }
  }

  private func apply(_ snapshot: NETeamSwiftUIMemberListSnapshot?,
                     phase: NETeamAsyncPhase? = nil) {
    if snapshot != nil {
      hasLoadedSnapshot = true
    }
    let snapshotMembers = (snapshot?.members ?? []).filter { !suppressedMemberAccountIds.contains($0.accountId) }
    let fallbackMembers = state.members.filter { !suppressedMemberAccountIds.contains($0.accountId) }
    let members = sortedMembers(mergedMembers(snapshotMembers, fallback: fallbackMembers))
    let nextKind = snapshot?.kind ?? state.kind
    let nextCurrentRole = snapshot?.currentRole ?? .unknown
    let nextMaxManagerCount = snapshot?.maxManagerCount ?? state.maxManagerCount
    let nextMemberLimit = snapshot?.memberLimit ?? 0
    let nextRemainingInviteCount = snapshot?.remainingInviteCount ?? 0
    let nextExistingAccountIds = (snapshot?.existingAccountIds ?? members.map(\.accountId))
      .filter { !suppressedMemberAccountIds.contains($0) }
    let nextCanInviteMembers = snapshot?.canInviteMembers ?? false
    let nextAllowsAIUserInvite = snapshot?.allowsAIUserInvite ?? false

    var nextState = state
    nextState.kind = nextKind
    nextState.members = members
    nextState.currentRole = nextCurrentRole
    nextState.maxManagerCount = nextMaxManagerCount
    nextState.memberLimit = nextMemberLimit
    nextState.remainingInviteCount = nextRemainingInviteCount
    nextState.existingAccountIds = nextExistingAccountIds
    nextState.canInviteMembers = nextCanInviteMembers
    nextState.allowsAIUserInvite = nextAllowsAIUserInvite
    nextState.filteredMembers = filteredMembers(in: members, searchText: nextState.searchText)
    if let phase {
      nextState.phase = phase
    }
    cacheMembers(members)
    if state != nextState {
      state = nextState
    }
  }

  private func restoreCachedMembersIfNeeded() {
    let cacheKey = memberCacheKey
    guard state.members.isEmpty,
          let cachedMap = Self.memberDisplayCache[cacheKey],
          !cachedMap.isEmpty else {
      return
    }
    state.members = sortedMembers(Array(cachedMap.values))
    state.phase = .loaded
    applySearch()
  }

  private func cacheMembers(_ members: [NETeamSwiftUIMemberState]) {
    Self.memberDisplayCache[memberCacheKey] = Dictionary(uniqueKeysWithValues: members.map { ($0.accountId, $0) })
  }

  private func suppressMembers(_ accountIds: Set<String>, removesTeamMembership: Bool) {
    guard !accountIds.isEmpty else {
      return
    }
    suppressedMemberAccountIds.formUnion(accountIds)
    // Prevent snapshots started before the local mutation or matching event from restoring rows.
    loadGeneration = UUID()
    refreshGeneration = UUID()
    inviteSelectionGeneration = UUID()
    state.members.removeAll { accountIds.contains($0.accountId) }
    if removesTeamMembership {
      state.existingAccountIds.removeAll { accountIds.contains($0) }
    }
    cacheMembers(state.members)
    applySearch()
  }

  private func restoreSuppressedMember(_ accountId: String,
                                       members: [NETeamSwiftUIMemberState],
                                       existingAccountIds: [String]? = nil) {
    suppressedMemberAccountIds.remove(accountId)
    state.members = members
    if let existingAccountIds {
      state.existingAccountIds = existingAccountIds
    }
    cacheMembers(members)
    applySearch()
  }

  private var memberCacheKey: String {
    "\(teamId)#\(teamType.cacheKey)#\(scope.cacheKey)"
  }

  private func mergedMembers(_ members: [NETeamSwiftUIMemberState],
                             fallback existingMembers: [NETeamSwiftUIMemberState]) -> [NETeamSwiftUIMemberState] {
    guard !existingMembers.isEmpty else {
      return members
    }
    let existingMap = Dictionary(uniqueKeysWithValues: existingMembers.map { ($0.accountId, $0) })
    return members.map { member in
      guard let existing = existingMap[member.accountId] else {
        return member
      }
      return mergedMember(member, fallback: existing)
    }
  }

  private func mergedMember(_ member: NETeamSwiftUIMemberState,
                            fallback existing: NETeamSwiftUIMemberState) -> NETeamSwiftUIMemberState {
    var next = member
    if next.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      next.avatarURL = existing.avatarURL
    }
    if next.avatarName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      next.avatarName = existing.avatarName
    }
    if next.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || next.displayName == next.accountId {
      let existingName = existing.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !existingName.isEmpty, existingName != existing.accountId {
        next.displayName = existing.displayName
      }
    }
    if next.teamNick?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      next.teamNick = existing.teamNick
    }
    return next
  }

  private func sortedMembers(_ members: [NETeamSwiftUIMemberState]) -> [NETeamSwiftUIMemberState] {
    switch scope {
    case .all:
      return members.sorted { left, right in
        let leftPriority = rolePriority(left.role)
        let rightPriority = rolePriority(right.role)
        if leftPriority != rightPriority {
          return leftPriority < rightPriority
        }
        return memberOrder(left, right)
      }
    case .managers:
      return members
        .filter { $0.role == .manager }
        .sorted(by: memberOrder)
    }
  }

  private func memberOrder(_ left: NETeamSwiftUIMemberState,
                           _ right: NETeamSwiftUIMemberState) -> Bool {
    if left.joinTime != right.joinTime {
      return left.joinTime < right.joinTime
    }
    return left.accountId.localizedCompare(right.accountId) == .orderedAscending
  }

  private func rolePriority(_ role: NETeamSwiftUIMemberRole) -> Int {
    switch role {
    case .owner:
      return 0
    case .manager:
      return 1
    default:
      return 2
    }
  }

  private func failForMissingTeam() {
    let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist")
    state.phase = .failed(message)
    state.toast = NETeamToastState(message: message, style: .warning)
  }

  private func applySearch() {
    let nextFilteredMembers = filteredMembers(in: state.members, searchText: state.searchText)
    if state.filteredMembers != nextFilteredMembers {
      state.filteredMembers = nextFilteredMembers
    }
  }

  private func filteredMembers(in members: [NETeamSwiftUIMemberState],
                               searchText: String) -> [NETeamSwiftUIMemberState] {
    let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      return []
    }
    return members.filter { member in
      member.displayName.localizedCaseInsensitiveContains(keyword)
    }
  }

  private func message(for error: Error) -> String {
    NETeamErrorMessageMapper.message(for: error)
  }

  private func noPermissionToast() {
    state.toast = NETeamToastState(
      message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noPermissionTip, value: "No permission"),
      style: .warning
    )
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NETeamNetworkGuard.allowsNetworkOperation else {
      state.toast = NETeamToastState(message: NETeamErrorMessageMapper.networkMessage(), style: .warning)
      return false
    }
    return true
  }

  private func trace(_ message: @autoclosure () -> String) {
    debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamMemberListViewModel \(message())")
  }
}

private extension NETeamSwiftUITeamType {
  var cacheKey: String {
    switch self {
    case .normal:
      return "normal"
    case .superTeam:
      return "superTeam"
    }
  }
}

private extension NETeamSwiftUIMemberListScope {
  var cacheKey: String {
    switch self {
    case .all:
      return "all"
    case .managers:
      return "managers"
    }
  }
}
