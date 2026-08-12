// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

enum NEChatCommonPresentation {
  static func commonTheme(for token: ChatThemeToken) -> NECommonThemeToken {
    var commonToken = token.styleMode == .fun ? NECommonThemeToken.fun : NECommonThemeToken.normal
    commonToken.palette = NECommonThemePalette(
      pageBackground: token.pageBackground,
      rowBackground: token.inputBackground,
      elevatedBackground: token.inputBackground,
      primaryText: token.incomingTextColor,
      secondaryText: token.secondaryTextColor,
      tertiaryText: NEUIKitSwiftUIStyle.ColorToken.lightText,
      accent: token.accentColor,
      destructive: token.warningColor,
      warning: token.warningColor,
      separator: token.dividerColor,
      disabled: token.dividerColor.opacity(0.82)
    )
    commonToken.button = NECommonButtonToken(
      primaryBackground: token.accentColor,
      primaryForeground: token.primaryButtonTextColor,
      secondaryBackground: token.panelItemBackground,
      secondaryForeground: token.accentColor,
      destructiveBackground: token.warningColor,
      destructiveForeground: token.primaryButtonTextColor,
      disabledBackground: token.dividerColor,
      disabledForeground: token.secondaryTextColor,
      cornerRadius: token.controlCornerRadius
    )
    commonToken.overlay = NECommonOverlayToken(
      toastBackground: token.secondaryTextColor.opacity(0.95),
      toastForeground: token.primaryButtonTextColor,
      scrim: token.styleMode == .normal
        ? Color.black.opacity(0.28)
        : Color.black.opacity(0.24),
      cornerRadius: token.controlCornerRadius
    )
    commonToken.avatar = NECommonAvatarToken(
      size: token.avatarSize,
      cornerRadius: token.avatarSize / 2,
      background: token.avatarBackgroundColor,
      foreground: token.avatarForegroundColor
    )
    commonToken.badge = NECommonBadgeToken(
      background: token.accentColor,
      foreground: token.primaryButtonTextColor,
      minSize: 18
    )
    return commonToken
  }

  private static func rowTheme(for token: ChatThemeToken) -> NECommonThemeToken {
    var commonToken = commonTheme(for: token)
    commonToken.palette.rowBackground = token.panelItemBackground
    commonToken.palette.elevatedBackground = token.panelItemBackground
    commonToken.palette.secondaryText = NEUIKitSwiftUIStyle.ColorToken.lightText
    commonToken.palette.tertiaryText = NEUIKitSwiftUIStyle.ColorToken.lightText
    commonToken.palette.separator = NEUIKitSwiftUIStyle.ColorToken.greyLine
    return commonToken
  }

  private static func inputTheme(for token: ChatThemeToken,
                                 background: Color? = nil) -> NECommonThemeToken {
    var commonToken = commonTheme(for: token)
    commonToken.palette.rowBackground = background ?? token.inputBackground
    commonToken.palette.elevatedBackground = background ?? token.inputBackground
    return commonToken
  }

