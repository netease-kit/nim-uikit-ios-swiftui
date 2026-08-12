// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

struct ConversationHeaderView: View {
  let title: String
  let config: ConversationSwiftUIConfig
  let token: ConversationThemeToken
  let onSearch: () -> Void
  let onAdd: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if config.showTitleBarLeftIcon {
        Image("brand_yunxin", bundle: NECommonUIKitSwiftUIBundle.bundle)
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .frame(width: 40, height: 29)
      }

      Text(title)
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(token.primaryTextColor)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      if showsNavigationSearchButton {
        Button(action: onSearch) {
          Image("nav_search", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(NEConversationUIKitSwiftUIBundle.localized("search", value: "Search"))
      }

      if config.showTitleBarRightIcon {
        Button(action: onAdd) {
          Image("nav_add", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(NEConversationUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts"))
      }
    }
    .padding(.leading, 20)
    .padding(.trailing, 8)
    .frame(height: 44)
    .background(token.navigationBackground)
  }

  private var showsNavigationSearchButton: Bool {
    token.styleMode == .normal && config.showTitleBarSearchIcon
  }
}
