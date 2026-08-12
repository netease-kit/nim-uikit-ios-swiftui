// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonNavigationBarView: View {
  @Environment(\.neCommonTheme) private var token
  private let title: String
  private let backAction: (() -> Void)?
  private let backIcon: NECommonNavigationIconResource
  private let trailingAction: NECommonNavigationAction?
  private let onTrailingAction: (() -> Void)?
  private let trailingActionEnabled: Bool
  private let customTrailingWidth: CGFloat?
  private let customTrailingContent: AnyView?
  private let backgroundColor: Color?
  private let separatorColor: Color?
  private let showsSeparator: Bool
  private let titleTruncationMode: Text.TruncationMode

  private enum Metrics {
    static let height: CGFloat = 44
    static let horizontalMargin: CGFloat = 16
    static let sideButtonWidth: CGFloat = 50
    static let sideButtonHeight: CGFloat = 44
    static let iconWidth: CGFloat = 10
    static let iconHeight: CGFloat = 18
    static let fallbackIconSize: CGFloat = 18
    static let titleSideInset: CGFloat = 72
  }

  public init(title: String,
              backAction: (() -> Void)? = nil,
              backIcon: NECommonNavigationIconResource = .back,
              trailingAction: NECommonNavigationAction? = nil,
              onTrailingAction: (() -> Void)? = nil,
              trailingActionEnabled: Bool = true,
              backgroundColor: Color? = nil,
              separatorColor: Color? = nil,
              showsSeparator: Bool = false,
              titleTruncationMode: Text.TruncationMode = .tail) {
    self.title = title
    self.backAction = backAction
    self.backIcon = backIcon
    self.trailingAction = trailingAction
    self.onTrailingAction = onTrailingAction
    self.trailingActionEnabled = trailingActionEnabled
    customTrailingWidth = nil
    customTrailingContent = nil
    self.backgroundColor = backgroundColor
    self.separatorColor = separatorColor
    self.showsSeparator = showsSeparator
    self.titleTruncationMode = titleTruncationMode
  }

  public init<Trailing: View>(title: String,
                              backAction: (() -> Void)? = nil,
                              backIcon: NECommonNavigationIconResource = .back,
                              trailingWidth: CGFloat,
                              backgroundColor: Color? = nil,
                              separatorColor: Color? = nil,
                              showsSeparator: Bool = false,
                              titleTruncationMode: Text.TruncationMode = .tail,
                              @ViewBuilder trailingContent: () -> Trailing) {
    self.title = title
    self.backAction = backAction
    self.backIcon = backIcon
    trailingAction = nil
    onTrailingAction = nil
    trailingActionEnabled = true
    customTrailingWidth = trailingWidth
    customTrailingContent = AnyView(trailingContent())
    self.backgroundColor = backgroundColor
    self.separatorColor = separatorColor
    self.showsSeparator = showsSeparator
    self.titleTruncationMode = titleTruncationMode
  }

  public var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(token.palette.primaryText)
          .lineLimit(1)
          .truncationMode(titleTruncationMode)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, Metrics.titleSideInset)

        HStack(spacing: 0) {
          leadingButton
          Spacer(minLength: 0)
          trailingButton
        }
        .padding(.horizontal, Metrics.horizontalMargin)
      }
      .frame(height: Metrics.height)

      if showsSeparator {
        Rectangle()
          .fill(separatorColor ?? token.palette.separator)
          .frame(height: 0.5)
      }
    }
    .background(backgroundColor ?? token.palette.elevatedBackground)
  }

  @ViewBuilder
  private var leadingButton: some View {
    if let backAction {
      Button(action: backAction) {
        backIconView(backIcon)
      }
      .buttonStyle(.plain)
      .frame(width: Metrics.sideButtonWidth, height: Metrics.sideButtonHeight, alignment: .leading)
      .contentShape(Rectangle())
      .accessibilityLabel(NECommonUIKitSwiftUIBundle.localized("common_back", fallback: "Back"))
    } else {
      Color.clear.frame(width: Metrics.sideButtonWidth, height: Metrics.sideButtonHeight)
    }
  }

  @ViewBuilder
  private var trailingButton: some View {
    if let customTrailingContent {
      customTrailingContent
        .frame(width: customTrailingWidth ?? Metrics.sideButtonWidth,
               height: Metrics.sideButtonHeight,
               alignment: .trailing)
    } else if let trailingAction, let onTrailingAction {
      Button(action: onTrailingAction) {
        trailingActionContent(trailingAction)
      }
      .buttonStyle(.plain)
      .foregroundColor(token.palette.accent)
      .opacity(trailingActionEnabled ? 1 : 0.45)
      .frame(width: trailingWidth(for: trailingAction), height: Metrics.sideButtonHeight, alignment: .trailing)
      .contentShape(Rectangle())
      .disabled(!trailingActionEnabled)
      .accessibilityLabel(trailingAction.title)
    } else {
      Color.clear.frame(width: Metrics.sideButtonWidth, height: Metrics.sideButtonHeight)
    }
  }

  @ViewBuilder
  private func trailingActionContent(_ action: NECommonNavigationAction) -> some View {
    if let imageName = action.imageName {
      let size = action.imageSize ?? CGSize(width: 17, height: 3)
      Image(imageName, bundle: action.imageBundle)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: size.width, height: size.height)
        .frame(width: trailingWidth(for: action), height: Metrics.sideButtonHeight, alignment: .trailing)
    } else if let systemImage = action.systemImage {
      NECommonFallbackIconView(name: systemImage)
        .frame(width: action.imageSize?.width ?? 20, height: action.imageSize?.height ?? 20)
        .frame(width: trailingWidth(for: action), height: Metrics.sideButtonHeight, alignment: .trailing)
    } else {
      Text(action.title)
        .font(.system(size: 16))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: trailingWidth(for: action), height: Metrics.sideButtonHeight, alignment: .trailing)
    }
  }

  @ViewBuilder
  private func backIconView(_ resource: NECommonNavigationIconResource) -> some View {
    if let assetName = resource.assetName, !assetName.isEmpty {
      Image(assetName, bundle: resource.bundle)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: Metrics.iconWidth, height: Metrics.iconHeight)
        .frame(width: Metrics.sideButtonWidth, height: Metrics.sideButtonHeight, alignment: .leading)
    } else {
      NECommonFallbackIconView(name: resource.systemImageName ?? "chevron.left")
        .foregroundColor(token.palette.primaryText)
        .frame(width: Metrics.fallbackIconSize, height: Metrics.fallbackIconSize)
        .frame(width: Metrics.sideButtonWidth, height: Metrics.sideButtonHeight, alignment: .leading)
    }
  }

  private func trailingWidth(for action: NECommonNavigationAction) -> CGFloat {
    if action.imageName != nil || action.systemImage != nil {
      return Metrics.sideButtonWidth
    }
    return 60
  }
}
