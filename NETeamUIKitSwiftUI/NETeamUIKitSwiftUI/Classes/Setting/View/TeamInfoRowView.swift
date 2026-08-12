// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamInfoRowView: View {
  public var row: TeamInfoRowState
  public var token: NETeamThemeToken
  public var style: NETeamSwiftUIStyleMode
  public var onSelect: (TeamInfoRowState) -> Void

  public init(row: TeamInfoRowState,
              token: NETeamThemeToken,
              style: NETeamSwiftUIStyleMode = .normal,
              onSelect: @escaping (TeamInfoRowState) -> Void) {
    self.row = row
    self.token = token
    self.style = style
    self.onSelect = onSelect
  }

  public var body: some View {
    NETeamCommonPresentation.settingRow(
      title: row.title,
      token: token,
      minHeight: rowHeight,
      leadingPadding: contentLeadingInset,
      trailingPadding: accessoryTrailingInset,
      verticalPadding: 0,
      titleLineLimit: 1,
      action: { onSelect(row) }
    ) {
      trailingAccessory
    }
    .accessibilityIdentifier(row.id)
  }

  @ViewBuilder
  private var trailingAccessory: some View {
    switch row.kind {
    case .avatar:
      HStack(spacing: style == .fun ? 16 : 22) {
        NETeamCommonPresentation.avatarView(
          imageURL: NECommonAvatarDisplayResolver.url(from: row.avatarURL),
          initials: initials(for: row.title),
          token: token,
          size: token.infoAvatarSize,
          cornerRadius: token.infoAvatarCornerRadius,
          hashID: row.hashID ?? row.value ?? row.id
        )
        NETeamCommonPresentation.chevron(token: token)
      }
    case .name, .introduce:
      NETeamCommonPresentation.chevron(token: token)
    }
  }

  private var rowHeight: CGFloat {
    row.kind == .avatar ? 74 : token.rowHeight
  }

  private var contentLeadingInset: CGFloat {
    style == .fun ? 16 : 36
  }

  private var accessoryTrailingInset: CGFloat {
    style == .fun ? 16 : 36
  }

  private func initials(for title: String) -> String {
    NECommonAvatarDisplayResolver.initials(
      displayName: title,
      fallbackID: row.hashID ?? row.value ?? row.id,
      defaultText: "#"
    )
  }
}
