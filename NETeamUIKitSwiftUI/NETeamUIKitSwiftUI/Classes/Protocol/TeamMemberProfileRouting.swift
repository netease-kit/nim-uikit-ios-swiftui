// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum TeamMemberProfileSource: String, Equatable {
  case settingPreview
  case memberList
  case managerList
}

public struct TeamMemberProfileRequest: Equatable {
  public var teamId: String
  public var accountId: String
  public var isCurrentUser: Bool
  public var source: TeamMemberProfileSource
  public var teamType: NETeamSwiftUITeamType

  public init(teamId: String,
              accountId: String,
              isCurrentUser: Bool,
              source: TeamMemberProfileSource,
              teamType: NETeamSwiftUITeamType) {
    self.teamId = teamId
    self.accountId = accountId
    self.isCurrentUser = isCurrentUser
    self.source = source
    self.teamType = teamType
  }
}

public enum TeamMemberProfileRouteResult: Equatable {
  case opened
  case cancelled
}

public protocol TeamMemberProfileRouting {
  func openTeamMemberProfile(_ request: TeamMemberProfileRequest,
                             completion: @escaping (Result<TeamMemberProfileRouteResult, Error>) -> Void)
}

public struct TeamMemberProfileRouter: TeamMemberProfileRouting {
  private let handler: (TeamMemberProfileRequest, @escaping (Result<TeamMemberProfileRouteResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (TeamMemberProfileRequest, @escaping (Result<TeamMemberProfileRouteResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func openTeamMemberProfile(_ request: TeamMemberProfileRequest,
                                    completion: @escaping (Result<TeamMemberProfileRouteResult, Error>) -> Void) {
    handler(request, completion)
  }
}
