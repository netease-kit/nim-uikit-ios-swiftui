// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamAvatarEditViewModel: ObservableObject {
  @Published public private(set) var state = TeamAvatarEditState()

  public let teamId: String
  public let teamType: NETeamSwiftUITeamType
  public let style: NETeamSwiftUIStyleMode

  private let teamRepo: TeamRepo
  private let client: NETeamUIKitSwiftUIClient
  private var listenerToken: NEChatKitListenerToken?
  private var loadGeneration = UUID()
  private var refreshGeneration = UUID()
  private var saveGeneration = UUID()
  private var avatarSelectionGeneration = UUID()

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared,
              client: NETeamUIKitSwiftUIClient = .shared) {
    self.teamId = teamId
    self.style = style
    self.teamType = teamType
    self.teamRepo = teamRepo
    self.client = client
    state.defaultAvatarURLs = teamRepo.swiftUIDefaultTeamAvatarURLs(style: Self.avatarStyle(from: style))
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

  public func updateDraftURL(_ text: String) {
    state.draftAvatarURL = text
  }

  public func selectDefaultAvatar(_ url: String) {
    guard state.canEdit else {
      noPermissionToast()
      return
    }
    guard !state.isSaving else {
      return
    }
    state.draftAvatarURL = url
  }

  public func selectAvatarFromHost() {
    guard state.canEdit else {
      noPermissionToast()
      return
    }
    guard let handler = client.avatarSelectionHandler else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.avatarDeferred, value: "Avatar editing requires a host selection handler"),
        style: .info
      )
      return
    }

    let request = TeamAvatarSelectionRequest(teamId: teamId, currentAvatarURL: state.currentAvatarURL)
    let generation = UUID()
    avatarSelectionGeneration = generation
    handler.selectTeamAvatar(request: request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.avatarSelectionGeneration == generation else {
          return
        }
        switch result {
        case let .success(.selected(url)):
          self.state.draftAvatarURL = url
          self.state.toast = NETeamToastState(
            message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.avatarSelected, value: "Avatar selected"),
            style: .success
          )
        case .success(.cancelled):
          break
        case let .failure(error):
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  public func save() {
    guard ensureNetworkForMutation() else {
      return
    }
    guard state.canSubmit else {
      if !state.canEdit {
        noPermissionToast()
      }
      return
    }

    let avatarURL = state.normalizedDraftURL
    let generation = UUID()
    saveGeneration = generation
    state.isSaving = true
    teamRepo.updateSwiftUITeamAvatarURL(teamId: teamId, teamType: teamType, avatarURL: avatarURL) { [weak self] error in
      Task { @MainActor in
        guard let self, self.saveGeneration == generation else {
          return
        }
        self.state.isSaving = false
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        } else {
          self.state.currentAvatarURL = avatarURL
          self.state.didSave = true
        }
      }
    }
  }

  public func consumeToast() {
    state.toast = nil
  }

  private func noPermissionToast() {
    state.toast = NETeamToastState(
      message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noPermissionTip, value: "No permission"),
      style: .warning
    )
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
            self.refreshAvatarSilently()
          }
        }
      )
    )
  }

  private func refreshAvatarSilently() {
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
            debugPrint("[NETeamUIKitSwiftUI] teamAvatarEdit refresh failed teamId=\(self.teamId) errorCode=\(error.code)")
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
    let previousAvatarURL = state.currentAvatarURL
    state.currentAvatarURL = snapshot.avatarURL
    state.canEdit = snapshot.canEditTeamInfo
    if !preservesDraft || state.draftAvatarURL == (previousAvatarURL ?? "") {
      state.draftAvatarURL = snapshot.avatarURL ?? ""
    }
  }

  private func failForMissingTeam() {
    let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist")
    state.phase = .failed(message)
    state.toast = NETeamToastState(message: message, style: .warning)
  }

  private func message(for error: Error) -> String {
    NETeamErrorMessageMapper.message(for: error)
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NETeamNetworkGuard.allowsNetworkOperation else {
      state.toast = NETeamToastState(message: NETeamErrorMessageMapper.networkMessage(), style: .warning)
      return false
    }
    return true
  }

  private static func avatarStyle(from style: NETeamSwiftUIStyleMode) -> NETeamSwiftUIAvatarStyle {
    style == .fun ? .fun : .normal
  }
}
