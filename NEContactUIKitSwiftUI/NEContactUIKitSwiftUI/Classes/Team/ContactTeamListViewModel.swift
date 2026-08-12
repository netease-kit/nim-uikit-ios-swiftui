// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

@MainActor
public final class ContactTeamListViewModel: ObservableObject {
  @Published public private(set) var phase: ContactListPhase = .idle
  @Published public private(set) var rows: [ContactEntryState] = []
  @Published public var toast: NECommonToast?

  private let teamRepo: TeamRepo
  private var listenerToken: NEChatKitListenerToken?

  public init(teamRepo: TeamRepo = .shared) {
    self.teamRepo = teamRepo
  }

  deinit {
    listenerToken?.cancel()
  }

  public func onAppear() {
    installListenerIfNeeded()
    load()
  }

  public func load() {
    phase = .loading
    teamRepo.getTeamList { [weak self] teams, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          let message = NEContactErrorMessageMapper.message(for: error)
          self.phase = .failed(message)
          self.toast = NECommonToast(message: message)
          return
        }
        self.rows = (teams ?? [])
          .sorted { $0.createTime > $1.createTime }
          .map { team in
            let teamId = team.teamId ?? ""
            return ContactEntryState(
              id: "team.\(teamId)",
              kind: .team,
              accountId: teamId,
              title: team.name ?? teamId,
              subtitle: nil,
              avatarURL: team.avatar,
              avatarName: team.name,
              team: team
            )
          }
        self.phase = .loaded
      }
    }
  }

  public func consumeToast(_ toast: NECommonToast) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  private func installListenerIfNeeded() {
    guard listenerToken == nil else {
      return
    }
    listenerToken = teamRepo.addTeamEventListener(
      NETeamEvent(
        teamCreated: { [weak self] _ in Task { @MainActor in self?.load() } },
        teamDismissed: { [weak self] _ in Task { @MainActor in self?.load() } },
        teamJoined: { [weak self] _ in Task { @MainActor in self?.load() } },
        teamLeft: { [weak self] _, _ in Task { @MainActor in self?.load() } },
        teamInfoUpdated: { [weak self] _ in Task { @MainActor in self?.load() } }
      )
    )
  }
}
