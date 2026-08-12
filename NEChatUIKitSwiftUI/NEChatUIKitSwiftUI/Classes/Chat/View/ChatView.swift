// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import SwiftUI
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

private struct NEChatChildRouteBackActionKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
  var neChatChildRouteBackAction: (() -> Void)? {
    get { self[NEChatChildRouteBackActionKey.self] }
    set { self[NEChatChildRouteBackActionKey.self] = newValue }
  }
}

public struct ChatView: View {
  private static let applicationWillResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
  private static let applicationDidEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
  private static let applicationDidBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
  private static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
  private static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
  private static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
  private static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"

  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var viewModel: ChatSessionViewModel
  @State private var isSecurityWarningDismissed = false
  @State private var pushedRoute: NEChatSwiftUIRoute?
  @State private var presentedMediaPreview: ChatMediaPreviewState?
  @State private var isInputTranslationLanguagePickerPresented = false
  @State private var inputOverlayHeight: CGFloat = Self.normalInputOverlayReservedHeight
  @State private var routePresentationGeneration = 0
  @State private var routeAwaitingKeyboardDismissalGeneration: Int?
  @State private var isInputFocused = false
  @State private var isKeyboardVisible = false
  @State private var isTimelineReady = false
  @State private var isApplicationActive: Bool
  @State private var wasTimelinePresentationActive = false
  @State private var timelineVisibilityMeasurementGeneration = 0
  @State private var handledTeamLifecycleExitIds = Set<String>()
  private let token: ChatThemeToken
  private let browserDestination: ((URL, String) -> AnyView)?
  private let onReplaceChatRoute: ((NEChatSwiftUIRoute) -> Void)?
  private let onTeamLifecycleExit: ((String) -> Void)?

