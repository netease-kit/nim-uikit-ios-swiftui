// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct P2PSettingView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: P2PSettingViewModel
  @State private var pushedRoute: P2PSettingRoute?
  private let token: ChatThemeToken
  private let networkOperationGuard: () -> Bool
  private let onPinMessageSelect: ((PinMessageSelection) -> Void)?
  private let onOpenUtilityMessageContent: ((MessageRowState) -> Void)?
  private let onCopy: (MessageRowState) -> Void
  private let onForward: (MessageRowState) -> Void
  private let onForwardMessage: ((MessageRowState, V2NIMMessage?) -> Void)?
  private let canCopy: (MessageRowState) -> Bool
  private let canForward: (MessageRowState) -> Bool
  private let onBack: (() -> Void)?

  @MainActor
  public init(context: ChatSessionContext,
              config: ChatSwiftUIConfig,
              token: ChatThemeToken? = nil,
              onPinMessageSelect: ((PinMessageSelection) -> Void)? = nil,
              onOpenUtilityMessageContent: ((MessageRowState) -> Void)? = nil,
              onCopy: @escaping (MessageRowState) -> Void = { _ in },
              onForward: @escaping (MessageRowState) -> Void = { _ in },
              onForwardMessage: ((MessageRowState, V2NIMMessage?) -> Void)? = nil,
              canCopy: @escaping (MessageRowState) -> Bool = { _ in false },
              canForward: @escaping (MessageRowState) -> Bool = { _ in false },
              networkOperationGuard: @escaping () -> Bool = { true },
              onOpenTeamChat: @escaping (ChatSessionContext) -> Void = { context in
                NEChatUIKitSwiftUIClient.shared.router.enqueue(.teamChat(context))
              },
              onBack: (() -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: P2PSettingViewModel(
      context: context,
      config: config,
      networkOperationGuard: networkOperationGuard,
      onOpenTeamChat: onOpenTeamChat
    ))
    self.token = token ?? config.themeToken
    self.networkOperationGuard = networkOperationGuard
    self.onPinMessageSelect = onPinMessageSelect
    self.onOpenUtilityMessageContent = onOpenUtilityMessageContent
    self.onCopy = onCopy
    self.onForward = onForward
    self.onForwardMessage = onForwardMessage
    self.canCopy = canCopy
    self.canForward = canForward
    self.onBack = onBack
  }

  public var body: some View {
    ZStack {
      settingPageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NECommonNavigationBarView(
          title: NEChatUIKitSwiftUIBundle.localized("chat_setting", value: "Settings"),
          backAction: {
            if let onBack { onBack() } else { dismiss() }
          },
          backgroundColor: settingNavigationBackground,
          separatorColor: token.dividerColor,
          showsSeparator: token.styleMode == .fun
        )
        .neCommonTheme(NEChatCommonPresentation.commonTheme(for: token))

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .onDisappear { viewModel.onDisappear() }
    .navigationDestination(isPresented: pushedRouteIsPresentedBinding) {
      pushedRouteDestination
    }
    .onChange(of: viewModel.state.route?.id) { _ in
      syncRoutePresentation()
    }
    .neCommonBlockingLoadingOverlay(
      NEChatCommonPresentation.blockingLoading(
        id: "p2pSettingCreateDiscuss",
        isPresented: viewModel.state.isCreatingDiscuss,
        fallbackText: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading")
      )
    )
    .neCommonTransientOverlay(
      viewModel.state.toast,
      placement: .top,
      topPadding: 10,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle, .loading:
      NEChatCommonPresentation.loadingView(token: token)
    case .failed(let message):
      NEChatCommonPresentation.errorView(message: message, token: token) {
        viewModel.load()
      }
    case .loaded:
      ScrollView {
        VStack(spacing: 12) {
          if let snapshot = viewModel.state.snapshot {
            P2PSettingHeaderView(snapshot: snapshot, token: token) {
              viewModel.createDiscuss()
            }
          }
          VStack(spacing: 0) {
            ForEach(viewModel.state.rows) { row in
              P2PSettingRowView(row: row, token: token) { selected in
                viewModel.select(selected)
                syncRoutePresentation()
              } onToggle: { selected, isOn in
                viewModel.setToggle(toggleKind(for: selected.kind), isOn: isOn)
              }
              if row.id != viewModel.state.rows.last?.id {
                NEChatCommonPresentation.settingSeparator(token: token, leadingInset: rowDividerLeadingInset)
              }
            }
          }
          .background(token.panelItemBackground)
          .clipShape(RoundedRectangle(cornerRadius: rowGroupCornerRadius, style: .continuous))
          .padding(.horizontal, rowGroupHorizontalPadding)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
      }
    }
  }

  @ViewBuilder
  private var pushedRouteDestination: some View {
    if let pushedRoute {
      routeDestination(pushedRoute)
    } else {
      EmptyView()
    }
  }

  private var pushedRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { pushedRoute != nil },
      set: { isActive in
        if !isActive {
          pushedRoute = nil
          viewModel.clearRoute()
        }
      }
    )
  }

  private func syncRoutePresentation() {
    guard let route = viewModel.state.route else {
      pushedRoute = nil
      return
    }
    switch route {
    case let .pinMessages(conversationId):
      pushedRoute = .pinMessages(conversationId: conversationId)
    case let .historySearch(conversationId):
      pushedRoute = .historySearch(conversationId: conversationId)
    case let .teamChat(context):
      pushedRoute = .teamChat(context)
    case let .p2pChat(context):
      pushedRoute = .p2pChat(context)
    default:
      pushedRoute = .unsupported(route)
    }
  }

  @ViewBuilder
  private func routeDestination(_ route: P2PSettingRoute) -> some View {
    switch route {
    case let .pinMessages(conversationId):
      if let provider = viewModel.config.p2pSettingPinMessagesViewProvider,
         let view = provider(
           conversationId,
           token,
           networkOperationGuard,
           openChat(selection:),
           closePushedRoute
         ) {
        view
      } else {
        PinMessagesView(
          viewModel: PinMessagesViewModel(
            conversationId: conversationId,
            networkOperationGuard: networkOperationGuard
          ),
          token: token,
          onContentSelect: onOpenUtilityMessageContent,
          onSelectMessage: { selection in
            openChat(selection: selection)
          },
          onCopy: onCopy,
          onForward: onForward,
          onForwardMessage: onForwardMessage,
          onBack: closePushedRoute,
          canCopy: canCopy,
          canForward: canForward
        )
      }
    case let .historySearch(conversationId):
      HistorySearchView(
        viewModel: HistorySearchViewModel(
          conversationId: conversationId,
          fileInteractionHandler: viewModel.config.fileInteractionHandler,
          mediaPreviewHandler: viewModel.config.mediaPreviewHandler,
          networkOperationGuard: networkOperationGuard,
          sessionContextProvider: {
            ChatSessionContext(
              kind: .p2p,
              conversationId: conversationId,
              title: viewModel.state.snapshot?.displayName,
              sessionId: viewModel.state.snapshot?.accountId,
              sessionName: viewModel.state.snapshot?.displayName
            )
          },
          conversationNameProvider: { viewModel.state.snapshot?.displayName }
        ),
        token: token,
        onSelectMessage: { selection in
          openChat(selection: selection, fallbackConversationId: conversationId)
        },
        onForward: onForward,
        onForwardMessage: onForwardMessage.map { handler in
          { row, sourceMessage in handler(row, sourceMessage) }
        },
        onSaveMedia: viewModel.config.mediaImageSaveHandler,
        onBack: closePushedRoute,
        canForward: canForward
      )
    case let .teamChat(context):
      ChatView(
        viewModel: ChatSessionViewModel(
          context: context,
          config: viewModel.config
        ),
        token: token
      )
    case let .p2pChat(context):
      ChatView(
        viewModel: ChatSessionViewModel(
          context: context,
          config: viewModel.config
        ),
        token: token
      )
    case let .unsupported(.teamChat(context)):
      UnsupportedRouteView(
        title: context.title ?? context.conversationId,
        reason: NEChatUIKitSwiftUIBundle.localized("chat_route_nested_chat_desc", value: "Nested chat routes should be handled by the app route host."),
        token: token
      )
    case let .unsupported(route):
      UnsupportedRouteView(
        title: route.id,
        reason: NEChatUIKitSwiftUIBundle.localized("chat_route_requires_host", value: "This route should be handled by the SwiftUI app route host."),
        token: token
      )
    }
  }

  private func toggleKind(for rowKind: P2PSettingRowKind) -> P2PSettingToggleKind {
    switch rowKind {
    case .messageRemind:
      return .messageRemind
    case .conversationPinned:
      return .conversationPinned
    case .aiUserPinned:
      return .aiUserPinned
    default:
      return .messageRemind
    }
  }

  private func closePushedRoute() {
    pushedRoute = nil
    viewModel.clearRoute()
  }

  private func openChat(selection: PinMessageSelection) {
    openChat(selection: selection, fallbackConversationId: viewModel.context.conversationId)
  }

  private func openChat(selection: PinMessageSelection, fallbackConversationId: String) {
    if let onPinMessageSelect {
      onPinMessageSelect(selection)
      return
    }

    var context = viewModel.context
    if let anchorMessage = selection.anchorMessage {
      context.kind = chatKind(for: anchorMessage, conversationId: anchorMessage.conversationId ?? context.conversationId)
      context.conversationId = anchorMessage.conversationId ?? context.conversationId
      context.sessionId = V2NIMConversationIdUtil.conversationTargetId(context.conversationId)
    } else if let conversationId = selection.row.conversationId, !conversationId.isEmpty {
      context.kind = chatKind(for: nil, conversationId: conversationId)
      context.conversationId = conversationId
      context.sessionId = V2NIMConversationIdUtil.conversationTargetId(conversationId)
    } else if !fallbackConversationId.isEmpty {
      context.kind = chatKind(for: nil, conversationId: fallbackConversationId)
      context.conversationId = fallbackConversationId
      context.sessionId = V2NIMConversationIdUtil.conversationTargetId(fallbackConversationId)
    }
    context.anchorMessage = selection.anchorMessage
    context.pendingMessages = selection.pendingMessages
    switch context.kind {
    case .p2p:
      pushedRoute = .p2pChat(context)
    case .team:
      pushedRoute = .teamChat(context)
    default:
      pushedRoute = .unsupported(.unsupported(url: context.conversationId, reason: "unsupported_chat_route"))
    }
  }

  private func chatKind(for message: V2NIMMessage?, conversationId: String) -> ChatSessionKind {
    switch message?.conversationType ?? V2NIMConversationIdUtil.conversationType(conversationId) {
    case .CONVERSATION_TYPE_P2P:
      return .p2p
    case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
      return .team
    default:
      return .history
    }
  }

  private var rowGroupHorizontalPadding: CGFloat {
    token.styleMode == .fun ? 0 : 20
  }

  private var rowGroupCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : 8
  }

  private var rowDividerLeadingInset: CGFloat {
    token.styleMode == .fun ? 16 : 36
  }

  private var settingPageBackground: Color {
    token.styleMode == .fun ? token.pageBackground : NEUIKitSwiftUIStyle.ColorToken.lightBackground
  }

  private var settingNavigationBackground: Color {
    token.panelItemBackground
  }
}

