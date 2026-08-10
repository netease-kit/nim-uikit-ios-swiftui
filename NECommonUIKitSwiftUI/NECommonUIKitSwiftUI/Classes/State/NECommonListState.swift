// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct NECommonPageState: Equatable {
  public var hasMore: Bool
  public var isLoadingMore: Bool
  public var cursor: String?

  public init(hasMore: Bool = false,
              isLoadingMore: Bool = false,
              cursor: String? = nil) {
    self.hasMore = hasMore
    self.isLoadingMore = isLoadingMore
    self.cursor = cursor
  }
}

public struct NECommonListState<Item: Identifiable & Equatable>: Equatable {
  public var items: [Item]
  public var phase: NECommonAsyncPhase
  public var page: NECommonPageState
  public var empty: NECommonEmptyState?
  public var error: NECommonErrorState?

  public init(items: [Item] = [],
              phase: NECommonAsyncPhase = .idle,
              page: NECommonPageState = NECommonPageState(),
              empty: NECommonEmptyState? = nil,
              error: NECommonErrorState? = nil) {
    self.items = items
    self.phase = phase
    self.page = page
    self.empty = empty
    self.error = error
  }

  public var shouldShowEmpty: Bool {
    items.isEmpty && empty != nil && !isLoading
  }

  public var isLoading: Bool {
    switch phase {
    case .loading, .refreshing:
      return true
    default:
      return false
    }
  }
}
