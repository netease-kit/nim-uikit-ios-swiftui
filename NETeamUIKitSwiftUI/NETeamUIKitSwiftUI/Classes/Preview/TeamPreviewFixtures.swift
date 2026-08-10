// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import SwiftUI

public enum TeamPreviewFixtures {
  public static let teamId = "team-preview"
  public static let conversationId = "team-\(teamId)"

  public static let members: [NETeamSwiftUIMemberState] = [
    NETeamSwiftUIMemberState(
      teamId: teamId,
      accountId: "owner",
      displayName: "Owner",
      avatarURL: nil,
      role: .owner,
      teamNick: "Captain",
      joinTime: 1_717_200_000,
      isChatBanned: false,
      isCurrentUser: true
    ),
    NETeamSwiftUIMemberState(
      teamId: teamId,
      accountId: "manager",
      displayName: "Manager",
      avatarURL: nil,
      role: .manager,
      teamNick: nil,
      joinTime: 1_717_201_000,
      isChatBanned: false,
      isCurrentUser: false
    ),
    NETeamSwiftUIMemberState(
      teamId: teamId,
      accountId: "member-muted",
      displayName: "Muted Member",
      avatarURL: nil,
      role: .member,
      teamNick: "Muted",
      joinTime: 1_717_202_000,
      isChatBanned: true,
      isCurrentUser: false
    ),
    NETeamSwiftUIMemberState(
      teamId: teamId,
      accountId: "member",
      displayName: "Member",
      avatarURL: nil,
      role: .member,
      teamNick: nil,
      joinTime: 1_717_203_000,
      isChatBanned: false,
      isCurrentUser: false
    ),
  ]

  public static let settingSnapshot = NETeamSwiftUISettingSnapshot(
    teamId: teamId,
    name: "SwiftUI Preview Group",
    avatarURL: nil,
    intro: "A value-state fixture for Team SwiftUI.",
    announcement: "Welcome to the preview group.",
    conversationId: conversationId,
    memberCount: members.count,
    kind: .advanced,
    currentRole: .owner,
    isMessageMuted: false,
    isConversationPinned: true,
    isChatBanned: false,
    showsChatBannedSetting: true,
    showsPinMessagesEntry: true,
    currentTeamNick: "Captain",
    showsTeamNick: true,
    memberPreview: members,
    memberLimit: 200,
    remainingInviteCount: 196,
    existingAccountIds: members.map(\.accountId),
    canInviteMembers: true,
    allowsAIUserInvite: true
  )

  public static let settingCustomAction = NETeamSettingCustomAction(
    id: "previewAudit",
    title: "Preview Audit",
    subtitle: "SwiftUI config custom action",
    value: "Enabled",
    systemImageName: "checkmark.seal",
    placement: .settings,
    role: .normal,
    isEnabled: true
  )

  public static let settingCustomInputAction = NETeamSettingCustomAction(
    id: "previewJsonConfig",
    title: "Preview JSON Config",
    subtitle: "SwiftUI text editor custom row",
    placement: .settings,
    role: .normal,
    isEnabled: true
  )

  public static let swiftUIConfig = NETeamSwiftUIConfig(
    titleProvider: { context in
      "\(context.snapshot.name) Settings"
    },
    headerSubtitleProvider: { _ in
      "SwiftUI Config Preview"
    },
    shouldShowSettingRow: { row, _ in
      row.id != "hidden-preview-row"
    },
    settingCustomActionsProvider: { _ in
      [settingCustomAction, settingCustomInputAction]
    },
    settingCustomActionHandler: { action, _ in
      action.id == settingCustomAction.id || action.id == settingCustomInputAction.id
    },
    settingRowContentProvider: NETeamSwiftUIConfig.eraseSettingRowContent { context -> AnyView? in
      guard context.row.id == "customAction-\(settingCustomInputAction.id)" else {
        return nil
      }
      return AnyView(
        NETeamCommonPresentation.formTextEditor(
          title: context.row.title,
          text: .constant("{\"teamId\":\"\(context.snapshot.teamId)\"}"),
          placeholder: "Input custom JSON",
          token: context.style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default,
          minHeight: 88
        )
      )
    },
    shouldShowMemberAvatar: { _ in true },
    shouldShowMemberAccountId: { context in
      context.displayScope != .transferOwner
    },
    shouldShowMemberRoleBadge: { context in
      context.member.role == .owner || context.member.role == .manager
    },
    memberRowContentProvider: NETeamSwiftUIConfig.eraseMemberRowContent { context in
      if context.displayScope == .selection {
        Text(context.member.displayName)
      } else {
        nil
      }
    }
  )