  @MainActor
  public init(viewModel: ChatSessionViewModel,
              token: ChatThemeToken? = nil,
              browserDestination: ((URL, String) -> AnyView)? = nil,
              onReplaceChatRoute: ((NEChatSwiftUIRoute) -> Void)? = nil,
              onTeamLifecycleExit: ((String) -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    _isApplicationActive = State(initialValue: viewModel.config.isApplicationActiveProvider())
    self.token = token ?? viewModel.config.themeToken
    self.browserDestination = browserDestination
    self.onReplaceChatRoute = onReplaceChatRoute
    self.onTeamLifecycleExit = onTeamLifecycleExit
  }

  public var body: some View {
    chatPresentationContent
  }

  private var chatRootContent: some View {
    VStack(spacing: 0) {
      if viewModel.config.shouldShowTitleBar {
        header
      }
      bodyTopContent
      content
        .overlay {
        }
      bodyBottomContent

      if viewModel.state.multiSelect == nil {
        inputOverlay
      }

      if let multiSelect = viewModel.state.multiSelect {
        MultiSelectActionBar(
          state: multiSelect,
          token: token,
          onSingleForward: { viewModel.requestSelectedForward(merged: false) },
          onMergedForward: { viewModel.requestSelectedForward(merged: true) },
          onDelete: { viewModel.requestSelectedDelete() },
          onCancel: { viewModel.clearSelection() }
        )
      }
    }
  }

  private var chatChromeContent: some View {
    chatRootContent
      .ignoresSafeArea(.container, edges: .bottom)
      .onPreferenceChange(ChatInputOverlayHeightPreferenceKey.self) { height in
        DispatchQueue.main.async {
          guard height > 0, abs(inputOverlayHeight - height) > 0.5 else {
            return
          }
          let didExpand = height > inputOverlayHeight
          inputOverlayHeight = height
          if didExpand {
            viewModel.inputAreaDidExpand()
          }
        }
      }
      .background(token.pageBackground)
      .overlay {
        voiceRecordingOverlay
      }
      .chatTheme(token)
      .navigationBarBackButtonHidden(true)
      .toolbar(.hidden, for: .navigationBar)
      .onAppear {
        isTimelineReady = true
        isApplicationActive = viewModel.config.isApplicationActiveProvider()
        viewModel.onAppear()
        updatePageVisibility()
      }
      .onDisappear {
        isTimelineReady = false
        wasTimelinePresentationActive = false
        viewModel.onDisappear()
      }
      .onChange(of: pushedRoute) { _ in
        updatePageVisibility()
      }
      .onChange(of: presentedMediaPreview?.id) { _ in
        updatePageVisibility()
      }
      .onChange(of: viewModel.state.clientRuntime.shouldShowNetworkWarning) { isVisible in
        NEChatSwiftUILogger.log(
          "offlineHistory banner conversationId=\(viewModel.context.conversationId) visible=\(isVisible) rows=\(viewModel.state.rows.count) loadingOlder=\(viewModel.state.isLoadingOlder) hasMoreOlder=\(viewModel.state.hasMoreOlder)"
        )
      }
      .onChange(of: scenePhase) { phase in
        guard phase == .active else {
          applicationDidBecomeInactive()
          return
        }
        // scenePhase and UIApplication notifications are delivered in an
        // unspecified order. Recheck on the next run loop so the active state
        // cannot remain false after returning from the background.
        DispatchQueue.main.async {
          isApplicationActive = viewModel.config.isApplicationActiveProvider()
          updatePageVisibility()
        }
      }
      .onChange(of: viewModel.state.teamLifecycleAlert) { alert in
        guard alert?.requiresUserConfirmation == false else {
          return
        }
        let teamId = alert?.teamId
        viewModel.closeTeamLifecycleRouteIfNeeded()
        if let teamId {
          notifyTeamLifecycleExitIfNeeded(teamId: teamId)
        }
      }
  }

  private var chatPresentationContent: some View {
    chatChromeContent
      .neCommonTransientOverlay(
        viewModel.state.toast,
        placement: .top,
        topPadding: 52,
        onDismiss: { viewModel.consumeToast($0) }
      ) { toast in
        ChatToastView(toast: toast, token: token)
      }
      .neCommonConfirmationDialog(
        pendingConfirmationDialogState,
        onAction: handlePendingConfirmationDialogAction,
        onDismiss: {
          viewModel.dismissPendingAction()
        }
      )
      .neCommonConfirmationDialog(
        teamLifecycleDialogState,
        onAction: handleTeamLifecycleDialogAction,
        onDismiss: {}
      )
      .modifier(ChatCompatibleNavigationDestinationModifier(item: pushedRouteItemBinding) { route in
        routeDestination(route)
          .environment(\.neChatChildRouteBackAction, childRouteBackAction(for: route))
          .onAppear {
            // Match UIKit viewWillDisappear even when a custom destination keeps
            // the parent SwiftUI chat view mounted in the navigation stack.
            viewModel.setPageVisible(false)
          }
      }
      )
      .fullScreenCover(item: presentedMediaPreviewBinding) { preview in
        ChatMediaPreviewView(
          preview: preview,
          token: token,
          onSaveImage: viewModel.config.mediaImageSaveHandler
        )
        .ignoresSafeArea()
      }
      .sheet(isPresented: $isInputTranslationLanguagePickerPresented) {
        if let inputTranslation = viewModel.state.inputTranslation {
          ChatInputTranslationLanguagePickerSheet(
            state: inputTranslation,
            token: token,
            onSelect: { language in
              viewModel.selectInputTranslationLanguage(language)
              isInputTranslationLanguagePickerPresented = false
            },
            onCancel: {
              isInputTranslationLanguagePickerPresented = false
            }
          )
          .presentationDetents([.height(404)])
          .presentationDragIndicator(.hidden)
          .modifier(ChatTranslationPickerPresentationModifier())
        }
      }
      .onChange(of: viewModel.state.route.currentRoute?.id) { _ in
        syncRoutePresentation()
      }
      .onReceive(NotificationCenter.default.publisher(for: Self.keyboardWillShowNotification)) { notification in
        isKeyboardVisible = true
        syncTimelineForKeyboardAppearance(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: Self.keyboardWillHideNotification)) { _ in
        isKeyboardVisible = false
      }
      .onReceive(NotificationCenter.default.publisher(for: Self.applicationWillResignActiveNotification)) { _ in
        applicationDidBecomeInactive()
      }
      .onReceive(NotificationCenter.default.publisher(for: Self.applicationDidEnterBackgroundNotification)) { _ in
        applicationDidBecomeInactive()
      }
      .onReceive(NotificationCenter.default.publisher(for: Self.applicationDidBecomeActiveNotification)) { _ in
        isApplicationActive = viewModel.config.isApplicationActiveProvider()
        updatePageVisibility()
      }
      .onReceive(NotificationCenter.default.publisher(for: Self.keyboardDidHideNotification)) { _ in
        isKeyboardVisible = false
        resumeRoutePresentationAfterKeyboardDismissal()
        viewModel.inputAreaDidContract()
      }
      .onChange(of: viewModel.timelineScrollTarget?.id) { targetId in
        let target = viewModel.timelineScrollTarget
        NEChatSwiftUILogger.log(
          "chatAction scrollTarget viewChanged id=\(targetId ?? "nil") messageId=\(target?.messageId ?? "nil") anchor=\(target?.anchor.rawValue ?? "nil") reason=\(target?.reason.rawValue ?? "nil") ageMs=\(target?.ageMilliseconds.description ?? "nil") state=\(viewModel.state.timelineScrollTarget?.id ?? "nil") rows=\(viewModel.state.rows.count) last=\(viewModel.state.rows.last?.id ?? "nil") indicator=\(viewModel.state.newMessageIndicator?.count.description ?? "nil")"
        )
      }
  }

  @ViewBuilder
  private var voiceRecordingOverlay: some View {
    if token.styleMode == .fun,
       viewModel.state.input.recording.isActive {
      FunVoiceRecordingOverlay(
        state: viewModel.state.input.recording,
        token: token
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)
    }
  }

  private var header: some View {
    NECommonNavigationBarView(
      title: "",
      backAction: {
        dismiss()
      },
      trailingAction: titleBarRightAction,
      onTrailingAction: viewModel.state.multiSelect != nil
        ? { viewModel.clearSelection() }
        : (viewModel.config.shouldShowTitleBarRightAction
          ? { viewModel.performTitleBarRightAction() }
          : nil),
      backgroundColor: token.navigationBackground,
      separatorColor: token.dividerColor,
      showsSeparator: true,
      titleTruncationMode: .middle
    )
    .neCommonTheme(NEChatCommonPresentation.commonTheme(for: token))
    .overlay(alignment: .top) {
      HStack(spacing: 4) {
        Text(chatTitle)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.middle)
        if isEarpieceMode {
          Image("op_earpiece", bundle: NEChatUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("operation_earpiece", value: "Earpiece"))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .padding(.horizontal, 72)
      .allowsHitTesting(false)
    }
  }

  private var isEarpieceMode: Bool {
    !SettingRepo.shared.getHandsetMode()
  }

  private var chatTitle: String {
    guard let p2pPresenceSubtitle else {
      return viewModel.title
    }
    if viewModel.state.p2pPresence.isTyping {
      return p2pPresenceSubtitle
    }
    return viewModel.title + p2pPresenceSubtitle
  }

  private var titleBarRightAction: NECommonNavigationAction? {
    if viewModel.state.multiSelect != nil {
      return NECommonNavigationAction(
        id: "chatMultiSelectCancel",
        title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel")
      )
    }
    guard viewModel.config.shouldShowTitleBarRightAction else {
      return nil
    }

    if let imageName = viewModel.config.titleBarRightImageName {
      return NECommonNavigationAction(
        id: "chatTitleRight",
        title: NEChatUIKitSwiftUIBundle.localized("chat_more", value: "More"),
        imageName: imageName,
        imageBundle: NEChatUIKitSwiftUIBundle.bundle,
        imageSize: CGSize(width: 24, height: 24)
      )
    }

    return NECommonNavigationAction(
      id: "chatTitleRight",
      title: NEChatUIKitSwiftUIBundle.localized("chat_more", value: "More"),
      systemImage: viewModel.config.titleBarRightSystemImageName,
      imageSize: CGSize(width: 20, height: 20)
    )
  }

  private var p2pPresenceSubtitle: String? {
    guard viewModel.context.kind == .p2p,
          viewModel.config.isP2PPresenceEnabled else {
      return nil
    }
    if viewModel.state.p2pPresence.isTyping {
      return NEChatUIKitSwiftUIBundle.localized("editing", value: "Typing")
    }
    let accountId = viewModel.context.sessionId ??
      V2NIMConversationIdUtil.conversationTargetId(viewModel.context.conversationId)
    guard IMKitConfigCenter.shared.enableOnlineStatus,
          let accountId,
          !NEAIUserManager.shared.isAIUser(accountId) else {
      return nil
    }
    return viewModel.state.p2pPresence.isOnline
      ? NEChatUIKitSwiftUIBundle.localized("p2p_chat_online", value: "(Online)")
      : NEChatUIKitSwiftUIBundle.localized("p2p_chat_offline", value: "(Offline)")
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .empty:
      VStack(spacing: 0) {
        chatStatusBanners
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    case .loading:
      NEChatCommonPresentation.loadingView(token: token)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      NEChatCommonPresentation.errorView(error, token: token) {
        viewModel.retryInitialLoad()
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    default:
      ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
          chatStatusBanners

          if let topMessage = viewModel.state.topMessage {
            TopPinnedMessageBanner(state: topMessage, token: token) {
              NEChatSwiftUILogger.log(
                "chatAction topBanner buttonTap id=\(topMessage.id) source=\(topMessage.source) rowId=\(topMessage.row?.id ?? "nil") rowServerId=\(topMessage.row?.serverId ?? "nil")"
              )
              viewModel.focusTopMessage()
            } onClose: {
              viewModel.closeTopMessage()
            }
          }

          ChatTimelineView(
              rows: viewModel.state.rows,
              isLoadingOlder: viewModel.state.isLoadingOlder,
              isLoadingNewer: viewModel.state.isLoadingNewer,
              hasMoreOlder: viewModel.state.hasMoreOlder,
              hasMoreNewer: viewModel.state.hasMoreNewer,
              isOlderPaginationSuspended: viewModel.isOlderPaginationSuspendedForNetworkBreak,
              isMultiSelecting: viewModel.state.multiSelect != nil,
              isActive: isTimelineActive,
              visibilityMeasurementGeneration: timelineVisibilityMeasurementGeneration,
              diagnosticConversationId: viewModel.context.conversationId,
              scrollTarget: viewModel.timelineScrollTarget,
              isScrollTargetCurrent: { target in
                guard let current = viewModel.timelineScrollTarget else {
                  return false
                }
                return current.id == target.id
              },
              keepsBottomPinned: viewModel.state.keepsTimelineBottomPinned,
              operationMenu: viewModel.state.operationMenu,
              token: token,
              shouldShowAvatar: { row in
                viewModel.config.shouldShowAvatar(row, viewModel.context)
              },
              shouldShowSenderName: { row in
                viewModel.config.shouldShowSenderName(row, viewModel.context)
              },
              customMessageContent: { row in
                viewModel.config.messageContentProvider?(
                  customMessageContext(for: row)
                )
              },
              customMessageLayout: { row in
                defaultCustomMessageLayout(for: row)
              },
              canLoadOlder: { viewModel.canLoadOlderMessages },
              onLoadOlder: { viewModel.loadOlderMessages(visibleAnchorId: $0) },
              onLoadNewer: { viewModel.loadNewerMessages() },
              onVisibleAnchorChange: { viewModel.updateVisibleTimelineAnchor($0) },
              onVisibleRowsChange: { viewModel.updateVisibleTimelineRows($0) },
              onLatestRowVisibilityChange: { viewModel.updateLatestTimelineRowVisibility($0) },
              onBottomVisibilityChange: { viewModel.updateTimelineBottomVisibility($0) },
              onScrollInteraction: {
                viewModel.timelineInteractionWillDismissInput()
                viewModel.dismissInputKeyboard()
                viewModel.dismissOperations()
              },
              onScrollTargetConsumed: { targetId in
                let didCompleteRouteTimelineRestore = viewModel.consumeTimelineScrollTarget(id: targetId)
                if didCompleteRouteTimelineRestore {
                  requestFreshVisibleTimelineMeasurement()
                }
              },
              onSelect: { viewModel.toggleSelection(for: $0.id) },
              onAvatarTap: { viewModel.handleAvatarTap($0) },
              onAvatarLongPress: { viewModel.handleAvatarLongPress($0) },
              onTap: { row in
                if !viewModel.handleMessageInteraction(.messageTap, row: row) {
                  viewModel.handleMessageTap(row)
                }
              },
              onAIStreamAction: { action, row in
                viewModel.performAIStreamAction(action, messageId: row.id)
              },
              onReedit: { row in
                viewModel.reeditMessage(row)
              },
              onReplyTap: { row in
                viewModel.focusReply(for: row)
              },
              onOpenURL: { url, displayText, source, row in
                guard viewModel.state.multiSelect == nil else {
                  return
                }
                viewModel.handleURLInteraction(
                  url,
                  displayText: displayText,
                  source: source,
                  message: row
                )
              },
              onReadReceiptTap: { row in
                if !viewModel.handleMessageInteraction(.readReceipt, row: row) {
                  viewModel.openReadReceipt(row: row)
                }
              },
              onResendTap: { row in
                viewModel.retryFailedMessage(row)
              }
            ) { row in
              if !viewModel.handleMessageInteraction(.messageLongPress, row: row) {
                viewModel.showOperations(for: row)
              }
            } onTextSelectionChange: { row, selectedText, isFullSelection in
              viewModel.updateTextSelection(
                selectedText,
                isFullSelection: isFullSelection,
                for: row.id
              )
            } onOperationSelect: { operation, messageId in
              viewModel.performOperation(operation, messageId: messageId)
            } onOperationDismiss: {
              viewModel.dismissOperations()
            }
          .id(viewModel.state.timelinePresentationGeneration)
        }

        if viewModel.state.multiSelect == nil,
           let indicator = viewModel.state.newMessageIndicator,
           indicator.count >= 0 {
          NewMessageIndicatorView(state: indicator, token: token) {
            NEChatSwiftUILogger.log(
              "chatAction jumpDown buttonTap count=\(indicator.count) first=\(indicator.firstMessageId ?? "nil") requiresReload=\(indicator.requiresLatestReload) currentTarget=\(viewModel.timelineScrollTarget?.id ?? "nil") currentReason=\(viewModel.timelineScrollTarget?.reason.rawValue ?? "nil") targetAgeMs=\(viewModel.timelineScrollTarget?.ageMilliseconds.description ?? "nil") rows=\(viewModel.state.rows.count) last=\(viewModel.state.rows.last?.id ?? "nil")"
            )
            viewModel.clearNewMessageIndicator()
          }
          .padding(.trailing, indicator.count > 0 ? -16 : 16)
          .padding(.bottom, newMessageIndicatorBottomPadding)
        }
      }
    }
  }

  private var pendingConfirmationTitle: String {
    guard let pending = viewModel.state.pendingConfirmation else {
      return ""
    }

    switch pending {
    case .deleteMessage:
      return NEChatUIKitSwiftUIBundle.localized("message_delete_confirm", value: "Whether to delete this message")
    case .revokeMessage:
      return NEChatUIKitSwiftUIBundle.localized("message_revoke_confirm", value: "Whether to recall this message")
    case let .deleteSelected(messageIds):
      return String(format: NEChatUIKitSwiftUIBundle.localized("chat_confirm_delete_selected_format", value: "Delete %d selected messages?"), messageIds.count)
    case .forwardSelected:
      return NEChatUIKitSwiftUIBundle.localized("exception_description", value: "Exception details")
    }
  }

  private var pendingConfirmationMessage: String? {
    guard case .forwardSelected = viewModel.state.pendingConfirmation else {
      return nil
    }
    return NEChatUIKitSwiftUIBundle.localized(
      "exist_invalid",
      value: "Some messages can't be forwarded. Remove them before retry?"
    )
  }

  private var pendingConfirmationDialogState: NECommonDialogState? {
    let hasPendingConfirmation = viewModel.state.pendingConfirmation != nil
    guard hasPendingConfirmation,
          let pending = viewModel.state.pendingConfirmation else {
      return nil
    }
    let confirmRole: NECommonDialogActionRole
    switch pending {
    case .deleteMessage, .deleteSelected, .revokeMessage:
      confirmRole = .normal
    case .forwardSelected:
      confirmRole = .normal
    }

    return NECommonDialogState(
      id: "chatPendingConfirmation:\(viewModel.state.pendingConfirmation?.id ?? "")",
      title: pendingConfirmationTitle,
      message: pendingConfirmationMessage,
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "confirm",
          title: NEChatUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: confirmRole
        ),
      ]
    )
  }

  private var teamLifecycleDialogState: NECommonDialogState? {
    // Match UIKit: only the currently visible route owns system alert presentation.
    // Keep the lifecycle state pending while a child page handles the same event.
    guard pushedRoute == nil else {
      return nil
    }
    guard let alert = viewModel.state.teamLifecycleAlert else {
      return nil
    }
    guard alert.requiresUserConfirmation else {
      return nil
    }

    return NECommonDialogState(
      id: alert.id,
      title: alert.message,
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "confirm",
          title: NEChatUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal
        ),
      ]
    )
  }

  private func handlePendingConfirmationDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "confirm":
      viewModel.confirmPendingAction()
    default:
      viewModel.dismissPendingAction()
    }
  }

  private func handleTeamLifecycleDialogAction(_ action: NECommonDialogAction) {
    guard action.id == "confirm" else {
      return
    }
    confirmTeamLifecycleAndDismiss()
  }

  private func confirmTeamLifecycleAndDismiss() {
    guard let alert = viewModel.state.teamLifecycleAlert else {
      return
    }
    viewModel.confirmTeamLifecycleAlert()
    notifyTeamLifecycleExitIfNeeded(teamId: alert.teamId)
  }

  private var pushedRouteItemBinding: Binding<NEChatSwiftUIRoute?> {
    Binding(
      get: { pushedRoute },
      set: { nextRoute in
        if let nextRoute {
          pushedRoute = nextRoute
        } else {
          handleSystemPushedRouteDismissal()
        }
      }
    )
  }

  private var presentedMediaPreviewBinding: Binding<ChatMediaPreviewState?> {
    Binding(
      get: { presentedMediaPreview },
      set: { nextPreview in
        if let nextPreview {
          presentedMediaPreview = nextPreview
        } else {
          handlePresentedMediaPreviewDismissal()
        }
      }
    )
  }

  private func handlePresentedMediaPreviewDismissal() {
    guard presentedMediaPreview != nil else {
      return
    }
    viewModel.restoreTimelinePositionAfterRouteReturnIfNeeded()
    presentedMediaPreview = nil
    viewModel.clearRoute()
  }

  private func handleSystemPushedRouteDismissal() {
    guard let closingRoute = pushedRoute else {
      return
    }
    let shouldRestoreTimeline = shouldRestoreTimelinePosition(after: closingRoute)
    if shouldRestoreTimeline {
      viewModel.restoreTimelinePositionAfterRouteReturnIfNeeded()
    } else {
      viewModel.discardTimelinePositionRestore()
    }
    viewModel.refreshContactDisplayAfterUserProfileReturnIfNeeded(closingRoute)
    pushedRoute = nil
    viewModel.clearRoute()
  }

  private func syncRoutePresentation() {
    routePresentationGeneration += 1
    let generation = routePresentationGeneration
    guard let route = viewModel.state.route.currentRoute else {
      routeAwaitingKeyboardDismissalGeneration = nil
      let returningRoute = pushedRoute
      let shouldRestoreTimeline = returningRoute.map { shouldRestoreTimelinePosition(after: $0) } ?? false
      if returningRoute != nil {
        if shouldRestoreTimeline {
          viewModel.restoreTimelinePositionAfterRouteReturnIfNeeded()
        } else {
          viewModel.discardTimelinePositionRestore()
        }
        if let returningRoute {
          viewModel.refreshContactDisplayAfterUserProfileReturnIfNeeded(returningRoute)
        }
      }
      pushedRoute = nil
      updatePageVisibility()
      return
    }
    if pushedRoute == nil && presentedMediaPreview == nil {
      viewModel.captureTimelinePositionBeforeRoute()
    }
    viewModel.setPageVisible(false)
    dismissInputBeforePresentingRoute(route, generation: generation)
  }

  private func dismissInputBeforePresentingRoute(_ route: NEChatSwiftUIRoute,
                                                 generation: Int) {
    let shouldAwaitKeyboardDismissal = isInputFocused || isKeyboardVisible
    routeAwaitingKeyboardDismissalGeneration = shouldAwaitKeyboardDismissal ? generation : nil
    viewModel.dismissInputKeyboard()
    guard shouldAwaitKeyboardDismissal else {
      scheduleRoutePresentationAfterInputSettles(route, generation: generation)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
      guard routeAwaitingKeyboardDismissalGeneration == generation else {
        return
      }
      resumeRoutePresentationAfterKeyboardDismissal()
    }
  }

  private func resumeRoutePresentationAfterKeyboardDismissal() {
    guard let generation = routeAwaitingKeyboardDismissalGeneration else {
      return
    }
    guard let route = viewModel.state.route.currentRoute,
          isCurrentRoutePresentation(route, generation: generation) else {
      routeAwaitingKeyboardDismissalGeneration = nil
      return
    }
    routeAwaitingKeyboardDismissalGeneration = nil
    scheduleRoutePresentationAfterInputSettles(route, generation: generation)
  }

  private func scheduleRoutePresentationAfterInputSettles(_ route: NEChatSwiftUIRoute,
                                                          generation: Int) {
    DispatchQueue.main.async {
      guard isCurrentRoutePresentation(route, generation: generation) else {
        return
      }
      DispatchQueue.main.async {
        guard isCurrentRoutePresentation(route, generation: generation) else {
          return
        }
        presentRoute(route)
      }
    }
  }

  private func isCurrentRoutePresentation(_ route: NEChatSwiftUIRoute,
                                          generation: Int) -> Bool {
    routePresentationGeneration == generation &&
      viewModel.state.route.currentRoute?.id == route.id
  }

  private func presentRoute(_ route: NEChatSwiftUIRoute) {
    if case let .mediaPreview(preview) = route,
       preview.kind == .image {
      pushedRoute = nil
      presentedMediaPreview = preview
      viewModel.clearRoute()
      return
    }
    pushedRoute = route
  }

  private var isTimelineActive: Bool {
    isTimelineReady && isTimelinePresentationActive
  }

  private var isTimelinePresentationActive: Bool {
    pushedRoute == nil &&
      presentedMediaPreview == nil &&
      isApplicationActive
  }

  private func updatePageVisibility() {
    let isVisible = isTimelineActive
    viewModel.setPageVisible(isVisible)
    guard isVisible != wasTimelinePresentationActive else {
      return
    }
    wasTimelinePresentationActive = isVisible
    guard isVisible else {
      return
    }
    requestFreshVisibleTimelineMeasurement()
  }

  private func requestFreshVisibleTimelineMeasurement() {
    timelineVisibilityMeasurementGeneration &+= 1
    let generation = timelineVisibilityMeasurementGeneration
    // The first pass reattaches the geometry probes. A second pass on the next
    // run loop guarantees that rows inserted while backgrounded are measured
    // after SwiftUI has committed the foreground layout.
    DispatchQueue.main.async {
      guard self.isTimelineActive,
            self.timelineVisibilityMeasurementGeneration == generation else {
        return
      }
      self.timelineVisibilityMeasurementGeneration &+= 1
    }
  }

  private func applicationDidBecomeInactive() {
    isApplicationActive = false
    updatePageVisibility()
  }

  private func notifyTeamLifecycleExitIfNeeded(teamId: String) {
    guard !handledTeamLifecycleExitIds.contains(teamId) else {
      return
    }
    handledTeamLifecycleExitIds = handledTeamLifecycleExitIds.union([teamId])
    guard let onTeamLifecycleExit else {
      return
    }
    // The view model clears the nested chat route first. A custom host callback
    // runs on the next navigation transaction and owns the outer pop.
    DispatchQueue.main.async {
      onTeamLifecycleExit(teamId)
    }
  }

  private func syncTimelineForKeyboardAppearance(_ notification: Notification) {
    guard isTimelinePresentationActive else {
      return
    }
    // UIKit scrolls in keyboardWillShow. Repeat after the keyboard animation so
    // the SwiftUI scroll view uses its final reduced viewport height.
    viewModel.inputAreaDidExpand()
    let duration = notification.userInfo?[Self.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, duration)) {
      guard self.isInputFocused, self.isTimelinePresentationActive else {
        return
      }
      self.viewModel.inputAreaDidExpand()
    }
  }

  private func closePushedRoute() {
    // Mirror UIKit viewDidDisappear: stop any playing audio before
    // dismissing collection or other sub-routes.
    viewModel.stopActiveMedia()
    let shouldRestoreTimeline = shouldRestoreTimelinePosition(after: pushedRoute)
    if let pushedRoute {
      viewModel.refreshContactDisplayAfterUserProfileReturnIfNeeded(pushedRoute)
    }
    if shouldRestoreTimeline {
      viewModel.restoreTimelinePositionAfterRouteReturnIfNeeded()
    } else {
      viewModel.discardTimelinePositionRestore()
    }
    pushedRoute = nil
    presentedMediaPreview = nil
    viewModel.clearRoute()
  }

  private func childRouteBackAction(for route: NEChatSwiftUIRoute) -> () -> Void {
    {
      guard self.pushedRoute?.id == route.id else {
        return
      }
      self.closePushedRoute()
    }
  }

  private func openCreatedTeamChat(_ context: ChatSessionContext) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      closePushedRoute()
      let route = NEChatSwiftUIRoute.teamChat(context)
      if let onReplaceChatRoute {
        onReplaceChatRoute(route)
      } else {
        NEChatUIKitSwiftUIClient.shared.router.enqueue(route)
      }
    }
  }

  private func openP2PChatFromUserProfile(accountId: String, title: String) {
    guard !accountId.isEmpty,
          let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
      return
    }
    let context = ChatSessionContext(
      kind: .p2p,
      conversationId: conversationId,
      title: title,
      sessionId: accountId,
      sessionName: title
    )
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      closePushedRoute()
      let route = NEChatSwiftUIRoute.p2pChat(context)
      if let onReplaceChatRoute {
        onReplaceChatRoute(route)
      } else {
        NEChatUIKitSwiftUIClient.shared.router.enqueue(route)
      }
    }
  }

  private func focusMessageAfterClosingRoute(_ row: MessageRowState) {
    pushedRoute = nil
    presentedMediaPreview = nil
    viewModel.focusMessage(row)
  }

  private func focusPinnedMessage(_ selection: PinMessageSelection) {
    NEChatSwiftUILogger.log(
      "messageJump route prepare \(messageJumpSelectionDescription(selection)) route=\(pushedRoute?.id ?? "nil") timelineActive=\(isTimelineActive) scene=\(scenePhase)"
    )
    viewModel.discardTimelinePositionRestore()
    viewModel.focusMessage(selection)
    NEChatSwiftUILogger.log(
      "messageJump route prepared \(messageJumpSelectionDescription(selection)) target=\(viewModel.timelineScrollTarget?.id ?? "pendingHistory") rows=\(viewModel.state.rows.count)"
    )
    pushedRoute = nil
    presentedMediaPreview = nil
    viewModel.clearRoute()
  }

  private func messageJumpSelectionDescription(_ selection: PinMessageSelection) -> String {
    "rowId=\(selection.row.id) serverId=\(selection.row.serverId ?? "nil") anchorClientId=\(selection.anchorMessage?.messageClientId ?? "nil") anchorServerId=\(selection.anchorMessage?.messageServerId ?? "nil") opensConversationOnly=\(selection.opensConversationOnly)"
  }

  private func shouldRestoreTimelinePosition(after route: NEChatSwiftUIRoute?) -> Bool {
    // UIKit keeps the chat controller and its pre-route table position for all
    // child details. Restore before making the timeline visible so covered
    // incoming messages remain below that position with a jump prompt.
    route != nil
  }

  @ViewBuilder
  private func routeDestination(_ route: NEChatSwiftUIRoute) -> some View {
    switch route {
    case let .pinMessages(conversationId):
      PinMessagesView(
        viewModel: PinMessagesViewModel(
          conversationId: conversationId,
          networkOperationGuard: chatNetworkOperationGuard
        ),
        token: token,
        onContentSelect: { row in
          viewModel.openUtilityMessageContent(row)
        },
        onSelectMessage: { selection in
          focusPinnedMessage(selection)
        },
        onCopy: { row in
          viewModel.copyUtilityMessage(row)
        },
        onForward: { row in
          viewModel.forwardUtilityMessage(row)
        },
        onForwardMessage: { row, sourceMessage in
          viewModel.forwardUtilityMessage(row, sourceMessage: sourceMessage)
        },
        onOpenURL: { url, displayText, source, row in
          viewModel.handleURLInteraction(
            url,
            displayText: displayText,
            source: source,
            message: row
          )
        },
        onBack: closePushedRoute,
        canCopy: { row in
          viewModel.canCopyUtilityMessage(row)
        },
        canForward: { row in
          viewModel.canForwardUtilityMessage(row)
        },
        playingAudioMessageId: viewModel.state.audioPlayback.messageId,
        onStopAudioPlayback: viewModel.stopActiveMedia
      )
    case let .historySearch(conversationId):
      HistorySearchView(
        viewModel: HistorySearchViewModel(
          conversationId: conversationId,
          fileInteractionHandler: viewModel.config.fileInteractionHandler,
          mediaPreviewHandler: viewModel.config.mediaPreviewHandler,
          networkOperationGuard: chatNetworkOperationGuard,
          sessionContextProvider: { viewModel.context },
          conversationNameProvider: { viewModel.title }
        ),
        token: token,
        onSelect: { row in
          focusMessageAfterClosingRoute(row)
        },
        onSelectMessage: { selection in
          focusPinnedMessage(selection)
        },
        onForward: { row in
          viewModel.forwardUtilityMessage(row)
        },
        onForwardMessage: { row, sourceMessage in
          viewModel.forwardUtilityMessage(row, sourceMessage: sourceMessage)
        },
        onForwardMessageWithToast: { row, sourceMessage, presentToast in
          viewModel.forwardUtilityMessage(
            row,
            sourceMessage: sourceMessage,
            resultToastHandler: presentToast
          )
        },
        onOpenURL: { url, displayText, source, row in
          viewModel.handleURLInteraction(
            url,
            displayText: displayText,
            source: source,
            message: row
          )
        },
        onSaveMedia: viewModel.config.mediaImageSaveHandler,
        onBack: closePushedRoute,
        canForward: { row in
          viewModel.canForwardUtilityMessage(row)
        }
      )
    case .collectionMessages:
      CollectionMessagesView(
        viewModel: CollectionMessagesViewModel(
          networkOperationGuard: chatNetworkOperationGuard
        ),
        token: token,
        onContentSelect: { row in
          viewModel.openCollectionMessage(row)
        },
        onSelectMessage: { selection in
          focusPinnedMessage(selection)
        },
        onCopy: { row in
          viewModel.copyCollectionMessage(row)
        },
        onForward: { row in
          viewModel.forwardUtilityMessage(row)
        },
        onForwardMessage: { row, sourceMessage in
          viewModel.forwardUtilityMessage(row, sourceMessage: sourceMessage)
        },
        onOpenURL: { url, displayText, source, row in
          if let messageRow = row.messageRow {
            viewModel.handleURLInteraction(
              url,
              displayText: displayText,
              source: source,
              message: messageRow
            )
          } else {
            viewModel.handleURLInteraction(
              url,
              displayText: displayText,
              source: source,
              preview: ChatTextPreviewState(
                messageId: row.id,
                body: row.previewText,
                source: .utility
              )
            )
          }
        },
        onBack: closePushedRoute,
        canCopy: { row in
          viewModel.canCopyUtilityMessage(row)
        },
        canForward: { row in
          viewModel.canForwardUtilityMessage(row)
        },
        playingAudioMessageId: viewModel.state.audioPlayback.messageId,
        onStopAudioPlayback: viewModel.stopActiveMedia
      )
    case let .readReceipt(messageId, _):
      ReadReceiptView(
        viewModel: ReadReceiptViewModel(
          messageId: messageId,
          networkOperationGuard: chatNetworkOperationGuard
        ),
        token: token
      )
    case let .aiRobot(state):
      switch state.kind {
      case .list:
        AIRobotEntryView(token: token) { route in
          viewModel.openRoute(route)
        }
      default:
        AIRobotRouteView(
          state: state,
          token: token,
          avatarSelectionHandler: viewModel.config.avatarSelectionHandler,
          configClipboardHandler: viewModel.config.aiRobotConfigClipboardHandler,
          onRoute: { viewModel.openRoute($0) },
          onDismiss: { viewModel.clearRoute() }
        )
      }
    case let .botSubSessionList(context):
      BotSubSessionListView(
        viewModel: BotSubSessionListViewModel(
          context: context,
          config: viewModel.config,
          networkOperationGuard: {
            viewModel.state.clientRuntime.shouldShowNetworkWarning == false
          }
        ),
        token: token,
        onRoute: { route in
          viewModel.openRoute(route)
        }
      )
    case let .botSubSessionChat(context):
      embeddedChatView(context: context)
    case let .userSetting(context):
      P2PSettingView(
        context: context,
        config: viewModel.config,
        token: token,
        onPinMessageSelect: { selection in
          focusPinnedMessage(selection)
        },
        onOpenUtilityMessageContent: { row in
          viewModel.openUtilityMessageContent(row)
        },
        onCopy: { row in
          viewModel.copyUtilityMessage(row)
        },
        onForward: { row in
          viewModel.forwardUtilityMessage(row)
        },
        onForwardMessage: { row, sourceMessage in
          viewModel.forwardUtilityMessage(row, sourceMessage: sourceMessage)
        },
        canCopy: { row in
          viewModel.canCopyUtilityMessage(row)
        },
        canForward: { row in
          viewModel.canForwardUtilityMessage(row)
        },
        networkOperationGuard: {
          viewModel.state.clientRuntime.shouldShowNetworkWarning == false
        },
        onOpenTeamChat: { context in
          openCreatedTeamChat(context)
        },
        onBack: closePushedRoute
      )
    case let .teamSetting(teamId, context):
      TeamSettingRouteHostView(
        teamId: teamId,
        context: context,
        provider: viewModel.config.teamSettingViewProvider,
        providerWithBackAction: viewModel.config.teamSettingViewProviderWithBackAction,
        providerWithActions: viewModel.config.teamSettingViewProviderWithActions,
        onBack: closePushedRoute,
        onSelectMessage: focusPinnedMessage,
        token: token
      )
    case let .userProfile(request):
      if let provider = viewModel.config.userProfilePushViewProviderWithChatRoute,
         let profileView = provider(request, token, openP2PChatFromUserProfile) {
        profileView
          .environment(\.neChatChildRouteBackAction, closePushedRoute)
      } else if let provider = viewModel.config.userProfilePushViewProvider,
         let profileView = provider(request, token) {
        profileView
          .environment(\.neChatChildRouteBackAction, closePushedRoute)
      } else {
        UnsupportedRouteView(
          title: request.displayName ?? request.accountId,
          reason: request.source == .selfAvatar
            ? NEChatUIKitSwiftUIBundle.localized("chat_user_profile_requires_mine_route", value: "User profile route should be handled by the SwiftUI Mine route host.")
            : NEChatUIKitSwiftUIBundle.localized("chat_user_profile_requires_contact_route", value: "User profile route should be handled by the SwiftUI Contact route host."),
          token: token
        )
      }
    case let .mediaPreview(preview):
      if let onSaveImage = viewModel.config.mediaImageSaveHandler {
        ChatMediaPreviewView(
          preview: preview,
          token: token,
          onSaveImage: onSaveImage,
          onClose: closePushedRoute
        )
      } else {
        ChatMediaPreviewView(preview: preview, token: token, onClose: closePushedRoute)
      }
    case let .filePreview(preview):
      ChatFilePreviewView(preview: preview, token: token)
    case let .textPreview(preview):
      ChatTextPreviewView(
        preview: preview,
        token: token,
        browserDestination: browserDestination
      ) { url, displayText, preview in
        viewModel.handleURLInteraction(
          url,
          displayText: displayText,
          source: .textPreview,
          preview: preview
        )
      }
    case let .multiForwardPreview(preview):
      MultiForwardMessagesView(
        viewModel: MultiForwardMessagesViewModel(
          preview: preview,
          networkOperationGuard: chatNetworkOperationGuard
        ),
        token: token,
        onSelect: { row in
          viewModel.openUtilityMessageContent(row)
        },
        onOpenURL: { url, displayText, source, row in
          viewModel.handleURLInteraction(
            url,
            displayText: displayText,
            source: source == .messageText ? .multiForwardPreview : source,
            message: row
          )
        },
        browserDestination: browserDestination,
        onSaveMedia: viewModel.config.mediaImageSaveHandler,
        onInitialLoadFailure: { error in
          viewModel.handleMultiForwardPreviewLoadFailure(error)
        },
        playingAudioMessageId: viewModel.state.audioPlayback.messageId
      )
      .environment(\.neChatChildRouteBackAction, closePushedRoute)
    case let .locationDetail(location):
      LocationDetailView(location: location, token: token)
    case let .forwardMessages(_, messageIds, merged):
      if let forwardSheet = viewModel.state.forwardSheet {
        ForwardSheetView(
          state: forwardSheet,
          token: token,
          onToggleTarget: { viewModel.toggleForwardTarget($0) },
          onCommentChange: { viewModel.updateForwardComment($0) },
          onConfirm: { viewModel.submitForwardSheet() },
          onCancel: { viewModel.dismissForwardSheet() }
        )
      } else {
        UnsupportedRouteView(
          title: merged
            ? NEChatUIKitSwiftUIBundle.localized("chat_forward_merged", value: "Merged Forward")
            : NEChatUIKitSwiftUIBundle.localized("chat_forward_one_by_one", value: "Forward One by One"),
          reason: String(format: NEChatUIKitSwiftUIBundle.localized("chat_forward_missing_state_format", value: "Forward state is missing for %d messages."), messageIds.count),
          token: token
        )
      }
    case let .moreAction(action, _):
      UnsupportedRouteView(
        title: action.rawValue,
        reason: NEChatUIKitSwiftUIBundle.localized("chat_more_action_requires_native_boundary", value: "This action requires a SwiftUI native boundary handler."),
        token: token
      )
    case let .unsupported(url, reason):
      UnsupportedRouteView(title: url, reason: reason, token: token)
    case .p2pChat, .teamChat:
      UnsupportedRouteView(
        title: NEChatUIKitSwiftUIBundle.localized("chat_route_nested_chat", value: "Chat route"),
        reason: NEChatUIKitSwiftUIBundle.localized("chat_route_nested_chat_desc", value: "Nested chat routes should be handled by the app route host."),
        token: token
      )
    }
  }

  @ViewBuilder
  private var bodyTopContent: some View {
    if let customView = viewModel.config.bodyTopContentProvider?(
      ChatBodyContentContext(
        session: viewModel.context,
        state: viewModel.state,
        placement: .top
      )
    ) {
      customView
    }
  }

  private func customMessageContext(for row: MessageRowState) -> ChatCustomMessageContext {
    ChatCustomMessageContext(row: row, session: viewModel.context)
  }

  private func defaultCustomMessageLayout(for row: MessageRowState) -> ChatCustomMessageLayout? {
    let context = customMessageContext(for: row)
    if let customLayout = viewModel.config.customMessageLayoutProvider?(context) {
      return customLayout
    }
    guard case .custom = row.content else {
      return nil
    }
    guard let customHeight = context.payload?.customHeight else {
      return nil
    }
    return ChatCustomMessageLayout(rowHeight: CGFloat(customHeight))
  }

  @ViewBuilder
  private var bodyBottomContent: some View {
    if let customView = viewModel.config.bodyBottomContentProvider?(
      ChatBodyContentContext(
        session: viewModel.context,
        state: viewModel.state,
        placement: .bottom
      )
    ) {
      customView
    }
  }

  @ViewBuilder
  private var chatStatusBanners: some View {
    securityWarning

    ChatNetworkBrokenBannerView(token: token)
      .frame(height: viewModel.state.clientRuntime.shouldShowNetworkWarning
        ? networkBrokenBannerHeight
        : 0)
      .opacity(viewModel.state.clientRuntime.shouldShowNetworkWarning ? 1 : 0)
      .clipped()
      .accessibilityHidden(!viewModel.state.clientRuntime.shouldShowNetworkWarning)
      .transaction { transaction in
        transaction.disablesAnimations = true
        transaction.animation = nil
      }

    if !viewModel.state.clientRuntime.shouldShowNetworkWarning {
      ChatRuntimeStatusBanner(
        runtime: viewModel.state.clientRuntime,
        readSync: viewModel.state.readSync,
        token: token
      )
    }
  }

  private var networkBrokenBannerHeight: CGFloat {
    token.styleMode == .fun ? 48 : 36
  }

  @ViewBuilder
  private var securityWarning: some View {
    if let customView = viewModel.config.securityWarningContentProvider?(
      ChatSecurityWarningContext(
        session: viewModel.context,
        isDismissed: isSecurityWarningDismissed,
        dismiss: {
          isSecurityWarningDismissed = true
        }
      )
    ) {
      if !isSecurityWarningDismissed {
        customView
      }
    } else if let customView = viewModel.config.securityWarningProvider?(viewModel.context) {
      customView
    }
  }

  @ViewBuilder
  private var inputAccessory: some View {
    VStack(spacing: 0) {
      if let inputTranslation = viewModel.state.inputTranslation {
        ChatInputTranslationPanelView(
          state: inputTranslation,
          token: token,
          onRequestLanguageSelection: {
            isInputTranslationLanguagePickerPresented = true
          },
          onClose: { viewModel.closeInputTranslation() },
          onStartOrUse: { viewModel.startOrUseInputTranslation() }
        )
      }

      if let customView = viewModel.config.inputAccessoryProvider?(
        ChatInputAccessoryContext(input: viewModel.state.input, session: viewModel.context)
      ) {
        customView
      }
    }
  }

  @ViewBuilder
  private var inputBar: some View {
    if let customView = viewModel.config.inputBarContentProvider?(
      ChatInputBarContentContext(
        input: viewModel.state.input,
        session: viewModel.context,
        layout: viewModel.config.inputBarLayout,
        actions: inputBarActions
      )
    ) {
      customView
    } else {
      defaultInputBar
    }
  }

  private var inputOverlay: some View {
    VStack(spacing: 0) {
      inputAccessory
      inputBar
    }
    .frame(minHeight: inputOverlayMinimumHeight, alignment: .top)
    .fixedSize(horizontal: false, vertical: true)
    .background(
      GeometryReader { proxy in
        token.inputBackground
          .preference(
            key: ChatInputOverlayHeightPreferenceKey.self,
            value: proxy.size.height
          )
      }
    )
    .transaction { transaction in
      transaction.disablesAnimations = true
      transaction.animation = nil
    }
  }

  private var newMessageIndicatorBottomPadding: CGFloat {
    24
  }

  private var inputOverlayMinimumHeight: CGFloat {
    guard token.styleMode == .fun else {
      return Self.normalInputOverlayReservedHeight
    }
    let reservedHeight = isKeyboardVisible
      ? Self.funKeyboardInputOverlayReservedHeight
      : Self.funInputOverlayReservedHeight
    guard viewModel.state.inputTranslation != nil else {
      return reservedHeight
    }
    return reservedHeight + Self.inputTranslationPanelHeight
  }

  private var defaultInputBar: some View {
    ChatInputBarView(
      state: Binding(
        get: { viewModel.state.input },
        set: { _ in }
      ),
      token: token,
      layout: viewModel.config.inputBarLayout,
      defaultPlaceholder: defaultInputPlaceholder,
      morePanelTopSpacing: funTranslationMorePanelSpacing,
      onTextChange: { viewModel.updateInputText($0) },
      onSelectionChange: { viewModel.updateInputSelection($0) },
      onRichTextTitleChange: { viewModel.updateRichTextTitle($0) },
      onRichTextTitleLimitReached: { viewModel.richTextTitleLimitReached() },
      onRichTextExpandedChange: { viewModel.setRichTextInputExpanded($0) },
      onLineBreak: { viewModel.insertInputLineBreak() },
      onModeChange: { setInputModeWithoutShortcutAnimation($0) },
      onInputFocusChange: { focused in
        isInputFocused = focused
        viewModel.inputFocusDidChange(focused)
      },
      onCancelReply: { viewModel.cancelReply() },
      onEmojiSelect: { viewModel.appendEmoji($0) },
      onEmojiDelete: { viewModel.deleteBackward() },
      onMoreAction: { viewModel.handleMoreAction($0) },
      onVoiceRecordStart: { viewModel.beginVoiceRecording() },
      onVoiceRecordCancelChange: { viewModel.updateVoiceRecording(cancelled: $0) },
      onVoiceRecordEnd: { viewModel.endVoiceRecording(cancelled: $0) },
      onMentionTrigger: { viewModel.requestMentionSelection(trigger: .inputAt) },
      onSend: {
        viewModel.sendText()
      }
    )
  }

  private var chatNetworkOperationGuard: () -> Bool {
    {
      viewModel.state.clientRuntime.shouldShowNetworkWarning == false
    }
  }

  fileprivate static let normalInputOverlayReservedHeight: CGFloat = 100
  fileprivate static let funInputOverlayReservedHeight: CGFloat = 90
  fileprivate static let funKeyboardInputOverlayReservedHeight: CGFloat = 60
  fileprivate static let inputTranslationPanelHeight: CGFloat = 70

  private var defaultInputPlaceholder: String {
    if token.styleMode == .fun {
      return NEChatUIKitSwiftUIBundle.localized(
        "fun_chat_input_placeholder",
        value: "Enter what you want to say..."
      )
    }

    return "\(NEChatUIKitSwiftUIBundle.localized("send_to", value: "Send to"))\(viewModel.title)"
  }

  private var funTranslationMorePanelSpacing: CGFloat {
    guard token.styleMode == .fun,
          !isKeyboardVisible,
          viewModel.state.input.mode == .more,
          viewModel.state.inputTranslation != nil else {
      return 0
    }
    return 30
  }

  private var inputBarActions: ChatInputBarActions {
    ChatInputBarActions(
      updateText: { viewModel.updateInputText($0) },
      setMode: { setInputModeWithoutShortcutAnimation($0) },
      cancelReply: { viewModel.cancelReply() },
      appendEmoji: { viewModel.appendEmoji($0) },
      deleteBackward: { viewModel.deleteBackward() },
      handleMoreAction: { viewModel.handleMoreAction($0) },
      beginVoiceRecording: { viewModel.beginVoiceRecording() },
      updateVoiceRecording: { viewModel.updateVoiceRecording(cancelled: $0) },
      endVoiceRecording: { viewModel.endVoiceRecording(cancelled: $0) },
      requestMentionSelection: { viewModel.requestMentionSelection(trigger: .inputAt) },
      send: { viewModel.sendText() }
    )
  }

  private func setInputModeWithoutShortcutAnimation(_ mode: ChatInputMode) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      viewModel.setInputMode(mode)
    }
  }
}

