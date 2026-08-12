// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import SwiftUI

public struct NormalTeamSettingView: View {
  public var teamId: String
  public var teamType: NETeamSwiftUITeamType
  public var config: NETeamSwiftUIConfig?
  public var onBack: (() -> Void)?

  public init(teamId: String,
              teamType: NETeamSwiftUITeamType = .normal,
              config: NETeamSwiftUIConfig? = nil,
              onBack: (() -> Void)? = nil) {
    self.teamId = teamId
    self.teamType = teamType
    self.config = config
    self.onBack = onBack
  }

  public var body: some View {
    TeamSettingView(teamId: teamId, style: .normal, teamType: teamType, token: NormalTeamThemeToken.default, config: config, onBack: onBack)
  }
}
