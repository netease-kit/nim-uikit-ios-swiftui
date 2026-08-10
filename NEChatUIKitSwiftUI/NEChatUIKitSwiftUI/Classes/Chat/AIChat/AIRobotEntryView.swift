// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

@MainActor
public struct AIRobotEntryView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  @StateObject private var viewModel: AIRobotEntryViewModel
  private let token: ChatThemeToken
  private let onRoute: (NEChatSwiftUIRoute) -> Void

  public init(viewModel: AIRobotEntryViewModel? = nil,
              token: ChatThemeToken = .normal,
              onRoute: @escaping (NEChatSwiftUIRoute) -> Void) {
    _viewModel = StateObject(wrappedValue: viewModel ?? AIRobotEntryViewModel())
    self.token = token
    self.onRoute = onRoute
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: NEChatUIKitSwiftUIBundle.localized("my_ai_robot", value: "My Robot"),
        token: token,
        backAction: {
          if let chatRouteBackAction {
            chatRouteBackAction()
          } else {
            dismiss()
          }
        },
        trailingWidth: 60
      ) {
        createButton
      }

      content
    }
    .background(pageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.load()
        }
      default:
        EmptyView()
      }
    }
    .neCommonTransientOverlay(
      viewModel.toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
    .refreshable {
      viewModel.load()
    }
    .onAppear {
      viewModel.load()
    }
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var createButton: some View {
    Button {
      guard viewModel.canCreateRobot else {
        viewModel.showCreateLimitToast()
        return
      }
      onRoute(viewModel.createRoute())
    } label: {
      NEChatCommonPresentation.iconView(
        imageName: "add_black",
        token: token,
        renderingMode: .original,
        size: CGSize(width: 18, height: 18),
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("create_ai_robot", value: "Create Robot")
      )
      .frame(width: 44, height: 44, alignment: .trailing)
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .accessibilityIdentifier("id.threePoint")
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .idle, .loading, .refreshing, .loadingMore:
      Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      AIRobotEmptyView(token: token) {
        guard viewModel.canCreateRobot else {
          viewModel.showCreateLimitToast()
          return
        }
        onRoute(viewModel.createRoute())
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 50)
        .background(pageBackground)
    case .failed:
      Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loaded:
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
            AIRobotRowView(
              row: row,
              token: token,
              isLast: index == viewModel.rows.count - 1
            ) {
              onRoute(viewModel.detailRoute(for: row))
            }
          }
        }
        .padding(.bottom, 12)
      }
      .background(pageBackground)
      .scrollDismissesKeyboard(.immediately)
    }
  }

  private var pageBackground: Color {
    token.styleMode == .fun ? token.pageBackground : .white
  }
}