private struct TeamSettingRouteHostView: View {
  let teamId: String
  let context: ChatSessionContext
  let provider: ((String, ChatSessionContext) -> AnyView?)?
  let providerWithBackAction: ((String, ChatSessionContext, @escaping () -> Void) -> AnyView?)?
  let providerWithActions: ((String, ChatSessionContext, ChatTeamSettingActions) -> AnyView?)?
  let onBack: () -> Void
  let onSelectMessage: (PinMessageSelection) -> Void
  let token: ChatThemeToken

  @State private var destination: AnyView?

  var body: some View {
    Group {
      if let destination {
        destination
      } else {
        NEChatCommonPresentation.loadingView(token: token)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(token.pageBackground)
      }
    }
    .onAppear {
      prepareDestinationIfNeeded()
    }
  }

  private func prepareDestinationIfNeeded() {
    guard destination == nil else {
      return
    }

    let actions = ChatTeamSettingActions(
      onBack: onBack,
      onSelectMessage: onSelectMessage
    )
    let teamSettingView = providerWithActions?(teamId, context, actions) ??
      providerWithBackAction?(teamId, context, onBack) ??
      provider?(teamId, context)
    guard let teamSettingView else {
      destination = AnyView(
        UnsupportedRouteView(
          title: NEChatUIKitSwiftUIBundle.localized("chat_setting", value: "Chat Setting"),
          reason: String(format: NEChatUIKitSwiftUIBundle.localized("chat_team_setting_requires_team_host_format", value: "Team setting for %@ should be handled by the Team SwiftUI module or the SwiftUI app route host."), teamId),
          token: token
        )
      )
      return
    }

    destination = AnyView(teamSettingView)
  }
}

