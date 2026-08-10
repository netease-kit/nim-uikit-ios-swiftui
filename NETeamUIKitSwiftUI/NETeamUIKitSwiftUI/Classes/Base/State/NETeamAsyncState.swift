// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NETeamAsyncPhase: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}

public struct NETeamToastState: Equatable, Identifiable {
  public enum Style: Equatable {
    case info
    case warning
    case error
    case success
  }

  public var id: String
  public var message: String
  public var style: Style

  public init(id: String = UUID().uuidString,
              message: String,
              style: Style = .info) {
    self.id = id
    self.message = message
    self.style = style
  }
}
