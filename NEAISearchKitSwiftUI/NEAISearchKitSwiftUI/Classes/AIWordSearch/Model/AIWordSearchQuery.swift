// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct AIWordSearchQuery: Equatable {
  public var text: String
  public var source: AIWordSearchSource

  public init(text: String, source: AIWordSearchSource = .messageMenu) {
    self.text = text
    self.source = source
  }
}
