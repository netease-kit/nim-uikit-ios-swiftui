// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct TeamJoinState: Equatable {
  public var teamIdText: String
  public var phase: NETeamAsyncPhase
  public var route: NETeamSwiftUIRoute?
  public var toast: NETeamToastState?

  public init(teamIdText: String = "",
              phase: NETeamAsyncPhase = .idle,
              route: NETeamSwiftUIRoute? = nil,
              toast: NETeamToastState? = nil) {
    self.teamIdText = teamIdText
    self.phase = phase
    self.route = route
    self.toast = toast
  }

  public var canSearch: Bool {
    !teamIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .loading
  }
}
