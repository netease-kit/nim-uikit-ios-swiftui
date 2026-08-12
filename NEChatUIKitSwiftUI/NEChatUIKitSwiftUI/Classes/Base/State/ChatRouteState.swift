// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct ChatRouteState: Equatable {
  public var currentRoute: NEChatSwiftUIRoute?
  public var handlingState: NEChatKitRouteHandlingState

  public init(currentRoute: NEChatSwiftUIRoute? = nil,
              handlingState: NEChatKitRouteHandlingState = .idle) {
    self.currentRoute = currentRoute
    self.handlingState = handlingState
  }
}