private extension ChatView {
  @ViewBuilder
  private func embeddedChatView(context: ChatSessionContext) -> some View {
    ChatView(
      viewModel: ChatSessionViewModel(
        context: context,
        config: viewModel.config
      ),
      token: token,
      browserDestination: browserDestination,
      onReplaceChatRoute: onReplaceChatRoute
    )
  }
}

private struct FunVoiceRecordingOverlay: View {
  var state: ChatVoiceRecordingState
  var token: ChatThemeToken

  private let progressMinWidth: CGFloat = 165
  private let progressHorizontalMargin: CGFloat = 30
  private let progressHeight: CGFloat = 80
  private let progressBottomOffset: CGFloat = 354
  private let closeImageSize: CGFloat = 88
  private let closeCenterYOffsetFromGestureCenter: CGFloat = -152
  private let textSpacing: CGFloat = 16
  private let maxRecordDuration: TimeInterval = 59.6
  private let lastSecondsThreshold: TimeInterval = 10
  private let progressAnimationStartDelay: TimeInterval = 0.3

  var body: some View {
    GeometryReader { geometry in
      let gestureHeight = gestureAreaHeight(for: geometry.size.width)
      let progressWidth = progressWidth(for: geometry.size.width)
      let gestureCenterY = geometry.size.height - gestureHeight / 2
      let closeCenterY = gestureCenterY + closeCenterYOffsetFromGestureCenter
      let progressTop = max(0, geometry.size.height - progressBottomOffset - progressHeight)
      let progressCenterY = progressTop + progressHeight / 2

      ZStack(alignment: .bottom) {
        Color.black.opacity(0.7)

        NEChatCommonPresentation.iconView(
          imageName: isCancelling ? "fun_chat_record_gesture_outter" : "fun_chat_record_gesture_inner",
          token: token,
          renderingMode: .original,
          size: CGSize(width: geometry.size.width, height: gestureHeight),
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_hold_to_talk", value: "Hold to talk")
        )
        .frame(width: geometry.size.width, height: gestureHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

        NEChatCommonPresentation.iconView(
          imageName: isCancelling ? "fun_chat_record_close_light" : "fun_chat_record_close_dark",
          token: token,
          renderingMode: .original,
          size: CGSize(width: closeImageSize, height: closeImageSize),
          accessibilityLabel: cancelText
        )
        .frame(width: closeImageSize, height: closeImageSize)
        .position(x: geometry.size.width / 2, y: closeCenterY)

        Group {
          if isCancelling {
            Text(cancelText)
              .font(.system(size: 16))
              .foregroundColor(recordTextColor)
              .position(x: geometry.size.width / 2,
                        y: closeCenterY - closeImageSize / 2 - textSpacing - 10)
          } else {
            Text(sendText)
              .font(.system(size: 16))
              .foregroundColor(recordTextColor)
              .position(x: geometry.size.width / 2,
                        y: geometry.size.height - gestureHeight - textSpacing - 10)
          }
        }

        Rectangle()
          .fill(progressColor)
          .frame(width: 21, height: 21)
          .rotationEffect(.degrees(45))
          .position(x: geometry.size.width / 2, y: progressTop + 60 + 10.5)

        FunVoiceRecordProgressView(
          state: state,
          progressWidth: progressWidth,
          color: progressColor,
          textColor: lastTimeTextColor,
          showsCountdown: showsCountdown,
          countdownText: countdownText
        )
        .frame(width: progressWidth, height: progressHeight)
        .animation(.linear(duration: 0.1), value: progressWidth)
        .position(x: geometry.size.width / 2, y: progressCenterY)
      }
    }
  }

  private var isCancelling: Bool {
    state.phase == .cancelling
  }

  private var progressColor: Color {
    isCancelling ? Color(hex: 0xE75D58) : Color(hex: 0xA9EA7A)
  }

  private var recordTextColor: Color {
    Color(hex: 0xAAAAAA)
  }

  private var lastTimeTextColor: Color {
    Color.black.opacity(0.4)
  }

  private var sendText: String {
    NEChatUIKitSwiftUIBundle.localized("release_to_send", value: "release to send")
  }

  private var cancelText: String {
    NEChatUIKitSwiftUIBundle.localized("release_to_cancel", value: "release to cancel")
  }

  private var showsCountdown: Bool {
    guard let remainingTime = state.progress.remainingTime else {
      return false
    }
    return remainingTime > 0 && remainingTime <= lastSecondsThreshold
  }

  private var countdownText: String {
    guard let remainingTime = state.progress.remainingTime else {
      return ""
    }
    return ChatUnitFormatter.recordingStopText(remainingTime: remainingTime)
  }

  private func gestureAreaHeight(for width: CGFloat) -> CGFloat {
    width / 375 * 128
  }

  private func progressWidth(for width: CGFloat) -> CGFloat {
    let maxWidth = max(progressMinWidth, width - progressHorizontalMargin * 2)
    let animatedDuration = max(1, maxRecordDuration - lastSecondsThreshold)
    let elapsed = max(0, state.progress.duration - progressAnimationStartDelay)
    let ratio = min(1, elapsed / animatedDuration)
    return progressMinWidth + (maxWidth - progressMinWidth) * ratio
  }
}

private struct FunVoiceRecordProgressView: View {
  var state: ChatVoiceRecordingState
  var progressWidth: CGFloat
  var color: Color
  var textColor: Color
  var showsCountdown: Bool
  var countdownText: String

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(color)

