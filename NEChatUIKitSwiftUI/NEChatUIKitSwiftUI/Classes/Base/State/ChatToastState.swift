// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct ChatToastState: Identifiable, Equatable {
  public enum Style: Equatable {
    case info
    case success
    case warning
    case error
  }

  public let id: UUID
  public var message: String
  public var style: Style

  public init(id: UUID = UUID(),
              message: String,
              style: Style = .info) {
    self.id = id
    self.message = message
    self.style = style
  }
}
