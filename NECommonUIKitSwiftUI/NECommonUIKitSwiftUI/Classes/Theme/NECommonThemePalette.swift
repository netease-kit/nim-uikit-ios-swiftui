// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum NEUIKitSwiftUIStyle {
  public enum ColorToken {
    public static let normalTheme = Color(hex: 0x337EFF)
    public static let funTheme = Color(hex: 0x58BE6B)
    public static let darkText = Color(hex: 0x333333)
    public static let greyText = Color(hex: 0x666666)
    public static let lightText = Color(hex: 0x999999)
    public static let emptyTitle = Color(hex: 0xB3B7BC)
    public static let redText = Color(hex: 0xE6605C)
    public static let disableRedText = Color(hex: 0xE6605C, opacity: 0.5)
    public static let red = Color(hex: 0xF24957)
    public static let greenText = Color(hex: 0x3EAF96)
    public static let back = Color(hex: 0xF2F4F5)
    public static let lightBackground = Color(hex: 0xEFF1F4)
    public static let background = Color(hex: 0xEFF1F3)
    public static let avatarBackground = Color(hex: 0x537FF4)
    public static let yellowBackground = Color(hex: 0xFFFBEA)
    public static let border = Color(hex: 0xDBDDE4)
    public static let operationBorder = Color(hex: 0x85888C)
    public static let greyLine = Color(hex: 0xF5F8FC)
    public static let navLine = Color(hex: 0xE9EFF5)
    public static let outline = Color(hex: 0xE2E5E8)
    public static let dateText = Color(hex: 0xCCCCCC)
    public static let normalInputBackground = Color(hex: 0xEFF1F3)
    public static let funBackground = Color(hex: 0xEDEDED)
    public static let funInputBackground = Color(hex: 0xF5F5F5)
    public static let funLineBorder = Color(hex: 0xE5E5E5)
    public static let funListLineBorder = Color(hex: 0xD8D8D8)
    public static let normalNetworkBrokenBackground = Color(hex: 0xFEE3E6)
    public static let normalNetworkBrokenTitle = Color(hex: 0xFC596A)
    public static let funNetworkBrokenBackground = Color(hex: 0xFCEEEE)
    public static let searchBackground = Color(hex: 0xF2F4F5)
    public static let detailText = Color(hex: 0xA6ADB6)
    public static let teamOwnerText = Color(hex: 0x656A72)
    public static let teamOwnerBackground = Color(hex: 0xF7F7F7)
    public static let teamOwnerBorder = Color(hex: 0xD6D8DB)
    public static let orangeWarning = Color(hex: 0xFF9000)
  }

  public enum FontToken {
    public static let navTitle = Font.system(size: 16, weight: .semibold)
    public static let navAction = Font.system(size: 16)
    public static let pageTitle = Font.system(size: 20, weight: .medium)
    public static let chatMessage = Font.system(size: 16)
    public static let chatInput = Font.system(size: 16)
    public static let chatMultiLinePlaceholder = Font.system(size: 18)
    public static let chatTime = Font.system(size: 14)
    public static let chatSenderName = Font.system(size: 12)
    public static let pinMessage = Font.system(size: 14)
    public static let moreActionTitle = Font.system(size: 10)
    public static let videoDuration = Font.system(size: 10)
    public static let conversationTitle = Font.system(size: 16)
    public static let conversationFunTitle = Font.system(size: 17)
    public static let conversationSubtitle = Font.system(size: 13)
    public static let conversationTime = Font.system(size: 12)
    public static let contactTitle = Font.system(size: 14)
    public static let contactFunTitle = Font.system(size: 17)
    public static let contactSection = Font.system(size: 14)
    public static let contactSearch = Font.system(size: 14)
    public static let settingTitle = Font.system(size: 16)
    public static let settingSubtitle = Font.system(size: 12)
    public static let settingDetail = Font.system(size: 12)
    public static let button14 = Font.system(size: 14)
    public static let button16 = Font.system(size: 16)
  }
}

public extension Color {
  init(hex: Int, opacity: Double = 1.0) {
    self.init(
      .sRGB,
      red: Double((hex & 0xFF0000) >> 16) / 255.0,
      green: Double((hex & 0x00FF00) >> 8) / 255.0,
      blue: Double(hex & 0x0000FF) / 255.0,
      opacity: opacity
    )
  }
}

public struct NECommonThemePalette: Equatable {
  public var pageBackground: Color
  public var rowBackground: Color
  public var elevatedBackground: Color
  public var primaryText: Color
  public var secondaryText: Color
  public var tertiaryText: Color
  public var accent: Color
  public var destructive: Color
  public var warning: Color
  public var separator: Color
  public var disabled: Color

  public init(pageBackground: Color,
              rowBackground: Color,
              elevatedBackground: Color,
              primaryText: Color,
              secondaryText: Color,
              tertiaryText: Color,
              accent: Color,
              destructive: Color,
              warning: Color,
              separator: Color,
              disabled: Color) {
    self.pageBackground = pageBackground
    self.rowBackground = rowBackground
    self.elevatedBackground = elevatedBackground
    self.primaryText = primaryText
    self.secondaryText = secondaryText
    self.tertiaryText = tertiaryText
    self.accent = accent
    self.destructive = destructive
    self.warning = warning
    self.separator = separator
    self.disabled = disabled
  }
}

public struct NECommonTypography: Equatable {
  public var title: Font
  public var headline: Font
  public var body: Font
  public var footnote: Font
  public var caption: Font

  public init(title: Font,
              headline: Font,
              body: Font,
              footnote: Font,
              caption: Font) {
    self.title = title
    self.headline = headline
    self.body = body
    self.footnote = footnote
    self.caption = caption
  }
}

public struct NECommonSpacing: Equatable {
  public var xsmall: CGFloat
  public var small: CGFloat
  public var medium: CGFloat
  public var large: CGFloat
  public var xlarge: CGFloat

  public init(xsmall: CGFloat = 4,
              small: CGFloat = 8,
              medium: CGFloat = 12,
              large: CGFloat = 16,
              xlarge: CGFloat = 24) {
    self.xsmall = xsmall
    self.small = small
    self.medium = medium
    self.large = large
    self.xlarge = xlarge
  }
}

public struct NECommonRadius: Equatable {
  public var small: CGFloat
  public var medium: CGFloat
  public var large: CGFloat
  public var control: CGFloat
  public var avatar: CGFloat

  public init(small: CGFloat = 6,
              medium: CGFloat = 8,
              large: CGFloat = 12,
              control: CGFloat = 10,
              avatar: CGFloat = 20) {
    self.small = small
    self.medium = medium
    self.large = large
    self.control = control
    self.avatar = avatar
  }
}

public struct NECommonShadow: Equatable {
  public var color: Color
  public var radius: CGFloat
  public var x: CGFloat
  public var y: CGFloat

  public init(color: Color = Color.black.opacity(0.08),
              radius: CGFloat = 12,
              x: CGFloat = 0,
              y: CGFloat = 4) {
    self.color = color
    self.radius = radius
    self.x = x
    self.y = y
  }
}
