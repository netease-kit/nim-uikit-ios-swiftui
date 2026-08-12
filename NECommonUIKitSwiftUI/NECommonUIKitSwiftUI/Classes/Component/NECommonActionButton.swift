// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum NECommonActionButtonStyle: Equatable {
  case primary
  case secondary
  case destructive
}

public struct NECommonActionButton: View {
  @Environment(\.neCommonTheme) private var token
  private let title: String
  private let systemImageName: String?
  private let imageResource: NECommonImageResource?
  private let style: NECommonActionButtonStyle
  private let isEnabled: Bool
  private let isLoading: Bool
  private let loadingTitle: String?
  private let minHeight: CGFloat?
  private let action: () -> Void

  public init(title: String,
              systemImageName: String? = nil,
              style: NECommonActionButtonStyle = .primary,
              isEnabled: Bool = true,
              isLoading: Bool = false,
              loadingTitle: String? = nil,
              minHeight: CGFloat? = nil,
              action: @escaping () -> Void) {
    self.title = title
    self.systemImageName = systemImageName
    imageResource = nil
    self.style = style
    self.isEnabled = isEnabled
    self.isLoading = isLoading
    self.loadingTitle = loadingTitle
    self.minHeight = minHeight
    self.action = action
  }

  public init(title: String,
              imageName: String,
              bundle: Bundle? = nil,
              renderingMode: NECommonImageRenderingMode = .template,
              style: NECommonActionButtonStyle = .primary,
              isEnabled: Bool = true,
              isLoading: Bool = false,
              loadingTitle: String? = nil,
              minHeight: CGFloat? = nil,
              action: @escaping () -> Void) {
    self.title = title
    systemImageName = nil
    imageResource = NECommonImageResource(imageName: imageName, bundle: bundle, renderingMode: renderingMode)
    self.style = style
    self.isEnabled = isEnabled
    self.isLoading = isLoading
    self.loadingTitle = loadingTitle
    self.minHeight = minHeight
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      content
        .font(token.typography.body)
        .fontWeight(.semibold)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: minHeight ?? token.button.minHeight)
        .padding(.horizontal, token.spacing.medium)
        .background(background)
        .foregroundColor(foreground)
        .clipShape(RoundedRectangle(cornerRadius: token.button.cornerRadius))
    }
    .disabled(!isEnabled || isLoading)
    .opacity(isEnabled ? 1 : 0.85)
  }

  @ViewBuilder
  private var content: some View {
    if isLoading {
      HStack(spacing: token.spacing.small) {
        ProgressView()
          .progressViewStyle(.circular)
          .controlSize(.small)
          .tint(foreground)
        Text(loadingTitle ?? title)
      }
    } else if let systemImageName {
      HStack(spacing: token.spacing.small) {
        NECommonFallbackIconView(name: systemImageName)
          .frame(width: 16, height: 16)
        Text(title)
      }
    } else if let imageResource {
      HStack(spacing: token.spacing.small) {
        let image = Image(imageResource.imageName, bundle: imageResource.bundle)
        if imageResource.renderingMode == .template {
          image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        } else {
          image
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
        Text(title)
      }
    } else {
      Text(title)
    }
  }

  private var background: Color {
    guard isEnabled else {
      return token.button.disabledBackground
    }
    switch style {
    case .primary:
      return token.button.primaryBackground
    case .secondary:
      return token.button.secondaryBackground
    case .destructive:
      return token.button.destructiveBackground
    }
  }

  private var foreground: Color {
    guard isEnabled else {
      return token.button.disabledForeground
    }
    switch style {
    case .primary:
      return token.button.primaryForeground
    case .secondary:
      return token.button.secondaryForeground
    case .destructive:
      return token.button.destructiveForeground
    }
  }
}
