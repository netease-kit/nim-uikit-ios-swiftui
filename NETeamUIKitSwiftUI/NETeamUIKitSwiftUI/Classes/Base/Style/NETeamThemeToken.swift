// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct NETeamThemeToken: Equatable {
  public var styleMode: NETeamSwiftUIStyleMode
  public var pageBackground: Color
  public var rowBackground: Color
  public var searchBackground: Color
  public var primaryText: Color
  public var secondaryText: Color
  public var accent: Color
  public var destructive: Color
  public var separator: Color
  public var detailText: Color
  public var ownerText: Color
  public var ownerBackground: Color
  public var ownerBorder: Color
  public var titleFont: Font
  public var subtitleFont: Font
  public var detailFont: Font
  public var headerHeight: CGFloat
  public var headerHorizontalMargin: CGFloat
  public var headerCornerRadius: CGFloat
  public var headerAvatarSize: CGFloat
  public var headerAvatarCornerRadius: CGFloat
  public var previewTitleHeight: CGFloat
  public var previewListHeight: CGFloat
  public var previewAvatarSize: CGFloat
  public var previewAvatarCornerRadius: CGFloat
  public var previewMemberSpacing: CGFloat
  public var memberRowHeight: CGFloat
  public var memberAvatarSize: CGFloat
  public var memberAvatarCornerRadius: CGFloat
  public var infoAvatarSize: CGFloat
  public var infoAvatarCornerRadius: CGFloat
  public var detailAvatarSize: CGFloat
  public var detailAvatarCornerRadius: CGFloat
  public var avatarEditPreviewSize: CGFloat
  public var avatarEditPreviewCornerRadius: CGFloat
  public var defaultAvatarSelectionSize: CGFloat
  public var defaultAvatarIconSize: CGFloat
  public var defaultAvatarIconCornerRadius: CGFloat
  public var sectionHorizontalMargin: CGFloat
  public var sectionCornerRadius: CGFloat
  public var destructiveButtonHeight: CGFloat
  public var destructiveButtonTopPadding: CGFloat
  public var destructiveButtonHorizontalMargin: CGFloat
  public var textEditContainerHeight: CGFloat
  public var textEditContainerHorizontalMargin: CGFloat
  public var textEditContainerTopPadding: CGFloat
  public var textEditContainerCornerRadius: CGFloat
  public var introduceEditContainerHeight: CGFloat
  public var rowHeight: CGFloat

  public init(styleMode: NETeamSwiftUIStyleMode = .normal,
              pageBackground: Color,
              rowBackground: Color,
              searchBackground: Color = NEUIKitSwiftUIStyle.ColorToken.searchBackground,
              primaryText: Color,
              secondaryText: Color,
              accent: Color,
              destructive: Color,
              separator: Color,
              detailText: Color = NEUIKitSwiftUIStyle.ColorToken.detailText,
              ownerText: Color = NEUIKitSwiftUIStyle.ColorToken.teamOwnerText,
              ownerBackground: Color = NEUIKitSwiftUIStyle.ColorToken.teamOwnerBackground,
              ownerBorder: Color = NEUIKitSwiftUIStyle.ColorToken.teamOwnerBorder,
              titleFont: Font = NEUIKitSwiftUIStyle.FontToken.settingTitle,
              subtitleFont: Font = NEUIKitSwiftUIStyle.FontToken.pinMessage,
              detailFont: Font = NEUIKitSwiftUIStyle.FontToken.settingDetail,
              headerHeight: CGFloat = 160,
              headerHorizontalMargin: CGFloat = 20,
              headerCornerRadius: CGFloat = 8,
              headerAvatarSize: CGFloat = 42,
              headerAvatarCornerRadius: CGFloat = 21,
              previewTitleHeight: CGFloat = 40,
              previewListHeight: CGFloat = 57,
              previewAvatarSize: CGFloat = 32,
              previewAvatarCornerRadius: CGFloat = 16,
              previewMemberSpacing: CGFloat = 15,
              memberRowHeight: CGFloat = 64,
              memberAvatarSize: CGFloat = 42,
              memberAvatarCornerRadius: CGFloat = 21,
              infoAvatarSize: CGFloat = 42,
              infoAvatarCornerRadius: CGFloat = 21,
              detailAvatarSize: CGFloat = 60,
              detailAvatarCornerRadius: CGFloat = 30,
              avatarEditPreviewSize: CGFloat = 88,
              avatarEditPreviewCornerRadius: CGFloat = 12,
              defaultAvatarSelectionSize: CGFloat = 48,
              defaultAvatarIconSize: CGFloat = 32,
              defaultAvatarIconCornerRadius: CGFloat = 8,
              sectionHorizontalMargin: CGFloat = 20,
              sectionCornerRadius: CGFloat = 8,
              destructiveButtonHeight: CGFloat = 40,
              destructiveButtonTopPadding: CGFloat = 12,
              destructiveButtonHorizontalMargin: CGFloat = 20,
              textEditContainerHeight: CGFloat = 60,
              textEditContainerHorizontalMargin: CGFloat = 20,
              textEditContainerTopPadding: CGFloat = 12,
              textEditContainerCornerRadius: CGFloat = 8,
              introduceEditContainerHeight: CGFloat = 170,
              rowHeight: CGFloat = 49) {
    self.styleMode = styleMode
    self.pageBackground = pageBackground
    self.rowBackground = rowBackground
    self.searchBackground = searchBackground
    self.primaryText = primaryText
    self.secondaryText = secondaryText
    self.accent = accent
    self.destructive = destructive
    self.separator = separator
    self.detailText = detailText
    self.ownerText = ownerText
    self.ownerBackground = ownerBackground
    self.ownerBorder = ownerBorder
    self.titleFont = titleFont
    self.subtitleFont = subtitleFont
    self.detailFont = detailFont
    self.headerHeight = headerHeight
    self.headerHorizontalMargin = headerHorizontalMargin
    self.headerCornerRadius = headerCornerRadius
    self.headerAvatarSize = headerAvatarSize
    self.headerAvatarCornerRadius = headerAvatarCornerRadius
    self.previewTitleHeight = previewTitleHeight
    self.previewListHeight = previewListHeight
    self.previewAvatarSize = previewAvatarSize
    self.previewAvatarCornerRadius = previewAvatarCornerRadius
    self.previewMemberSpacing = previewMemberSpacing
    self.memberRowHeight = memberRowHeight
    self.memberAvatarSize = memberAvatarSize
    self.memberAvatarCornerRadius = memberAvatarCornerRadius
    self.infoAvatarSize = infoAvatarSize
    self.infoAvatarCornerRadius = infoAvatarCornerRadius
    self.detailAvatarSize = detailAvatarSize
    self.detailAvatarCornerRadius = detailAvatarCornerRadius
    self.avatarEditPreviewSize = avatarEditPreviewSize
    self.avatarEditPreviewCornerRadius = avatarEditPreviewCornerRadius
    self.defaultAvatarSelectionSize = defaultAvatarSelectionSize
    self.defaultAvatarIconSize = defaultAvatarIconSize
    self.defaultAvatarIconCornerRadius = defaultAvatarIconCornerRadius
    self.sectionHorizontalMargin = sectionHorizontalMargin
    self.sectionCornerRadius = sectionCornerRadius
    self.destructiveButtonHeight = destructiveButtonHeight
    self.destructiveButtonTopPadding = destructiveButtonTopPadding
    self.destructiveButtonHorizontalMargin = destructiveButtonHorizontalMargin
    self.textEditContainerHeight = textEditContainerHeight
    self.textEditContainerHorizontalMargin = textEditContainerHorizontalMargin
    self.textEditContainerTopPadding = textEditContainerTopPadding
    self.textEditContainerCornerRadius = textEditContainerCornerRadius
    self.introduceEditContainerHeight = introduceEditContainerHeight
    self.rowHeight = rowHeight
  }
}
