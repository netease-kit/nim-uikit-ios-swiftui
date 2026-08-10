// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class TeamInfoViewModel: ObservableObject {
  @Published public private(set) var state = TeamInfoState()

  public let teamId: String
  public let style: NETeamSwiftUIStyleMode
  public let teamType: NETeamSwiftUITeamType

  private let teamRepo: TeamRepo
  private var listenerToken: NEChatKitListenerToken?
  private var loadGeneration = UUID()

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              teamRepo: TeamRepo = .shared) {
    self.teamId = teamId
    self.style = style
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

  public func select(_ row: TeamInfoRowState) {
    guard let snapshot = state.snapshot else {
      return
    }

    switch row.kind {
    case .avatar:
      state.route = .editAvatar(teamId: snapshot.teamId, teamType: teamType)
    case .name:
      state.route = .editName(teamId: snapshot.teamId, teamType: teamType)
    case .introduce:
      state.route = .editIntroduce(teamId: snapshot.teamId, teamType: teamType)
    }
  }

  public func dismissRoute(reload: Bool = false) {
    state.route = nil
    if reload {
      load()
    }
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
            self.state.phase = .failed(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist"))
          }
        },
        teamLeft: { [weak self] team, _ in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.state.phase = .failed(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamNotExist, value: "Team does not exist"))
          }
        },
        teamInfoUpdated: { [weak self] team in
          Task { @MainActor in
            guard let self, team.teamId == self.teamId else {
              return
            }
            self.load()
          }
        }
      )
    )
  }

  private func apply(_ snapshot: NETeamSwiftUIInfoSnapshot) {
    state.snapshot = snapshot
    state.rows = makeRows(snapshot)
    state.phase = .loaded
  }

  private func makeRows(_ snapshot: NETeamSwiftUIInfoSnapshot) -> [TeamInfoRowState] {
    var rows = [
      TeamInfoRowState(
        id: "avatar",
        title: snapshot.kind.isDiscuss
          ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussAvatar, value: "Profile Picture")
          : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamHeader, value: "Profile Picture"),
        avatarURL: snapshot.avatarURL,
        hashID: snapshot.teamId,
        kind: .avatar
      ),
      TeamInfoRowState(
        id: "name",
        title: snapshot.kind.isDiscuss
          ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussName, value: "Group Name")
          : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamName, value: "Group Name"),
        value: snapshot.name,
        kind: .name
      ),
    ]

    if !snapshot.kind.isDiscuss {
      rows.append(
        TeamInfoRowState(
          id: "introduce",
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamIntr, value: "Description"),
          value: snapshot.intro,
          kind: .introduce
        )
      )
    }

    return rows
  }

  private func message(for error: NSError) -> String {
    NETeamErrorMessageMapper.message(for: error)
  }
}
