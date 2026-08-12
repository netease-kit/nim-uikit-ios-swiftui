// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import SwiftUI

public enum NETeamSettingCustomActionPlacement: Equatable {
  case info
  case settings
  case actions
}

public enum NETeamSettingCustomActionRole: Equatable {
  case normal
  case destructive
}

public enum NETeamMemberDisplayScope: Equatable {
  case all
  case managers
  case selection
  case transferOwner

  public init(listScope: NETeamSwiftUIMemberListScope) {
    switch listScope {
    case .all:
      self = .all
    case .managers:
      self = .managers
    }
  }
}

public struct NETeamSettingCustomAction: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var value: String?
  public var systemImageName: String?
  public var imageName: String?
  public var imageBundle: Bundle?
  public var placement: NETeamSettingCustomActionPlacement
  public var role: NETeamSettingCustomActionRole
  public var isEnabled: Bool

  public init(id: String,
              title: String,
              subtitle: String? = nil,
              value: String? = nil,
              systemImageName: String? = nil,
              imageName: String? = nil,
              imageBundle: Bundle? = nil,
              placement: NETeamSettingCustomActionPlacement = .settings,
              role: NETeamSettingCustomActionRole = .normal,
              isEnabled: Bool = true) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.value = value
    self.systemImageName = systemImageName
    self.imageName = imageName
    self.imageBundle = imageBundle
    self.placement = placement
    self.role = role
    self.isEnabled = isEnabled
  }

  public static func == (lhs: NETeamSettingCustomAction,
                         rhs: NETeamSettingCustomAction) -> Bool {
    lhs.id == rhs.id &&
      lhs.title == rhs.title &&
      lhs.subtitle == rhs.subtitle &&
      lhs.value == rhs.value &&
      lhs.systemImageName == rhs.systemImageName &&
      lhs.imageName == rhs.imageName &&
      lhs.imageBundle?.bundleURL == rhs.imageBundle?.bundleURL &&
      lhs.placement == rhs.placement &&
      lhs.role == rhs.role &&
      lhs.isEnabled == rhs.isEnabled
  }
}

public struct NETeamSettingContext: Equatable {
  public var snapshot: NETeamSwiftUISettingSnapshot
  public var style: NETeamSwiftUIStyleMode
  public var teamType: NETeamSwiftUITeamType

  public init(snapshot: NETeamSwiftUISettingSnapshot,
              style: NETeamSwiftUIStyleMode,
              teamType: NETeamSwiftUITeamType) {
    self.snapshot = snapshot
    self.style = style
    self.teamType = teamType
  }
}

public struct NETeamSettingRowContext: Equatable {
  public var row: TeamSettingRowState
  public var snapshot: NETeamSwiftUISettingSnapshot
  public var style: NETeamSwiftUIStyleMode
  public var teamType: NETeamSwiftUITeamType

  public init(row: TeamSettingRowState,
              snapshot: NETeamSwiftUISettingSnapshot,
              style: NETeamSwiftUIStyleMode,
              teamType: NETeamSwiftUITeamType) {
    self.row = row
    self.snapshot = snapshot
    self.style = style
    self.teamType = teamType
  }

  public init(row: TeamSettingRowState, settingContext: NETeamSettingContext) {
    self.init(
      row: row,
      snapshot: settingContext.snapshot,
      style: settingContext.style,
      teamType: settingContext.teamType
    )
  }
}

public struct NETeamMemberContext: Equatable {
  public var member: NETeamSwiftUIMemberState
  public var style: NETeamSwiftUIStyleMode
  public var teamType: NETeamSwiftUITeamType
  public var displayScope: NETeamMemberDisplayScope

  public init(member: NETeamSwiftUIMemberState,
              style: NETeamSwiftUIStyleMode,
              teamType: NETeamSwiftUITeamType,
              displayScope: NETeamMemberDisplayScope) {
    self.member = member
    self.style = style
    self.teamType = teamType
    self.displayScope = displayScope
  }

  public init(member: NETeamSwiftUIMemberState,
              style: NETeamSwiftUIStyleMode,
              teamType: NETeamSwiftUITeamType,
              listScope: NETeamSwiftUIMemberListScope) {
    self.init(
      member: member,
      style: style,
      teamType: teamType,
      displayScope: NETeamMemberDisplayScope(listScope: listScope)
    )
  }
}