      if showsCountdown {
        Text(countdownText)
          .font(.system(size: 18))
          .foregroundColor(textColor)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      } else {
        FunVoiceWaveformView(level: state.progress.level)
          .frame(width: 80, height: 40)
          .clipped()
      }
    }
  }
}

private struct FunVoiceWaveformView: View {
  var level: Double

  private let barCount = 18
  private let baseHeights: [CGFloat] = [
    8, 20, 28, 16, 34, 22, 12, 30, 38,
    18, 26, 10, 32, 20, 36, 16, 24, 12,
  ]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
      let frame = Int(context.date.timeIntervalSinceReferenceDate * 30)
      HStack(spacing: 2) {
        ForEach(0 ..< barCount, id: \.self) { index in
          RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.black.opacity(0.4))
            .frame(width: 2, height: barHeight(index: index, frame: frame))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func barHeight(index: Int, frame: Int) -> CGFloat {
    let shifted = baseHeights[(index + frame / 4) % baseHeights.count]
    let levelBoost = CGFloat(max(0, min(1, level))) * 12
    return min(40, max(8, shifted + levelBoost))
  }
}

private struct TopPinnedMessageBanner: View {
  var state: TopMessageState
  var token: ChatThemeToken
  var onTap: () -> Void
  var onClose: () -> Void