private enum P2PSettingRoute: Identifiable, Equatable {
  case pinMessages(conversationId: String)
  case historySearch(conversationId: String)
  case p2pChat(ChatSessionContext)
  case teamChat(ChatSessionContext)
  case unsupported(NEChatSwiftUIRoute)

  var id: String {
    switch self {
    case let .pinMessages(conversationId):
      return "p2pSettingPinMessages:\(conversationId)"
    case let .historySearch(conversationId):
      return "p2pSettingHistorySearch:\(conversationId)"
    case let .p2pChat(context):
      return "p2pSettingP2PChat:\(context.id)"
    case let .teamChat(context):
      return "p2pSettingTeamChat:\(context.id)"
    case let .unsupported(route):
      return "p2pSettingUnsupported:\(route.id)"
    }
  }
}

private struct P2PSettingHeaderView: View {
  var snapshot: NEChatSwiftUIP2PSettingSnapshot
  var token: ChatThemeToken
  var onCreateDiscuss: () -> Void

  private let headerHeight: CGFloat = 86
  private let avatarSize: CGFloat = 60
  private let discussAvatarSize: CGFloat = 42

  var body: some View {
    Group {
      if snapshot.canCreateDiscuss {
        discussHeader
      } else {
        normalHeader
      }
    }
    .frame(height: headerHeight)
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: headerCornerRadius, style: .continuous))
    .padding(.horizontal, token.styleMode == .fun ? 0 : 20)
  }

  private var normalHeader: some View {
    HStack(spacing: 16) {
      NEChatCommonPresentation.avatarView(
        imageURL: ChatAvatarURLResolver.url(from: snapshot.avatarURL),
        initials: snapshot.shortName,
        token: token,
        size: avatarSize,
        cornerRadius: avatarSize / 2,
        hashID: snapshot.accountId
      )

      Text(snapshot.displayName)
        .font(.system(size: 16))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.leading, 16)
    .padding(.trailing, 0)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: headerHeight)
  }

  private var discussHeader: some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(spacing: 6) {
        NEChatCommonPresentation.avatarView(
          imageURL: ChatAvatarURLResolver.url(from: snapshot.avatarURL),
          initials: snapshot.shortName,
          token: token,
          size: discussAvatarSize,
          cornerRadius: discussAvatarCornerRadius,
          hashID: snapshot.accountId
        )

        Text(snapshot.displayName)
          .font(.system(size: 12))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
          .multilineTextAlignment(.center)
          .frame(width: discussAvatarSize + 24)
      }
      .frame(width: discussAvatarSize + 24)

      NEChatCommonPresentation.iconButton(
        imageName: "setting_add",
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_create_discuss", value: "Create Discussion"),
        token: token,
        renderingMode: .original,
        size: CGSize(width: discussAvatarSize, height: discussAvatarSize),
        font: .system(size: 18, weight: .semibold),
        action: onCreateDiscuss
      )
      .padding(.leading, 8)
    }
    .padding(.leading, 4)
    .padding(.top, 12)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .frame(height: headerHeight, alignment: .top)
  }

  private var headerCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : 8
  }

  private var discussAvatarCornerRadius: CGFloat {
    token.styleMode == .normal ? 21 : token.controlCornerRadius / 2
  }
}

