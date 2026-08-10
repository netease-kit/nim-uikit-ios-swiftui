// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

enum NETeamCommonPresentation {
  static func commonTheme(for token: NETeamThemeToken) -> NECommonThemeToken {
    var commonToken = token.styleMode == .fun ? NECommonThemeToken.fun : NECommonThemeToken.normal
    commonToken.palette = NECommonThemePalette(
      pageBackground: token.pageBackground,
      rowBackground: token.rowBackground,
      elevatedBackground: token.rowBackground,
      primaryText: token.primaryText,
      secondaryText: token.secondaryText,
      tertiaryText: NEUIKitSwiftUIStyle.ColorToken.lightText,
      accent: token.accent,
      destructive: token.destructive,
      warning: token.destructive,
      separator: token.separator,
      disabled: token.separator.opacity(0.82)
    )
    commonToken.typography = NECommonTypography(
      title: NEUIKitSwiftUIStyle.FontToken.navTitle,
      headline: token.titleFont,
      body: token.titleFont,
      footnote: token.subtitleFont,
      caption: token.detailFont
    )
    commonToken.button = NECommonButtonToken(
      primaryBackground: token.accent,
      primaryForeground: .white,
      secondaryBackground: token.rowBackground,
      secondaryForeground: token.accent,
      destructiveBackground: token.destructive,
      destructiveForeground: .white,
      disabledBackground: token.separator,
      disabledForeground: token.secondaryText
    )
    commonToken.overlay = NECommonOverlayToken(
      toastBackground: token.secondaryText.opacity(0.95),
      toastForeground: .white,
      scrim: Color.black.opacity(0.28)
    )
    commonToken.avatar = NECommonAvatarToken(
      cornerRadius: 8,
      background: NEUIKitSwiftUIStyle.ColorToken.avatarBackground,
      foreground: .white
    )
    commonToken.badge = NECommonBadgeToken(
      background: NEUIKitSwiftUIStyle.ColorToken.red,
      foreground: .white,
      minSize: 18
    )
    return commonToken
  }

  static func searchTheme(for token: NETeamThemeToken) -> NECommonThemeToken {
    var commonToken = commonTheme(for: token)
    commonToken.palette.rowBackground = token.searchBackground
    commonToken.palette.elevatedBackground = token.searchBackground
    return commonToken
  }

  private static func rowTheme(for token: NETeamThemeToken) -> NECommonThemeToken {
    var commonToken = commonTheme(for: token)
    commonToken.palette.secondaryText = NEUIKitSwiftUIStyle.ColorToken.lightText
    commonToken.palette.tertiaryText = NEUIKitSwiftUIStyle.ColorToken.lightText
    commonToken.palette.separator = NEUIKitSwiftUIStyle.ColorToken.greyLine
    return commonToken
  }

