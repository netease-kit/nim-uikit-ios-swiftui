// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NECommonToastLevel: Equatable {
  case info
  case success
  case warning
  case error
}

public struct NECommonToastState: Equatable, Identifiable {
  public var id: String
  public var textKey: String?
  public var fallbackText: String
  public var level: NECommonToastLevel
  public var duration: TimeInterval

  public init(id: String = UUID().uuidString,
              textKey: String? = nil,
              fallbackText: String,
              level: NECommonToastLevel = .info,
              duration: TimeInterval = NECommonUIKitSwiftUIConstants.defaultToastDuration) {
    self.id = id
    self.textKey = textKey
    self.fallbackText = fallbackText
    self.level = level
    self.duration = duration
  }
}
