// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamManageViewModel: ObservableObject {
  @Published public private(set) var state = TeamManageState()

  public let teamId: String
  public let teamType: NETeamSwiftUITeamType

  private let teamRepo: TeamRepo
  private var listenerToken: NEChatKitListenerToken?
  private var loadGeneration = UUID()
  private var refreshGeneration = UUID()
  private var updateGeneration = [String: UUID]()

  public init(teamId: String,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared) {
    self.teamId = teamId
    self.teamType = teamType
    self.teamRepo = teamRepo
    bindTeamEvents()
  }

  deinit {
    listenerToken?.cancel()
  }

  public func load() {
    let generation = UUID()
    loadGeneration = generation
    state.phase = .loading

    teamRepo.loadSwiftUIManageSnapshot(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.loadGeneration == generation else {
          return
        }
        if let error {
          let message = self.message(for: error)
          self.state.phase = .failed(message)
          self.state.toast = NETeamToastState(message: message, style: .error)
          return
        }
        guard let snapshot else {
          let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.emptyTeam, value: "No team info")
          self.state.phase = .failed(message)
          self.state.toast = NETeamToastState(message: message, style: .warning)
          return
        }
        self.apply(snapshot)
      }
    }
  }

  public func refreshIfNeeded() {
    guard state.phase == .idle else {
      return
    }
    load()
  }

  public func refresh() {
    switch state.phase {
    case .idle, .failed:
      load()
    case .loaded:
      refreshManageSnapshotSilently()
    case .loading:
      break
    }
  }

  public func select(_ row: TeamManageRowState) {
    guard row.isEnabled else {
      noPermissionToast()
      return
    }
    switch row.kind {
    case .managerList:
      state.route = .managerList(teamId: teamId, teamType: teamType)
    case .transferOwner:
      state.route = .transferOwner(teamId: teamId, teamType: teamType)
    case let .permission(kind):
      state.pendingPermissionKind = kind
    case let .toggle(kind):
      setToggle(kind, isOn: !row.isOn)
    }
  }

  public func setPermission(_ option: NETeamSwiftUIManagePermissionOption) {
    guard let kind = state.pendingPermissionKind else {
      return
    }
    state.pendingPermissionKind = nil
    guard ensureNetworkForMutation() else {
      return
    }
    updatePermission(kind, option: option)
  }

  public func setToggle(_ kind: TeamManageToggleKind, isOn: Bool) {
    guard ensureNetworkForMutation() else {
      return
    }
    guard state.snapshot?.canManageSettings == true else {
      noPermissionToast()
      return
    }

    switch kind {
    case .joinAgreeRequired:
      updateJoinAgreeRequired(isOn)
    case .joinVerificationRequired:
      updateJoinVerificationRequired(isOn)
    }
  }

  public func dismissRoute() {
    state.route = nil
  }

  public func dismissPermissionOptions() {
    state.pendingPermissionKind = nil
  }

  public func consumeToast() {
    state.toast = nil
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
        teamInfoUpdated: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.refreshManageSnapshotSilently()
          }
        },
        teamMemberJoined: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshManageSnapshotSilently()
          }
        },
        teamMemberKicked: { [weak self] _, members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshManageSnapshotSilently()
          }
        },
        teamMemberLeft: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshManageSnapshotSilently()
          }
        },
        teamMemberInfoUpdated: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshManageSnapshotSilently()
          }
        }
      )
    )
  }

  private func updatePermission(_ kind: NETeamSwiftUIManagePermissionKind,
                                option: NETeamSwiftUIManagePermissionOption) {
    guard var snapshot = state.snapshot else {
      return
    }
    guard snapshot.canManageSettings else {
      noPermissionToast()
      return
    }

    let key = "permission-\(kind)"
    guard updateGeneration[key] == nil,
          permissionOption(for: kind, in: snapshot) != option else {
      return
    }

    let previous = snapshot
    applyPermission(option, kind: kind, snapshot: &snapshot)
    apply(snapshot)
    invalidateManageSnapshotLoads()

    let generation = UUID()
    updateGeneration[key] = generation
    teamRepo.updateSwiftUIManagePermission(teamId: teamId, teamType: teamType, kind: kind, option: option) { [weak self] error in
      Task { @MainActor in
        guard let self, self.updateGeneration[key] == generation else {
          return
        }
        self.updateGeneration[key] = nil
        if let error {
          self.rollbackPermission(kind, to: previous)
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  private func updateJoinAgreeRequired(_ isRequired: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }
    let key = "toggle-joinAgreeRequired"
    guard updateGeneration[key] == nil,
          snapshot.isJoinAgreeRequired != isRequired else {
      return
    }
    let previous = snapshot
    snapshot.isJoinAgreeRequired = isRequired
    apply(snapshot)
    invalidateManageSnapshotLoads()

    let generation = UUID()
    updateGeneration[key] = generation
    teamRepo.setSwiftUITeamJoinAgreeRequired(teamId: teamId, teamType: teamType, isRequired: isRequired) { [weak self] error in
      Task { @MainActor in
        guard let self, self.updateGeneration[key] == generation else {
          return
        }
        self.updateGeneration[key] = nil
        if let error {
          self.rollbackJoinAgreeRequired(to: previous.isJoinAgreeRequired)
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  private func updateJoinVerificationRequired(_ isRequired: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }
    let key = "toggle-joinVerificationRequired"
    guard updateGeneration[key] == nil,
          snapshot.isJoinVerificationRequired != isRequired else {
      return
    }
    let previous = snapshot
    snapshot.isJoinVerificationRequired = isRequired
    apply(snapshot)
    invalidateManageSnapshotLoads()

    let generation = UUID()
    updateGeneration[key] = generation
    teamRepo.setSwiftUITeamJoinVerificationRequired(teamId: teamId, teamType: teamType, isRequired: isRequired) { [weak self] error in
      Task { @MainActor in
        guard let self, self.updateGeneration[key] == generation else {
          return
        }
        self.updateGeneration[key] = nil
        if let error {
          self.rollbackJoinVerificationRequired(to: previous.isJoinVerificationRequired)
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  private func apply(_ snapshot: NETeamSwiftUIManageSnapshot) {
    guard state.snapshot != snapshot || state.phase != .loaded else {
      return
    }
    state.snapshot = snapshot
    state.sections = makeSections(snapshot)
    state.phase = .loaded
  }

  private func invalidateManageSnapshotLoads() {
    loadGeneration = UUID()
    refreshGeneration = UUID()
  }

  private func rollbackPermission(_ kind: NETeamSwiftUIManagePermissionKind,
                                  to previous: NETeamSwiftUIManageSnapshot) {
    guard var snapshot = state.snapshot else {
      return
    }
    let option: NETeamSwiftUIManagePermissionOption
    switch kind {
    case .editTeamInfo:
      option = previous.editTeamInfoPermission
    case .inviteMember:
      option = previous.inviteMemberPermission
    case .atAll:
      option = previous.atAllPermission
    case .topMessage:
      option = previous.topMessagePermission
    }
    applyPermission(option, kind: kind, snapshot: &snapshot)
    apply(snapshot)
  }

  private func permissionOption(for kind: NETeamSwiftUIManagePermissionKind,
                                in snapshot: NETeamSwiftUIManageSnapshot) -> NETeamSwiftUIManagePermissionOption {
    switch kind {
    case .editTeamInfo:
      return snapshot.editTeamInfoPermission
    case .inviteMember:
      return snapshot.inviteMemberPermission
    case .atAll:
      return snapshot.atAllPermission
    case .topMessage:
      return snapshot.topMessagePermission
    }
  }

  private func rollbackJoinAgreeRequired(to value: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }
    snapshot.isJoinAgreeRequired = value
    apply(snapshot)
  }

  private func rollbackJoinVerificationRequired(to value: Bool) {
    guard var snapshot = state.snapshot else {
      return
    }
    snapshot.isJoinVerificationRequired = value
    apply(snapshot)
  }

  private func refreshManageSnapshotSilently() {
    guard state.phase == .loaded, updateGeneration.isEmpty else {
      return
    }
    let generation = UUID()
    refreshGeneration = generation

    teamRepo.loadSwiftUIManageSnapshot(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self,
              self.refreshGeneration == generation,
              self.updateGeneration.isEmpty else {
          return
        }
        if let error {
          if error.code == teamNotExistCode {
            self.failForMissingTeam()
          } else {
            debugPrint("[NETeamUIKitSwiftUI] teamManage refresh failed teamId=\(self.teamId) errorCode=\(error.code)")
          }
          return
        }
        guard let snapshot else {
          self.failForMissingTeam()
          return
        }
        self.apply(snapshot)
      }
    }
  }

  private func failForMissingTeam() {
    let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist")
    state.phase = .failed(message)
    state.toast = NETeamToastState(message: message, style: .warning)
  }

  private func makeSections(_ snapshot: NETeamSwiftUIManageSnapshot) -> [TeamManageSectionState] {
    var sections = [TeamManageSectionState]()

    if snapshot.canManageManagers {
      sections.append(
        TeamManageSectionState(
          id: "manager",
          rows: [
            TeamManageRowState(
              id: "managerList",
              title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.manageManager, value: "Edit Admin"),
              value: "\(snapshot.managerCount)",
              isEnabled: snapshot.canManageManagers,
              kind: .managerList
            ),
          ]
        )
      )
    }

    var permissionRows = [
      TeamManageRowState(
        id: "editTeamInfo",
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.whoEditTeamInfo, value: "Edit Group Info Permission"),
        value: title(for: snapshot.editTeamInfoPermission),
        isEnabled: snapshot.canManageSettings,
        kind: .permission(.editTeamInfo)
      ),
      TeamManageRowState(
        id: "inviteMember",
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.whoEditUserInfo, value: "Add Member Permission"),
        value: title(for: snapshot.inviteMemberPermission),
        isEnabled: snapshot.canManageSettings,
        kind: .permission(.inviteMember)
      ),
      TeamManageRowState(
        id: "atAll",
        title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.whoAtAll, value: "@All Permission"),
        value: title(for: snapshot.atAllPermission),
        isEnabled: snapshot.canManageSettings,
        kind: .permission(.atAll)
      ),
    ]
    if snapshot.showsTopMessagePermission {
      permissionRows.append(
        TeamManageRowState(
          id: "topMessage",
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.whoCanTopMessage, value: "Top Message Permission"),
          value: title(for: snapshot.topMessagePermission),
          isEnabled: snapshot.canManageSettings,
          kind: .permission(.topMessage)
        )
      )
    }
    sections.append(TeamManageSectionState(id: "permission", rows: permissionRows))

    if snapshot.showsJoinApprovalSettings {
      sections.append(
        TeamManageSectionState(
          id: "join",
          rows: [
            TeamManageRowState(
              id: "joinAgreeRequired",
              title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.invitationAcceptanceRequirement, value: "Invitation acceptance requirement"),
              subtitle: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.invitationAcceptanceRequirementDesc, value: "Invitee approval is required"),
              isOn: snapshot.isJoinAgreeRequired,
              isEnabled: snapshot.canManageSettings,
              kind: .toggle(.joinAgreeRequired)
            ),
            TeamManageRowState(
              id: "joinVerificationRequired",
              title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.requireVerificationToJoin, value: "Require verification to join"),
              subtitle: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.requireVerificationToJoinDesc, value: "Owner or admin approval is required"),
              isOn: snapshot.isJoinVerificationRequired,
              isEnabled: snapshot.canManageSettings,
              kind: .toggle(.joinVerificationRequired)
            ),
          ]
        )
      )
    }

    return sections
  }

  private func applyPermission(_ option: NETeamSwiftUIManagePermissionOption,
                               kind: NETeamSwiftUIManagePermissionKind,
                               snapshot: inout NETeamSwiftUIManageSnapshot) {
    switch kind {
    case .editTeamInfo:
      snapshot.editTeamInfoPermission = option
    case .inviteMember:
      snapshot.inviteMemberPermission = option
    case .atAll:
      snapshot.atAllPermission = option
    case .topMessage:
      snapshot.topMessagePermission = option
    }
  }

  public func title(for option: NETeamSwiftUIManagePermissionOption) -> String {
    switch option {
    case .all:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamAll, value: "Everyone")
    case .ownerAndManager:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamOwnerAndManager, value: "Owner & Admin")
    }
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

  private func message(for error: NSError) -> String {
    NETeamErrorMessageMapper.message(for: error)
  }
}