  static func navigationBar(title: String,
                            token: NETeamThemeToken,
                            backAction: (() -> Void)?,
                            trailingAction: NECommonNavigationAction? = nil,
                            onTrailingAction: (() -> Void)? = nil,
                            trailingActionEnabled: Bool = true,
                            backgroundColor: Color? = nil,
                            showsSeparator: Bool = false) -> some View {
    NECommonNavigationBarView(
      title: title,
      backAction: backAction,
      trailingAction: trailingAction,
      onTrailingAction: onTrailingAction,
      trailingActionEnabled: trailingActionEnabled,
      backgroundColor: backgroundColor ?? navigationBackground(for: token),
      separatorColor: token.separator,
      showsSeparator: showsSeparator
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func navigationBar<Trailing: View>(title: String,
                                            token: NETeamThemeToken,
                                            backAction: (() -> Void)?,
                                            trailingWidth: CGFloat,
                                            showsSeparator: Bool = false,
                                            @ViewBuilder trailingContent: @escaping () -> Trailing) -> some View {
    NECommonNavigationBarView(
      title: title,
      backAction: backAction,
      trailingWidth: trailingWidth,
      backgroundColor: navigationBackground(for: token),
      separatorColor: token.separator,
      showsSeparator: showsSeparator,
      trailingContent: trailingContent
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func textNavigationAction(id: String,
                                   title: String) -> NECommonNavigationAction {
    NECommonNavigationAction(id: id, title: title)
  }

  private static func navigationBackground(for token: NETeamThemeToken) -> Color {
    token.styleMode == .fun ? token.rowBackground : token.pageBackground
  }

  static func imageNavigationAction(id: String,
                                    title: String,
                                    imageName: String,
                                    bundle: Bundle? = NETeamUIKitSwiftUIBundle.bundle,
                                    imageSize: CGSize = CGSize(width: 20, height: 20)) -> NECommonNavigationAction {
    NECommonNavigationAction(
      id: id,
      title: title,
      imageName: imageName,
      imageBundle: bundle,
      imageSize: imageSize
    )
  }

  static func toast(_ toast: NETeamToastState?) -> NECommonToastState? {
    guard let toast else {
      return nil
    }
    return NECommonToastState(
      id: toast.id,
      fallbackText: toast.message,
      level: commonToastLevel(for: toast.style)
    )
  }

  static func blockingLoading(id: String, isPresented: Bool) -> NECommonBlockingLoadingState? {
    guard isPresented else {
      return nil
    }
    return NECommonBlockingLoadingState(
      id: id,
      textKey: nil,
      fallbackText: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.loading, value: "Loading")
    )
  }

  static func loadingView() -> NECommonLoadingView {
    NECommonLoadingView(
      title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.loading, value: "Loading")
    )
  }

  static func inlineLoadingView(title: String? = nil) -> NECommonInlineLoadingView {
    NECommonInlineLoadingView(title: title)
  }

  static func separator(token: NETeamThemeToken,
                        leadingInset: CGFloat = 16,
                        height: CGFloat = 1,
                        opacity: Double = 1) -> some View {
    NECommonSeparatorView(height: height, opacity: opacity)
      .padding(.leading, leadingInset)
      .neCommonTheme(commonTheme(for: token))
  }

  static func settingSeparator(token: NETeamThemeToken,
                               leadingInset: CGFloat = 16,
                               height: CGFloat = 1,
                               opacity: Double = 1) -> some View {
    NECommonSeparatorView(height: height, opacity: opacity)
      .padding(.leading, leadingInset)
      .neCommonTheme(rowTheme(for: token))
  }

  static func settingRow<Accessory: View>(title: String,
                                          value: String? = nil,
                                          subtitle: String? = nil,
                                          token: NETeamThemeToken,
                                          isEnabled: Bool = true,
                                          minHeight: CGFloat? = nil,
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
                           minHeight: minHeight ?? token.rowHeight,
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
                         token: NETeamThemeToken,
                         isEnabled: Bool = true,
                         minHeight: CGFloat? = nil,
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
      EmptyView()
    }
  }

  static func settingToggleRow(title: String,
                               subtitle: String? = nil,
                               isOn: Binding<Bool>,
                               token: NETeamThemeToken,
                               isEnabled: Bool = true,
                               minHeight: CGFloat? = nil,
                               leadingPadding: CGFloat? = nil,
                               trailingPadding: CGFloat? = nil,
                               verticalPadding: CGFloat? = nil,
                               titleLineLimit: Int = 2,
                               subtitleLineLimit: Int = 2) -> some View {
    NECommonSettingToggleRowView(title: title,
                                 subtitle: subtitle,
                                 isOn: isOn,
                                 isEnabled: isEnabled,
                                 minHeight: minHeight ?? token.rowHeight,
                                 leadingPadding: leadingPadding,
                                 trailingPadding: trailingPadding,
                                 verticalPadding: verticalPadding,
                                 titleLineLimit: titleLineLimit,
                                 subtitleLineLimit: subtitleLineLimit)
      .neCommonTheme(rowTheme(for: token))
  }

  static func selectionIndicator(isSelected: Bool,
                                 isEnabled: Bool = true,
                                 token: NETeamThemeToken,
                                 size: CGFloat = 20) -> some View {
    NECommonSelectionIndicatorView(
      isSelected: isSelected,
      isEnabled: isEnabled,
      size: size
    )
    .neCommonTheme(commonTheme(for: token))
  }

  static func badgeView(text: String,
                        token: NETeamThemeToken,
                        minSize: CGFloat = 18,
                        horizontalPadding: CGFloat = 5,
                        verticalPadding: CGFloat = 2,
                        background: Color? = nil,
                        foreground: Color? = nil) -> some View {
    NECommonBadgeView(text: text,
                      minSize: minSize,
                      horizontalPadding: horizontalPadding,
                      verticalPadding: verticalPadding,
                      background: background,
                      foreground: foreground)
      .neCommonTheme(commonTheme(for: token))
  }

  static func characterCounter(count: Int,
                               limit: Int?,
                               token: NETeamThemeToken,
                               isWarning: Bool = false,
                               font: Font? = .system(size: 12)) -> some View {
    NECommonCharacterCounterView(count: count,
                                 limit: limit,
                                 isWarning: isWarning,
                                 font: font)
      .neCommonTheme(commonTheme(for: token))
  }

  static func chevron(token: NETeamThemeToken,
                      isEnabled: Bool = true,
                      font: Font? = .system(size: 12, weight: .semibold)) -> some View {
    NECommonChevronView(isEnabled: isEnabled, font: font)
      .neCommonTheme(commonTheme(for: token))
  }

  static func iconButton(systemImageName: String,
                         accessibilityLabel: String,
                         token: NETeamThemeToken,
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
                         accessibilityLabel: String,
                         token: NETeamThemeToken,
                         renderingMode: NECommonImageRenderingMode = .template,
                         isEnabled: Bool = true,
                         size: CGSize = CGSize(width: 24, height: 24),
                         font: Font? = nil,
                         foregroundColor: Color? = nil,
                         action: @escaping () -> Void) -> some View {
    NECommonIconButton(imageName: imageName,
                       bundle: NETeamUIKitSwiftUIBundle.bundle,
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
                       token: NETeamThemeToken,
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

  static func iconView(imageName: String,
                       token: NETeamThemeToken,
                       bundle: Bundle? = NETeamUIKitSwiftUIBundle.bundle,
                       renderingMode: NECommonImageRenderingMode = .template,
                       isEnabled: Bool = true,
                       size: CGSize? = nil,
                       font: Font? = nil,
                       foregroundColor: Color? = nil,
                       accessibilityLabel: String? = nil) -> some View {
    NECommonIconView(imageName: imageName,
                     bundle: bundle,
                     renderingMode: renderingMode,
                     isEnabled: isEnabled,
                     size: size,
                     font: font,
                     foregroundColor: foregroundColor,
                     accessibilityLabel: accessibilityLabel)
      .neCommonTheme(commonTheme(for: token))
  }

  static func actionButton(title: String,
                           token: NETeamThemeToken,
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
                           token: NETeamThemeToken,
                           imageName: String,
                           renderingMode: NECommonImageRenderingMode = .template,
                           style: NECommonActionButtonStyle = .primary,
                           isEnabled: Bool = true,
                           isLoading: Bool = false,
                           loadingTitle: String? = nil,
                           minHeight: CGFloat? = nil,
                           action: @escaping () -> Void) -> some View {
    NECommonActionButton(title: title,
                         imageName: imageName,
                         bundle: NETeamUIKitSwiftUIBundle.bundle,
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
                                             token: NETeamThemeToken,
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

  static func avatarView(imageURL: URL? = nil,
                         initials: String,
                         token: NETeamThemeToken,
                         size: CGFloat = 40,
                         cornerRadius: CGFloat = 8,
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
                         token: NETeamThemeToken,
                         size: CGFloat = 40,
                         cornerRadius: CGFloat = 8,
                         fallbackImageName: String,
                         fallbackRenderingMode: NECommonImageRenderingMode = .original,
                         hashID: String? = nil) -> some View {
    NECommonAvatarView(imageURL: imageURL,
                       initials: initials,
                       size: size,
                       cornerRadius: cornerRadius,
                       fallbackImageName: fallbackImageName,
                       fallbackBundle: NETeamUIKitSwiftUIBundle.bundle,
                       fallbackRenderingMode: fallbackRenderingMode,
                       hashID: hashID)
      .neCommonTheme(commonTheme(for: token))
  }

  static func inlineEmptyView(title: String,
                              systemImageName: String,
                              token: NETeamThemeToken,
                              message: String? = nil) -> some View {
    NECommonInlineEmptyView(title: title,
                            systemImageName: systemImageName,
                            message: message)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(commonTheme(for: token))
  }

  static func inlineEmptyView(title: String,
                              imageKind: NECommonEmptyImageKind,
                              token: NETeamThemeToken,
                              message: String? = nil) -> some View {
    NECommonInlineEmptyView(title: title,
                            imageKind: imageKind,
                            message: message)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(commonTheme(for: token))
  }

  static func inlineEmptyView(title: String,
                              imageName: String,
                              token: NETeamThemeToken,
                              message: String? = nil) -> some View {
    NECommonInlineEmptyView(title: title,
                            imageName: imageName,
                            bundle: NETeamUIKitSwiftUIBundle.bundle,
                            renderingMode: .original,
                            message: message)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(commonTheme(for: token))
  }

  static func searchField<Trailing: View>(text: Binding<String>,
                                          placeholder: String,
                                          token: NETeamThemeToken,
                                          height: CGFloat = 34,
                                          onSubmit: (() -> Void)? = nil,
                                          @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
    NECommonSearchFieldView(text: text,
                            placeholder: placeholder,
                            height: height,
                            onSubmit: onSubmit,
                            trailingContent: trailing)
      .neCommonTheme(searchTheme(for: token))
  }

  static func searchField(text: Binding<String>,
                          placeholder: String,
                          token: NETeamThemeToken,
                          height: CGFloat = 34,
                          onSubmit: (() -> Void)? = nil) -> some View {
    NECommonSearchFieldView(text: text,
                            placeholder: placeholder,
                            height: height,
                            onSubmit: onSubmit)
      .neCommonTheme(searchTheme(for: token))
  }

  static func formTextField(title: String? = nil,
                            text: Binding<String>,
                            placeholder: String,
                            token: NETeamThemeToken,
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
    let commonTheme = commonTheme(for: token)
    return NECommonFormTextFieldView(title: title,
                              text: text,
                              placeholder: placeholder,
                              error: error,
                              isEnabled: isEnabled,
                              submitLabel: submitLabel,
                              axis: axis,
                              horizontalPadding: horizontalPadding,
                              verticalPadding: verticalPadding,
                              minHeight: minHeight,
                              backgroundCornerRadius: backgroundCornerRadius ?? commonTheme.radius.control,
                              characterLimit: characterLimit,
                              onSubmit: onSubmit)
      .neCommonTheme(commonTheme)
  }

  static func formTextEditor(title: String? = nil,
                             text: Binding<String>,
                             placeholder: String,
                             token: NETeamThemeToken,
                             error: String? = nil,
                             isEnabled: Bool = true,
                             horizontalPadding: CGFloat = 14,
                             verticalPadding: CGFloat = 10,
                             minHeight: CGFloat = 96,
                             backgroundCornerRadius: CGFloat? = nil,
                             characterLimit: Int? = nil) -> some View {
    let commonTheme2 = commonTheme(for: token)
    return NECommonFormTextEditorView(title: title,
                               text: text,
                               placeholder: placeholder,
                               error: error,
                               isEnabled: isEnabled,
                               horizontalPadding: horizontalPadding,
                               verticalPadding: verticalPadding,
                               minHeight: minHeight,
                               backgroundCornerRadius: backgroundCornerRadius ?? commonTheme2.radius.control,
                               characterLimit: characterLimit)
      .neCommonTheme(commonTheme2)
  }

  static func errorView(_ message: String,
                        retry: (() -> Void)? = nil) -> NECommonErrorStateView {
    NECommonErrorStateView(
      state: NECommonErrorState(
        textKey: "team_error",
        fallbackText: message,
        severity: .info,
        retryable: retry != nil
      ),
      retry: retry
    )
  }

  private static func commonToastLevel(for style: NETeamToastState.Style) -> NECommonToastLevel {
    switch style {
    case .info:
      return .info
    case .warning:
      return .warning
    case .error:
      return .error
    case .success:
      return .success
    }
  }
}
