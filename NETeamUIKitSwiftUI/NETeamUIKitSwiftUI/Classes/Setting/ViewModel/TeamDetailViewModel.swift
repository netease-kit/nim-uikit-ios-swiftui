// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamDetailViewModel: ObservableObject {
  @Published public private(set) var state = TeamDetailState()

  public let teamId: String
  public let teamType: NETeamSwiftUITeamType

  private let teamRepo: TeamRepo
  private let client: NETeamUIKitSwiftUIClient
  private var listenerToken: NEChatKitListenerToken?
  private var loadGeneration = UUID()
  private var refreshGeneration = UUID()
  private var applyGeneration = UUID()

  public init(teamId: String,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared,
              client: NETeamUIKitSwiftUIClient = .shared) {
    self.teamId = teamId
    self.teamType = teamType
    self.teamRepo = teamRepo
    self.client = client
    bindTeamEvents()
  }

  deinit {
    listenerToken?.cancel()
  }

  public func load() {
    let generation = UUID()
    loadGeneration = generation
    state.phase = .loading

    teamRepo.loadSwiftUIDetail(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
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
          let message = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noTeamFind, value: "no team was fond")
          self.state.phase = .failed(message)
          self.state.toast = NETeamToastState(message: message, style: .warning)
          return
        }
        self.state.snapshot = snapshot
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

  public func primaryAction(onOpenTeamChat: ((String) -> Void)? = nil) {
    guard let snapshot = state.snapshot else {
      return
    }
    if snapshot.isJoined {
      openTeamChat(snapshot.conversationId, handler: onOpenTeamChat)
    } else {
      applyJoin(onOpenTeamChat: onOpenTeamChat)
    }
  }

  public func consumeToast() {
    state.toast = nil
  }

  private func applyJoin(onOpenTeamChat: ((String) -> Void)?) {
    guard !state.isApplying else {
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }
    state.isApplying = true
    let generation = UUID()
    applyGeneration = generation

    teamRepo.applyJoinSwiftUITeam(teamId: teamId, teamType: teamType) { [weak self] result, error in
      Task { @MainActor in
        guard let self, self.applyGeneration == generation else {
          return
        }
        self.state.isApplying = false
        if let error {
          let message = self.message(for: error)
          self.state.toast = NETeamToastState(message: message, style: .error)
          return
        }
        switch result {
        case let .joined(conversationId):
          self.openTeamChat(conversationId, handler: onOpenTeamChat)
        case .applied:
          self.state.toast = NETeamToastState(
            message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.sendTeamJoinApply, value: "Team Join Request Sent"),
            style: .success
          )
        case .none:
          self.state.toast = NETeamToastState(
            message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.failedOperation, value: "Operation failed"),
            style: .error
          )
        }
      }
    }
  }

  private func openTeamChat(_ conversationId: String,
                            handler: ((String) -> Void)?) {
    if let handler {
      handler(conversationId)
    } else {
      client.openTeamChat(conversationId: conversationId)
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
        teamJoined: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.refreshDetailSilently()
          }
        },
        teamLeft: { [weak self] team, _ in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.refreshDetailSilently()
          }
        },
        teamInfoUpdated: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.refreshDetailSilently()
          }
        },
        teamMemberJoined: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshDetailSilently()
          }
        },
        teamMemberKicked: { [weak self] _, members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshDetailSilently()
          }
        },
        teamMemberLeft: { [weak self] members in
          Task { @MainActor in
            guard let self, members.contains(where: { $0.teamId == self.teamId }) else {
              return
            }
            self.refreshDetailSilently()
          }
        }
      )
    )
  }

  private func refreshDetailSilently() {
    guard state.phase == .loaded, !state.isApplying else {
      return
    }
    let generation = UUID()
    refreshGeneration = generation

    teamRepo.loadSwiftUIDetail(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.refreshGeneration == generation else {
          return
        }
        if let error {
          if error.code == teamNotExistCode {
            self.failForMissingTeam()
          } else {
            debugPrint("[NETeamUIKitSwiftUI] teamDetail refresh failed teamId=\(self.teamId) errorCode=\(error.code)")
          }
          return
        }
        guard let snapshot else {
          self.failForMissingTeam()
          return
        }
        self.state.snapshot = snapshot
        self.state.phase = .loaded
      }
    }
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
