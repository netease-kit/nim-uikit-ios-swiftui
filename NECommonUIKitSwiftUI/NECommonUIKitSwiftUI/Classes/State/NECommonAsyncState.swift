// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum NECommonAsyncState<Value: Equatable>: Equatable {
  case idle
  case loading
  case success(Value)
  case failure(NECommonErrorState)

  public var isLoading: Bool {
    if case .loading = self {
      return true
    }
    return false
  }
}

public enum NECommonAsyncPhase: Equatable {
  case idle
  case loading
  case refreshing
  case loaded
  case failed(NECommonErrorState)
}