  public static let settingState = TeamSettingState(
    phase: .loaded,
    snapshot: settingSnapshot,
    sections: [
      TeamSettingSectionState(id: "profile", rows: [
        TeamSettingRowState(
          id: "teamInfo",
          title: "Group Info",
          value: settingSnapshot.name,
          kind: .navigation(.teamInfo(teamId: teamId))
        ),
        TeamSettingRowState(
          id: "members",
          title: "Members",
          value: "\(members.count)",
          kind: .navigation(.memberList(teamId: teamId))
        ),
        TeamSettingRowState(
          id: "managers",
          title: "Group Manager",
          value: "1",
          kind: .navigation(.managerList(teamId: teamId))
        ),
      ]),
      TeamSettingSectionState(id: "conversation", rows: [
        TeamSettingRowState(
          id: "mute",
          title: "Message Notifications",
          isOn: settingSnapshot.isMessageMuted,
          kind: .toggle(.messageMute)
        ),
        TeamSettingRowState(
          id: "pin",
          title: "Pin Conversation",
          isOn: settingSnapshot.isConversationPinned,
          kind: .toggle(.conversationPinned)
        ),
        TeamSettingRowState(
          id: "pinMessages",
          title: "Pinned Messages",
          kind: .hostAction(.pinMessages(conversationId: conversationId))
        ),
        TeamSettingRowState(
          id: "history",
          title: "History",
          kind: .hostAction(.historySearch(conversationId: conversationId))
        ),
        TeamSettingRowState(customAction: settingCustomAction),
        TeamSettingRowState(customAction: settingCustomInputAction),
      ]),
      TeamSettingSectionState(id: "danger", rows: [
        TeamSettingRowState(
          id: "leave",
          title: "Leave Group",
          isEnabled: true,
          kind: .destructive(.leaveOrDismiss)
        ),
      ]),
    ],
    toast: NETeamToastState(message: "Setting fixture toast", style: .success),
    route: .teamInfo(teamId: teamId),
    pendingDestructiveAction: .leaveOrDismiss,
    isSubmittingDestructiveAction: true,
    isInviting: true
  )

  public static let infoSnapshot = NETeamSwiftUIInfoSnapshot(
    teamId: teamId,
    name: settingSnapshot.name,
    avatarURL: nil,
    intro: settingSnapshot.intro,
    kind: .advanced,
    currentRole: .owner,
    canEditTeamInfo: true,
    currentAccountId: "owner",
    currentTeamNick: "Captain"
  )

  public static let infoState = TeamInfoState(
    phase: .loaded,
    snapshot: infoSnapshot,
    rows: [
      TeamInfoRowState(id: "avatar", title: "Profile Picture", avatarURL: nil, kind: .avatar),
      TeamInfoRowState(id: "name", title: "Group Name", value: infoSnapshot.name, kind: .name),
      TeamInfoRowState(id: "intro", title: "Description", value: infoSnapshot.intro, kind: .introduce),
    ],
    route: .editName(teamId: teamId),
    toast: NETeamToastState(message: "Info fixture warning", style: .warning)
  )

  public static let manageSnapshot = NETeamSwiftUIManageSnapshot(
    teamId: teamId,
    managerCount: 1,
    currentRole: .owner,
    canManageSettings: true,
    canManageManagers: true,
    editTeamInfoPermission: .ownerAndManager,
    inviteMemberPermission: .ownerAndManager,
    atAllPermission: .ownerAndManager,
    topMessagePermission: .ownerAndManager,
    isJoinAgreeRequired: true,
    isJoinVerificationRequired: false,
    showsTopMessagePermission: true,
    showsJoinApprovalSettings: true
  )

  public static let manageState = TeamManageState(
    phase: .loaded,
    snapshot: manageSnapshot,
    sections: [
      TeamManageSectionState(id: "members", rows: [
        TeamManageRowState(
          id: "managerList",
          title: "Group Manager",
          value: "1",
          kind: .managerList
        ),
        TeamManageRowState(
          id: "transferOwner",
          title: "Transfer group owner",
          kind: .transferOwner
        ),
      ]),
      TeamManageSectionState(id: "permissions", rows: [
        TeamManageRowState(
          id: "editTeamInfo",
          title: "Edit group info",
          value: "Owner and manager",
          kind: .permission(.editTeamInfo)
        ),
        TeamManageRowState(
          id: "topMessage",
          title: "Top message",
          value: "Owner and manager",
          kind: .permission(.topMessage)
        ),
      ]),
      TeamManageSectionState(id: "join", rows: [
        TeamManageRowState(
          id: "joinAgree",
          title: "Join approval",
          isOn: true,
          kind: .toggle(.joinAgreeRequired)
        ),
        TeamManageRowState(
          id: "joinVerify",
          title: "Join verification",
          isOn: false,
          kind: .toggle(.joinVerificationRequired)
        ),
      ]),
    ],
    pendingPermissionKind: .topMessage,
    route: .managerList(teamId: teamId),
    toast: NETeamToastState(message: "Manage fixture toast", style: .info)
  )

