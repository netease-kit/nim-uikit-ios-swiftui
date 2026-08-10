// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct TeamMemberSelectState: Equatable {
  public var phase: NETeamAsyncPhase
  public var members: [NETeamSwiftUIMemberState]
  public var filteredMembers: [NETeamSwiftUIMemberState]
  public var selectedAccountIds: Set<String>
  public var searchText: String
  public var selectedManagerCount: Int
  public var maxManagerCount: Int
  public var canSubmit: Bool
  public var isSubmitting: Bool
  public var didSubmit: Bool
  public var toast: NETeamToastState?

  public init(phase: NETeamAsyncPhase = .idle,
              members: [NETeamSwiftUIMemberState] = [],
              filteredMembers: [NETeamSwiftUIMemberState] = [],
              selectedAccountIds: Set<String> = [],
              searchText: String = "",
              selectedManagerCount: Int = 0,
              maxManagerCount: Int = 10,
              canSubmit: Bool = false,
              isSubmitting: Bool = false,
              didSubmit: Bool = false,
              toast: NETeamToastState? = nil) {
    self.phase = phase
    self.members = members
    self.filteredMembers = filteredMembers
    self.selectedAccountIds = selectedAccountIds
    self.searchText = searchText
    self.selectedManagerCount = selectedManagerCount
    self.maxManagerCount = maxManagerCount
    self.canSubmit = canSubmit
    self.isSubmitting = isSubmitting
    self.didSubmit = didSubmit
    self.toast = toast
  }

  public var visibleMembers: [NETeamSwiftUIMemberState] {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? members : filteredMembers
  }

  public var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var selectionLimit: Int {
    maxManagerCount == -1 ? Int.max : maxManagerCount
  }

  public var remainingManagerSlots: Int {
    maxManagerCount == -1 ? Int.max : max(0, maxManagerCount - selectedManagerCount)
  }
}
