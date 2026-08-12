// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSettingRowView<Accessory: View>: View {
  @Environment(\.neCommonTheme) private var token
  private let title: String
  private let subtitle: String?
  private let value: String?
  private let isEnabled: Bool
  private let minHeight: CGFloat
  private let leadingPadding: CGFloat?
  private let trailingPadding: CGFloat?
  private let verticalPadding: CGFloat?
  private let titleLineLimit: Int
  private let subtitleLineLimit: Int
  private let accessory: Accessory
  private let action: (() -> Void)?

  public init(title: String,
              subtitle: String? = nil,
              value: String? = nil,
              isEnabled: Bool = true,
              minHeight: CGFloat = 52,
              leadingPadding: CGFloat? = nil,
              trailingPadding: CGFloat? = nil,
              verticalPadding: CGFloat? = nil,
              titleLineLimit: Int = 2,
              subtitleLineLimit: Int = 2,
              action: (() -> Void)? = nil,
              @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
    self.title = title
    self.subtitle = subtitle
    self.value = value
    self.isEnabled = isEnabled
    self.minHeight = minHeight
    self.leadingPadding = leadingPadding
    self.trailingPadding = trailingPadding
    self.verticalPadding = verticalPadding
    self.titleLineLimit = titleLineLimit
    self.subtitleLineLimit = subtitleLineLimit
    self.action = action
    self.accessory = accessory()
  }

  public var body: some View {
    if let action {
      Button(action: action) {
        rowContent
      }
      .buttonStyle(.plain)
      .disabled(!isEnabled)
    } else {
      rowContent
    }
  }

  private var rowContent: some View {
    HStack(spacing: token.spacing.medium) {
      VStack(alignment: .leading, spacing: token.spacing.xsmall) {
        Text(title)
          .font(token.typography.body)
          .foregroundColor(isEnabled ? token.palette.primaryText : token.palette.secondaryText.opacity(0.55))
          .lineLimit(titleLineLimit)
          .truncationMode(.tail)
          .multilineTextAlignment(.leading)

        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(token.typography.footnote)
            .foregroundColor(token.palette.secondaryText)
            .lineLimit(subtitleLineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let value, !value.isEmpty {
        Text(value)
          .font(token.typography.footnote)
          .foregroundColor(token.palette.secondaryText)
          .lineLimit(1)
          .truncationMode(.tail)
          .multilineTextAlignment(.trailing)
      }

      accessory
        .foregroundColor(token.palette.tertiaryText)
        .fixedSize()
    }
    .padding(.leading, leadingPadding ?? token.spacing.large)
    .padding(.trailing, trailingPadding ?? token.spacing.large)
    .padding(.vertical, verticalPadding ?? token.spacing.medium)
    .frame(minHeight: minHeight)
    .background(token.palette.rowBackground)
    .contentShape(Rectangle())
  }
}
