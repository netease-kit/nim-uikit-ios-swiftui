// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct AIWordSearchResultRowView: View {
  public var result: AIWordSearchResult
  public var showsSeparator: Bool

  public init(result: AIWordSearchResult, showsSeparator: Bool) {
    self.result = result
    self.showsSeparator = showsSeparator
  }

  public var body: some View {
    VStack(spacing: 0) {
      Text(result.text)
        .font(.system(size: 14))
        .foregroundStyle(NEAISearchSwiftUIConstants.darkTextColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityIdentifier("id.content")

      if showsSeparator {
        Rectangle()
          .fill(NEAISearchSwiftUIConstants.separatorColor)
          .frame(height: 4)
      }
    }
    .background(Color.white)
  }
}
