// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum TeamInfoRowKind: Equatable {
  case avatar
  case name
  case introduce
}

public struct TeamInfoRowState: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var value: String?
  public var avatarURL: String?
  public var hashID: String?
  public var kind: TeamInfoRowKind

  public init(id: String,
              title: String,
              value: String? = nil,
              avatarURL: String? = nil,
              hashID: String? = nil,
              kind: TeamInfoRowKind) {
    self.id = id
    self.title = title
    self.value = value
    self.avatarURL = avatarURL
    self.hashID = hashID
    self.kind = kind
  }
}

public struct TeamInfoState: Equatable {
  public var phase: NETeamAsyncPhase
  public var snapshot: NETeamSwiftUIInfoSnapshot?
  public var rows: [TeamInfoRowState]
  public var route: NETeamSwiftUIRoute?
  public var toast: NETeamToastState?

  public init(phase: NETeamAsyncPhase = .idle,
              snapshot: NETeamSwiftUIInfoSnapshot? = nil,
              rows: [TeamInfoRowState] = [],
              route: NETeamSwiftUIRoute? = nil,
              toast: NETeamToastState? = nil) {
    self.phase = phase
    self.snapshot = snapshot
    self.rows = rows
    self.route = route
    self.toast = toast
  }
}