  static func navigationBar(title: String,
                            token: ChatThemeToken,
                            backAction: (() -> Void)?,
                            trailingAction: NECommonNavigationAction? = nil,
                            onTrailingAction: (() -> Void)? = nil,
                            trailingActionEnabled: Bool = true,
                            backgroundColor: Color? = nil,
                            showsSeparator: Bool = true) -> some View {
    NECommonNavigationBarView(
      title: title,
      backAction: backAction,
      trailingAction: trailingAction,
      onTrailingAction: onTrailingAction,
      trailingActionEnabled: trailingActionEnabled,
      backgroundColor: backgroundColor ?? token.navigationBackground,
      separatorColor: token.dividerColor,
      showsSeparator: showsSeparator
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func navigationBar<Trailing: View>(title: String,
                                            token: ChatThemeToken,
                                            backAction: (() -> Void)?,
                                            trailingWidth: CGFloat,
                                            backgroundColor: Color? = nil,
                                            showsSeparator: Bool = true,
                                            @ViewBuilder trailingContent: @escaping () -> Trailing) -> some View {
    NECommonNavigationBarView(
      title: title,
      backAction: backAction,
      trailingWidth: trailingWidth,
      backgroundColor: backgroundColor ?? token.navigationBackground,
      separatorColor: token.dividerColor,
      showsSeparator: showsSeparator,
      trailingContent: trailingContent
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func textNavigationAction(id: String,
                                   title: String) -> NECommonNavigationAction {
    NECommonNavigationAction(id: id, title: title)
  }

  static func imageNavigationAction(id: String,
                                    title: String,
                                    imageName: String,
                                    bundle: Bundle? = NEChatUIKitSwiftUIBundle.bundle,
                                    imageSize: CGSize = CGSize(width: 20, height: 20)) -> NECommonNavigationAction {
    NECommonNavigationAction(
      id: id,
      title: title,
      imageName: imageName,
      imageBundle: bundle,
      imageSize: imageSize
    )
  }

  static func loadingView(token: ChatThemeToken) -> some View {
    NECommonLoadingView(
      title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading")
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func inlineLoadingView(token: ChatThemeToken,
                                title: String? = nil) -> some View {
    NECommonInlineLoadingView(title: title)
      .neCommonTheme(commonTheme(for: token))
  }

  static func linearProgress(value: Double,
                             token: ChatThemeToken,
                             height: CGFloat = 4,
                             foregroundColor: Color? = nil,
                             backgroundColor: Color? = nil,
                             accessibilityLabel: String? = nil) -> some View {
    NECommonLinearProgressView(value: value,
                               height: height,
                               foregroundColor: foregroundColor,
                               backgroundColor: backgroundColor,
                               accessibilityLabel: accessibilityLabel)
      .neCommonTheme(commonTheme(for: token))
  }

  static func avatarView(imageURL: URL? = nil,
                         initials: String,
                         token: ChatThemeToken,
                         size: CGFloat? = nil,
                         cornerRadius: CGFloat? = nil,
                         fallbackSystemImageName: String? = nil,
                         hashID: String? = nil) -> some View {
    NECommonAvatarView(imageURL: imageURL,
                       initials: initials,
                       size: size,
                       cornerRadius: cornerRadius,
                       fallbackSystemImageName: fallbackSystemImageName,
                       hashID: hashID)
      .neCommonTheme(commonTheme(for: token))
  }

  static func avatarView(imageURL: URL? = nil,
                         initials: String,
                         token: ChatThemeToken,
                         size: CGFloat? = nil,
                         cornerRadius: CGFloat? = nil,
                         fallbackImageName: String,
                         fallbackRenderingMode: NECommonImageRenderingMode = .original,
                         hashID: String? = nil) -> some View {
    NECommonAvatarView(imageURL: imageURL,
                       initials: initials,
                       size: size,
                       cornerRadius: cornerRadius,
                       fallbackImageName: fallbackImageName,
                       fallbackBundle: NEChatUIKitSwiftUIBundle.bundle,
                       fallbackRenderingMode: fallbackRenderingMode,
                       hashID: hashID)
      .neCommonTheme(commonTheme(for: token))
  }

  static func separator(token: ChatThemeToken,
                        leadingInset: CGFloat = 0,
                        height: CGFloat = 0.5,
                        opacity: Double = 1) -> some View {
    NECommonSeparatorView(height: height, opacity: opacity)
      .padding(.leading, leadingInset)
      .neCommonTheme(commonTheme(for: token))
  }

  static func settingSeparator(token: ChatThemeToken,
                               leadingInset: CGFloat = 0,
                               height: CGFloat = 0.5,
                               opacity: Double = 1) -> some View {
    NECommonSeparatorView(height: height, opacity: opacity)
      .padding(.leading, leadingInset)
      .neCommonTheme(rowTheme(for: token))
  }

  static func selectionIndicator(isSelected: Bool,
                                 isEnabled: Bool = true,
                                 token: ChatThemeToken,
                                 size: CGFloat = 20) -> some View {
    NECommonSelectionIndicatorView(
      isSelected: isSelected,
      isEnabled: isEnabled,
      size: size
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func badgeView(count: Int,
                        token: ChatThemeToken,
                        showZero: Bool = false,
                        minSize: CGFloat = 20,
                        horizontalPadding: CGFloat = 6,
                        verticalPadding: CGFloat = 0) -> some View {
    NECommonBadgeView(count: count,
                      showZero: showZero,
                      minSize: minSize,
                      horizontalPadding: horizontalPadding,
                      verticalPadding: verticalPadding)
      .neCommonTheme(commonTheme(for: token))
  }

  static func badgeView(text: String,
                        token: ChatThemeToken,
                        minSize: CGFloat = 18,
                        horizontalPadding: CGFloat = 6,
                        verticalPadding: CGFloat = 0) -> some View {
    NECommonBadgeView(text: text,
                      minSize: minSize,
                      horizontalPadding: horizontalPadding,
                      verticalPadding: verticalPadding)
      .neCommonTheme(commonTheme(for: token))
  }

  static func characterCounter(count: Int,
                               limit: Int?,
                               token: ChatThemeToken,
                               isWarning: Bool = false,
                               font: Font? = .caption2) -> some View {
    NECommonCharacterCounterView(count: count,
                                 limit: limit,
                                 isWarning: isWarning,
                                 font: font)
      .neCommonTheme(commonTheme(for: token))
  }

  static func chevron(token: ChatThemeToken,
                      isEnabled: Bool = true,
                      font: Font? = .footnote.weight(.semibold)) -> some View {
    NECommonChevronView(isEnabled: isEnabled, font: font)
      .neCommonTheme(commonTheme(for: token))
  }

  static func iconButton(systemImageName: String,
                         accessibilityLabel: String,
                         token: ChatThemeToken,
                         isEnabled: Bool = true,
                         size: CGSize = CGSize(width: 24, height: 24),
                         font: Font? = nil,
                         foregroundColor: Color? = nil,
                         action: @escaping () -> Void) -> some View {
    NECommonIconButton(systemImageName: systemImageName,
                       accessibilityLabel: accessibilityLabel,
                       isEnabled: isEnabled,
                       size: size,
                       font: font,
                       foregroundColor: foregroundColor,
                       action: action)
      .neCommonTheme(commonTheme(for: token))
  }

  static func iconButton(imageName: String,
                         bundle: Bundle? = NEChatUIKitSwiftUIBundle.bundle,
                         accessibilityLabel: String,
                         token: ChatThemeToken,
                         renderingMode: NECommonImageRenderingMode = .template,
                         isEnabled: Bool = true,
                         size: CGSize = CGSize(width: 24, height: 24),
                         font: Font? = nil,
                         foregroundColor: Color? = nil,
                         action: @escaping () -> Void) -> some View {
    NECommonIconButton(imageName: imageName,
                       bundle: bundle,
                       renderingMode: renderingMode,
                       accessibilityLabel: accessibilityLabel,
                       isEnabled: isEnabled,
                       size: size,
                       font: font,
                       foregroundColor: foregroundColor,
                       action: action)
      .neCommonTheme(commonTheme(for: token))
  }

  static func commonIconButton(imageName: String,
                               accessibilityLabel: String,
                               token: ChatThemeToken,
                               renderingMode: NECommonImageRenderingMode = .template,
                               isEnabled: Bool = true,
                               size: CGSize = CGSize(width: 24, height: 24),
                               font: Font? = nil,
                               foregroundColor: Color? = nil,
                               action: @escaping () -> Void) -> some View {
    NECommonIconButton(imageName: imageName,
                       bundle: NECommonUIKitSwiftUIBundle.bundle,
                       renderingMode: renderingMode,
                       accessibilityLabel: accessibilityLabel,
                       isEnabled: isEnabled,
                       size: size,
                       font: font,
                       foregroundColor: foregroundColor,
                       action: action)
      .neCommonTheme(commonTheme(for: token))
  }

  static func iconView(systemImageName: String,
                       token: ChatThemeToken,
                       isEnabled: Bool = true,
                       size: CGSize? = nil,
                       font: Font? = nil,
                       foregroundColor: Color? = nil,
                       accessibilityLabel: String? = nil) -> some View {
    NECommonIconView(systemImageName: systemImageName,
                     isEnabled: isEnabled,
                     size: size,
                     font: font,
                     foregroundColor: foregroundColor,
                     accessibilityLabel: accessibilityLabel)
      .neCommonTheme(commonTheme(for: token))
  }

  /// Icon view that loads an image from the asset catalog by name (instead of SF Symbol).
  static func iconView(imageName: String,
                       token: ChatThemeToken,
                       renderingMode: NECommonImageRenderingMode = .template,
                       isEnabled: Bool = true,
                       size: CGSize? = nil,
                       font: Font? = nil,
                       foregroundColor: Color? = nil,
                       accessibilityLabel: String? = nil) -> some View {
    NECommonIconView(imageName: imageName,
                     bundle: NEChatUIKitSwiftUIBundle.bundle,
                     renderingMode: renderingMode,
                     isEnabled: isEnabled,
                     size: size,
                     font: font,
                     foregroundColor: foregroundColor,
                     accessibilityLabel: accessibilityLabel)
      .neCommonTheme(commonTheme(for: token))
  }

  static func iconView(resource: NECommonImageResource,
                       token: ChatThemeToken,
                       isEnabled: Bool = true,
                       size: CGSize? = nil,
                       font: Font? = nil,
                       foregroundColor: Color? = nil,
                       accessibilityLabel: String? = nil) -> some View {
    NECommonIconView(imageName: resource.imageName,
                     bundle: resource.bundle,
                     renderingMode: resource.renderingMode,
                     isEnabled: isEnabled,
                     size: size,
                     font: font,
                     foregroundColor: foregroundColor,
                     accessibilityLabel: accessibilityLabel)
      .neCommonTheme(commonTheme(for: token))
  }

  static func commonIconView(imageName: String,
                             token: ChatThemeToken,
                             renderingMode: NECommonImageRenderingMode = .template,
                             isEnabled: Bool = true,
                             size: CGSize? = nil,
                             font: Font? = nil,
                             foregroundColor: Color? = nil,
                             accessibilityLabel: String? = nil) -> some View {
    NECommonIconView(imageName: imageName,
                     bundle: NECommonUIKitSwiftUIBundle.bundle,
                     renderingMode: renderingMode,
                     isEnabled: isEnabled,
                     size: size,
                     font: font,
                     foregroundColor: foregroundColor,
                     accessibilityLabel: accessibilityLabel)
      .neCommonTheme(commonTheme(for: token))
  }

  static func actionButton(title: String,
                           token: ChatThemeToken,
                           systemImageName: String? = nil,
                           style: NECommonActionButtonStyle = .primary,
                           isEnabled: Bool = true,
                           isLoading: Bool = false,
                           loadingTitle: String? = nil,
                           minHeight: CGFloat? = nil,
                           action: @escaping () -> Void) -> some View {
    NECommonActionButton(title: title,
                         systemImageName: systemImageName,
                         style: style,
                         isEnabled: isEnabled,
                         isLoading: isLoading,
                         loadingTitle: loadingTitle,
                         minHeight: minHeight,
                         action: action)
      .neCommonTheme(commonTheme(for: token))
  }

  static func actionButton(title: String,
                           token: ChatThemeToken,
                           imageName: String,
                           bundle: Bundle? = NEChatUIKitSwiftUIBundle.bundle,
                           renderingMode: NECommonImageRenderingMode = .template,
                           style: NECommonActionButtonStyle = .primary,
                           isEnabled: Bool = true,
                           isLoading: Bool = false,
                           loadingTitle: String? = nil,
                           minHeight: CGFloat? = nil,
                           action: @escaping () -> Void) -> some View {
    NECommonActionButton(title: title,
                         imageName: imageName,
                         bundle: bundle,
                         renderingMode: renderingMode,
                         style: style,
                         isEnabled: isEnabled,
                         isLoading: isLoading,
                         loadingTitle: loadingTitle,
                         minHeight: minHeight,
                         action: action)
      .neCommonTheme(commonTheme(for: token))
  }

  static func segmentedControl<ID: Hashable>(options: [NECommonSegmentedOption<ID>],
                                             selection: Binding<ID>,
                                             token: ChatThemeToken,
                                             height: CGFloat = 32,
                                             spacing: CGFloat = 8,
                                             allowsHorizontalScroll: Bool = true) -> some View {
    NECommonSegmentedControlView(options: options,
                                 selection: selection,
                                 height: height,
                                 spacing: spacing,
                                 allowsHorizontalScroll: allowsHorizontalScroll)
      .neCommonTheme(commonTheme(for: token))
  }

  static func inlineEmptyView(title: String,
                              token: ChatThemeToken,
                              systemImageName: String? = nil,
                              message: String? = nil) -> some View {
    NECommonInlineEmptyView(title: title,
                            systemImageName: systemImageName,
                            message: message)
      .neCommonTheme(commonTheme(for: token))
  }

  static func inlineEmptyView(title: String,
                              token: ChatThemeToken,
                              imageKind: NECommonEmptyImageKind,
                              message: String? = nil) -> some View {
    NECommonInlineEmptyView(title: title,
                            imageKind: imageKind,
                            message: message)
      .neCommonTheme(commonTheme(for: token))
  }

  static func inlineEmptyView(title: String,
                              token: ChatThemeToken,
                              imageName: String,
                              bundle: Bundle? = NEChatUIKitSwiftUIBundle.bundle,
                              message: String? = nil) -> some View {
    NECommonInlineEmptyView(title: title,
                            imageName: imageName,
                            bundle: bundle,
                            renderingMode: .original,
                            message: message)
      .neCommonTheme(commonTheme(for: token))
  }

  static func mediaPlaceholderImageName(token: ChatThemeToken) -> String {
    NECommonPlaceholderImage.mediaImageName(styleMode: commonStyleMode(for: token))
  }

  static func searchField<Trailing: View>(text: Binding<String>,
                                          placeholder: String,
                                          token: ChatThemeToken,
                                          height: CGFloat = 34,
                                          onSubmit: (() -> Void)? = nil,
                                          @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
    NECommonSearchFieldView(text: text,
                            placeholder: placeholder,
                            height: height,
                            onSubmit: onSubmit,
                            trailingContent: trailing)
      .neCommonTheme(inputTheme(for: token, background: token.searchFieldBackground))
  }

  static func searchField(text: Binding<String>,
                          placeholder: String,
                          token: ChatThemeToken,
                          height: CGFloat = 34,
                          onSubmit: (() -> Void)? = nil) -> some View {
    NECommonSearchFieldView(text: text,
                            placeholder: placeholder,
                            height: height,
                            onSubmit: onSubmit)
      .neCommonTheme(inputTheme(for: token, background: token.searchFieldBackground))
  }

  static func formTextField(title: String? = nil,
                            text: Binding<String>,
                            placeholder: String,
                            token: ChatThemeToken,
                            error: String? = nil,
                            isEnabled: Bool = true,
                            submitLabel: SubmitLabel = .done,
                            axis: Axis = .horizontal,
                            horizontalPadding: CGFloat = 14,
                            verticalPadding: CGFloat = 10,
                            minHeight: CGFloat? = nil,
                            backgroundCornerRadius: CGFloat? = nil,
                            characterLimit: Int? = nil,
                            onSubmit: (() -> Void)? = nil) -> some View {
    NECommonFormTextFieldView(title: title,
                              text: text,
                              placeholder: placeholder,
                              error: error,
                              isEnabled: isEnabled,
                              submitLabel: submitLabel,
                              axis: axis,
                              horizontalPadding: horizontalPadding,
                              verticalPadding: verticalPadding,
                              minHeight: minHeight,
                              backgroundCornerRadius: backgroundCornerRadius,
                              characterLimit: characterLimit,
                              onSubmit: onSubmit)
      .neCommonTheme(inputTheme(for: token, background: token.inputFieldBackground))
  }

  static func settingRow<Accessory: View>(title: String,
                                          value: String? = nil,
                                          subtitle: String? = nil,
                                          token: ChatThemeToken,
                                          isEnabled: Bool = true,
                                          minHeight: CGFloat = 50,
                                          leadingPadding: CGFloat? = nil,
                                          trailingPadding: CGFloat? = nil,
                                          verticalPadding: CGFloat? = nil,
                                          titleLineLimit: Int = 2,
                                          subtitleLineLimit: Int = 2,
                                          action: (() -> Void)? = nil,
                                          @ViewBuilder accessory: @escaping () -> Accessory) -> some View {
    NECommonSettingRowView(title: title,
                           subtitle: subtitle,
                           value: value,
                           isEnabled: isEnabled,
                           minHeight: minHeight,
                           leadingPadding: leadingPadding,
                           trailingPadding: trailingPadding,
                           verticalPadding: verticalPadding,
                           titleLineLimit: titleLineLimit,
                           subtitleLineLimit: subtitleLineLimit,
                           action: action,
                           accessory: accessory)
      .neCommonTheme(rowTheme(for: token))
  }

  static func settingRow(title: String,
                         value: String? = nil,
                         subtitle: String? = nil,
                         token: ChatThemeToken,
                         isEnabled: Bool = true,
                         minHeight: CGFloat = 50,
                         leadingPadding: CGFloat? = nil,
                         trailingPadding: CGFloat? = nil,
                         verticalPadding: CGFloat? = nil,
                         titleLineLimit: Int = 2,
                         subtitleLineLimit: Int = 2,
                         action: (() -> Void)? = nil) -> some View {
    settingRow(title: title,
               value: value,
               subtitle: subtitle,
               token: token,
               isEnabled: isEnabled,
               minHeight: minHeight,
               leadingPadding: leadingPadding,
               trailingPadding: trailingPadding,
               verticalPadding: verticalPadding,
               titleLineLimit: titleLineLimit,
               subtitleLineLimit: subtitleLineLimit,
               action: action) {
      NECommonChevronView(isEnabled: isEnabled)
    }
  }

  static func settingToggleRow(title: String,
                               subtitle: String? = nil,
                               isOn: Binding<Bool>,
                               token: ChatThemeToken,
                               isEnabled: Bool = true,
                               minHeight: CGFloat = 50,
                               leadingPadding: CGFloat? = nil,
                               trailingPadding: CGFloat? = nil,
                               verticalPadding: CGFloat? = nil,
                               titleLineLimit: Int = 2,
                               subtitleLineLimit: Int = 2) -> some View {
    NECommonSettingToggleRowView(title: title,
                                 subtitle: subtitle,
                                 isOn: isOn,
                                 isEnabled: isEnabled,
                                 minHeight: minHeight,
                                 leadingPadding: leadingPadding,
                                 trailingPadding: trailingPadding,
                                 verticalPadding: verticalPadding,
                                 titleLineLimit: titleLineLimit,
                                 subtitleLineLimit: subtitleLineLimit)
      .neCommonTheme(rowTheme(for: token))
  }

  static func emptyView(token: ChatThemeToken,
                        titleKey: String = "chat_empty",
                        fallbackTitle: String? = nil,
                        imageKind: NECommonEmptyImageKind = .generic) -> some View {
    NECommonEmptyStateView(
      state: NECommonEmptyState(
        titleKey: titleKey,
        fallbackTitle: fallbackTitle ?? NEChatUIKitSwiftUIBundle.localized(titleKey, value: "No messages"),
        imageKind: imageKind
      )
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func errorView(_ error: NEChatKitErrorState,
                        token: ChatThemeToken,
                        retry: (() -> Void)? = nil) -> some View {
    errorView(message: error.message, token: token, retry: retry)
  }

  static func errorView(message: String,
                        token: ChatThemeToken,
                        retry: (() -> Void)? = nil) -> some View {
    NECommonErrorStateView(
      state: NECommonErrorState(
        textKey: "chat_error",
        fallbackText: message,
        severity: .warning,
        retryable: retry != nil
      ),
      retry: retry
    )
    .neCommonTheme(commonTheme(for: token))
  }

  private static func commonStyleMode(for token: ChatThemeToken) -> NECommonStyleMode {
    token.styleMode == .fun ? .fun : .normal
  }

  static func blockingLoading(id: String,
                              isPresented: Bool,
                              fallbackText: String? = nil,
                              showsScrim: Bool = true,
                              blocksInteraction: Bool = true) -> NECommonBlockingLoadingState? {
    guard isPresented else {
      return nil
    }
    return NECommonBlockingLoadingState(
      id: id,
      textKey: nil,
      fallbackText: fallbackText ?? NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"),
      showsScrim: showsScrim,
      blocksInteraction: blocksInteraction
    )
  }
}

private struct OptionalForegroundColorModifier: ViewModifier {
  let color: Color?

  func body(content: Content) -> some View {
    if let color {
      content.foregroundColor(color)
    } else {
      content
    }
  }
}

private struct OptionalAccessibilityLabelModifier: ViewModifier {
  let label: String?

  func body(content: Content) -> some View {
    if let label {
      content.accessibilityLabel(label)
    } else {
      content
    }
  }
}
