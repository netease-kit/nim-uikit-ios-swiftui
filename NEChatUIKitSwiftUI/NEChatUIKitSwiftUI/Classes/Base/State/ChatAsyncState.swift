// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum ChatAsyncState<Value> {
  case idle
  case loading
  case loaded(Value)
  case empty
  case failed(NEChatKitErrorState)

  public var isLoading: Bool {
    if case .loading = self {
      return true
    }
    return false
  }
}
