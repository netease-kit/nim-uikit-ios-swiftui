// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct ChatP2PDiscussSelectionRequest: Equatable {
  public var peerAccountId: String
  public var peerDisplayName: String
  public var filterAccountIds: [String]
  public var limit: Int
  public var allowsAIUser: Bool

  public init(peerAccountId: String,
              peerDisplayName: String,
              filterAccountIds: [String],
              limit: Int,
              allowsAIUser: Bool) {
    self.peerAccountId = peerAccountId
    self.peerDisplayName = peerDisplayName
    self.filterAccountIds = filterAccountIds
    self.limit = limit
    self.allowsAIUser = allowsAIUser
  }
}

public struct ChatP2PDiscussSelectionResult: Equatable {
  public var selectedAccountIds: [String]
  public var selectedNames: [String]

  public init(selectedAccountIds: [String],
              selectedNames: [String] = []) {
    self.selectedAccountIds = selectedAccountIds
    self.selectedNames = selectedNames
  }
}

public protocol ChatP2PDiscussSelectionHandling {
  func selectDiscussMembers(request: ChatP2PDiscussSelectionRequest,
                            completion: @escaping (Result<ChatP2PDiscussSelectionResult, Error>) -> Void)
}
