// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NECommonUIKitSwiftUI

@MainActor
public final class TeamCreateViewModel: ObservableObject {
  @Published public private(set) var state: TeamCreateState

  private let teamRepo: TeamRepo
  private let client: NETeamUIKitSwiftUIClient
  private let defaultAvatarURL: String
  private var memberSelectionGeneration = UUID()
  private var avatarSelectionGeneration = UUID()
  private var createGeneration = UUID()

  public init(teamRepo: TeamRepo = .shared,
              client: NETeamUIKitSwiftUIClient = .shared,
              style: NETeamSwiftUIStyleMode = .normal,
              defaultName: String? = nil,
              defaultAvatarURL: String? = nil) {
    self.teamRepo = teamRepo
    self.client = client
    let defaultAvatarURLs = teamRepo.swiftUIDefaultTeamAvatarURLs(style: Self.avatarStyle(from: style))
    let resolvedDefaultAvatarURL = defaultAvatarURL ?? defaultAvatarURLs.first ?? TeamCreateViewModel.defaultAdvancedTeamAvatarURL
    self.defaultAvatarURL = resolvedDefaultAvatarURL
    state = TeamCreateState(
      draftName: defaultName ?? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.seniorTeam, value: "Group"),
      draftAvatarURL: resolvedDefaultAvatarURL,
      defaultAvatarURLs: defaultAvatarURLs
    )
  }

  public func updateName(_ text: String) {
    state.draftName = NECommonTextLimit.limitedUTF16(text, limit: 30)
  }

  public func updateAvatarURL(_ text: String) {
    state.draftAvatarURL = text
  }

  public func selectDefaultAvatar(_ url: String) {
    guard !state.isCreating else {
      return
    }
    state.draftAvatarURL = url
  }

  public func selectMembersFromHost() {
    guard !state.isCreating else {
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
    memberSelectionGeneration = generation
    state.isSelectingMembers = true
    handler.selectTeamMembersToInvite(request: state.memberSelectionRequest) { [weak self] result in
      Task { @MainActor in
        guard let self, self.memberSelectionGeneration == generation else {
          return
        }
        self.state.isSelectingMembers = false
        switch result {
        case let .success(.selected(accountIds)):
          self.state.selectedAccountIds = Self.deduplicatedAccountIds(accountIds)
        case .success(.cancelled):
          break
        case let .failure(error):
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
        }
      }
    }
  }

  public func selectAvatarFromHost() {
    guard !state.isCreating else {
      return
    }
    guard let handler = client.avatarSelectionHandler else {
      state.toast = NETeamToastState(
        message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.avatarDeferred, value: "Avatar editing requires a host selection handler"),
        style: .info
      )
      return
    }

    let generation = UUID()
    avatarSelectionGeneration = generation
    state.isSelectingAvatar = true
    let request = TeamAvatarSelectionRequest(teamId: "", currentAvatarURL: state.normalizedAvatarURL)
    handler.selectTeamAvatar(request: request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.avatarSelectionGeneration == generation else {
          return
        }
        self.state.isSelectingAvatar = false
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

  public func createTeam() {
    guard ensureNetworkForMutation() else {
      return
    }
    guard state.canSubmit else {
      if state.normalizedName.isEmpty {
        state.toast = NETeamToastState(
          message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.spaceNotSupport, value: "All spaces are not supported"),
          style: .warning
        )
      } else if state.selectedAccountIds.isEmpty {
        state.toast = NETeamToastState(
          message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.memberEmptyTip, value: "Select Member"),
          style: .warning
        )
      }
      return
    }

    let generation = UUID()
    createGeneration = generation
    state.isCreating = true
    let request = NETeamSwiftUICreateAdvancedTeamRequest(
      name: state.normalizedName,
      avatarURL: state.normalizedAvatarURL.isEmpty ? defaultAvatarURL : state.normalizedAvatarURL,
      inviteeAccountIds: state.selectedAccountIds,
      createTipText: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.createSeniorTeamNoti, value: "Group created")
    )

    teamRepo.createSwiftUIAdvancedTeam(request: request) { [weak self] result, error in
      Task { @MainActor in
        guard let self, self.createGeneration == generation else {
          return
        }
        self.state.isCreating = false
        if let error {
          self.state.toast = NETeamToastState(message: self.message(for: error), style: .error)
          return
        }
        guard let result else {
          self.state.toast = NETeamToastState(
            message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.failedOperation, value: "Operation failed"),
            style: .error
          )
          return
        }
        self.state.createdConversationId = result.conversationId
        self.state.didCreate = true
        self.state.toast = NETeamToastState(
          message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.createTeamSuccess, value: "Team created"),
          style: .success
        )
        self.client.openTeamChat(conversationId: result.conversationId)
      }
    }
  }

  public func consumeToast() {
    state.toast = nil
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

  private static func deduplicatedAccountIds(_ accountIds: [String]) -> [String] {
    var seen = Set<String>()
    return accountIds.compactMap { accountId in
      let value = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty, !seen.contains(value) else {
        return nil
      }
      seen.insert(value)
      return value
    }
  }

  private static func avatarStyle(from style: NETeamSwiftUIStyleMode) -> NETeamSwiftUIAvatarStyle {
    style == .fun ? .fun : .normal
  }

  public static let defaultAdvancedTeamAvatarURL = "https://yx-web-nosdn.netease.im/common/2425b4cc058e5788867d63c322feb7ac/groupAvatar1.png"
}
