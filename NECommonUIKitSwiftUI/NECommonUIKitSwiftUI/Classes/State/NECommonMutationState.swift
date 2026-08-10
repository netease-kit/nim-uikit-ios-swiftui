// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct NECommonMutationState: Equatable {
  public var isMutating: Bool
  public var error: NECommonErrorState?
  public var rollbackIntent: String?

  public init(isMutating: Bool = false,
              error: NECommonErrorState? = nil,
              rollbackIntent: String? = nil) {
    self.isMutating = isMutating
    self.error = error
    self.rollbackIntent = rollbackIntent
  }
}

public struct NECommonSelectionState<ID: Hashable & Equatable>: Equatable {
  public var selectedIDs: Set<ID>
  public var limit: Int?

  public init(selectedIDs: Set<ID> = [],
              limit: Int? = nil) {
    self.selectedIDs = selectedIDs
    self.limit = limit
  }

  public func contains(_ id: ID) -> Bool {
    selectedIDs.contains(id)
  }

  public var canSelectMore: Bool {
    guard let limit else {
      return true
    }
    return selectedIDs.count < limit
  }
}
