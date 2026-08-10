// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct TeamMemberListState: Equatable {
  public var teamId: String
  public var kind: NETeamSwiftUIKind
  public var phase: NETeamAsyncPhase
  public var members: [NETeamSwiftUIMemberState]
  public var filteredMembers: [NETeamSwiftUIMemberState]
  public var searchText: String
  public var currentRole: NETeamSwiftUIMemberRole
  public var maxManagerCount: Int
  public var memberLimit: Int
  public var remainingInviteCount: Int
  public var existingAccountIds: [String]
  public var canInviteMembers: Bool
  public var allowsAIUserInvite: Bool
  public var route: NETeamSwiftUIRoute?
  public var pendingRemoveManager: NETeamSwiftUIMemberState?
  public var pendingRemoveMember: NETeamSwiftUIMemberState?
  public var isUpdating: Bool
  public var isInviting: Bool
  public var toast: NETeamToastState?

  public init(teamId: String = "",
              kind: NETeamSwiftUIKind = .advanced,
              phase: NETeamAsyncPhase = .idle,
              members: [NETeamSwiftUIMemberState] = [],
              filteredMembers: [NETeamSwiftUIMemberState] = [],
              searchText: String = "",
              currentRole: NETeamSwiftUIMemberRole = .unknown,
              maxManagerCount: Int = 10,
              memberLimit: Int = 0,
              remainingInviteCount: Int = 0,
              existingAccountIds: [String] = [],
              canInviteMembers: Bool = false,
              allowsAIUserInvite: Bool = false,
              route: NETeamSwiftUIRoute? = nil,
              pendingRemoveManager: NETeamSwiftUIMemberState? = nil,
              pendingRemoveMember: NETeamSwiftUIMemberState? = nil,
              isUpdating: Bool = false,
              isInviting: Bool = false,
              toast: NETeamToastState? = nil) {
    self.teamId = teamId
    self.kind = kind
    self.phase = phase
    self.members = members
    self.filteredMembers = filteredMembers
    self.searchText = searchText
    self.currentRole = currentRole
    self.maxManagerCount = maxManagerCount
    self.memberLimit = memberLimit
    self.remainingInviteCount = remainingInviteCount
    self.existingAccountIds = existingAccountIds
    self.canInviteMembers = canInviteMembers
    self.allowsAIUserInvite = allowsAIUserInvite
    self.route = route
    self.pendingRemoveManager = pendingRemoveManager
    self.pendingRemoveMember = pendingRemoveMember
    self.isUpdating = isUpdating
    self.isInviting = isInviting
    self.toast = toast
  }

  public var visibleMembers: [NETeamSwiftUIMemberState] {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? members : filteredMembers
  }

  public var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var canManageManagers: Bool {
    !kind.isDiscuss && currentRole == .owner
  }

  public var inviteSelectionRequest: TeamMemberInviteSelectionRequest {
    TeamMemberInviteSelectionRequest(
      teamId: teamId,
      memberLimit: memberLimit,
      remainingInviteCount: remainingInviteCount,
      existingAccountIds: existingAccountIds,
      allowsAIUserInvite: allowsAIUserInvite
    )
  }

  public func canRemove(_ member: NETeamSwiftUIMemberState) -> Bool {
    guard !kind.isDiscuss, !member.isCurrentUser else {
      return false
    }
    switch currentRole {
    case .owner:
      return member.role == .manager || member.role == .member
    case .manager:
      return member.role == .member
    default:
      return false
    }
  }
}
