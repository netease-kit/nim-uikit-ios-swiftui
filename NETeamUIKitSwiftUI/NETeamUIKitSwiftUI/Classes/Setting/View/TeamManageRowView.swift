// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct TeamManageRowView: View {
  public var row: TeamManageRowState
  public var token: NETeamThemeToken
  public var style: NETeamSwiftUIStyleMode
  public var onSelect: (TeamManageRowState) -> Void
  public var onToggle: (TeamManageToggleKind, Bool) -> Void

  public init(row: TeamManageRowState,
              token: NETeamThemeToken,
              style: NETeamSwiftUIStyleMode = .normal,
              onSelect: @escaping (TeamManageRowState) -> Void,
              onToggle: @escaping (TeamManageToggleKind, Bool) -> Void) {
    self.row = row
    self.token = token
    self.style = style
    self.onSelect = onSelect
    self.onToggle = onToggle
  }

  public var body: some View {
    switch row.kind {
    case let .toggle(kind):
      NETeamCommonPresentation.settingToggleRow(
        title: row.title,
        subtitle: row.subtitle,
        isOn: Binding(
          get: { row.isOn },
          set: { onToggle(kind, $0) }
        ),
        token: token,
        isEnabled: row.isEnabled,
        minHeight: 73,
        leadingPadding: titleLeadingInset,
        trailingPadding: switchTrailingInset,
        verticalPadding: 0,
        titleLineLimit: 1,
        subtitleLineLimit: 2
      )
      .accessibilityIdentifier(row.id)
    case .managerList, .transferOwner:
      NETeamCommonPresentation.settingRow(
        title: row.title,
        value: row.value,
        subtitle: row.subtitle,
        token: token,
        isEnabled: row.isEnabled,
        minHeight: token.rowHeight,
        leadingPadding: titleLeadingInset,
        trailingPadding: accessoryTrailingInset,
        verticalPadding: 0,
        titleLineLimit: 1,
        subtitleLineLimit: 1,
        action: { onSelect(row) }
      ) {
        NETeamCommonPresentation.chevron(token: token, isEnabled: row.isEnabled)
      }
      .accessibilityIdentifier(row.id)
    case .permission:
      NETeamCommonPresentation.settingRow(
        title: row.title,
        value: nil,
        subtitle: row.value ?? row.subtitle,
        token: token,
        isEnabled: row.isEnabled,
        minHeight: 73,
        leadingPadding: titleLeadingInset,
        trailingPadding: accessoryTrailingInset,
        verticalPadding: 0,
        titleLineLimit: 1,
        subtitleLineLimit: 1,
        action: { onSelect(row) }
      ) {
        NETeamCommonPresentation.chevron(token: token, isEnabled: row.isEnabled)
      }
      .accessibilityIdentifier(row.id)
    }
  }

  private var titleLeadingInset: CGFloat {
    style == .fun ? 16 : 36
  }

  private var accessoryTrailingInset: CGFloat {
    style == .fun ? 16 : 36
  }

  private var switchTrailingInset: CGFloat {
    style == .fun ? 14 : 36
  }
}
