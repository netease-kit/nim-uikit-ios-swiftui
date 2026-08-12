// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum TeamSettingRowKind: Equatable {
  case navigation(NETeamSwiftUIRoute)
  case hostAction(TeamSettingHostAction)
  case toggle(TeamSettingToggleKind)
  case destructive(TeamSettingDestructiveAction)
  case customAction(NETeamSettingCustomAction)
}

public enum TeamSettingHostAction: Equatable {
  case pinMessages(conversationId: String)
  case historySearch(conversationId: String)
}

public enum TeamSettingToggleKind: Equatable {
  case messageMute
  case conversationPinned
  case chatBanned
}

public enum TeamSettingDestructiveAction: Equatable {
  case leaveOrDismiss
}

public struct TeamSettingRowState: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var value: String?
  public var isOn: Bool
  public var isEnabled: Bool
  public var kind: TeamSettingRowKind

  public init(id: String,
              title: String,
              subtitle: String? = nil,
              value: String? = nil,
              isOn: Bool = false,
              isEnabled: Bool = true,
              kind: TeamSettingRowKind) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.value = value
    self.isOn = isOn
    self.isEnabled = isEnabled
    self.kind = kind
  }

  public init(customAction action: NETeamSettingCustomAction) {
    self.init(
      id: "customAction-\(action.id)",
      title: action.title,
      subtitle: action.subtitle,
      value: action.value,
      isEnabled: action.isEnabled,
      kind: .customAction(action)
    )
  }
}

public struct TeamSettingSectionState: Equatable, Identifiable {
  public var id: String
  public var rows: [TeamSettingRowState]

  public init(id: String, rows: [TeamSettingRowState]) {
    self.id = id
    self.rows = rows
  }
}

public struct TeamSettingState: Equatable {
  public var phase: NETeamAsyncPhase
  public var snapshot: NETeamSwiftUISettingSnapshot?
  public var sections: [TeamSettingSectionState]
  public var toast: NETeamToastState?
  public var route: NETeamSwiftUIRoute?
  public var pendingDestructiveAction: TeamSettingDestructiveAction?
  public var isSubmittingDestructiveAction: Bool
  public var isInviting: Bool
  public var isRemoteTeamDismissedAlertPresented: Bool
  public var didLeaveTeam: Bool

  public init(phase: NETeamAsyncPhase = .idle,
              snapshot: NETeamSwiftUISettingSnapshot? = nil,
              sections: [TeamSettingSectionState] = [],
              toast: NETeamToastState? = nil,
              route: NETeamSwiftUIRoute? = nil,
              pendingDestructiveAction: TeamSettingDestructiveAction? = nil,
              isSubmittingDestructiveAction: Bool = false,
              isInviting: Bool = false,
              isRemoteTeamDismissedAlertPresented: Bool = false,
              didLeaveTeam: Bool = false) {
    self.phase = phase
    self.snapshot = snapshot
    self.sections = sections
    self.toast = toast
    self.route = route
    self.pendingDestructiveAction = pendingDestructiveAction
    self.isSubmittingDestructiveAction = isSubmittingDestructiveAction
    self.isInviting = isInviting
    self.isRemoteTeamDismissedAlertPresented = isRemoteTeamDismissedAlertPresented
    self.didLeaveTeam = didLeaveTeam
  }

  public var inviteSelectionRequest: TeamMemberInviteSelectionRequest? {
    guard let snapshot else {
      return nil
    }
    return TeamMemberInviteSelectionRequest(
      teamId: snapshot.teamId,
      memberLimit: snapshot.memberLimit,
      remainingInviteCount: snapshot.remainingInviteCount,
      existingAccountIds: snapshot.existingAccountIds,
      allowsAIUserInvite: snapshot.allowsAIUserInvite
    )
  }
}
