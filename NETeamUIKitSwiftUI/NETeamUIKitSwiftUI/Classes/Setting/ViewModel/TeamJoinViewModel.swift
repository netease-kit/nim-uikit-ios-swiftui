// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamJoinViewModel: ObservableObject {
  @Published public private(set) var state: TeamJoinState

  private let teamRepo: TeamRepo
  private let teamType: NETeamSwiftUITeamType
  private var searchGeneration = UUID()

  public init(initialTeamId: String? = nil,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared) {
    state = TeamJoinState(teamIdText: initialTeamId ?? "")
    self.teamType = teamType
    self.teamRepo = teamRepo
  }

  public func updateTeamIdText(_ text: String) {
    state.teamIdText = text
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       case .failed = state.phase {
      state.phase = .idle
    }
  }

  public func search() {
    let teamId = state.teamIdText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !teamId.isEmpty, state.phase != .loading else {
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }

    let generation = UUID()
    searchGeneration = generation
    state.phase = .loading
    teamRepo.loadSwiftUIDetail(teamId: teamId, teamType: teamType) { [weak self] snapshot, error in
      Task { @MainActor in
        guard let self, self.searchGeneration == generation else {
          return
        }
        if let error {
          self.state.phase = .failed(self.message(for: error))
          return
        }
        guard let snapshot else {
          self.state.phase = .failed(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noTeamFind, value: "no team was fond"))
          return
        }
        self.state.phase = .idle
        self.state.route = .teamDetail(teamId: snapshot.teamId, teamType: self.teamType)
      }
    }
  }

  public func dismissRoute() {
    state.route = nil
  }

  public func consumeToast() {
    state.toast = nil
  }

  private func message(for error: NSError) -> String {
    NETeamErrorMessageMapper.message(
      for: error,
      fallbackMessage: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noTeamFind, value: "no team was fond"),
      teamNotExistMessage: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noTeamFind, value: "no team was fond")
    )
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NETeamNetworkGuard.allowsNetworkOperation else {
      state.toast = NETeamToastState(message: NETeamErrorMessageMapper.networkMessage(), style: .warning)
      return false
    }
    return true
  }
}
