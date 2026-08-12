// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ContactHeaderView: View {
  var title: String
  var config: ContactSwiftUIConfig
  var token: ContactThemeToken
  var onSearch: () -> Void
  var onAdd: () -> Void

  public var body: some View {
    Group {
      if token.styleMode == .fun {
        funHeader
      } else {
        normalHeader
      }
    }
    .frame(height: 44)
    .background(token.navigationBackground)
  }

  private var normalHeader: some View {
    HStack(spacing: 0) {
      Text(title)
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(token.primaryTextColor)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      if config.showSearchEntry {
        Button(action: onSearch) {
          Image("nav_search", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("id.titleBarSearchImg")
        .accessibilityLabel(NEContactUIKitSwiftUIBundle.localized("search", value: "Search"))
      }

      if config.showAddEntry {
        Button(action: onAdd) {
          Image("nav_add", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("id.titleBarMoreImg")
        .accessibilityLabel(NEContactUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts"))
      }
    }
    .padding(.leading, 20)
    .padding(.trailing, 10)
  }

  private var funHeader: some View {
    ZStack {
      Text(title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(token.primaryTextColor)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 72)

      HStack {
        if config.showSearchEntry, token.styleMode != .fun {
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
          .accessibilityIdentifier("id.titleBarSearchImg")
          .accessibilityLabel(NEContactUIKitSwiftUIBundle.localized("search", value: "Search"))
        }

        Spacer(minLength: 0)

        if config.showAddEntry {
          Button(action: onAdd) {
            ContactImageResource(name: ContactImageResource.addName(style: token.styleMode), size: 25, fallbackSystemImage: "plus")
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .contentShape(Rectangle())
          .accessibilityIdentifier("id.titleBarMoreImg")
          .accessibilityLabel(NEContactUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts"))
        }
      }
      .padding(.trailing, 8)
    }
  }
}
