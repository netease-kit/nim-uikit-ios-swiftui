// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public protocol TeamUserVisibleError: Error {
  var userVisibleMessage: String { get }
}

public struct TeamAvatarSelectionRequest: Equatable {
  public var teamId: String
  public var currentAvatarURL: String?

  public init(teamId: String, currentAvatarURL: String?) {
    self.teamId = teamId
    self.currentAvatarURL = currentAvatarURL
  }
}

public enum TeamAvatarSelectionResult: Equatable {
  case selected(url: String)
  case cancelled
}

public protocol TeamAvatarSelectionHandling {
  func selectTeamAvatar(request: TeamAvatarSelectionRequest,
                        completion: @escaping (Result<TeamAvatarSelectionResult, Error>) -> Void)
}

public struct TeamAvatarSelectionHandler: TeamAvatarSelectionHandling {
  private let handler: (TeamAvatarSelectionRequest, @escaping (Result<TeamAvatarSelectionResult, Error>) -> Void) -> Void

  public init(_ handler: @escaping (TeamAvatarSelectionRequest, @escaping (Result<TeamAvatarSelectionResult, Error>) -> Void) -> Void) {
    self.handler = handler
  }

  public func selectTeamAvatar(request: TeamAvatarSelectionRequest,
                               completion: @escaping (Result<TeamAvatarSelectionResult, Error>) -> Void) {
    handler(request, completion)
  }
}
