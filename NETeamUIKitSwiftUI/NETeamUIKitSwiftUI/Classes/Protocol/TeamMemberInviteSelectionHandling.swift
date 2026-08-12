// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct TeamMemberInviteSelectionRequest: Equatable {
  public var teamId: String
  public var memberLimit: Int
  public var remainingInviteCount: Int
  public var existingAccountIds: [String]
  public var allowsAIUserInvite: Bool

  public init(teamId: String,
              memberLimit: Int,
              remainingInviteCount: Int,
              existingAccountIds: [String],
              allowsAIUserInvite: Bool) {
    self.teamId = teamId
    self.memberLimit = memberLimit
    self.remainingInviteCount = remainingInviteCount
    self.existingAccountIds = existingAccountIds
    self.allowsAIUserInvite = allowsAIUserInvite
  }
}

public enum TeamMemberInviteSelectionResult: Equatable {
  case selected(accountIds: [String])
  case cancelled
}

public protocol TeamMemberInviteSelectionHandling {
  func selectTeamMembersToInvite(request: TeamMemberInviteSelectionRequest,
                                 completion: @escaping (Result<TeamMemberInviteSelectionResult, Error>) -> Void)
}

public struct TeamMemberInviteSelectionHandler: TeamMemberInviteSelectionHandling {
  private let handler: (TeamMemberInviteSelectionRequest, @escaping (Result<TeamMemberInviteSelectionResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (TeamMemberInviteSelectionRequest, @escaping (Result<TeamMemberInviteSelectionResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func selectTeamMembersToInvite(request: TeamMemberInviteSelectionRequest,
                                        completion: @escaping (Result<TeamMemberInviteSelectionResult, Error>) -> Void) {
    handler(request, completion)
  }
}
