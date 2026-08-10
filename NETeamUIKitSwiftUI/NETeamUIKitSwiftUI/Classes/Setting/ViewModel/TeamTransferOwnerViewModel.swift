// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamTransferOwnerViewModel: ObservableObject {
  @Published public private(set) var state = TeamTransferOwnerState()

  public let teamId: String
  public let teamType: NETeamSwiftUITeamType

  private let teamRepo: TeamRepo
  private var listenerToken: NEChatKitListenerToken?
  private var profileListenerToken: NEChatKitListenerToken?
  private var loadGeneration = UUID()
  private var refreshGeneration = UUID()
  private var submitGeneration = UUID()

  public init(teamId: String,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared) {
    self.teamId = teamId
    self.teamType = teamType
    self.teamRepo = teamRepo
    bindTeamEvents()
    bindProfileEvents()
  }

  deinit {
    listenerToken?.cancel()
    profileListenerToken?.cancel()
  }

  public func load() {
    let generation = UUID()
    loadGeneration = generation
    state.phase = .loading

    teamRepo.loadSwiftUITransferOwnerSelection(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
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
        self.apply(snapshot, preservesSelection: true)
        self.state.phase = .loaded
      }
    }
  }

  public func refreshIfNeeded() {
    guard state.phase == .idle else {
      return
    }
    load()
  }

  public func updateSearchText(_ text: String) {
    state.searchText = text
    applySearch()
  }

  public func select(_ member: NETeamSwiftUIMemberState) {
    state.selectedAccountId = member.accountId
  }

  public func submit() {
    guard let accountId = state.selectedAccountId else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.memberEmptyTip, value: "Select Member"),
        style: .warning
      )
      return
    }
    guard state.canSubmit else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noPermissionTip, value: "No permission"),
        style: .warning
      )
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }

    state.isSubmitting = true
    let generation = UUID()
    submitGeneration = generation
    teamRepo.transferSwiftUITeamOwner(teamId: teamId, teamType: teamType, accountId: accountId) { [weak self] error in
      Task { @MainActor in
        guard let self, self.submitGeneration == generation else {
          return
        }
        self.state.isSubmitting = false
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        } else {
          self.state.didSubmit = true
        }
      }
    }
  }

  public func consumeToast() {
    state.toast = nil
  }

  private func applySearch() {
    let keyword = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      state.filteredMembers = []
      return
    }
    state.filteredMembers = state.members.filter { member in
      member.displayName.localizedCaseInsensitiveContains(keyword) ||
        member.accountId.localizedCaseInsensitiveContains(keyword) ||
        (member.teamNick?.localizedCaseInsensitiveContains(keyword) == true)
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
        teamInfoUpdated: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.refreshTransferSnapshotSilently()
          }
        },
        teamMemberJoined: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshTransferSnapshotSilently()
          }
        },
        teamMemberKicked: { [weak self] _, members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshTransferSnapshotSilently()
          }
        },
        teamMemberLeft: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshTransferSnapshotSilently()
          }
        },
        teamMemberInfoUpdated: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshTransferSnapshotSilently()
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
        self.refreshTransferSnapshotSilently()
      }
    }
  }

  private func refreshTransferSnapshotSilently() {
    guard state.phase == .loaded, !state.isSubmitting else {
      return
    }
    let generation = UUID()
    refreshGeneration = generation

    teamRepo.loadSwiftUITransferOwnerSelection(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.refreshGeneration == generation else {
          return
        }
        if let error {
          if error.code == teamNotExistCode {
            self.failForMissingTeam()
          } else {
            debugPrint("[NETeamUIKitSwiftUI] teamTransferOwner refresh failed teamId=\(self.teamId) errorCode=\(error.code)")
          }
          return
        }
        guard let snapshot else {
          self.failForMissingTeam()
          return
        }
        self.apply(snapshot, preservesSelection: true)
      }
    }
  }

  private func apply(_ snapshot: NETeamSwiftUITransferOwnerSnapshot,
                     preservesSelection: Bool) {
    let members = mergedMembers(snapshot.members, fallback: state.members)
    let allowedAccountIds = Set(members.map(\.accountId))
    state.members = members
    state.canSubmit = snapshot.canTransferOwner
    if preservesSelection, let accountId = state.selectedAccountId, allowedAccountIds.contains(accountId) {
      state.selectedAccountId = accountId
    } else {
      state.selectedAccountId = nil
    }
    applySearch()
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

  private func failForMissingTeam() {
    let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist")
    state.phase = .failed(message)
    state.toast = NETeamToastState(message: message, style: .warning)
  }

  private func message(for error: NSError) -> String {
    NETeamErrorMessageMapper.message(for: error)
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NETeamNetworkGuard.allowsNetworkOperation else {
      state.toast = NETeamToastState(message: NETeamErrorMessageMapper.networkMessage(), style: .warning)
      return false
    }
    return true
  }
}