private struct AIRobotRowView: View {
  var row: AIRobotRowState
  var token: ChatThemeToken
  var isLast: Bool
  var onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: metrics.avatarNameSpacing) {
        AIRobotAvatarView(row: row, token: token)
        Text(row.title)
          .font(.system(size: metrics.nameFontSize))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer()
        NEChatCommonPresentation.chevron(token: token)
          .frame(width: 16, height: 16)
      }
      .frame(height: metrics.rowHeight)
      .padding(.leading, metrics.leading)
      .padding(.trailing, metrics.trailing)
      .background(Color.white)
      .overlay(alignment: .bottom) {
        if !isLast {
          Rectangle()
            .fill(metrics.separatorColor)
            .frame(height: 0.5)
            .padding(.leading, metrics.separatorLeading)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private var metrics: AIRobotListMetrics {
    AIRobotListMetrics(style: token.styleMode)
  }
}

private struct AIRobotAvatarView: View {
  var row: AIRobotRowState
  var token: ChatThemeToken

  var body: some View {
    NEChatCommonPresentation.avatarView(
      imageURL: row.avatarURL,
      initials: initials,
      token: token,
      size: metrics.avatarSize,
      cornerRadius: metrics.avatarCornerRadius,
      hashID: row.id
    )
  }

  private var initials: String {
    let source = row.title.isEmpty ? row.id : row.title
    return ChatAvatarDisplayResolver.initials(displayName: source, accountId: row.id)
  }

  private var metrics: AIRobotListMetrics {
    AIRobotListMetrics(style: token.styleMode)
  }
}

private struct AIRobotEmptyView: View {
  var token: ChatThemeToken
  var onCreate: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.2")
        .font(.system(size: 42, weight: .regular))
        .foregroundColor(token.secondaryTextColor.opacity(0.35))
        .frame(width: 96, height: 72)

      Text(NEChatUIKitSwiftUIBundle.localized("no_ai_robot", value: "No Robot, click create"))
        .font(.system(size: 14))
        .foregroundColor(token.secondaryTextColor)
        .multilineTextAlignment(.center)

      NEChatCommonPresentation.actionButton(
        title: NEChatUIKitSwiftUIBundle.localized("create_ai_robot", value: "Create Robot"),
        token: token,
        imageName: "add_black",
        renderingMode: .original,
        minHeight: 42,
        action: onCreate
      )
      .frame(maxWidth: 180)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct AIRobotListMetrics {
  var rowHeight: CGFloat
  var avatarSize: CGFloat
  var avatarCornerRadius: CGFloat
  var leading: CGFloat
  var trailing: CGFloat
  var avatarNameSpacing: CGFloat
  var nameFontSize: CGFloat
  var separatorLeading: CGFloat
  var separatorColor: Color

  init(style: ChatStyleMode) {
    switch style {
    case .fun:
      rowHeight = 74
      avatarSize = 40
      avatarCornerRadius = 4
      leading = 16
      trailing = 16
      avatarNameSpacing = 11
      nameFontSize = 17
      separatorLeading = 16
      separatorColor = Color(hex: 0xE5E5E5)
    case .normal:
      rowHeight = 60
      avatarSize = 36
      avatarCornerRadius = 18
      leading = 20
      trailing = 36
      avatarNameSpacing = 12
      nameFontSize = 14
      separatorLeading = 20
      separatorColor = NEUIKitSwiftUIStyle.ColorToken.border
    }
  }
}

public struct AIRobotRouteView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: AIRobotRouteViewModel
  private var token: ChatThemeToken
  private var onRoute: (NEChatSwiftUIRoute) -> Void
  private var onDismiss: (() -> Void)?
  private var avatarSelectionHandler: ChatAvatarSelectionHandling?
  private var configClipboardHandler: AIRobotConfigClipboardHandling?
  @State private var isDeleteConfirmPresented = false
  @State private var isRefreshTokenConfirmPresented = false
  @State private var pendingBindRoute: NEChatSwiftUIRoute?
  @State private var isBindConfirmPresented = false

  @MainActor
  public init(state: AIRobotRouteState,
              token: ChatThemeToken,
              avatarSelectionHandler: ChatAvatarSelectionHandling? = nil,
              configClipboardHandler: AIRobotConfigClipboardHandling? = nil,
              onRoute: @escaping (NEChatSwiftUIRoute) -> Void = { _ in },
              onDismiss: (() -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: AIRobotRouteViewModel(route: state))
    self.token = token
    self.avatarSelectionHandler = avatarSelectionHandler
    self.configClipboardHandler = configClipboardHandler
    self.onRoute = onRoute
    self.onDismiss = onDismiss
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: viewModel.state.title,
        token: token,
        backAction: {
          handleBackAction()
        },
        trailingAction: routeTrailingAction,
        onTrailingAction: routeTrailingActionHandler,
        trailingActionEnabled: routeTrailingActionEnabled,
        backgroundColor: routeNavigationBackground
      )

      ScrollView {
        VStack(spacing: contentSpacing) {
          switch viewModel.state.route.kind {
          case .chatCard:
            chatCard
          case .config:
            configPanel
          case .bind:
            bindPanel
          case .create, .nicknameEdit:
            formPanel
          default:
            detailPanel
          }
        }
        .padding(contentInsets)
      }
      .scrollDismissesKeyboard(.immediately)
    }
    .background(routePageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .neCommonTheme(NEChatCommonPresentation.commonTheme(for: token))
    .neCommonBlockingLoadingOverlay(
      NEChatCommonPresentation.blockingLoading(
        id: "aiRobotRouteLoading",
        isPresented: viewModel.state.phase == .loading,
        showsScrim: false
      )
    )
    .neCommonTransientOverlay(
      viewModel.state.toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
    .neCommonConfirmationDialog(
      confirmationDialogState,
      onAction: { action in
        handleConfirmationDialogAction(action)
      },
      onDismiss: {
        isDeleteConfirmPresented = false
        isRefreshTokenConfirmPresented = false
        isBindConfirmPresented = false
        pendingBindRoute = nil
      }
    )
  }

  private var routeTrailingAction: NECommonNavigationAction? {
    switch viewModel.state.route.kind {
    case .create:
      return NEChatCommonPresentation.textNavigationAction(
        id: "save",
        title: NEChatUIKitSwiftUIBundle.localized("save", value: "Save")
      )
    case .nicknameEdit:
      return NEChatCommonPresentation.textNavigationAction(
        id: "done",
        title: NEChatUIKitSwiftUIBundle.localized("done", value: "Done")
      )
    default:
      return nil
    }
  }

  private var routeTrailingActionEnabled: Bool {
    switch viewModel.state.route.kind {
    case .create, .nicknameEdit:
      return viewModel.state.phase != .loading
    default:
      return true
    }
  }

  private var routeTrailingActionHandler: (() -> Void)? {
    guard routeTrailingAction != nil else {
      return nil
    }
    return {
      switch viewModel.state.route.kind {
      case .create:
        viewModel.submitForm { _ in }
      case .nicknameEdit:
        viewModel.saveNicknameEdit {}
      default:
        break
      }
    }
  }

  private func handleBackAction() {
    if viewModel.state.route.kind == .nicknameEdit {
      viewModel.cancelNicknameEdit()
      return
    }
    if let onDismiss {
      onDismiss()
    } else {
      dismiss()
    }
  }

  private var confirmationDialogState: NECommonDialogState? {
    if let refreshTokenDialogState {
      return refreshTokenDialogState
    }
    if let bindDialogState {
      return bindDialogState
    }
    return deleteDialogState
  }

  private var refreshTokenDialogState: NECommonDialogState? {
    guard isRefreshTokenConfirmPresented else {
      return nil
    }
    return NECommonDialogState(
      id: "aiRobotRefreshTokenConfirm",
      title: NEChatUIKitSwiftUIBundle.localized("ai_robot_refresh_token_title", value: "Confirm Refresh Token?"),
      message: NEChatUIKitSwiftUIBundle.localized("ai_robot_refresh_token_desc", value: "After refreshing, the old Token will immediately expire and robots in use need to be reconfigured"),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "refreshToken",
          title: NEChatUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal
        ),
      ]
    )
  }

  private var deleteDialogState: NECommonDialogState? {
    guard isDeleteConfirmPresented else {
      return nil
    }
    return NECommonDialogState(
      id: "aiRobotDeleteConfirm",
      title: NEChatUIKitSwiftUIBundle.localized("ai_robot_delete_confirm_title", value: "Delete AI Robot?"),
      message: NEChatUIKitSwiftUIBundle.localized("ai_robot_delete_confirm_desc", value: "After deletion, the robot in use will be disconnected and needs to be reconfigured"),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "delete",
          title: NEChatUIKitSwiftUIBundle.localized("delete", value: "Delete"),
          role: .destructive
        ),
      ]
    )
  }

  private var bindDialogState: NECommonDialogState? {
    guard isBindConfirmPresented else {
      return nil
    }
    return NECommonDialogState(
      id: "aiRobotBindConfirm",
      title: NEChatUIKitSwiftUIBundle.localized("ai_robot_bind_confirm_title", value: "Confirm Bind Account?"),
      message: NEChatUIKitSwiftUIBundle.localized("ai_robot_bind_confirm_desc", value: "After binding, the robot will be associated with this account. Robots already configured for this account will be disconnected and need to be reconfigured"),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "bind",
          title: NEChatUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal
        ),
      ]
    )
  }

  private func handleConfirmationDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "refreshToken":
      viewModel.refreshToken()
      isRefreshTokenConfirmPresented = false
    case "delete":
      viewModel.deleteRobot {
        onDismiss?()
      }
      isDeleteConfirmPresented = false
    case "bind":
      if case let .aiRobot(bindState)? = pendingBindRoute,
         let bot = bindState.bot {
        viewModel.bindRobot(bot: bot) { boundBot in
          route(.aiRobot(.init(kind: .detail, bot: boundBot, sourceURL: ContactAIRobotDetailRouter)))
        }
      }
      pendingBindRoute = nil
      isBindConfirmPresented = false
    default:
      isRefreshTokenConfirmPresented = false
      isDeleteConfirmPresented = false
      isBindConfirmPresented = false
      pendingBindRoute = nil
    }
  }

  private var chatCard: some View {
    VStack(spacing: 14) {
      robotAvatar(size: 64)
      Text(viewModel.state.displayName)
        .font(.system(size: 17, weight: .medium))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(2)
        .multilineTextAlignment(.center)
      if let subtitle = viewModel.state.subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      primaryButton(
        title: NEChatUIKitSwiftUIBundle.localized("ai_robot_chat", value: "Chat"),
        imageName: "chat_rtc",
        isEnabled: viewModel.state.canChat
      ) {
        route(viewModel.chatRoute())
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(token.inputBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
  }

  private var detailPanel: some View {
    let metrics = AIRobotDetailMetrics(style: token.styleMode)
    return VStack(spacing: 0) {
      detailHeader(metrics: metrics)
        .padding(.bottom, metrics.sectionSpacing)

      detailOperationList(metrics: metrics)

      Rectangle()
        .fill(detailPageBackground)
        .frame(height: metrics.chatSeparatorHeight)

      detailChatDeleteCard(metrics: metrics)
    }
  }

  private func detailHeader(metrics: AIRobotDetailMetrics) -> some View {
    Button {
      route(viewModel.editRoute())
    } label: {
      HStack(spacing: 12) {
        detailAvatar(metrics: metrics)
        Text(viewModel.state.displayName)
          .font(.system(size: 16))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        NECommonChevronView()
          .frame(width: 16, height: 16)
      }
      .padding(.leading, 16)
      .padding(.trailing, 16)
      .frame(maxWidth: .infinity, minHeight: metrics.headerHeight, maxHeight: metrics.headerHeight)
      .background(Color.white)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    .overlay(alignment: .bottom) {
      if metrics.showsEveryFunSeparator {
        Rectangle()
          .fill(metrics.separatorColor)
          .frame(height: 0.5)
          .padding(.leading, 16)
      }
    }
  }

  private func detailOperationList(metrics: AIRobotDetailMetrics) -> some View {
    VStack(spacing: 0) {
      detailOperationRow(
        title: NEChatUIKitSwiftUIBundle.localized("ai_robot_view_config", value: "View Config"),
        metrics: metrics,
        isLast: false
      ) {
        route(viewModel.configRoute())
      }
      detailOperationRow(
        title: NEChatUIKitSwiftUIBundle.localized("ai_robot_refresh_token", value: "Refresh Token"),
        metrics: metrics,
        isLast: true
      ) {
        if viewModel.state.canRefreshToken {
          isRefreshTokenConfirmPresented = true
        }
      }
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
  }

  private func detailOperationRow(title: String,
                                  metrics: AIRobotDetailMetrics,
                                  isLast: Bool,
                                  action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(size: 16))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        NECommonChevronView()
          .frame(width: 16, height: 16)
      }
      .padding(.leading, metrics.rowLeading)
      .padding(.trailing, 16)
      .frame(maxWidth: .infinity, minHeight: metrics.rowHeight, maxHeight: metrics.rowHeight)
      .background(Color.white)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.state.canRefreshToken && title == NEChatUIKitSwiftUIBundle.localized("ai_robot_refresh_token", value: "Refresh Token"))
    .overlay(alignment: .bottom) {
      if !isLast || metrics.showsEveryFunSeparator {
        Rectangle()
          .fill(metrics.separatorColor)
          .frame(height: 0.5)
          .padding(.leading, metrics.separatorLeading)
      }
    }
  }

  private func detailChatDeleteCard(metrics: AIRobotDetailMetrics) -> some View {
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        Button {
          if let chatRoute = viewModel.chatRoute() {
            onDismiss?()
            onRoute(chatRoute)
          }
        } label: {
          Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_chat", value: "Chat"))
            .font(metrics.chatFont)
            .foregroundColor(metrics.chatColor)
            .frame(maxWidth: .infinity, minHeight: metrics.chatRowHeight, maxHeight: metrics.chatRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.state.canChat)

        if viewModel.state.canDelete {
          Button {
            isDeleteConfirmPresented = true
          } label: {
            Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_delete", value: "Delete"))
              .font(metrics.deleteFont)
              .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.redText)
              .frame(maxWidth: .infinity, minHeight: metrics.deleteRowHeight, maxHeight: metrics.deleteRowHeight)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }

      if viewModel.state.canDelete {
        Rectangle()
          .fill(metrics.separatorColor)
          .frame(height: 0.5)
          .padding(.top, metrics.chatRowHeight)
      }
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
  }

  private var formPanel: some View {
    Group {
      if viewModel.state.route.kind == .nicknameEdit {
        nicknameEditPanel
      } else {
        createEditPanel
      }
    }
  }

  private var createEditPanel: some View {
    let metrics = AIRobotFormMetrics(style: token.styleMode)
    return VStack(spacing: 0) {
      avatarSelectionControl(metrics: metrics)

      Rectangle()
        .fill(metrics.separatorColor)
        .frame(height: 0.5)
        .padding(.leading, 16)

      Button {
        viewModel.openNicknameEditor()
      } label: {
        HStack(spacing: 12) {
          Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_name", value: "Name"))
            .font(.system(size: 16))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
          Spacer(minLength: 12)
          Text(viewModel.state.form?.name ?? "")
            .font(.system(size: 16))
            .foregroundColor(Color(hex: 0x999999))
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.trailing)
          NECommonChevronView()
            .frame(width: 16, height: 16)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
  }

  private func avatarSelectionControl(metrics: AIRobotFormMetrics) -> some View {
    Button {
      viewModel.selectAvatar(handler: avatarSelectionHandler)
    } label: {
      HStack(spacing: 12) {
        Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_avatar", value: "Avatar"))
          .font(.system(size: 16))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
        Spacer(minLength: 12)
        formAvatar(metrics: metrics)
        NECommonChevronView()
          .frame(width: 16, height: 16)
      }
      .padding(.leading, 16)
      .padding(.trailing, 16)
      .frame(height: 74)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("ai_robot_select_avatar", value: "Select Avatar"))
    .accessibilityHint(NEChatUIKitSwiftUIBundle.localized("ai_robot_avatar_requires_host_hint", value: "Avatar selection is provided by the SwiftUI native boundary handler."))
  }

  private var nicknameEditPanel: some View {
    AIRobotNicknameEditField(
      text: Binding(
        get: { viewModel.state.form?.name ?? "" },
        set: { viewModel.updateFormName($0) }
      ),
      token: token
    )
  }

  private func formAvatar(metrics: AIRobotFormMetrics) -> some View {
    NEChatCommonPresentation.avatarView(
      imageURL: viewModel.state.avatarURL,
      initials: ChatAvatarDisplayResolver.initials(
        displayName: formAvatarDisplayName,
        accountId: viewModel.state.route.bot?.accid ?? viewModel.state.form?.accid
      ),
      token: token,
      size: metrics.avatarSize,
      cornerRadius: metrics.avatarCornerRadius,
      hashID: viewModel.state.route.bot?.accid ?? viewModel.state.form?.accid ?? formAvatarDisplayName
    )
  }

  private var formAvatarDisplayName: String {
    let source = viewModel.state.avatarDisplayName ?? viewModel.state.form?.name ?? viewModel.state.displayName
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ""
    }
    return trimmed
  }

  private var configPanel: some View {
    let metrics = AIRobotConfigMetrics(style: token.styleMode)
    return VStack(spacing: 0) {
      if let config = viewModel.state.configString, !config.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_config_title", value: "Config String"))
            .font(.system(size: 16))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .padding(.horizontal, 16)

          Text(config)
            .font(.system(size: 14))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .padding(.bottom, 24)

        Button {
          copyConfigString(config)
        } label: {
          Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_config_copy", value: "Copy full config string"))
            .font(.system(size: 16))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .background(token.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: metrics.copyButtonCornerRadius, style: .continuous))
        .padding(.horizontal, metrics.copyButtonHorizontalMargin - metrics.cardHorizontalMargin)
        .padding(.bottom, 16)

        Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_config_warning", value: "Keep it safe, don't share with others"))
          .font(.system(size: 14))
          .foregroundColor(Color(hex: 0xFF9000))
          .frame(maxWidth: .infinity, alignment: .center)
      }
    }
  }

  private var bindPanel: some View {
    VStack(spacing: 14) {
      if viewModel.state.route.bot == nil {
        AIRobotBindSelectionView(token: token) { action in
          handleBindSelection(action)
        }
      } else {
        chatCard
        infoFields
        primaryButton(
          title: NEChatUIKitSwiftUIBundle.localized("ai_robot_bind", value: "Bind AI Robot"),
          imageName: "chat_read_all",
          isEnabled: viewModel.state.canBind
        ) {
          viewModel.bindRobot { bot in
            onRoute(.aiRobot(.init(kind: .detail, bot: bot, sourceURL: ContactAIRobotDetailRouter)))
          }
        }
      }
    }
  }

  private var actionList: some View {
    VStack(spacing: 0) {
      actionRow(
        title: NEChatUIKitSwiftUIBundle.localized("ai_robot_view_config", value: "View Config"),
        imageName: "op_file",
        isEnabled: viewModel.configRoute() != nil
      ) {
        route(viewModel.configRoute())
      }
      divider
      actionRow(
        title: NEChatUIKitSwiftUIBundle.localized("ai_robot_refresh_token", value: "Refresh Token"),
        imageName: "ai_reload",
        isEnabled: viewModel.state.canRefreshToken
      ) {
        viewModel.refreshToken()
      }
      divider
      actionRow(
        title: NEChatUIKitSwiftUIBundle.localized("ai_robot_chat", value: "Chat"),
        imageName: "chat_rtc",
        isEnabled: viewModel.state.canChat
      ) {
        route(viewModel.chatRoute())
      }
      if viewModel.state.canDelete {
        divider
        actionRow(
          title: NEChatUIKitSwiftUIBundle.localized("ai_robot_delete", value: "Delete"),
          imageName: "op_delete",
          tint: token.warningColor,
          isEnabled: true
        ) {
          isDeleteConfirmPresented = true
        }
      }
    }
    .background(token.inputBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
  }

  private var infoFields: some View {
    VStack(spacing: 0) {
      ForEach(viewModel.state.fields) { field in
        AIRobotFieldRow(field: field, token: token)
        if field.id != viewModel.state.fields.last?.id {
          divider
        }
      }
    }
    .background(token.inputBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
  }

  private var divider: some View {
    NEChatCommonPresentation.separator(
      token: token,
      leadingInset: 14,
      opacity: 0.6
    )
  }

  private func robotAvatar(size: CGFloat) -> some View {
    NEChatCommonPresentation.avatarView(
      imageURL: viewModel.state.avatarURL,
      initials: ChatAvatarDisplayResolver.initials(
        displayName: viewModel.state.displayName,
        accountId: viewModel.state.route.bot?.accid
      ),
      token: token,
      size: size,
      cornerRadius: size / 2,
      hashID: viewModel.state.route.bot?.accid ?? viewModel.state.displayName
    )
  }

  private func detailAvatar(metrics: AIRobotDetailMetrics) -> some View {
    NEChatCommonPresentation.avatarView(
      imageURL: viewModel.state.avatarURL,
      initials: detailAvatarInitials,
      token: token,
      size: metrics.avatarSize,
      cornerRadius: metrics.avatarCornerRadius,
      hashID: viewModel.state.route.bot?.accid ?? viewModel.state.displayName
    )
  }

  private var detailAvatarInitials: String {
    let name = viewModel.state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = name.isEmpty ? viewModel.state.route.bot?.accid ?? "" : name
    return ChatAvatarDisplayResolver.initials(
      displayName: source,
      accountId: viewModel.state.route.bot?.accid
    )
  }

  private func actionRow(title: String,
                         imageName: String,
                         tint: Color? = nil,
                         isEnabled: Bool,
                         action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        NEChatCommonPresentation.iconView(
          imageName: imageName,
          token: token,
          renderingMode: .original,
          isEnabled: isEnabled,
          size: CGSize(width: 24, height: 24),
          foregroundColor: isEnabled ? (tint ?? token.incomingTextColor) : token.secondaryTextColor.opacity(0.55),
          accessibilityLabel: title
        )
        Text(title)
          .font(.system(size: 16))
        Spacer()
        NEChatCommonPresentation.chevron(token: token, isEnabled: isEnabled)
      }
      .foregroundColor(isEnabled ? (tint ?? token.incomingTextColor) : token.secondaryTextColor.opacity(0.55))
      .padding(.horizontal, 14)
      .frame(height: 50)
    }
    .disabled(!isEnabled)
    .buttonStyle(.plain)
  }

  private func primaryButton(title: String,
                             imageName: String,
                             bundle: Bundle? = NEChatUIKitSwiftUIBundle.bundle,
                             isEnabled: Bool,
                             action: @escaping () -> Void) -> some View {
    NEChatCommonPresentation.actionButton(
      title: title,
      token: token,
      imageName: imageName,
      bundle: bundle,
      renderingMode: .original,
      isEnabled: isEnabled,
      minHeight: 48,
      action: action
    )
  }

  private func route(_ route: NEChatSwiftUIRoute?) {
    guard let route else {
      return
    }
    onRoute(route)
  }

  private func handleBindSelection(_ action: AIRobotBindSelectionAction) {
    switch action {
    case .create:
      guard viewModel.state.route.autoBindQrCode?.isEmpty == false else {
        return
      }
      onRoute(.aiRobot(.init(
        kind: .create,
        defaultName: AIRobotEntryViewModel().defaultCreateName,
        autoBindQrCode: viewModel.state.route.autoBindQrCode,
        previousBoundAccid: viewModel.state.route.previousBoundAccid,
        sourceURL: ContactCreateAIRobotRouter
      )))
    case let .existing(row):
      pendingBindRoute = viewModel.bindSelectedRoute(for: row)
      isBindConfirmPresented = true
    }
  }

  private func copyConfigString(_ config: String) {
    guard let configClipboardHandler else {
      viewModel.showToast(ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_copy_requires_boundary", value: "Copy requires a SwiftUI clipboard handler."),
        style: .info
      ))
      return
    }
    configClipboardHandler.copyConfig(AIRobotConfigClipboardRequest(configString: config)) { result in
      Task { @MainActor in
        switch result {
        case let .success(toast):
          if let toast {
            viewModel.showToast(toast)
          } else {
            viewModel.showToast(ChatToastState(
              message: NEChatUIKitSwiftUIBundle.localized("ai_robot_config_copy_success", value: "Config copied"),
              style: .success
            ))
          }
        case let .failure(error):
          viewModel.showToast(ChatToastState(
            message: NEChatErrorMessageMapper.message(
              for: error,
              fallbackKey: "ai_robot_config_copy_failed",
              fallbackValue: "Copy failed. Please try again."
            ),
            style: .error
          ))
        }
      }
    }
  }

  private func maskedConfigString(_ config: String) -> String {
    guard !config.isEmpty else {
      return config
    }
    let visibleCount = max(1, config.count / 3)
    return "\(config.prefix(visibleCount))..."
  }

  private var contentInsets: EdgeInsets {
    switch viewModel.state.route.kind {
    case .detail:
      let metrics = AIRobotDetailMetrics(style: token.styleMode)
      return EdgeInsets(top: metrics.topPadding,
                        leading: metrics.horizontalMargin,
                        bottom: 16,
                        trailing: metrics.horizontalMargin)
    case .create:
      let metrics = AIRobotFormMetrics(style: token.styleMode)
      return EdgeInsets(top: 12,
                        leading: metrics.horizontalMargin,
                        bottom: 16,
                        trailing: metrics.horizontalMargin)
    case .nicknameEdit:
      return EdgeInsets(top: 12, leading: 0, bottom: 16, trailing: 0)
    case .config:
      let metrics = AIRobotConfigMetrics(style: token.styleMode)
      return EdgeInsets(top: 12,
                        leading: metrics.cardHorizontalMargin,
                        bottom: 16,
                        trailing: metrics.cardHorizontalMargin)
    case .bind:
      return EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
    default:
      return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }
  }

  private var contentSpacing: CGFloat {
    viewModel.state.route.kind == .detail ? 0 : 16
  }

  private var detailPageBackground: Color {
    token.styleMode == .fun ? NEUIKitSwiftUIStyle.ColorToken.funBackground : NEUIKitSwiftUIStyle.ColorToken.lightBackground
  }

  private var routePageBackground: Color {
    switch viewModel.state.route.kind {
    case .detail, .create, .config, .bind, .nicknameEdit:
      return detailPageBackground
    default:
      return token.pageBackground
    }
  }

  private var routeNavigationBackground: Color {
    switch viewModel.state.route.kind {
    case .detail, .create, .config, .bind, .nicknameEdit:
      return token.styleMode == .fun ? .white : detailPageBackground
    default:
      return token.navigationBackground
    }
  }
}

private struct AIRobotFormMetrics {
  var horizontalMargin: CGFloat
  var cardCornerRadius: CGFloat
  var avatarSize: CGFloat
  var avatarCornerRadius: CGFloat
  var separatorColor: Color

  init(style: ChatStyleMode) {
    horizontalMargin = 20
    cardCornerRadius = 8
    avatarSize = 40
    avatarCornerRadius = style == .fun ? 4 : 20
    separatorColor = style == .fun ? NEUIKitSwiftUIStyle.ColorToken.funLineBorder : NEUIKitSwiftUIStyle.ColorToken.greyLine
  }
}

private struct AIRobotConfigMetrics {
  var cardHorizontalMargin: CGFloat
  var cardCornerRadius: CGFloat
  var copyButtonHorizontalMargin: CGFloat
  var copyButtonCornerRadius: CGFloat

  init(style: ChatStyleMode) {
    switch style {
    case .fun:
      cardHorizontalMargin = 0
      cardCornerRadius = 0
      copyButtonHorizontalMargin = 16
      copyButtonCornerRadius = 12
    case .normal:
      cardHorizontalMargin = 20
      cardCornerRadius = 8
      copyButtonHorizontalMargin = 20
      copyButtonCornerRadius = 8
    }
  }
}

private struct AIRobotDetailMetrics {
  var topPadding: CGFloat
  var horizontalMargin: CGFloat
  var headerHeight: CGFloat
  var avatarSize: CGFloat
  var avatarCornerRadius: CGFloat
  var cardCornerRadius: CGFloat
  var sectionSpacing: CGFloat
  var rowHeight: CGFloat
  var rowLeading: CGFloat
  var separatorLeading: CGFloat
  var separatorColor: Color
  var chatSeparatorHeight: CGFloat
  var chatRowHeight: CGFloat
  var deleteSeparatorHeight: CGFloat
  var deleteRowHeight: CGFloat
  var chatColor: Color
  var chatFont: Font
  var deleteFont: Font
  var showsEveryFunSeparator: Bool

  init(style: ChatStyleMode) {
    switch style {
    case .fun:
      topPadding = 0
      horizontalMargin = 0
      headerHeight = 82
      avatarSize = 50
      avatarCornerRadius = 5
      cardCornerRadius = 0
      sectionSpacing = 8
      rowHeight = 56
      rowLeading = 16
      separatorLeading = 16
      separatorColor = NEUIKitSwiftUIStyle.ColorToken.funLineBorder
      chatSeparatorHeight = 8
      chatRowHeight = 56
      deleteSeparatorHeight = 0
      deleteRowHeight = 56
      chatColor = Color(hex: 0x525C8C)
      chatFont = .system(size: 16, weight: .medium)
      deleteFont = .system(size: 16, weight: .medium)
      showsEveryFunSeparator = true
    case .normal:
      topPadding = 0
      horizontalMargin = 20
      headerHeight = 74
      avatarSize = 42
      avatarCornerRadius = 21
      cardCornerRadius = 8
      sectionSpacing = 12
      rowHeight = 48
      rowLeading = 16
      separatorLeading = 16
      separatorColor = NEUIKitSwiftUIStyle.ColorToken.greyLine
      chatSeparatorHeight = 6
      chatRowHeight = 50
      deleteSeparatorHeight = 0
      deleteRowHeight = 50
      chatColor = NEUIKitSwiftUIStyle.ColorToken.normalTheme
      chatFont = .system(size: 16)
      deleteFont = .system(size: 16)
      showsEveryFunSeparator = false
    }
  }
}

private struct AIRobotTextFieldRow: View {
  var title: String
  @Binding var text: String
  var placeholder: String
  var error: String?
  var token: ChatThemeToken
  var characterLimit: Int?

  var body: some View {
    NEChatCommonPresentation.formTextField(
      title: title,
      text: $text,
      placeholder: placeholder,
      token: token,
      error: error,
      characterLimit: characterLimit
    )
  }
}

private struct AIRobotStaticFieldRow: View {
  var title: String
  var value: String
  var token: ChatThemeToken

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 12))
        .foregroundColor(token.secondaryTextColor)
      Text(value)
        .font(.system(size: 16))
        .foregroundColor(token.incomingTextColor)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

