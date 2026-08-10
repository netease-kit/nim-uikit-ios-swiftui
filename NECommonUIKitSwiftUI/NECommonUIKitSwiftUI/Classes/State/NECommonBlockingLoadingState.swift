// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct NECommonBlockingLoadingState: Equatable, Identifiable {
  public var id: String
  public var textKey: String?
  public var fallbackText: String?
  public var showsScrim: Bool
  public var blocksInteraction: Bool

  public init(id: String = "commonBlockingLoading",
              textKey: String? = "common_loading",
              fallbackText: String? = "Loading",
              showsScrim: Bool = true,
              blocksInteraction: Bool = true) {
    self.id = id
    self.textKey = textKey
    self.fallbackText = fallbackText
    self.showsScrim = showsScrim
    self.blocksInteraction = blocksInteraction
  }
}
