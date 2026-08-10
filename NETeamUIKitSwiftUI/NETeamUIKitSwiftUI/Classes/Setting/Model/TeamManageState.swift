// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum TeamManageRowKind: Equatable {
  case managerList
  case transferOwner
  case permission(NETeamSwiftUIManagePermissionKind)
  case toggle(TeamManageToggleKind)
}

public enum TeamManageToggleKind: Equatable {
  case joinAgreeRequired
  case joinVerificationRequired
}

public struct TeamManageRowState: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var value: String?
  public var isOn: Bool
  public var isEnabled: Bool
  public var kind: TeamManageRowKind

  public init(id: String,
              title: String,
              subtitle: String? = nil,
              value: String? = nil,
              isOn: Bool = false,
              isEnabled: Bool = true,
              kind: TeamManageRowKind) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.value = value
    self.isOn = isOn
    self.isEnabled = isEnabled
    self.kind = kind
  }
}

public struct TeamManageSectionState: Equatable, Identifiable {
  public var id: String
  public var rows: [TeamManageRowState]

  public init(id: String, rows: [TeamManageRowState]) {
    self.id = id
    self.rows = rows
  }
}

public struct TeamManageState: Equatable {
  public var phase: NETeamAsyncPhase
  public var snapshot: NETeamSwiftUIManageSnapshot?
  public var sections: [TeamManageSectionState]
  public var pendingPermissionKind: NETeamSwiftUIManagePermissionKind?
  public var route: NETeamSwiftUIRoute?
  public var toast: NETeamToastState?

  public init(phase: NETeamAsyncPhase = .idle,
              snapshot: NETeamSwiftUIManageSnapshot? = nil,
              sections: [TeamManageSectionState] = [],
              pendingPermissionKind: NETeamSwiftUIManagePermissionKind? = nil,
              route: NETeamSwiftUIRoute? = nil,
              toast: NETeamToastState? = nil) {
    self.phase = phase
    self.snapshot = snapshot
    self.sections = sections
    self.pendingPermissionKind = pendingPermissionKind
    self.route = route
    self.toast = toast
  }
}