  var body: some View {
    HStack(spacing: state.source.canClose ? 6 : 0) {
      Button(action: onTap) {
        HStack(spacing: 0) {
          NEChatCommonPresentation.iconView(
            imageName: "top_message_image",
            token: token,
            renderingMode: .original,
            size: CGSize(width: 18, height: 18),
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_pinned", value: "Pinned")
          )
          .frame(width: 18, height: 18)
          .padding(.leading, 8)

          topThumbnail
            .padding(.leading, 8)

          MessageEmoticonTextView(text: displayText, token: token, baseColor: token.incomingTextColor)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, hasTopThumbnail ? 4 : 8)

          if !state.source.canClose {
            Spacer(minLength: 30)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)

      if state.source.canClose {
        NEChatCommonPresentation.commonIconButton(
          imageName: "remove",
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("operation_untop", value: "Untop"),
          token: token,
          renderingMode: .original,
          size: CGSize(width: 20, height: 20),
          action: onClose
        )
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
        .accessibilityIdentifier("id.topClose")
      }
    }
    .padding(.trailing, state.source.canClose ? 8 : 14)
    .frame(maxWidth: .infinity)
    .frame(height: 40)
    .background(token.floatingPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: token.floatingPanelCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: token.floatingPanelCornerRadius, style: .continuous)
        .stroke(borderColor, lineWidth: token.styleMode == .normal ? 1 : 0)
    )
    .padding(.horizontal, 8)
    .padding(.top, 8)
    .accessibilityLabel(
      String(format: NEChatUIKitSwiftUIBundle.localized("chat_top_message_accessibility_format", value: "Pinned message: %@"), state.title)
    )
  }

