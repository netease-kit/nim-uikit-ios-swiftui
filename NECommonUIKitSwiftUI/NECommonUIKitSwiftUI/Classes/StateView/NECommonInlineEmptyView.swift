// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct NECommonInlineEmptyView: View {
  @Environment(\.neCommonTheme) private var token
  private let title: String
  private let systemImageName: String?
  private let imageResource: NECommonImageResource?
  private let imageKind: NECommonEmptyImageKind?
  private let message: String?
  private let minHeight: CGFloat

  public init(title: String,
              systemImageName: String? = nil,
              message: String? = nil,
              minHeight: CGFloat = 120) {
    self.title = title
    self.systemImageName = systemImageName
    imageResource = nil
    imageKind = nil
    self.message = message
    self.minHeight = minHeight
  }

  public init(title: String,
              imageKind: NECommonEmptyImageKind,
              message: String? = nil,
              minHeight: CGFloat = 120) {
    self.title = title
    systemImageName = nil
    imageResource = nil
    self.imageKind = imageKind
    self.message = message
    self.minHeight = minHeight
  }

  public init(title: String,
              imageName: String,
              bundle: Bundle? = nil,
              renderingMode: NECommonImageRenderingMode = .template,
              message: String? = nil,
              minHeight: CGFloat = 120) {
    self.title = title
    systemImageName = nil
    imageResource = NECommonImageResource(imageName: imageName, bundle: bundle, renderingMode: renderingMode)
    imageKind = nil
    self.message = message
    self.minHeight = minHeight
  }

  public var body: some View {
    VStack(spacing: token.spacing.small) {
      if let imageKind {
        Image(NECommonPlaceholderImage.emptyImageName(kind: imageKind, styleMode: token.styleMode),
              bundle: NECommonUIKitSwiftUIBundle.bundle)
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .frame(width: 122, height: 91)
      } else if let imageResource {
        let image = Image(imageResource.imageName, bundle: imageResource.bundle)
        if imageResource.renderingMode == .template {
          image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .foregroundColor(token.palette.secondaryText.opacity(0.7))
        } else {
          image
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
        }
      } else if let systemImageName, !systemImageName.isEmpty {
        NECommonFallbackIconView(name: systemImageName)
          .frame(width: 28, height: 28)
          .foregroundColor(token.palette.secondaryText.opacity(0.7))
      }

      Text(title)
        .font(.system(size: 14))
        .foregroundColor(imageKind == nil ? token.palette.secondaryText : NEUIKitSwiftUIStyle.ColorToken.emptyTitle)
        .multilineTextAlignment(.center)

      if let message, !message.isEmpty {
        Text(message)
          .font(token.typography.caption)
          .foregroundColor(token.palette.tertiaryText)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight)
    .padding(token.spacing.large)
    .accessibilityElement(children: .combine)
  }
}
