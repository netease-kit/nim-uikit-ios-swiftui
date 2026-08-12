// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum NECommonStyleMode: Equatable {
  case normal
  case fun
}

public struct NECommonAvatarToken: Equatable {
  public var size: CGFloat
  public var cornerRadius: CGFloat
  public var background: Color
  public var foreground: Color

  public init(size: CGFloat = 40,
              cornerRadius: CGFloat = 20,
              background: Color,
              foreground: Color) {
    self.size = size
    self.cornerRadius = cornerRadius
    self.background = background
    self.foreground = foreground
  }
}

public struct NECommonBadgeToken: Equatable {
  public var background: Color
  public var foreground: Color
  public var minSize: CGFloat
  public var maxCount: Int

  public init(background: Color,
              foreground: Color,
              minSize: CGFloat = 18,
              maxCount: Int = NECommonUIKitSwiftUIConstants.maxBadgeCount) {
    self.background = background
    self.foreground = foreground
    self.minSize = minSize
    self.maxCount = maxCount
  }
}

public struct NECommonButtonToken: Equatable {
  public var primaryBackground: Color
  public var primaryForeground: Color
  public var secondaryBackground: Color
  public var secondaryForeground: Color
  public var destructiveBackground: Color
  public var destructiveForeground: Color
  public var disabledBackground: Color
  public var disabledForeground: Color
  public var cornerRadius: CGFloat
  public var minHeight: CGFloat

  public init(primaryBackground: Color,
              primaryForeground: Color,
              secondaryBackground: Color,
              secondaryForeground: Color,
              destructiveBackground: Color,
              destructiveForeground: Color,
              disabledBackground: Color,
              disabledForeground: Color,
              cornerRadius: CGFloat = 8,
              minHeight: CGFloat = 44) {
    self.primaryBackground = primaryBackground
    self.primaryForeground = primaryForeground
    self.secondaryBackground = secondaryBackground
    self.secondaryForeground = secondaryForeground
    self.destructiveBackground = destructiveBackground
    self.destructiveForeground = destructiveForeground
    self.disabledBackground = disabledBackground
    self.disabledForeground = disabledForeground
    self.cornerRadius = cornerRadius
    self.minHeight = minHeight
  }
}

public struct NECommonOverlayToken: Equatable {
  public var toastBackground: Color
  public var toastForeground: Color
  public var scrim: Color
  public var cornerRadius: CGFloat

  public init(toastBackground: Color,
              toastForeground: Color,
              scrim: Color,
              cornerRadius: CGFloat = 8) {
    self.toastBackground = toastBackground
    self.toastForeground = toastForeground
    self.scrim = scrim
    self.cornerRadius = cornerRadius
  }
}

public struct NECommonThemeToken: Equatable {
  public var styleMode: NECommonStyleMode
  public var palette: NECommonThemePalette
  public var typography: NECommonTypography
  public var spacing: NECommonSpacing
  public var radius: NECommonRadius
  public var shadow: NECommonShadow
  public var avatar: NECommonAvatarToken
  public var badge: NECommonBadgeToken
  public var button: NECommonButtonToken
  public var overlay: NECommonOverlayToken

  public init(styleMode: NECommonStyleMode,
              palette: NECommonThemePalette,
              typography: NECommonTypography,
              spacing: NECommonSpacing,
              radius: NECommonRadius,
              shadow: NECommonShadow,
              avatar: NECommonAvatarToken,
              badge: NECommonBadgeToken,
              button: NECommonButtonToken,
              overlay: NECommonOverlayToken) {
    self.styleMode = styleMode
    self.palette = palette
    self.typography = typography
    self.spacing = spacing
    self.radius = radius
    self.shadow = shadow
    self.avatar = avatar
    self.badge = badge
    self.button = button
    self.overlay = overlay
  }

  public static let normal = NormalCommonThemeToken.token
  public static let fun = FunCommonThemeToken.token
}