  @ViewBuilder
  private var topThumbnail: some View {
    if let media = topMedia,
       let url = topMediaURL(for: media) {
      ChatCachedAsyncImage(url: url, fallbackURL: topMediaFallbackURL(for: media)) { image in
        image
          .resizable()
          .scaledToFill()
      } placeholder: {
        Color.clear
      }
      .frame(width: 28, height: 28)
      .clipped()
      .overlay {
        if isVideoTopMessage {
          Image("video_play", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        }
      }
    }
  }

  private var borderColor: Color {
    Color(hex: 0xE8EAED)
  }

  private var hasTopThumbnail: Bool {
    guard let media = topMedia else {
      return false
    }
    return topMediaURL(for: media) != nil
  }

  private var displayText: String {
    guard let subtitle = state.subtitle, !subtitle.isEmpty else {
      return state.title
    }
    return "\(NEFriendUserCache.getCutName(subtitle))：\(state.title)"
  }

  private var topMedia: MessageMediaState? {
    guard let row = state.row else {
      return nil
    }
    switch row.content {
    case let .image(media), let .video(media):
      return media
    default:
      return nil
    }
  }

  private var isVideoTopMessage: Bool {
    guard let row = state.row else {
      return false
    }
    if case .video = row.content {
      return true
    }
    return false
  }

  private func topMediaURL(for media: MessageMediaState) -> URL? {
    if isVideoTopMessage {
      return media.thumbnailURL ?? media.url ?? localFileURL(for: media)
    }
    return media.thumbnailURL ?? media.url ?? localFileURL(for: media)
  }

  private func topMediaFallbackURL(for media: MessageMediaState) -> URL? {
    if isVideoTopMessage {
      return media.url ?? media.thumbnailURL ?? localFileURL(for: media)
    }
    return media.url ?? media.thumbnailURL ?? localFileURL(for: media)
  }

  private func localFileURL(for media: MessageMediaState) -> URL? {
    guard let localPath = media.localPath, !localPath.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: localPath)
  }
}

private struct ChatInputOverlayHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = ChatView.normalInputOverlayReservedHeight

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

private struct ChatRuntimeStatusBanner: View {
  var runtime: ChatClientRuntimeState
  var readSync: ChatReadSyncState
  var token: ChatThemeToken

  var body: some View {
    if let status = status {
      HStack(spacing: 8) {
        NEChatCommonPresentation.iconView(
          systemImageName: status.systemImageName,
          token: token,
          size: CGSize(width: 14, height: 14),
          font: .system(size: 13, weight: .semibold),
          foregroundColor: status.foregroundColor(token: token),
          accessibilityLabel: status.message
        )
        Text(status.message)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        if status.showsProgress {
          NEChatCommonPresentation.inlineLoadingView(token: token)
        }
      }
      .foregroundColor(status.foregroundColor(token: token))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(status.backgroundColor(token: token))
      .accessibilityLabel(status.message)
    }
  }

  private var status: ChatRuntimeStatusPresentation? {
    if runtime.loginPhase == .kickedOffline {
      return ChatRuntimeStatusPresentation(
        message: NEChatUIKitSwiftUIBundle.localized("chat_kicked_offline", value: "You were kicked offline"),
        systemImageName: "exclamationmark.triangle",
        severity: .error
      )
    }

    if runtime.loginPhase == .failed {
      return ChatRuntimeStatusPresentation(
        message: NEChatUIKitSwiftUIBundle.localized("chat_login_failed", value: "Login failed"),
        systemImageName: "exclamationmark.triangle",
        severity: .error
      )
    }

    if case let .failed(message) = readSync.phase {
      return ChatRuntimeStatusPresentation(
        message: message,
        systemImageName: "exclamationmark.triangle",
        severity: .warning
      )
    }

    switch runtime.dataSync.phase {
    case .waiting, .syncing:
      return ChatRuntimeStatusPresentation(
        message: NEChatUIKitSwiftUIBundle.localized("chat_data_syncing", value: "Syncing chat data"),
        systemImageName: "arrow.triangle.2.circlepath",
        severity: .info,
        showsProgress: true
      )
    case .failed:
      return ChatRuntimeStatusPresentation(
        message: NEChatUIKitSwiftUIBundle.localized("chat_data_sync_failed", value: "Chat data sync failed"),
        systemImageName: "exclamationmark.triangle",
        severity: .warning
      )
    case .idle, .completed:
      return nil
    }
  }
}

private struct ChatRuntimeStatusPresentation: Equatable {
  enum Severity: Equatable {
    case info
    case warning
    case error
  }