private struct P2PSettingRowView: View {
  var row: P2PSettingRowState
  var token: ChatThemeToken
  var onSelect: (P2PSettingRowState) -> Void
  var onToggle: (P2PSettingRowState, Bool) -> Void

  var body: some View {
    if row.isToggle {
      NEChatCommonPresentation.settingToggleRow(
        title: row.title,
        subtitle: settingSubtitle,
        isOn: Binding(
          get: { row.isOn },
          set: { onToggle(row, $0) }
        ),
        token: token,
        isEnabled: row.isEnabled,
        minHeight: rowHeight,
        leadingPadding: leadingInset,
        trailingPadding: switchTrailingInset,
        verticalPadding: 0,
        titleLineLimit: 1,
        subtitleLineLimit: 1
      )
    } else {
      NEChatCommonPresentation.settingRow(
        title: row.title,
        subtitle: settingSubtitle,
        token: token,
        isEnabled: row.isEnabled,
        minHeight: rowHeight,
        leadingPadding: leadingInset,
        trailingPadding: arrowTrailingInset,
        verticalPadding: 0,
        titleLineLimit: 1,
        subtitleLineLimit: 1,
        action: { onSelect(row) }
      )
    }
  }

  private var settingSubtitle: String? {
    guard token.styleMode == .normal,
          let subtitle = row.subtitle,
          !subtitle.isEmpty else {
      return nil
    }
    return subtitle
  }

  private var rowHeight: CGFloat {
    token.styleMode == .fun ? 56 : 49
  }

  private var leadingInset: CGFloat {
    token.styleMode == .fun ? 16 : 36
  }

  private var arrowTrailingInset: CGFloat {
    token.styleMode == .fun ? 20 : 36
  }

  private var switchTrailingInset: CGFloat {
    token.styleMode == .fun ? 14 : 36
  }
}
