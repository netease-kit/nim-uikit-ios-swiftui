// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct AIWordSearchResult: Identifiable, Equatable {
  public var id: String
  public var requestId: String
  public var text: String
  public var isError: Bool
  public var createdAt: Date

  public init(id: String = UUID().uuidString,
              requestId: String,
              text: String,
              isError: Bool = false,
              createdAt: Date = Date()) {
    self.id = id
    self.requestId = requestId
    self.text = text
    self.isError = isError
    self.createdAt = createdAt
  }
}