  var message: String
  var systemImageName: String
  var severity: Severity
  var showsProgress: Bool

  init(message: String,
       systemImageName: String,
       severity: Severity,
       showsProgress: Bool = false) {
    self.message = message
    self.systemImageName = systemImageName
    self.severity = severity
    self.showsProgress = showsProgress
  }

  func foregroundColor(token: ChatThemeToken) -> Color {
    switch severity {
    case .info:
      return token.secondaryTextColor
    case .warning, .error:
      return token.warningColor
    }
  }

  func backgroundColor(token: ChatThemeToken) -> Color {
    switch severity {
    case .info:
      return token.inputBackground
    case .warning, .error:
      return token.warningColor.opacity(0.10)
    }
  }
}

private struct NewMessageIndicatorView: View {
  var state: NewMessageIndicatorState
  var token: ChatThemeToken
  var onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 0) {
        NEChatCommonPresentation.iconView(
          imageName: iconName,
          token: token,
          size: CGSize(width: 16, height: 16),
          foregroundColor: token.accentColor,
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_new_message", value: "New message")
        )
        if state.count > 0 {
          Text(String(format: NEChatUIKitSwiftUIBundle.localized("chat_new_message_count_format", value: " %d new message"), state.count))
            .font(.system(size: 14))
            .lineLimit(1)
        }
      }
      .padding(.leading, 12)
      .padding(.trailing, state.count > 0 ? 30 : 12)
      .frame(minWidth: 40)
      .frame(height: 40)
      .background(token.floatingPanelBackground)
      .foregroundColor(token.accentColor)
      .overlay(
        RoundedRectangle(cornerRadius: token.floatingPillCornerRadius, style: .continuous)
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: token.floatingPillCornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var iconName: String {
    // Keep both UIKit asset names here: NormalUI uses chat_jump_to_new, FunUI uses fun_chat_jump_to_new.
    token.styleMode == .fun ? "fun_chat_jump_to_new" : "chat_jump_to_new"
  }
}

struct UnsupportedRouteView: View {
  var title: String
  var reason: String
  var token: ChatThemeToken

  var body: some View {
    VStack(spacing: 12) {
      NEChatCommonPresentation.iconView(
        imageName: "sendMessage_failed",
        token: token,
        size: CGSize(width: 30, height: 30),
        font: .system(size: 30),
        foregroundColor: token.warningColor,
        accessibilityLabel: title
      )
      Text(title)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(token.incomingTextColor)
        .multilineTextAlignment(.center)
      Text(reason)
        .font(.system(size: 14))
        .foregroundColor(token.secondaryTextColor)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(token.pageBackground)
  }
}

private struct ChatInputTranslationPanelView: View {
  var state: ChatInputTranslationState
  var token: ChatThemeToken
  var onRequestLanguageSelection: () -> Void
  var onClose: () -> Void
  var onStartOrUse: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button(action: onRequestLanguageSelection) {
          Text(languageShortText)
            .font(.system(size: 14))
            .foregroundColor(token.incomingTextColor)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 4)
            .background(token.inputFieldBackground)
            .overlay(
              RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(token.dividerColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)

        Spacer()

        NEChatCommonPresentation.commonIconButton(
          imageName: "remove",
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("close", value: "Close"),
          token: token,
          renderingMode: .original,
          size: CGSize(width: 16, height: 16),
          foregroundColor: token.secondaryTextColor,
          action: onClose
        )
        .frame(width: 40, height: 34)
        .contentShape(Rectangle())
      }
      .frame(height: 34)
      .padding(.horizontal, 12)

      Rectangle()
        .fill(token.dividerColor)
        .frame(height: 1)
        .padding(.horizontal, 12)

      HStack(spacing: 10) {
        Text(contentText)
          .font(.system(size: 14))
          .foregroundColor(contentColor)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: onStartOrUse) {
          HStack(spacing: 4) {
            if state.phase == .translating {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(token.accentColor)
                .scaleEffect(0.65)
            }
            Text(actionTitle)
              .font(.system(size: 14))
              .foregroundColor(token.accentColor)
            if state.phase == .translated {
              Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(token.accentColor)
            }
          }
          .frame(minWidth: 66, minHeight: 36)
          .contentShape(Rectangle())
        }
        .disabled(state.phase == .translating)
        .buttonStyle(.plain)
      }
      .frame(minHeight: 35)
      .padding(.horizontal, 12)
    }
    .frame(minHeight: 70)
    .background(token.inputBackground)
  }

  private var languageShortText: String {
    guard let current = state.languages.first(where: { $0.code == state.selectedLanguage }) else {
      return String(state.selectedLanguage.prefix(1))
    }
    return String(current.title.prefix(1))
  }

  private var contentText: String {
    if state.phase == .translated, !state.translatedText.isEmpty {
      return state.translatedText
    }
    return NEChatUIKitSwiftUIBundle.localized("translate_default", value: "Translate to")
  }

  private var contentColor: Color {
    state.phase == .translated ? token.incomingTextColor : token.secondaryTextColor
  }

  private var actionTitle: String {
    switch state.phase {
    case .idle:
      return NEChatUIKitSwiftUIBundle.localized("translate_sure", value: "AI Translate")
    case .translating:
      return NEChatUIKitSwiftUIBundle.localized("ai_translating", value: "AI Translating...")
    case .translated:
      return NEChatUIKitSwiftUIBundle.localized("translate_use", value: "Use")
    }
  }
}

private struct ChatInputTranslationLanguagePickerSheet: View {
  var state: ChatInputTranslationState
  var token: ChatThemeToken
  var onSelect: (ChatTranslationLanguageState) -> Void
  var onCancel: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Text(NEChatUIKitSwiftUIBundle.localized("language_title", value: "Translate to"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(token.incomingTextColor)

        HStack {
          NEChatCommonPresentation.iconButton(
            imageName: "arrowDown",
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("close", value: "Close"),
            token: token,
            renderingMode: .original,
            size: CGSize(width: 20, height: 20),
            foregroundColor: token.secondaryTextColor,
            action: onCancel
          )
          .frame(width: 50, height: 50)
          Spacer()
        }
        .padding(.leading, 16)
      }
      .frame(height: 50)

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(state.languages) { language in
            Button {
              onSelect(language)
            } label: {
              HStack(spacing: 12) {
                Text(language.title)
                  .font(.system(size: 16))
                  .foregroundColor(language.code == state.selectedLanguage
                    ? token.accentColor
                    : token.incomingTextColor)
                Spacer()
                if language.code == state.selectedLanguage {
                  NEChatCommonPresentation.iconView(
                    imageName: "chat_map_select",
                    token: token,
                    renderingMode: .original,
                    size: CGSize(width: 20, height: 16),
                    foregroundColor: token.accentColor,
                    accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("selected", value: "Selected")
                  )
                }
              }
              .padding(.horizontal, 20)
              .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(languageRowBackground(for: language))
          }
        }
        .padding(.top, 8)
        .padding(.horizontal, token.styleMode == .fun ? 20 : 0)
        .background(languageListBackground)
        .clipShape(RoundedRectangle(
          cornerRadius: token.styleMode == .fun ? 10 : 0,
          style: .continuous
        ))
      }
    }
    .background(token.pageBackground.ignoresSafeArea())
  }

  @ViewBuilder
  private func languageRowBackground(for language: ChatTranslationLanguageState) -> some View {
    if token.styleMode == .fun,
       language.code == state.selectedLanguage {
      Color(hex: 0xF5F8FF)
    } else {
      Color.clear
    }
  }

  private var languageListBackground: Color {
    token.styleMode == .fun ? .white : .clear
  }
}

private struct ChatTranslationPickerPresentationModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 16.4, *) {
      content.presentationCornerRadius(0)
    } else {
      content
    }
  }
}

private struct ChatCompatibleNavigationDestinationModifier<Item: Hashable, Destination: View>: ViewModifier {
  @Binding var item: Item?
  let destination: (Item) -> Destination

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content.navigationDestination(item: $item, destination: destination)
    } else {
      content.background {
        NavigationLink(isActive: Binding(
          get: { item != nil },
          set: { isPresented in
            if !isPresented {
              item = nil
            }
          }
        )) {
          if let item {
            destination(item)
              .id(item)
          } else {
            EmptyView()
          }
        } label: {
          EmptyView()
        }
        .hidden()
      }
    }
  }
}

public struct ChatEmptyView: View {
  public var token: ChatThemeToken

  public init(token: ChatThemeToken) {
    self.token = token
  }

  public var body: some View {
    Color.clear
  }
}

public struct ChatErrorView: View {
  public var message: String
  public var token: ChatThemeToken

  public init(message: String, token: ChatThemeToken) {
    self.message = message
    self.token = token
  }

  public var body: some View {
    NEChatCommonPresentation.errorView(message: message, token: token)
  }
}

public struct ChatToastView: View {
  public var toast: ChatToastState
  public var token: ChatThemeToken

  public init(toast: ChatToastState, token: ChatThemeToken) {
    self.toast = toast
    self.token = token
  }

  public var body: some View {
    Text(toast.message)
      .font(.system(size: 14, weight: .medium))
      .foregroundColor(token.primaryButtonTextColor)
      .lineLimit(2)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .frame(maxWidth: 260)
      .background(backgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: token.controlCornerRadius, style: .continuous))
      .padding(.horizontal, 16)
  }

  private var backgroundColor: Color {
    Color.black.opacity(0.82)
  }
}