  public static let memberListState = TeamMemberListState(
    teamId: teamId,
    phase: .loaded,
    members: members,
    filteredMembers: Array(members.suffix(2)),
    searchText: "member",
    currentRole: .owner,
    maxManagerCount: 10,
    memberLimit: 200,
    remainingInviteCount: 196,
    existingAccountIds: members.map(\.accountId),
    canInviteMembers: true,
    allowsAIUserInvite: true,
    route: .memberSelect(teamId: teamId),
    pendingRemoveManager: members.first { $0.role == .manager },
    pendingRemoveMember: members.first { $0.accountId == "member-muted" },
    isUpdating: true,
    isInviting: true,
    toast: NETeamToastState(message: "Member fixture toast", style: .warning)
  )

  public static let memberSelectState = TeamMemberSelectState(
    phase: .loaded,
    members: members,
    filteredMembers: Array(members.suffix(2)),
    selectedAccountIds: Set(["member"]),
    searchText: "member",
    selectedManagerCount: 1,
    maxManagerCount: 10,
    canSubmit: true,
    isSubmitting: true,
    didSubmit: false,
    toast: NETeamToastState(message: "Select fixture toast", style: .info)
  )

  public static let transferOwnerState = TeamTransferOwnerState(
    phase: .loaded,
    members: members.filter { !$0.isCurrentUser },
    filteredMembers: members.filter { $0.role == .member },
    selectedAccountId: "member",
    searchText: "member",
    canSubmit: true,
    isSubmitting: true,
    didSubmit: false,
    toast: NETeamToastState(message: "Transfer fixture toast", style: .warning)
  )

  public static let detailSnapshot = NETeamSwiftUIDetailSnapshot(
    teamId: teamId,
    conversationId: conversationId,
    name: settingSnapshot.name,
    avatarURL: nil,
    intro: settingSnapshot.intro,
    memberCount: members.count,
    ownerAccountId: "owner",
    ownerDisplayName: "Captain",
    kind: .advanced,
    isJoined: true
  )

  public static let detailState = TeamDetailState(
    phase: .loaded,
    snapshot: detailSnapshot,
    isApplying: true,
    toast: NETeamToastState(message: "Detail fixture toast", style: .success)
  )

  public static let joinState = TeamJoinState(
    teamIdText: teamId,
    phase: .loaded,
    route: .teamDetail(teamId: teamId),
    toast: NETeamToastState(message: "Join fixture toast", style: .info)
  )

  public static let textEditState = TeamTextEditState(
    phase: .loaded,
    text: "SwiftUI Preview Group",
    canEdit: true,
    isSaving: true,
    toast: NETeamToastState(message: "Text edit fixture toast", style: .warning),
    didSave: false
  )

  public static let avatarEditState = TeamAvatarEditState(
    phase: .loaded,
    currentAvatarURL: nil,
    draftAvatarURL: "https://example.com/avatar.png",
    defaultAvatarURLs: TeamRepo.shared.swiftUIDefaultTeamAvatarURLs(style: .normal),
    canEdit: true,
    isSaving: true,
    didSave: false,
    toast: NETeamToastState(message: "Avatar fixture toast", style: .success)
  )

  public static let createState = TeamCreateState(
    phase: .loaded,
    draftName: "SwiftUI Advanced Group",
    draftAvatarURL: "https://example.com/team.png",
    defaultAvatarURLs: TeamRepo.shared.swiftUIDefaultTeamAvatarURLs(style: .normal),
    selectedAccountIds: ["manager", "member"],
    isSelectingMembers: true,
    isSelectingAvatar: true,
    isCreating: true,
    didCreate: false,
    createdConversationId: nil,
    toast: NETeamToastState(message: "Create fixture toast", style: .info),
    memberLimit: 200,
    allowsAIUserInvite: true
  )

  public static let routes: [NETeamSwiftUIRoute] = [
    .setting(teamId: teamId, style: .normal),
    .setting(teamId: teamId, style: .normal, teamType: .superTeam),
    .setting(teamId: teamId, style: .fun),
    .teamInfo(teamId: teamId),
    .teamInfo(teamId: teamId, teamType: .superTeam),
    .memberList(teamId: teamId),
    .memberList(teamId: teamId, teamType: .superTeam),
    .memberSelect(teamId: teamId),
    .manager(teamId: teamId),
    .manager(teamId: teamId, teamType: .superTeam),
    .managerList(teamId: teamId),
    .transferOwner(teamId: teamId),
    .teamDetail(teamId: teamId),
    .teamDetail(teamId: teamId, teamType: .superTeam),
    .editName(teamId: teamId),
    .editNick(teamId: teamId),
    .editAvatar(teamId: teamId),
    .editAvatar(teamId: teamId, teamType: .superTeam),
    .editIntroduce(teamId: teamId),
    .joinTeam(teamId: teamId),
    .joinTeam(teamId: teamId, teamType: .superTeam),
    .joinTeam(teamId: nil),
    .createAdvancedTeam,
  ]
}
