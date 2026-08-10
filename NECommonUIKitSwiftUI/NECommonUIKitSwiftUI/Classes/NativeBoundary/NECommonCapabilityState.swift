// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NECommonCapabilityState: Equatable {
  case available
  case unavailable(reason: String)
}

public enum NECommonBoundaryResult: Equatable {
  case success
  case failure(NECommonErrorState)
  case unavailable(String)
}

public struct NECommonPermissionState: Equatable {
  public var capability: NECommonCapabilityState
  public var isGranted: Bool

  public init(capability: NECommonCapabilityState = .available,
              isGranted: Bool = false) {
    self.capability = capability
    self.isGranted = isGranted
  }
}