private struct AIRobotNicknameEditField: View {
  @Binding var text: String
  var token: ChatThemeToken
  @FocusState private var isFocused: Bool
  private let limit = 15

  var body: some View {
    HStack(spacing: 4) {
      NEChatCommonPresentation.formTextField(
        text: limitedTextBinding,
        placeholder: "",
        token: token,
        submitLabel: .done,
        horizontalPadding: 16,
        verticalPadding: 0,
        minHeight: 48,
        characterLimit: 15
      )
      .focused($isFocused)

      Text("\(text.count)/\(limit)")
        .font(.system(size: 13))
        .foregroundColor(Color(hex: 0x999999))
        .frame(width: 40, alignment: .trailing)

      NEChatCommonPresentation.iconButton(
        systemImageName: "xmark.circle.fill",
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("close", value: "Close"),
        token: token,
        size: CGSize(width: 20, height: 20),
        font: .system(size: 14, weight: .regular),
        foregroundColor: Color(hex: 0xCCCCCC)
      ) {
        isFocused = false
        text = ""
      }
      .padding(.trailing, 8)
    }
    .frame(height: 48)
    .background(Color.white)
    .onAppear {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        isFocused = true
      }
    }
  }

  private var limitedTextBinding: Binding<String> {
    Binding(
      get: { text },
      set: { newValue in
        let limitedValue = NECommonTextLimit.limitedUTF16(newValue, limit: limit)
        text = limitedValue
        if limitedValue.isEmpty {
          isFocused = false
        }
      }
    )
  }
}

