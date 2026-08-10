// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonSegmentedOption<ID: Hashable>: Identifiable {
  public var id: ID
  public var title: String
  public var accessibilityLabel: String?
  public var isEnabled: Bool

  public init(id: ID,
              title: String,
              accessibilityLabel: String? = nil,
              isEnabled: Bool = true) {
    self.id = id
    self.title = title
    self.accessibilityLabel = accessibilityLabel
    self.isEnabled = isEnabled
  }
}

public struct NECommonSegmentedControlView<ID: Hashable>: View {
  @Environment(\.neCommonTheme) private var token
  private let options: [NECommonSegmentedOption<ID>]
  @Binding private var selection: ID
  private let height: CGFloat
  private let spacing: CGFloat
  private let allowsHorizontalScroll: Bool

  public init(options: [NECommonSegmentedOption<ID>],
              selection: Binding<ID>,
              height: CGFloat = 32,
              spacing: CGFloat = 8,
              allowsHorizontalScroll: Bool = true) {
    self.options = options
    _selection = selection
    self.height = height
    self.spacing = spacing
    self.allowsHorizontalScroll = allowsHorizontalScroll
  }

  public var body: some View {
    Group {
      if allowsHorizontalScroll {
        ScrollView(.horizontal, showsIndicators: false) {
          segments
        }
      } else {
        segments
      }
    }
  }

  private var segments: some View {
    HStack(spacing: spacing) {
      ForEach(options) { option in
        Button {
          guard option.isEnabled else {
            return
          }
          selection = option.id
        } label: {
          Text(option.title)
            .font(.system(size: 13, weight: selection == option.id ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(foreground(for: option))
            .padding(.horizontal, token.spacing.medium)
            .frame(height: height)
            .background(background(for: option))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .accessibilityLabel(option.accessibilityLabel ?? option.title)
        .accessibilityAddTraits(selection == option.id ? .isSelected : [])
      }
    }
    .padding(.vertical, token.spacing.xsmall)
  }

  private func foreground(for option: NECommonSegmentedOption<ID>) -> Color {
    guard option.isEnabled else {
      return token.palette.disabled
    }
    return selection == option.id ? token.button.primaryForeground : token.palette.primaryText
  }

  private func background(for option: NECommonSegmentedOption<ID>) -> Color {
    guard option.isEnabled else {
      return token.button.disabledBackground
    }
    return selection == option.id ? token.palette.accent : token.palette.elevatedBackground
  }
}
