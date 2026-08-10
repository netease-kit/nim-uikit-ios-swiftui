// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct TeamCreateState: Equatable {
  public var phase: NETeamAsyncPhase
  public var draftName: String
  public var draftAvatarURL: String
  public var defaultAvatarURLs: [String]
  public var selectedAccountIds: [String]
  public var isSelectingMembers: Bool
  public var isSelectingAvatar: Bool
  public var isCreating: Bool
  public var didCreate: Bool
  public var createdConversationId: String?
  public var toast: NETeamToastState?
  public var memberLimit: Int
  public var allowsAIUserInvite: Bool

  public init(phase: NETeamAsyncPhase = .loaded,
              draftName: String = "",
              draftAvatarURL: String = "",
              defaultAvatarURLs: [String] = [],
              selectedAccountIds: [String] = [],
              isSelectingMembers: Bool = false,
              isSelectingAvatar: Bool = false,
              isCreating: Bool = false,
              didCreate: Bool = false,
              createdConversationId: String? = nil,
              toast: NETeamToastState? = nil,
              memberLimit: Int = Int.max,
              allowsAIUserInvite: Bool = IMKitConfigCenter.shared.enableAIUser) {
    self.phase = phase
    self.draftName = draftName
    self.draftAvatarURL = draftAvatarURL
    self.defaultAvatarURLs = defaultAvatarURLs
    self.selectedAccountIds = selectedAccountIds
    self.isSelectingMembers = isSelectingMembers
    self.isSelectingAvatar = isSelectingAvatar
    self.isCreating = isCreating
    self.didCreate = didCreate
    self.createdConversationId = createdConversationId
    self.toast = toast
    self.memberLimit = memberLimit
    self.allowsAIUserInvite = allowsAIUserInvite
  }

  public var normalizedName: String {
    draftName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var normalizedAvatarURL: String {
    draftAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var nameUTF16Count: Int {
    normalizedName.utf16.count
  }

  public var canSubmit: Bool {
    !isCreating && !normalizedName.isEmpty && !selectedAccountIds.isEmpty
  }

  public var memberSelectionRequest: TeamMemberInviteSelectionRequest {
    TeamMemberInviteSelectionRequest(
      teamId: "",
      memberLimit: memberLimit,
      remainingInviteCount: memberLimit,
      existingAccountIds: [],
      allowsAIUserInvite: allowsAIUserInvite
    )
  }
}