private enum AIRobotBindSelectionAction {
  case create
  case existing(AIRobotRowState)
}

@MainActor
private struct AIRobotBindSelectionView: View {
  @StateObject private var viewModel: AIRobotEntryViewModel
  var token: ChatThemeToken
  var onSelect: (AIRobotBindSelectionAction) -> Void

  init(viewModel: AIRobotEntryViewModel? = nil,
       token: ChatThemeToken,
       onSelect: @escaping (AIRobotBindSelectionAction) -> Void) {
    _viewModel = StateObject(wrappedValue: viewModel ?? AIRobotEntryViewModel())
    self.token = token
    self.onSelect = onSelect
  }

  var body: some View {
    let metrics = AIRobotBindMetrics(style: token.styleMode)
    return VStack(spacing: 0) {
      createEntry

      if viewModel.robotCount >= AIRobotEntryViewModel.maxRobotCount {
        Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_exceed_limit", value: "Robot limit reached. Please select an existing robot or delete one"))
          .font(NEUIKitSwiftUIStyle.FontToken.settingSubtitle)
          .foregroundColor(token.warningColor)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 14)
      }

      Rectangle()
        .fill(token.styleMode == .fun ? NEUIKitSwiftUIStyle.ColorToken.funBackground : NEUIKitSwiftUIStyle.ColorToken.lightBackground)
        .frame(height: metrics.dividerBlockHeight)

      Text(NEChatUIKitSwiftUIBundle.localized("ai_robot_bind_select_hint", value: "Select an existing robot"))
        .font(.system(size: 14, weight: token.styleMode == .fun ? .medium : .regular))
        .foregroundColor(token.styleMode == .fun ? .black : NEUIKitSwiftUIStyle.ColorToken.emptyTitle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .frame(height: metrics.sectionHeaderHeight)
        .background(Color.white)

      VStack(spacing: 0) {
        ForEach(viewModel.rows) { row in
          Button {
            onSelect(.existing(row))
          } label: {
            HStack(spacing: 12) {
              AIRobotAvatarView(row: row, token: token)
              VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                  .font(.system(size: 16, weight: .medium))
                  .foregroundColor(token.incomingTextColor)
                  .lineLimit(1)
                  .truncationMode(.tail)
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                  Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(token.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
              }
              Spacer()
              NEChatCommonPresentation.chevron(token: token)
            }
            .padding(.horizontal, 14)
            .frame(height: metrics.bindRowHeight)
            .background(Color.white)
          }
          .buttonStyle(.plain)

          if row.id != viewModel.rows.last?.id {
            NEChatCommonPresentation.separator(
              token: token,
              leadingInset: 70,
              opacity: 0.6
            )
          }
        }
      }
      .background(Color.white)
    }
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty:
        NEChatCommonPresentation.emptyView(token: token)
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.load()
        }
      default:
        EmptyView()
      }
    }
    .onAppear {
      viewModel.load()
    }
  }

  private var createEntry: some View {
    let metrics = AIRobotBindMetrics(style: token.styleMode)
    return Button {
      guard viewModel.canCreateRobot else {
        viewModel.showCreateLimitToast()
        return
      }
      onSelect(.create)
    } label: {
      HStack(spacing: 12) {
        AIRobotBindCreateIcon(token: token)
        Text(NEChatUIKitSwiftUIBundle.localized("create_ai_robot", value: "Create Robot"))
          .font(.system(size: 14))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
        Spacer()
        if token.styleMode == .normal {
          NEChatCommonPresentation.chevron(token: token)
            .frame(width: 14, height: 14)
        }
      }
      .padding(.leading, 16)
      .padding(.trailing, 16)
      .frame(height: metrics.createRowHeight)
      .background(Color.white)
    }
    .buttonStyle(.plain)
  }
}

