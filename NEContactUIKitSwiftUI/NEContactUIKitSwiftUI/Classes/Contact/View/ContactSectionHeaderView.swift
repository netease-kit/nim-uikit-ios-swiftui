// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct ContactSectionHeaderView: View {
  var title: String
  var token: ContactThemeToken

  public var body: some View {
    Text(title)
      .font(.system(size: 14))
      .foregroundColor(token.sectionTitleColor)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, token.rowHorizontalPadding)
      .frame(height: token.sectionHeaderHeight)
      .background(token.sectionBackground)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(token.rowSeparatorColor)
          .frame(height: 1)
          .padding(.leading, token.rowHorizontalPadding)
      }
  }
}
