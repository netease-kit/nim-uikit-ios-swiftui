// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct TeamDetailState: Equatable {
  public var phase: NETeamAsyncPhase
  public var snapshot: NETeamSwiftUIDetailSnapshot?
  public var isApplying: Bool
  public var toast: NETeamToastState?

  public init(phase: NETeamAsyncPhase = .idle,
              snapshot: NETeamSwiftUIDetailSnapshot? = nil,
              isApplying: Bool = false,
              toast: NETeamToastState? = nil) {
    self.phase = phase
    self.snapshot = snapshot
    self.isApplying = isApplying
    self.toast = toast
  }
}
