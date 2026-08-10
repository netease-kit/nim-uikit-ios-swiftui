// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NECommonUIKitSwiftUI

@MainActor
public final class TeamTextEditViewModel: ObservableObject {
  @Published public private(set) var state = TeamTextEditState()

  public let teamId: String
  public let field: TeamTextEditField
  public let teamType: NETeamSwiftUITeamType

  private let teamRepo: TeamRepo
  private var listenerToken: NEChatKitListenerToken?
  private var currentAccountId: String?
  private var loadedText = ""
  private var loadGeneration = UUID()
  private var refreshGeneration = UUID()
  private var saveGeneration = UUID()

  public init(teamId: String,
              field: TeamTextEditField,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared) {
    self.teamId = teamId
    self.field = field
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

    teamRepo.loadSwiftUITeamInfo(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
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
        self.apply(snapshot, preservesDraft: false)
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

  public func updateText(_ text: String) {
    state.text = NECommonTextLimit.limitedUTF16(text, limit: field.limit)
  }

  public func clearText() {
    state.text = ""
  }

  public func save() {
    guard ensureNetworkForMutation() else {
      return
    }
    guard state.canSubmit(field: field) else {
      if !state.canEdit {
        state.toast = NETeamToastState(
          message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noPermissionTip, value: "No permission"),
          style: .warning
        )
      }
      return
    }

    if (field == .name || field == .nick),
       !state.text.isEmpty,
       state.text.trimmingCharacters(in: .whitespaces).isEmpty {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.spaceNotSupport, value: "All spaces are not supported"),
        style: .warning
      )
      state.text = state.text.trimmingCharacters(in: .whitespaces)
      return
    }

    let generation = UUID()
    saveGeneration = generation
    state.isSaving = true

    let completion: (NSError?) -> Void = { [weak self] error in
      Task { @MainActor in
        guard let self, self.saveGeneration == generation else {
          return
        }
        self.state.isSaving = false
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
          return
        }
        self.state.didSave = true
      }
    }

    switch field {
    case .name:
      teamRepo.updateSwiftUITeamName(teamId: teamId, teamType: teamType, name: state.text, completion: completion)
    case .nick:
      teamRepo.updateSwiftUITeamNick(teamId: teamId, teamType: teamType, nick: state.text, completion: completion)
    case .introduce:
      teamRepo.updateSwiftUITeamIntroduce(teamId: teamId, teamType: teamType, introduce: state.text, completion: completion)
    }
  }

  public func consumeToast() {
    state.toast = nil
  }

  private func initialText(from snapshot: NETeamSwiftUIInfoSnapshot) -> String {
    switch field {
    case .name:
      return snapshot.name
    case .nick:
      return snapshot.currentTeamNick ?? ""
    case .introduce:
      return snapshot.intro ?? ""
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
            self.refreshInfoSilently()
          }
        },
        teamMemberInfoUpdated: { [weak self] members in
          Task { @MainActor in
            guard let self,
                  self.field == .nick,
                  let currentAccountId = self.currentAccountId,
                  !currentAccountId.isEmpty else {
              return
            }
            if members.contains(where: { $0.teamId == self.teamId && $0.accountId == currentAccountId }) {
              self.refreshInfoSilently()
            }
          }
        }
      )
    )
  }

  private func refreshInfoSilently() {
    guard state.phase == .loaded, !state.isSaving else {
      return
    }
    let generation = UUID()
    refreshGeneration = generation

    teamRepo.loadSwiftUITeamInfo(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.refreshGeneration == generation else {
          return
        }
        if let error {
          if error.code == teamNotExistCode {
            self.failForMissingTeam()
          } else {
            debugPrint("[NETeamUIKitSwiftUI] teamTextEdit refresh failed teamId=\(self.teamId) errorCode=\(error.code)")
          }
          return
        }
        guard let snapshot else {
          self.failForMissingTeam()
          return
        }
        self.apply(snapshot, preservesDraft: true)
      }
    }
  }

  private func apply(_ snapshot: NETeamSwiftUIInfoSnapshot,
                     preservesDraft: Bool) {
    currentAccountId = snapshot.currentAccountId
    let latestText = initialText(from: snapshot)
    state.canEdit = field == .nick ? true : snapshot.canEditTeamInfo
    if !preservesDraft || state.text == loadedText {
      state.text = latestText
    }
    loadedText = latestText
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