public struct NETeamSwiftUIConfig {
  public var styleMode: NETeamSwiftUIStyleMode
  public var titleProvider: ((NETeamSettingContext) -> String?)?
  public var headerSubtitleProvider: ((NETeamSettingContext) -> String?)?
  public var shouldShowSettingRow: (TeamSettingRowState, NETeamSettingContext) -> Bool
  public var settingCustomActionsProvider: ((NETeamSettingContext) -> [NETeamSettingCustomAction])?
  public var settingCustomActionHandler: ((NETeamSettingCustomAction, NETeamSettingContext) -> Bool)?
  public var settingRowContentProvider: ((NETeamSettingRowContext) -> AnyView?)?
  public var pinMessagesViewProvider: ((String, NETeamSettingContext) -> AnyView?)?
  public var historySearchViewProvider: ((String, NETeamSettingContext) -> AnyView?)?
  public var pinMessagesPushViewProvider: ((String, NETeamSettingContext, @escaping () -> Void) -> AnyView?)?
  public var historySearchPushViewProvider: ((String, NETeamSettingContext, @escaping () -> Void) -> AnyView?)?
  public var memberProfilePushViewProvider: ((TeamMemberProfileRequest, NETeamSwiftUIStyleMode) -> AnyView?)?
  public var shouldShowMemberAvatar: (NETeamMemberContext) -> Bool
  public var shouldShowMemberAccountId: (NETeamMemberContext) -> Bool
  public var shouldShowMemberRoleBadge: (NETeamMemberContext) -> Bool
  public var memberRowContentProvider: ((NETeamMemberContext) -> AnyView?)?

  public init(styleMode: NETeamSwiftUIStyleMode = .normal,
              titleProvider: ((NETeamSettingContext) -> String?)? = nil,
              headerSubtitleProvider: ((NETeamSettingContext) -> String?)? = nil,
              shouldShowSettingRow: @escaping (TeamSettingRowState, NETeamSettingContext) -> Bool = { _, _ in true },
              settingCustomActionsProvider: ((NETeamSettingContext) -> [NETeamSettingCustomAction])? = nil,
              settingCustomActionHandler: ((NETeamSettingCustomAction, NETeamSettingContext) -> Bool)? = nil,
              settingRowContentProvider: ((NETeamSettingRowContext) -> AnyView?)? = nil,
              pinMessagesViewProvider: ((String, NETeamSettingContext) -> AnyView?)? = nil,
              historySearchViewProvider: ((String, NETeamSettingContext) -> AnyView?)? = nil,
              pinMessagesPushViewProvider: ((String, NETeamSettingContext, @escaping () -> Void) -> AnyView?)? = nil,
              historySearchPushViewProvider: ((String, NETeamSettingContext, @escaping () -> Void) -> AnyView?)? = nil,
              memberProfilePushViewProvider: ((TeamMemberProfileRequest, NETeamSwiftUIStyleMode) -> AnyView?)? = nil,
              shouldShowMemberAvatar: @escaping (NETeamMemberContext) -> Bool = { _ in true },
              shouldShowMemberAccountId: @escaping (NETeamMemberContext) -> Bool = { _ in false },
              shouldShowMemberRoleBadge: @escaping (NETeamMemberContext) -> Bool = { context in
                context.member.role == .owner || context.member.role == .manager
              },
              memberRowContentProvider: ((NETeamMemberContext) -> AnyView?)? = nil) {
    self.styleMode = styleMode
    self.titleProvider = titleProvider
    self.headerSubtitleProvider = headerSubtitleProvider
    self.shouldShowSettingRow = shouldShowSettingRow
    self.settingCustomActionsProvider = settingCustomActionsProvider
    self.settingCustomActionHandler = settingCustomActionHandler
    self.settingRowContentProvider = settingRowContentProvider
    self.pinMessagesViewProvider = pinMessagesViewProvider
    self.historySearchViewProvider = historySearchViewProvider
    self.pinMessagesPushViewProvider = pinMessagesPushViewProvider
    self.historySearchPushViewProvider = historySearchPushViewProvider
    self.memberProfilePushViewProvider = memberProfilePushViewProvider
    self.shouldShowMemberAvatar = shouldShowMemberAvatar
    self.shouldShowMemberAccountId = shouldShowMemberAccountId
    self.shouldShowMemberRoleBadge = shouldShowMemberRoleBadge
    self.memberRowContentProvider = memberRowContentProvider
  }

  public var themeToken: NETeamThemeToken {
    switch styleMode {
    case .normal:
      return NormalTeamThemeToken.default
    case .fun:
      return FunTeamThemeToken.default
    }
  }
}

public extension NETeamSwiftUIConfig {
  static func eraseSettingRowContent<V: View>(_ builder: @escaping (NETeamSettingRowContext) -> V?) -> (NETeamSettingRowContext) -> AnyView? {
    { context in
      builder(context).map { AnyView($0) }
    }
  }

  static func eraseMemberRowContent<V: View>(_ builder: @escaping (NETeamMemberContext) -> V?) -> (NETeamMemberContext) -> AnyView? {
    { context in
      builder(context).map { AnyView($0) }
    }
  }
}
