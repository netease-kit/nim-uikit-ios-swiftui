// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonIconView: View {
  @Environment(\.neCommonTheme) private var token
  private let systemImageName: String?
  private let imageResource: NECommonImageResource?
  private let isEnabled: Bool
  private let size: CGSize?
  private let font: Font?
  private let foregroundColor: Color?
  private let accessibilityLabel: String?

  public init(systemImageName: String,
              isEnabled: Bool = true,
              size: CGSize? = nil,
              font: Font? = nil,
              foregroundColor: Color? = nil,
              accessibilityLabel: String? = nil) {
    self.systemImageName = systemImageName
    imageResource = nil
    self.isEnabled = isEnabled
    self.size = size
    self.font = font
    self.foregroundColor = foregroundColor
    self.accessibilityLabel = accessibilityLabel
  }

  public init(imageName: String,
              bundle: Bundle? = nil,
              renderingMode: NECommonImageRenderingMode = .template,
              isEnabled: Bool = true,
              size: CGSize? = nil,
              font: Font? = nil,
              foregroundColor: Color? = nil,
              accessibilityLabel: String? = nil) {
    systemImageName = nil
    imageResource = NECommonImageResource(imageName: imageName, bundle: bundle, renderingMode: renderingMode)
    self.isEnabled = isEnabled
    self.size = size
    self.font = font
    self.foregroundColor = foregroundColor
    self.accessibilityLabel = accessibilityLabel
  }

  public var body: some View {
    icon
      .accessibilityHidden(accessibilityLabel == nil)
      .accessibilityLabel(accessibilityLabel ?? "")
  }

  @ViewBuilder
  private var icon: some View {
    if let imageResource {
      let image = Image(imageResource.imageName, bundle: imageResource.bundle)
      if imageResource.renderingMode == .template {
        image
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .foregroundColor(iconColor)
          .frame(width: size?.width, height: size?.height)
      } else {
        image
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .opacity(isEnabled ? 1 : 0.45)
          .frame(width: size?.width, height: size?.height)
      }
    } else if let systemImageName {
      NECommonFallbackIconView(name: systemImageName)
        .foregroundColor(iconColor)
        .frame(width: size?.width, height: size?.height)
    }
  }

  private var iconColor: Color {
    guard isEnabled else {
      return token.palette.secondaryText.opacity(0.45)
    }
    return foregroundColor ?? token.palette.secondaryText
  }
}

public struct NECommonIconButton: View {
  @Environment(\.neCommonTheme) private var token
  private let systemImageName: String?
  private let imageResource: NECommonImageResource?
  private let accessibilityLabel: String
  private let isEnabled: Bool
  private let size: CGSize
  private let font: Font?
  private let foregroundColor: Color?
  private let action: () -> Void

  public init(systemImageName: String,
              accessibilityLabel: String,
              isEnabled: Bool = true,
              size: CGSize = CGSize(width: 24, height: 24),
              font: Font? = nil,
              foregroundColor: Color? = nil,
              action: @escaping () -> Void) {
    self.systemImageName = systemImageName
    imageResource = nil
    self.accessibilityLabel = accessibilityLabel
    self.isEnabled = isEnabled
    self.size = size
    self.font = font
    self.foregroundColor = foregroundColor
    self.action = action
  }

  public init(imageName: String,
              bundle: Bundle? = nil,
              renderingMode: NECommonImageRenderingMode = .template,
              accessibilityLabel: String,
              isEnabled: Bool = true,
              size: CGSize = CGSize(width: 24, height: 24),
              font: Font? = nil,
              foregroundColor: Color? = nil,
              action: @escaping () -> Void) {
    systemImageName = nil
    imageResource = NECommonImageResource(imageName: imageName, bundle: bundle, renderingMode: renderingMode)
    self.accessibilityLabel = accessibilityLabel
    self.isEnabled = isEnabled
    self.size = size
    self.font = font
    self.foregroundColor = foregroundColor
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      if let imageResource {
        NECommonIconView(imageName: imageResource.imageName,
                         bundle: imageResource.bundle,
                         renderingMode: imageResource.renderingMode,
                         isEnabled: isEnabled,
                         size: size,
                         font: font,
                         foregroundColor: foregroundColor)
          .contentShape(Rectangle())
      } else if let systemImageName {
        NECommonIconView(systemImageName: systemImageName,
                         isEnabled: isEnabled,
                         size: size,
                         font: font,
                         foregroundColor: foregroundColor)
          .contentShape(Rectangle())
      }
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
  }

  private var iconColor: Color {
    guard isEnabled else {
      return token.palette.secondaryText.opacity(0.45)
    }
    return foregroundColor ?? token.palette.secondaryText
  }
}
