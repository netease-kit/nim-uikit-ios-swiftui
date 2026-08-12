// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct TeamSettingRowView: View {
  public var row: TeamSettingRowState
  public var token: NETeamThemeToken
  public var style: NETeamSwiftUIStyleMode
  public var customContent: AnyView?
  public var onSelect: (TeamSettingRowState) -> Void
  public var onToggle: (TeamSettingToggleKind, Bool) -> Void

  public init(row: TeamSettingRowState,
              token: NETeamThemeToken,
              style: NETeamSwiftUIStyleMode = .normal,
              customContent: AnyView? = nil,
              onSelect: @escaping (TeamSettingRowState) -> Void,
              onToggle: @escaping (TeamSettingToggleKind, Bool) -> Void) {
    self.row = row
    self.token = token
    self.style = style
    self.customContent = customContent
    self.onSelect = onSelect
    self.onToggle = onToggle
  }

  @ViewBuilder
  public var body: some View {
    if let customContent {
      customRowContent(customContent)
    } else {
      defaultContent
    }
  }

  @ViewBuilder
  private func customRowContent(_ content: AnyView) -> some View {
    if isToggleRow {
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(token.rowBackground)
        .accessibilityIdentifier(row.id)
    } else {
      Button {
        onSelect(row)
      } label: {
        content
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!row.isEnabled)
      .background(token.rowBackground)
      .accessibilityIdentifier(row.id)
    }
  }

  private var isToggleRow: Bool {
    if case .toggle = row.kind {
      return true
    }
    return false
  }

  @ViewBuilder
  private var defaultContent: some View {
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
        leadingPadding: titleLeadingInset,
        trailingPadding: switchTrailingInset,
        verticalPadding: 0,
        titleLineLimit: 1,
        subtitleLineLimit: 1
      )
      .accessibilityIdentifier(row.id)
    case .destructive:
      Button(role: .destructive) {
        onSelect(row)
      } label: {
        Text(row.title)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(token.destructive)
          .frame(maxWidth: .infinity)
          .frame(minHeight: token.destructiveButtonHeight)
      }
      .buttonStyle(.plain)
      .background(token.rowBackground)
      .accessibilityIdentifier(row.id)
    case let .customAction(action) where action.role == .destructive:
      Button(role: .destructive) {
        onSelect(row)
      } label: {
        Text(row.title)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(row.isEnabled ? token.destructive : token.secondaryText.opacity(0.45))
          .frame(maxWidth: .infinity)
          .frame(minHeight: token.destructiveButtonHeight)
      }
      .buttonStyle(.plain)
      .disabled(!row.isEnabled)
      .background(token.rowBackground)
      .accessibilityIdentifier(row.id)
    case let .customAction(action):
      buttonRow {
        if let imageName = action.imageName {
          NETeamCommonPresentation.iconView(
            imageName: imageName,
            token: token,
            bundle: action.imageBundle ?? NETeamUIKitSwiftUIBundle.bundle,
            renderingMode: .original,
            isEnabled: row.isEnabled,
            size: CGSize(width: 20, height: 20),
            foregroundColor: row.isEnabled ? token.accent : token.secondaryText.opacity(0.45),
            accessibilityLabel: row.title
          )
        } else if let systemImageName = action.systemImageName {
          NETeamCommonPresentation.iconView(
            systemImageName: systemImageName,
            token: token,
            isEnabled: row.isEnabled,
            size: CGSize(width: 20, height: 20),
            font: .system(size: 15, weight: .medium),
            foregroundColor: row.isEnabled ? token.accent : token.secondaryText.opacity(0.45),
            accessibilityLabel: row.title
          )
        } else {
          NETeamCommonPresentation.chevron(token: token, isEnabled: row.isEnabled)
        }
      }
      .accessibilityIdentifier(row.id)
    case .navigation, .hostAction:
      buttonRow {
        NETeamCommonPresentation.chevron(token: token, isEnabled: row.isEnabled)
      }
      .accessibilityIdentifier(row.id)
    }
  }

  private func buttonRow<Accessory: View>(@ViewBuilder accessory: @escaping () -> Accessory) -> some View {
    NETeamCommonPresentation.settingRow(
      title: row.title,
      value: row.value,
      subtitle: row.subtitle,
      token: token,
      isEnabled: row.isEnabled,
      leadingPadding: titleLeadingInset,
      trailingPadding: accessoryTrailingInset,
      verticalPadding: 0,
      titleLineLimit: 1,
      subtitleLineLimit: 1,
      action: { onSelect(row) }
    ) {
      accessory()
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
