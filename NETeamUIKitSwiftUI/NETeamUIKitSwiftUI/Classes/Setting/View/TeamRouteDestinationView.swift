// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

struct TeamRouteDestinationView: View {
  var route: NETeamSwiftUIRoute
  var token: NETeamThemeToken
  var style: NETeamSwiftUIStyleMode
  var config: NETeamSwiftUIConfig = NETeamSwiftUIConfigCenter.shared.current()
  var onOpenTeamChat: ((String) -> Void)? = nil
  var onBack: (() -> Void)? = nil
  var onCompleted: (NETeamSwiftUIRoute) -> Void = { _ in }

  var body: some View {
    destination
  }

  private var destination: AnyView {
    switch route {
    case let .setting(teamId, style, teamType):
      return AnyView(TeamSettingView(teamId: teamId, style: style, teamType: teamType, token: token, config: config))
    case let .teamInfo(teamId, teamType):
      return AnyView(TeamInfoView(teamId: teamId, style: style, teamType: teamType, token: token, onBack: onBack))
    case let .memberList(teamId, teamType):
      return AnyView(TeamMemberListView(teamId: teamId, scope: .all, style: style, teamType: teamType, token: token, config: config, onBack: onBack))
    case let .memberSelect(teamId, teamType):
      return AnyView(TeamMemberSelectView(teamId: teamId, style: style, teamType: teamType, token: token, config: config) {
        onCompleted(route)
      })
    case let .manager(teamId, teamType):
      return AnyView(TeamManageView(teamId: teamId, style: style, teamType: teamType, token: token, onBack: onBack))
    case let .managerList(teamId, teamType):
      return AnyView(TeamMemberListView(teamId: teamId, scope: .managers, style: style, teamType: teamType, token: token, config: config, onBack: onBack))
    case let .transferOwner(teamId, teamType):
      return AnyView(TeamTransferOwnerView(teamId: teamId, style: style, teamType: teamType, token: token, config: config) {
        onCompleted(route)
      })
    case let .teamDetail(teamId, teamType):
      return AnyView(TeamDetailView(
        teamId: teamId,
        style: style,
        teamType: teamType,
        token: token,
        onOpenTeamChat: onOpenTeamChat
      ))
    case let .editName(teamId, teamType):
      return AnyView(TeamTextEditView(teamId: teamId, field: .name, style: style, teamType: teamType, token: token, onBack: onBack) {
        onCompleted(route)
      })
    case let .editNick(teamId, teamType):
      return AnyView(TeamTextEditView(teamId: teamId, field: .nick, style: style, teamType: teamType, token: token, onBack: onBack) {
        onCompleted(route)
      })
    case let .editAvatar(teamId, teamType):
      return AnyView(TeamAvatarEditView(teamId: teamId, style: style, teamType: teamType, token: token) {
        onCompleted(route)
      })
    case let .editIntroduce(teamId, teamType):
      return AnyView(TeamTextEditView(teamId: teamId, field: .introduce, style: style, teamType: teamType, token: token, onBack: onBack) {
        onCompleted(route)
      })
    case let .joinTeam(teamId, teamType):
      return AnyView(TeamJoinView(teamId: teamId, style: style, teamType: teamType, token: token))
    case .createAdvancedTeam:
      return AnyView(TeamCreateView(style: style, token: token) {
        onCompleted(route)
      })
    }
  }
}
