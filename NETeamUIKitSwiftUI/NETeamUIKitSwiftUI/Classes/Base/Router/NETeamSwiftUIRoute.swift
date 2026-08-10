// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum NETeamSwiftUIRoute: Equatable, Identifiable {
  case setting(teamId: String, style: NETeamSwiftUIStyleMode, teamType: NETeamSwiftUITeamType = .normal)
  case teamInfo(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case memberList(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case memberSelect(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case manager(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case managerList(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case transferOwner(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case teamDetail(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case editName(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case editNick(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case editAvatar(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case editIntroduce(teamId: String, teamType: NETeamSwiftUITeamType = .normal)
  case joinTeam(teamId: String?, teamType: NETeamSwiftUITeamType = .normal)
  case createAdvancedTeam

  public var id: String {
    switch self {
    case let .setting(teamId, style, teamType):
      return "setting-\(teamId)-\(style)-\(teamType.id)"
    case let .teamInfo(teamId, teamType):
      return "teamInfo-\(teamId)-\(teamType.id)"
    case let .memberList(teamId, teamType):
      return "memberList-\(teamId)-\(teamType.id)"
    case let .memberSelect(teamId, teamType):
      return "memberSelect-\(teamId)-\(teamType.id)"
    case let .manager(teamId, teamType):
      return "manager-\(teamId)-\(teamType.id)"
    case let .managerList(teamId, teamType):
      return "managerList-\(teamId)-\(teamType.id)"
    case let .transferOwner(teamId, teamType):
      return "transferOwner-\(teamId)-\(teamType.id)"
    case let .teamDetail(teamId, teamType):
      return "teamDetail-\(teamId)-\(teamType.id)"
    case let .editName(teamId, teamType):
      return "editName-\(teamId)-\(teamType.id)"
    case let .editNick(teamId, teamType):
      return "editNick-\(teamId)-\(teamType.id)"
    case let .editAvatar(teamId, teamType):
      return "editAvatar-\(teamId)-\(teamType.id)"
    case let .editIntroduce(teamId, teamType):
      return "editIntroduce-\(teamId)-\(teamType.id)"
    case let .joinTeam(teamId, teamType):
      return "joinTeam-\(teamId ?? "manual")-\(teamType.id)"
    case .createAdvancedTeam:
      return "createAdvancedTeam"
    }
  }
}

private extension NETeamSwiftUITeamType {
  var id: String {
    switch self {
    case .normal:
      return "normal"
    case .superTeam:
      return "superTeam"
    }
  }
}
