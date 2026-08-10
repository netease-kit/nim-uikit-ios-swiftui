// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public struct AIWordSearchState: Equatable {
  public var isLoading: Bool
  public var isSupplementExpanded: Bool
  public var supplementText: String
  public var results: [AIWordSearchResult]
  public var toastMessage: String?
  public var isDismissed: Bool

  public init(isLoading: Bool = false,
              isSupplementExpanded: Bool = false,
              supplementText: String = "",
              results: [AIWordSearchResult] = [],
              toastMessage: String? = nil,
              isDismissed: Bool = false) {
    self.isLoading = isLoading
    self.isSupplementExpanded = isSupplementExpanded
    self.supplementText = supplementText
    self.results = results
    self.toastMessage = toastMessage
    self.isDismissed = isDismissed
  }

  public var title: String {
    if isLoading {
      return NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.aiWordSearching, value: "AI Word Searching")
    }
    return NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.aiWordSearch, value: "AI Word Search")
  }

  public var canSubmitSupplement: Bool {
    !supplementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
