// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSettingToggleRowView: View {
  @Environment(\.neCommonTheme) private var token
  @Binding private var isOn: Bool
  private let title: String
  private let subtitle: String?
  private let isEnabled: Bool
  private let minHeight: CGFloat
  private let leadingPadding: CGFloat?
  private let trailingPadding: CGFloat?
  private let verticalPadding: CGFloat?
  private let titleLineLimit: Int
  private let subtitleLineLimit: Int

  public init(title: String,
              subtitle: String? = nil,
              isOn: Binding<Bool>,
              isEnabled: Bool = true,
              minHeight: CGFloat = 52,
              leadingPadding: CGFloat? = nil,
              trailingPadding: CGFloat? = nil,
              verticalPadding: CGFloat? = nil,
              titleLineLimit: Int = 2,
              subtitleLineLimit: Int = 2) {
    self.title = title
    self.subtitle = subtitle
    _isOn = isOn
    self.isEnabled = isEnabled
    self.minHeight = minHeight
    self.leadingPadding = leadingPadding
    self.trailingPadding = trailingPadding
    self.verticalPadding = verticalPadding
    self.titleLineLimit = titleLineLimit
    self.subtitleLineLimit = subtitleLineLimit
  }

  public var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: token.spacing.xsmall) {
        Text(title)
          .font(token.typography.body)
          .foregroundColor(isEnabled ? token.palette.primaryText : token.palette.secondaryText.opacity(0.55))
          .lineLimit(titleLineLimit)
          .multilineTextAlignment(.leading)

        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(token.typography.caption)
            .foregroundColor(token.palette.secondaryText)
            .lineLimit(subtitleLineLimit)
            .multilineTextAlignment(.leading)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .toggleStyle(.switch)
    .tint(token.palette.accent)
    .disabled(!isEnabled)
    .padding(.leading, leadingPadding ?? token.spacing.large)
    .padding(.trailing, trailingPadding ?? token.spacing.large)
    .padding(.vertical, verticalPadding ?? token.spacing.medium)
    .frame(minHeight: minHeight)
    .background(token.palette.rowBackground)
  }
}