private struct AIRobotBindMetrics {
  var createRowHeight: CGFloat
  var bindRowHeight: CGFloat
  var dividerBlockHeight: CGFloat
  var sectionHeaderHeight: CGFloat

  init(style: ChatStyleMode) {
    switch style {
    case .fun:
      createRowHeight = 74
      bindRowHeight = 74
      dividerBlockHeight = 8
      sectionHeaderHeight = 44
    case .normal:
      createRowHeight = 60
      bindRowHeight = 60
      dividerBlockHeight = 6
      sectionHeaderHeight = 44
    }
  }
}

private struct AIRobotBindCreateIcon: View {
  var token: ChatThemeToken

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: token.styleMode == .fun ? 4 : 18, style: .continuous)
        .fill(token.accentColor)
      Rectangle()
        .fill(Color.white)
        .frame(width: 14, height: 1.5)
      Rectangle()
        .fill(Color.white)
        .frame(width: 1.5, height: 14)
    }
    .frame(width: 36, height: 36)
  }
}

private struct AIRobotFieldRow: View {
  var field: AIRobotInfoFieldState
  var token: ChatThemeToken

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(field.title)
        .font(.system(size: 12))
        .foregroundColor(token.secondaryTextColor)
      Text(displayValue)
        .font(.system(size: 15))
        .foregroundColor(token.incomingTextColor)
        .textSelection(.enabled)
        .lineLimit(field.isSensitive ? 1 : 5)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  private var displayValue: String {
    if field.isSensitive, field.value.count > 12 {
      return "\(field.value.prefix(6))...\(field.value.suffix(4))"
    }
    return field.value
  }
}
