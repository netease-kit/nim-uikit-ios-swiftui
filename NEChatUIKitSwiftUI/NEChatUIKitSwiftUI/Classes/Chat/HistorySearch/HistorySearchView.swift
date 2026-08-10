// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct HistorySearchView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: HistorySearchViewModel
  @State private var pushedRoute: HistorySearchRoute?
  @State private var filePreviewRoute: HistoryFilePreviewRoute?
  private let token: ChatThemeToken
  private let onSelect: (MessageRowState) -> Void
  private let onSelectMessage: (PinMessageSelection) -> Void
  private let onForward: (MessageRowState) -> Void
  private let onForwardMessage: ((MessageRowState, V2NIMMessage) -> Void)?
  private let onForwardMessageWithToast: ((MessageRowState, V2NIMMessage, @escaping (ChatToastState) -> Void) -> Void)?
  private let onOpenURL: (URL, String, ChatURLInteractionSource, MessageRowState) -> Void
  private let onSaveMedia: ((ChatMediaItem) async throws -> Void)?
  private let onBack: (() -> Void)?
  private let canForward: (MessageRowState) -> Bool

  @MainActor
  public init(viewModel: HistorySearchViewModel,
              token: ChatThemeToken = .normal,
              onSelect: @escaping (MessageRowState) -> Void = { _ in },
              onSelectMessage: ((PinMessageSelection) -> Void)? = nil,
              onForward: @escaping (MessageRowState) -> Void = { _ in },
              onForwardMessage: ((MessageRowState, V2NIMMessage) -> Void)? = nil,
              onForwardMessageWithToast: ((MessageRowState, V2NIMMessage, @escaping (ChatToastState) -> Void) -> Void)? = nil,
              onOpenURL: @escaping (URL, String, ChatURLInteractionSource, MessageRowState) -> Void = { _, _, _, _ in },
              onSaveMedia: ((ChatMediaItem) async throws -> Void)? = nil,
              onBack: (() -> Void)? = nil,
              canForward: @escaping (MessageRowState) -> Bool = { _ in false }) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onSelect = onSelect
    self.onSelectMessage = onSelectMessage ?? { selection in
      onSelect(selection.row)
    }
    self.onForward = onForward
    self.onForwardMessage = onForwardMessage
    self.onForwardMessageWithToast = onForwardMessageWithToast
    self.onOpenURL = onOpenURL
    self.onSaveMedia = onSaveMedia
    self.onBack = onBack
    self.canForward = canForward
  }

  public var body: some View {
    ZStack {
      VStack(spacing: 0) {
        if shouldShowNavigationBar {
          NEChatCommonPresentation.navigationBar(
            title: viewModel.activeTitle,
            token: token,
            backAction: {
              performBack()
            },
            backgroundColor: navigationBackground,
            showsSeparator: viewModel.scope == .member
          )
        }

        content
      }
      .background(pageBackground.ignoresSafeArea())

      if let pushedRoute {
        pushedRouteDestination(pushedRoute)
          .environment(\.neChatChildRouteBackAction, childRouteBackAction(for: pushedRoute))
          .zIndex(1)
      }

      if let filePreviewRoute {
        ChatFilePreviewView(preview: filePreviewRoute.preview, token: token)
          .id(filePreviewRoute.id)
          .environment(\.neChatChildRouteBackAction, filePreviewBackAction(for: filePreviewRoute))
          .zIndex(2)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .fullScreenCover(item: $viewModel.mediaPreview) { preview in
      ChatMediaPreviewView(preview: preview, token: token, onSaveImage: onSaveMedia)
    }
    .neCommonConfirmationDialog(
      fileActionDialogState,
      onAction: handleFileAction,
      onDismiss: {
        viewModel.dismissFileActionMenu()
      }
    )
    .onChange(of: viewModel.query) { query in
      if viewModel.scope == .keyword,
         query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        viewModel.resetToKeyword()
      }
    }
    .onSubmit(of: .search) {
      viewModel.searchKeyword()
    }
    .onAppear {
      syncFilePreviewRoute(viewModel.filePreview)
    }
    .onChange(of: viewModel.filePreview) { preview in
      syncFilePreviewRoute(preview)
    }
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty where !shouldShowQuickPanel:
        NEChatCommonPresentation.emptyView(
          token: token,
          titleKey: "no_search_results",
          fallbackTitle: NEChatUIKitSwiftUIBundle.localized("no_search_results", value: "No search results")
        )
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.search(reset: true)
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
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var content: some View {
    VStack(spacing: 0) {
      if shouldShowSearchArea {
        searchArea
      }

      ScrollView {
        LazyVStack(spacing: 0) {
        if shouldShowQuickPanel {
          quickPanel
        }

        if !viewModel.rows.isEmpty {
          resultsList
        }

        if viewModel.phase == .loadingMore {
          NEChatCommonPresentation.inlineLoadingView(token: token)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }

          if shouldShowNoMore {
            historyNoMoreView
          }
        }
      }
      .scrollDismissesKeyboard(.immediately)
    }
  }

  private var searchArea: some View {
    HStack(spacing: token.styleMode == .fun ? 8 : 0) {
      NEChatCommonPresentation.searchField(
        text: $viewModel.query,
        placeholder: NEChatUIKitSwiftUIBundle.localized("search", value: "Search"),
        token: token,
        height: token.styleMode == .fun ? 36 : 32,
        onSubmit: {
          viewModel.searchKeyword()
        }
      )

      if token.styleMode == .fun {
        Button {
          performBack()
        } label: {
          Text(NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"))
            .font(.system(size: 16))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
            .frame(width: NEAppLanguageUtil.getCurrentLanguage() == .english ? 60 : 44, height: 36)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.top, token.styleMode == .fun ? 12 : 20)
    .padding(.horizontal, token.styleMode == .fun ? 8 : 20)
  }

  private var quickPanel: some View {
    VStack(spacing: 0) {
      Text(NEChatUIKitSwiftUIBundle.localized("quick_search_tips", value: "Quick search chat messages"))
        .font(.system(size: 14))
        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.emptyTitle)
        .padding(.top, token.styleMode == .fun ? 60 : 48)
        .padding(.bottom, token.styleMode == .fun ? 28 : 24)

      if token.styleMode == .fun {
        LazyVGrid(columns: funQuickColumns, spacing: 0) {
          ForEach(Array(viewModel.quickScopes.enumerated()), id: \.offset) { index, scope in
            HistoryQuickActionView(scope: scope, token: token, style: .fun, showsDivider: (index % 3) != 2) {
              openQuickScope(scope)
            }
          }
        }
        .padding(.horizontal, 48)
      } else {
        LazyVGrid(columns: normalQuickColumns, spacing: 0) {
          ForEach(viewModel.quickScopes) { scope in
            HistoryQuickActionView(scope: scope, token: token, style: .normal, showsDivider: false) {
              openQuickScope(scope)
            }
          }
        }
        .padding(.horizontal, 26)
      }
    }
  }

  private var resultsList: some View {
    LazyVStack(spacing: 0) {
      ForEach(viewModel.rows) { row in
        HistoryResultRowView(
          row: historyDisplayRow(row),
          token: token,
          scope: viewModel.scope,
          onSelect: {
            select(row, using: viewModel)
          }
        ) { url, displayText in
          onOpenURL(url, displayText, .textPreview, row)
        }
        .contentShape(Rectangle())
        .onTapGesture {
          select(row, using: viewModel)
        }
        .onAppear {
          viewModel.loadMoreIfNeeded(currentRow: row)
        }
      }
    }
    .padding(.top, viewModel.scope == .member ? 0 : 16)
  }

  @ViewBuilder
  private func pushedRouteDestination(_ route: HistorySearchRoute) -> some View {
    switch route.destination {
    case let .memberSelection(teamId):
      HistoryMemberSelectionView(
        teamId: teamId,
        teamType: viewModel.teamType,
        token: token,
        onBack: childRouteBackAction(for: route),
        onSelect: { member in
          openMemberSearchResult(accountId: member.accountId)
        }
      )
      .id(route.id)
    case let .memberResult(memberViewModel):
      HistorySearchView(
        viewModel: memberViewModel,
        token: token,
        onSelect: onSelect,
        onSelectMessage: { selection in
          locate(selection)
        },
        onForward: onForward,
        onForwardMessage: onForwardMessage,
        onForwardMessageWithToast: onForwardMessageWithToast,
        onOpenURL: onOpenURL,
        onSaveMedia: onSaveMedia,
        onBack: childRouteBackAction(for: route),
        canForward: canForward
      )
      .id(route.id)
    case let .date(seed):
      HistoryDatePickerView(
        token: token,
        initialDate: seed,
        onBack: childRouteBackAction(for: route),
        onComplete: { date in
          viewModel.locateFirstMessageSelection(after: date) { selection in
            locate(selection ?? viewModel.fallbackSelectionForDateRoute())
          }
        }
      )
      .id(route.id)
    case let .media(scope, mediaViewModel):
      HistoryMediaResultView(
        viewModel: mediaViewModel,
        token: token,
        scope: scope,
        onBack: childRouteBackAction(for: route),
        onSelect: { selection in
          locate(selection)
        },
        onForward: onForward,
        onForwardMessage: onForwardMessage,
        onForwardMessageWithToast: onForwardMessageWithToast,
        onSaveMedia: onSaveMedia,
        canForward: canForward
      )
      .id(route.id)
    }
  }

  private var shouldShowNavigationBar: Bool {
    token.styleMode == .normal || viewModel.scope == .member
  }

  private var shouldShowSearchArea: Bool {
    viewModel.scope != .member
  }

  private var shouldShowQuickPanel: Bool {
    viewModel.scope == .keyword &&
      viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      viewModel.rows.isEmpty
  }

  private var shouldShowNoMore: Bool {
    !viewModel.rows.isEmpty && !viewModel.hasMore && viewModel.phase == .loaded
  }

  private var historyNoMoreView: some View {
    Text(NEChatUIKitSwiftUIBundle.localized("search_message_has_no_more", value: "No more content"))
      .font(.system(size: 12))
      .foregroundColor(token.secondaryTextColor)
      .frame(maxWidth: .infinity, minHeight: 20)
      .padding(.vertical, 8)
  }

  private var navigationBackground: Color {
    token.styleMode == .fun ? token.navigationBackground : token.inputBackground
  }

  private var pageBackground: Color {
    token.styleMode == .fun ? token.pageBackground : .white
  }

  private var normalQuickColumns: [GridItem] {
    [GridItem(.adaptive(minimum: 84, maximum: 84), spacing: 0, alignment: .top)]
  }

  private var funQuickColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(minimum: 72, maximum: 90), spacing: 0), count: 3)
  }

  private func openQuickScope(_ scope: HistorySearchScope) {
    switch scope {
    case .member:
      guard let teamId = viewModel.teamId else {
        return
      }
      pushedRoute = HistorySearchRoute(destination: .memberSelection(teamId: teamId))
    case .date:
      pushedRoute = HistorySearchRoute(destination: .date(seed: Date()))
    case .image, .video, .file:
      let mediaViewModel = viewModel.sibling()
      mediaViewModel.updateScope(scope)
      pushedRoute = HistorySearchRoute(destination: .media(scope: scope, viewModel: mediaViewModel))
    case .keyword:
      viewModel.resetToKeyword()
    }
  }

  private func childRouteBackAction(for route: HistorySearchRoute) -> () -> Void {
    {
      guard pushedRoute?.id == route.id else {
        return
      }
      pushedRoute = nil
    }
  }

  private func openMemberSearchResult(accountId: String) {
    let memberViewModel = viewModel.sibling()
    memberViewModel.searchMember(accountId: accountId)
    pushedRoute = HistorySearchRoute(destination: .memberResult(viewModel: memberViewModel))
  }

  private func syncFilePreviewRoute(_ preview: ChatFilePreviewState?) {
    guard let preview else {
      filePreviewRoute = nil
      return
    }
    guard filePreviewRoute?.preview != preview else {
      return
    }
    filePreviewRoute = HistoryFilePreviewRoute(preview: preview)
  }

  private func filePreviewBackAction(for route: HistoryFilePreviewRoute) -> () -> Void {
    {
      guard filePreviewRoute?.id == route.id else {
        return
      }
      filePreviewRoute = nil
      if viewModel.filePreview == route.preview {
        viewModel.consumeFilePreview()
      }
    }
  }

  private func select(_ row: MessageRowState, using viewModel: HistorySearchViewModel) {
    locate(viewModel.selection(for: row))
  }

  private func locate(_ selection: PinMessageSelection) {
    onSelectMessage(selection)
  }

  private func historyDisplayRow(_ row: MessageRowState) -> MessageRowState {
    var next = row
    if next.direction != .system {
      next.direction = .incoming
      next.deliveryState = .none
      next.readReceipt = nil
    }
    next.timeDividerText = HistorySearchView.dateText(row.timestamp)
    next.suppressesTimeDivider = false
    next.isPinned = false
    return next
  }

  private var fileActionDialogState: NECommonDialogState? {
    guard let menu = viewModel.fileActionMenu else {
      return nil
    }
    return NECommonDialogState(
      id: menu.id,
      title: actionMenuTitle,
      showsTitle: !isMediaActionMenu(for: menu.row),
      actions: historyActionDialogActions(
        for: menu.row,
        style: token.styleMode,
        canForward: shouldShowForward(for:)
      )
    )
  }

  private func shouldShowForward(for row: MessageRowState) -> Bool {
    guard canForward(row) else {
      return false
    }
    return !NEChatUtilityMessageOperationRules.isAudioMessage(row.content)
  }

  private var actionMenuTitle: String {
    switch viewModel.fileActionMenu?.row.content {
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("msg_image", value: "Image")
    case .video:
      return NEChatUIKitSwiftUIBundle.localized("msg_video", value: "Video")
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("chat_file", value: "File")
    default:
      return ""
    }
  }

  private func isMediaActionMenu(for row: MessageRowState) -> Bool {
    switch row.content {
    case .image, .video:
      return true
    default:
      return false
    }
  }

  private func handleFileAction(_ action: NECommonDialogAction) {
    guard let fileAction = HistoryFileAction(rawValue: action.id),
          let menu = viewModel.fileActionMenu else {
      viewModel.dismissFileActionMenu()
      return
    }
    let row = menu.row
    viewModel.dismissFileActionMenu()
    switch fileAction {
    case .locate:
      locate(viewModel.selection(for: row))
    case .forward:
      forward(row)
    case .collect:
      viewModel.collect(row: row)
    case .cancel:
      break
    }
  }

  private func forward(_ row: MessageRowState) {
    if let message = viewModel.sourceMessage(for: row) {
      if let onForwardMessageWithToast {
        onForwardMessageWithToast(row, message) { toast in
          viewModel.presentToast(toast)
        }
        return
      }
      if let onForwardMessage {
        onForwardMessage(row, message)
        return
      }
    }
    onForward(row)
  }

  private func performBack() {
    if let onBack {
      onBack()
    } else {
      dismiss()
    }
  }

  fileprivate static func dateText(_ timestamp: TimeInterval?) -> String {
    ChatUnitFormatter.messageTimeText(timestamp)
  }

  fileprivate static func fileDateText(_ timestamp: TimeInterval?) -> String {
    ChatUnitFormatter.historyFileDateText(timestamp)
  }
}

private struct HistorySearchRoute: Identifiable {
  enum Destination {
    case memberSelection(teamId: String)
    case memberResult(viewModel: HistorySearchViewModel)
    case date(seed: Date)
    case media(scope: HistorySearchScope, viewModel: HistorySearchViewModel)
  }

  let id = UUID()
  var destination: Destination
}

private struct HistoryFilePreviewRoute: Identifiable {
  let id = UUID()
  var preview: ChatFilePreviewState
}

private enum HistoryFileAction: String {
  case locate
  case forward
  case collect
  case cancel
}

private func historyActionDialogActions(for row: MessageRowState,
                                        style: ChatStyleMode,
                                        canForward: (MessageRowState) -> Bool) -> [NECommonDialogAction] {
  var actions = [NECommonDialogAction]()
  switch row.content {
  case .image, .video:
    actions.append(historyLocateAction())
    if canForward(row) {
      actions.append(historyForwardAction())
    }
    actions.append(historyCancelAction())
    return actions
  case .file:
    actions.append(historyForwardAction())
    actions.append(historyCollectAction())
  default:
    if canForward(row) {
      actions.append(historyForwardAction())
    } else {
      actions.append(historyCollectAction())
    }
  }
  actions.append(historyCancelAction())
  return actions
}

private func historyLocateAction() -> NECommonDialogAction {
  NECommonDialogAction(
    id: HistoryFileAction.locate.rawValue,
    title: NEChatUIKitSwiftUIBundle.localized("search_result_find_in_chat", value: "Find in Chat"),
    imageName: "op_search",
    imageBundle: NEChatUIKitSwiftUIBundle.bundle
  )
}

private func historyForwardAction() -> NECommonDialogAction {
  NECommonDialogAction(
    id: HistoryFileAction.forward.rawValue,
    title: NEChatUIKitSwiftUIBundle.localized("operation_forward", value: "Forward"),
    imageName: "op_forward",
    imageBundle: NEChatUIKitSwiftUIBundle.bundle
  )
}

private func historyCollectAction() -> NECommonDialogAction {
  NECommonDialogAction(
    id: HistoryFileAction.collect.rawValue,
    title: NEChatUIKitSwiftUIBundle.localized("operation_collection", value: "Collect"),
    imageName: "op_collect",
    imageBundle: NEChatUIKitSwiftUIBundle.bundle
  )
}

private func historyCancelAction() -> NECommonDialogAction {
  NECommonDialogAction(
    id: HistoryFileAction.cancel.rawValue,
    title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
    role: .cancel
  )
}

private enum HistoryQuickActionStyle {
  case normal
  case fun
}

private struct HistoryQuickActionView: View {
  var scope: HistorySearchScope
  var token: ChatThemeToken
  var style: HistoryQuickActionStyle
  var showsDivider: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      if style == .fun {
        HStack(spacing: 0) {
          Text(scope.quickTitle)
            .font(.system(size: 16))
            .foregroundColor(Color(hex: 0x596C96))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: 48)
          if showsDivider {
            Rectangle()
              .fill(Color(hex: 0xC9C9C9))
              .frame(width: 0.5, height: 20)
          }
        }
      } else {
        VStack(spacing: 12) {
          ZStack {
            Circle()
              .fill(Color(hex: 0xF9F9F9))
              .frame(width: 48, height: 48)
            NEChatCommonPresentation.iconView(
              imageName: scope.iconImageName,
              token: token,
              renderingMode: .original,
              size: CGSize(width: 24, height: 24),
              accessibilityLabel: scope.quickTitle
            )
            .frame(width: 48, height: 48)
          }

          Text(scope.quickTitle)
            .font(.system(size: 14))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(width: 84, alignment: .top)
            .frame(minHeight: 18, alignment: .top)
        }
        .frame(width: 84, height: 102, alignment: .top)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct HistoryMediaResultView: View {
  @StateObject private var viewModel: HistorySearchViewModel
  @State private var filePreviewRoute: HistoryFilePreviewRoute?
  @State private var didUserScrollMediaGrid = false
  @State private var didRequestInitialMediaLatestScroll = false
  @State private var isMediaDragActive = false
  @State private var isMediaLoadMoreArmed = false
  @State private var pendingMediaPrependAnchorId: String?
  @State private var pendingMediaPrependRowCount = 0
  var token: ChatThemeToken
  var scope: HistorySearchScope
  var onBack: () -> Void
  var onSelect: (PinMessageSelection) -> Void
  var onForward: (MessageRowState) -> Void
  var onForwardMessage: ((MessageRowState, V2NIMMessage) -> Void)?
  var onForwardMessageWithToast: ((MessageRowState, V2NIMMessage, @escaping (ChatToastState) -> Void) -> Void)?
  var onSaveMedia: ((ChatMediaItem) async throws -> Void)?
  var canForward: (MessageRowState) -> Bool

  init(viewModel: HistorySearchViewModel,
       token: ChatThemeToken,
       scope: HistorySearchScope,
       onBack: @escaping () -> Void,
       onSelect: @escaping (PinMessageSelection) -> Void,
       onForward: @escaping (MessageRowState) -> Void,
       onForwardMessage: ((MessageRowState, V2NIMMessage) -> Void)?,
       onForwardMessageWithToast: ((MessageRowState, V2NIMMessage, @escaping (ChatToastState) -> Void) -> Void)?,
       onSaveMedia: ((ChatMediaItem) async throws -> Void)?,
       canForward: @escaping (MessageRowState) -> Bool) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.scope = scope
    self.onBack = onBack
    self.onSelect = onSelect
    self.onForward = onForward
    self.onForwardMessage = onForwardMessage
    self.onForwardMessageWithToast = onForwardMessageWithToast
    self.onSaveMedia = onSaveMedia
    self.canForward = canForward
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        NEChatCommonPresentation.navigationBar(
          title: scope.mediaTitle,
          token: token,
          backAction: onBack,
          backgroundColor: .white,
          showsSeparator: false
        )

        Group {
          if scope == .file {
            fileList
          } else {
            mediaGrid
          }
        }
      }
      .background(Color.white.ignoresSafeArea())

      if let filePreviewRoute {
        ChatFilePreviewView(preview: filePreviewRoute.preview, token: token)
          .id(filePreviewRoute.id)
          .environment(\.neChatChildRouteBackAction, filePreviewBackAction(for: filePreviewRoute))
          .zIndex(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty:
        NEChatCommonPresentation.emptyView(
          token: token,
          titleKey: emptyTitleKey,
          fallbackTitle: emptyTitleFallback
        )
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.search(reset: true)
        }
      default:
        EmptyView()
      }
    }
    .fullScreenCover(item: $viewModel.mediaPreview) { preview in
      ChatMediaPreviewView(preview: preview, token: token, onSaveImage: onSaveMedia)
    }
    .onAppear {
      syncFilePreviewRoute(viewModel.filePreview)
    }
    .onChange(of: viewModel.filePreview) { preview in
      syncFilePreviewRoute(preview)
    }
    .neCommonConfirmationDialog(
      fileActionDialogState,
      onAction: handleFileAction,
      onDismiss: {
        viewModel.dismissFileActionMenu()
      }
    )
    .neCommonTransientOverlay(
      viewModel.toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var mediaGrid: some View {
    GeometryReader { geometry in
      let itemWidth = mediaItemWidth(availableWidth: geometry.size.width)
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            if shouldShowNoMore {
              historyNoMoreView
            }

            ForEach(mediaSections) { section in
              HistoryMediaSectionView(
                section: section,
                token: token,
                scope: scope,
                itemWidth: itemWidth,
                downloadProgressByRowId: viewModel.mediaDownloadProgressByRowId,
                onSelect: { row in
                  viewModel.openMedia(row: row)
                },
                onLongPress: { row in
                  viewModel.showFileActionMenu(row: row)
                },
                onLoadOlder: { row in
                  guard didUserScrollMediaGrid,
                        isMediaLoadMoreArmed,
                        viewModel.hasMore,
                        viewModel.phase != .loadingMore,
                        row.id == viewModel.rows.first?.id else {
                    return
                  }
                  isMediaLoadMoreArmed = false
                  pendingMediaPrependAnchorId = viewModel.rows.first?.id
                  pendingMediaPrependRowCount = viewModel.rows.count
                  viewModel.loadMore()
                }
              )
            }

            if !viewModel.rows.isEmpty {
              Color.clear
                .frame(height: 1)
            }
          }
          .padding(.bottom, viewModel.hasMore ? 0 : 20)
        }
        .overlay(alignment: .top) {
          if viewModel.phase == .loadingMore {
            NEChatCommonPresentation.inlineLoadingView(
              token: token,
              title: NEChatUIKitSwiftUIBundle.localized(
                "search_loading_more_messages",
                value: "Loading more messages"
              )
            )
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white.opacity(0.96))
            .allowsHitTesting(false)
          }
        }
        .simultaneousGesture(
          DragGesture(minimumDistance: 1)
            .onChanged { _ in
              didUserScrollMediaGrid = true
              guard !isMediaDragActive else {
                return
              }
              isMediaDragActive = true
              isMediaLoadMoreArmed = true
            }
            .onEnded { _ in
              isMediaDragActive = false
            }
        )
        .onAppear {
          beginInitialMediaBottomAlignmentIfNeeded(using: proxy)
        }
        .onChange(of: viewModel.phase) { _ in
          beginInitialMediaBottomAlignmentIfNeeded(using: proxy)
          if viewModel.phase != .loadingMore,
             pendingMediaPrependAnchorId != nil,
             viewModel.rows.count <= pendingMediaPrependRowCount {
            clearPendingMediaPrependAnchor()
          }
        }
        .onChange(of: viewModel.rows.count) { count in
          if restoreMediaPrependAnchorIfNeeded(rowCount: count, using: proxy) {
            return
          }
          beginInitialMediaBottomAlignmentIfNeeded(using: proxy)
        }
      }
    }
  }

  private var fileList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(mediaSections) { section in
          HistoryMediaSectionHeader(title: section.title, token: token)
          ForEach(section.rows) { row in
            HistoryFileResultRow(
              row: row,
              token: token,
              downloadProgress: viewModel.mediaDownloadProgressByRowId[row.id]
            ) {
              viewModel.openFile(row: row)
            } onMore: {
              viewModel.showFileActionMenu(row: row)
            }
            .onAppear {
              viewModel.loadMoreIfNeeded(currentRow: row)
            }
          }
        }

        if viewModel.phase == .loadingMore {
          NEChatCommonPresentation.inlineLoadingView(
            token: token,
            title: NEChatUIKitSwiftUIBundle.localized("search_loading_more_messages", value: "Loading more messages")
          )
          .frame(maxWidth: .infinity)
          .frame(height: 44)
        }

        if shouldShowNoMore {
          historyNoMoreView
        }
      }
      .padding(.bottom, 20)
    }
    .scrollDismissesKeyboard(.immediately)
  }

  private var mediaSections: [HistoryMessageSection] {
    HistoryMessageSection.group(rows: viewModel.rows, scope: scope)
  }

  private var shouldShowNoMore: Bool {
    !viewModel.rows.isEmpty && !viewModel.hasMore && viewModel.phase == .loaded
  }

  private var emptyTitleKey: String {
    switch scope {
    case .image:
      return "no_search_result_image"
    case .video:
      return "no_search_result_video"
    case .file:
      return "no_search_result_file"
    default:
      return "no_search_results"
    }
  }

  private var emptyTitleFallback: String {
    switch scope {
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("no_search_result_image", value: "No image")
    case .video:
      return NEChatUIKitSwiftUIBundle.localized("no_search_result_video", value: "No video")
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("no_search_result_file", value: "No file")
    default:
      return NEChatUIKitSwiftUIBundle.localized("no_search_results", value: "No search results")
    }
  }

  private var historyNoMoreView: some View {
    Text(NEChatUIKitSwiftUIBundle.localized("search_message_has_no_more", value: "No more content"))
      .font(.system(size: 12))
      .foregroundColor(token.secondaryTextColor)
      .frame(maxWidth: .infinity, minHeight: 20)
  }

  private func mediaItemWidth(availableWidth: CGFloat) -> CGFloat {
    max(1, availableWidth - 6) / 4
  }

  private func beginInitialMediaBottomAlignmentIfNeeded(using proxy: ScrollViewProxy) {
    guard scope != .file,
          viewModel.phase == .loaded,
          !didUserScrollMediaGrid,
          !didRequestInitialMediaLatestScroll,
          let latestRowId = viewModel.rows.last?.id else {
      return
    }
    didRequestInitialMediaLatestScroll = true
    // UIKit reloads the collection view first and performs the initial
    // bottom alignment on the next run loop. SwiftUI's lazy grid does not
    // have a target layout yet during the phase callback, so defer the
    // request until the row has been registered with ScrollViewReader.
    DispatchQueue.main.async {
      guard !didUserScrollMediaGrid,
            viewModel.rows.last?.id == latestRowId else {
        return
      }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        proxy.scrollTo(latestRowId, anchor: .bottom)
      }
    }
  }

  @discardableResult
  private func restoreMediaPrependAnchorIfNeeded(rowCount: Int,
                                                 using proxy: ScrollViewProxy) -> Bool {
    guard let anchorId = pendingMediaPrependAnchorId,
          rowCount > pendingMediaPrependRowCount else {
      return false
    }
    clearPendingMediaPrependAnchor()
    DispatchQueue.main.async {
      guard viewModel.rows.contains(where: { $0.id == anchorId }) else {
        return
      }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        // UIKit targets the first item from the previous page at the bottom
        // after reloadData. This keeps the old visible content in place when
        // the earlier page is inserted at the head of a section/grid.
        proxy.scrollTo(anchorId, anchor: .bottom)
      }
    }
    return true
  }

  private func clearPendingMediaPrependAnchor() {
    pendingMediaPrependAnchorId = nil
    pendingMediaPrependRowCount = 0
  }

  private var fileActionDialogState: NECommonDialogState? {
    guard let menu = viewModel.fileActionMenu else {
      return nil
    }
    return NECommonDialogState(
      id: menu.id,
      title: actionMenuTitle,
      showsTitle: !isMediaActionMenu(for: menu.row),
      actions: historyActionDialogActions(
        for: menu.row,
        style: token.styleMode,
        canForward: shouldShowForward(for:)
      )
    )
  }

  private func shouldShowForward(for row: MessageRowState) -> Bool {
    guard canForward(row) else {
      return false
    }
    return !NEChatUtilityMessageOperationRules.isAudioMessage(row.content)
  }

  private var actionMenuTitle: String {
    switch viewModel.fileActionMenu?.row.content {
    case .image:
      return ""
    case .video:
      return ""
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("chat_file", value: "File")
    default:
      return ""
    }
  }

  private func isMediaActionMenu(for row: MessageRowState) -> Bool {
    switch row.content {
    case .image, .video:
      return true
    default:
      return false
    }
  }

  private func handleFileAction(_ action: NECommonDialogAction) {
    guard let fileAction = HistoryFileAction(rawValue: action.id),
          let menu = viewModel.fileActionMenu else {
      viewModel.dismissFileActionMenu()
      return
    }
    let row = menu.row
    viewModel.dismissFileActionMenu()
    switch fileAction {
    case .locate:
      locate(row)
    case .forward:
      forward(row)
    case .collect:
      viewModel.collect(row: row)
    case .cancel:
      break
    }
  }

  private func forward(_ row: MessageRowState) {
    if let message = viewModel.sourceMessage(for: row) {
      if let onForwardMessageWithToast {
        onForwardMessageWithToast(row, message) { toast in
          viewModel.presentToast(toast)
        }
        return
      }
      if let onForwardMessage {
        onForwardMessage(row, message)
        return
      }
    }
    onForward(row)
  }

  private func locate(_ row: MessageRowState) {
    let selection = viewModel.selection(for: row)
    onSelect(selection)
  }

  private func syncFilePreviewRoute(_ preview: ChatFilePreviewState?) {
    guard let preview else {
      filePreviewRoute = nil
      return
    }
    guard filePreviewRoute?.preview != preview else {
      return
    }
    filePreviewRoute = HistoryFilePreviewRoute(preview: preview)
  }

  private func filePreviewBackAction(for route: HistoryFilePreviewRoute) -> () -> Void {
    {
      guard filePreviewRoute?.id == route.id else {
        return
      }
      filePreviewRoute = nil
      if viewModel.filePreview == route.preview {
        viewModel.consumeFilePreview()
      }
    }
  }
}

private struct HistoryMediaSectionView: View {
  var section: HistoryMessageSection
  var token: ChatThemeToken
  var scope: HistorySearchScope
  var itemWidth: CGFloat
  var downloadProgressByRowId: [String: Double]
  var onSelect: (MessageRowState) -> Void
  var onLongPress: (MessageRowState) -> Void
  var onLoadOlder: (MessageRowState) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HistoryMediaSectionHeader(title: section.title, token: token)
      LazyVGrid(columns: mediaColumns(itemWidth: itemWidth), spacing: 2) {
        ForEach(section.rows) { row in
          HistoryMediaGridCell(
            row: row,
            token: token,
            scope: scope,
            itemWidth: itemWidth,
            downloadProgress: downloadProgressByRowId[row.id]
          )
            .frame(width: itemWidth, height: itemWidth)
            .contentShape(Rectangle())
            .onTapGesture {
              onSelect(row)
            }
            .onLongPressGesture {
              onLongPress(row)
            }
            .onAppear {
              onLoadOlder(row)
            }
            .id(row.id)
        }
      }
    }
  }

  private func mediaColumns(itemWidth: CGFloat) -> [GridItem] {
    Array(repeating: GridItem(.fixed(itemWidth), spacing: 2), count: 4)
  }
}

private struct HistoryMediaSectionHeader: View {
  var title: String
  var token: ChatThemeToken

  var body: some View {
    HStack {
      Text(title)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(token.incomingTextColor)
      Spacer()
    }
    .frame(height: 40)
    .padding(.horizontal, 16)
    .background(Color.white)
  }
}

private struct HistoryMediaGridCell: View {
  var row: MessageRowState
  var token: ChatThemeToken
  var scope: HistorySearchScope
  var itemWidth: CGFloat
  var downloadProgress: Double?

  var body: some View {
    ZStack {
      mediaImage
        .frame(width: itemWidth, height: itemWidth)
        .clipped()

      if scope == .video {
        if isDownloading {
          HistoryVideoDownloadProgressView(progress: downloadProgress, token: token)
            .frame(width: itemWidth, height: itemWidth, alignment: .center)
        }
      }
    }
    .overlay(alignment: .bottom) {
      if scope == .video {
        videoInfoOverlay
      }
    }
    .frame(width: itemWidth, height: itemWidth)
    .clipped()
  }

  private var videoInfoOverlay: some View {
    HStack(spacing: 4) {
      videoIcon
      if let duration = videoDurationText {
        Text(duration)
          .font(.system(size: 12))
          .foregroundColor(.white)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .shadow(color: Color.black.opacity(0.75), radius: 1.5, x: 0, y: 1)
      }
    }
    .frame(height: 24, alignment: .center)
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, alignment: .center)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private var videoIcon: some View {
    if let image = NEChatUIKitSwiftUIBundle.loadImage("history_search_video") {
      Image(uiImage: image)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: 24, height: 24)
        .accessibilityLabel(scope.mediaTitle)
        .shadow(color: Color.black.opacity(0.75), radius: 1.5, x: 0, y: 1)
    } else {
      HistorySearchVideoFallbackIcon()
        .accessibilityLabel(scope.mediaTitle)
    }
  }

  @ViewBuilder
  private var mediaImage: some View {
    if let url = displayURL {
      ChatCachedAsyncImage(url: url) { image in
        image
          .resizable()
          .scaledToFill()
      } placeholder: {
        placeholder
      }
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    Image(NEChatCommonPresentation.mediaPlaceholderImageName(token: token),
          bundle: NECommonUIKitSwiftUIBundle.bundle)
      .renderingMode(.original)
      .resizable()
      .scaledToFill()
      .background(Color(hex: 0xF4F4F4))
  }

  private var displayURL: URL? {
    switch row.content {
    case let .image(media):
      return media.thumbnailURL ?? media.url ?? media.localFileURL
    case let .video(media):
      return media.thumbnailURL ?? media.url ?? media.localFileURL
    default:
      return nil
    }
  }

  private var videoDurationText: String? {
    guard case let .video(media) = row.content else {
      return nil
    }
    let duration = media.duration ?? 0
    guard duration > 0 else {
      return nil
    }
    return ChatUnitFormatter.playTime(duration)
  }

  private var isDownloading: Bool {
    downloadProgress != nil
  }
}

private struct HistorySearchVideoFallbackIcon: View {
  var body: some View {
    ZStack {
      Rectangle()
        .stroke(Color.white, lineWidth: 1.6)
        .frame(width: 14, height: 11)
        .offset(x: -3)

      Path { path in
        path.move(to: CGPoint(x: 15, y: 7))
        path.addLine(to: CGPoint(x: 21, y: 3))
        path.addLine(to: CGPoint(x: 21, y: 17))
        path.addLine(to: CGPoint(x: 15, y: 13))
        path.closeSubpath()
      }
      .stroke(Color.white, lineWidth: 1.6)
    }
    .frame(width: 24, height: 24)
    .shadow(color: Color.black.opacity(0.75), radius: 1.5, x: 0, y: 1)
  }
}

private struct HistoryVideoDownloadProgressView: View {
  var progress: Double?
  var token: ChatThemeToken

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.black.opacity(0.2))
        .frame(width: 42, height: 42)

      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(token.primaryButtonTextColor)
          .frame(width: 3, height: 18)
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(token.primaryButtonTextColor)
          .frame(width: 3, height: 18)
      }

      Circle()
        .stroke(token.primaryButtonTextColor.opacity(0.5), lineWidth: 4)
        .frame(width: 42, height: 42)

      if let progress {
        Circle()
          .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
          .stroke(token.primaryButtonTextColor, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
          .rotationEffect(.degrees(-90))
          .frame(width: 42, height: 42)
      } else {
        NEChatCommonPresentation.inlineLoadingView(token: token)
          .scaleEffect(0.86)
      }
    }
    .frame(width: 60, height: 60)
    .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_downloading", value: "Downloading"))
  }
}

private struct HistoryFileDownloadProgressView: View {
  var progress: Double?
  var token: ChatThemeToken

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.black.opacity(0.2))
        .frame(width: 32, height: 32)

      Circle()
        .stroke(token.primaryButtonTextColor.opacity(0.45), lineWidth: 3)
        .frame(width: 18, height: 18)

      Circle()
        .trim(from: 0, to: CGFloat(max(0, min(1, progress ?? 0))))
        .stroke(token.primaryButtonTextColor, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
        .rotationEffect(.degrees(-90))
        .frame(width: 18, height: 18)

      HStack(spacing: 5) {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(token.primaryButtonTextColor)
          .frame(width: 2, height: 10)
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(token.primaryButtonTextColor)
          .frame(width: 2, height: 10)
      }
    }
    .frame(width: 32, height: 32)
    .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_downloading", value: "Downloading"))
  }
}

private struct HistoryFileResultRow: View {
  var row: MessageRowState
  var token: ChatThemeToken
  var downloadProgress: Double?
  var onOpen: () -> Void
  var onMore: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        NEChatCommonPresentation.avatarView(
          imageURL: row.avatarURL,
          initials: avatarInitials,
          token: token,
          size: 24,
          cornerRadius: token.styleMode == .fun ? 4 : 12,
          hashID: row.senderId
        )

        Text(senderText)
          .font(.system(size: 14))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer(minLength: 8)

        Text(HistorySearchView.fileDateText(row.timestamp))
          .font(.system(size: 12))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(1)
      }
      .frame(height: 36)
      .padding(.horizontal, 20)
      .padding(.top, 0)

      HStack(spacing: 0) {
        Button(action: onOpen) {
          HStack(spacing: 12) {
            ZStack {
              NEChatCommonPresentation.iconView(
                imageName: ChatFileIconResource.imageName(for: file),
                token: token,
                renderingMode: .original,
                size: CGSize(width: 48, height: 48),
                accessibilityLabel: file.name
              )

              if downloadProgress != nil {
                HistoryFileDownloadProgressView(progress: downloadProgress, token: token)
              }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 8) {
              Text(file.name)
                .font(.system(size: 14))
                .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.greyText)
                .lineLimit(1)
                .truncationMode(.middle)
              if let sizeText = file.sizeText, !sizeText.isEmpty {
                Text(sizeText)
                  .font(.system(size: 12))
                  .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.greyText)
                  .lineLimit(1)
              }
            }

            Spacer(minLength: 8)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button(action: onMore) {
          NEChatCommonPresentation.iconView(
            imageName: "history_file_more",
            token: token,
            renderingMode: .original,
            size: CGSize(width: 24, height: 24),
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("more", value: "More")
          )
          .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("more", value: "More"))
      }
      .frame(height: 60)
      .padding(.leading, 10)
      .padding(.trailing, 8)
      .background(Color(hex: 0xF4F4F4))
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .padding(.leading, 20)
      .padding(.trailing, 20)
      .padding(.top, 16)
      .accessibilityElement(children: .contain)

      Rectangle()
        .fill(Color(hex: 0xD5D5D5).opacity(0.5))
        .frame(height: 1)
        .padding(.leading, 20)
        .padding(.top, 11)
    }
    .frame(height: 124)
    .background(Color.white)
  }

  private var file: MessageFileState {
    if case let .file(file) = row.content {
      return file
    }
    return MessageFileState(name: ChatMessageMapper.previewText(for: row.content))
  }

  private var senderText: String {
    row.senderName?.isEmpty == false ? row.senderName ?? "" : row.senderId ?? ""
  }

  private var avatarInitials: String {
    ChatAvatarDisplayResolver.initials(displayName: row.avatarName, accountId: row.senderId)
  }
}

private struct HistoryDatePickerView: View {
  var token: ChatThemeToken
  var initialDate: Date
  var onBack: () -> Void
  var onComplete: (Date) -> Void

  @State private var selectedDate: Date?
  @State private var currentDisplayMonth: Date
  @State private var scrollTargetMonth: Date?
  @State private var quickSelectType: HistoryQuickDateSelection = .today
  @State private var showsMonthPicker = false
  @State private var didInitialScroll = false
  @State private var toast: ChatToastState?

  init(token: ChatThemeToken,
       initialDate: Date,
       onBack: @escaping () -> Void,
       onComplete: @escaping (Date) -> Void) {
    self.token = token
    self.initialDate = initialDate
    self.onBack = onBack
    self.onComplete = onComplete
    let start = Calendar.current.startOfDay(for: initialDate)
    _selectedDate = State(initialValue: start)
    _currentDisplayMonth = State(initialValue: Calendar.current.startOfMonth(for: start))
    _scrollTargetMonth = State(initialValue: Calendar.current.startOfMonth(for: start))
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        NEChatCommonPresentation.navigationBar(
          title: NEChatUIKitSwiftUIBundle.localized("search_message_by_date", value: "Date"),
          token: token,
          backAction: onBack,
          trailingAction: NEChatCommonPresentation.textNavigationAction(
            id: "complete",
            title: NEChatUIKitSwiftUIBundle.localized("complete", value: "Done")
          ),
          onTrailingAction: {
            guard let selectedDate else {
              toast = ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("choose", value: "Please select"),
                style: .info
              )
              return
            }
            NEChatSwiftUILogger.log(
              "messageJump datePicker complete selectedTime=\(selectedDate.timeIntervalSince1970) selectedDay=\(Self.dateComponentsDescription(selectedDate))"
            )
            onComplete(selectedDate)
          },
          backgroundColor: .white,
          showsSeparator: true
        )

        quickButtons
          .padding(.top, 12)

        monthSelector
          .padding(.top, 20)

        weekdayHeader
          .padding(.top, 10)

        monthList
          .padding(.top, 5)
      }

      if showsMonthPicker {
        HistoryMonthYearPickerOverlay(
          currentDate: currentDisplayMonth,
          maxDate: Date(),
          token: token,
          onCancel: {
            showsMonthPicker = false
          },
          onConfirm: { date in
            currentDisplayMonth = Calendar.current.startOfMonth(for: date)
            scrollTargetMonth = currentDisplayMonth
            selectedDate = nil
            quickSelectType = .none
            showsMonthPicker = false
          }
        )
        .transition(.opacity)
      }
    }
    .background(Color.white.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .neCommonTransientOverlay(
      toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { value in
        if toast?.id == value.id {
          toast = nil
        }
      }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
    .onAppear {
      if let selectedDate {
        updateQuickSelection(for: selectedDate)
        currentDisplayMonth = Calendar.current.startOfMonth(for: selectedDate)
      }
      scrollTargetMonth = currentDisplayMonth
    }
  }

  private var quickButtons: some View {
    HStack(spacing: 12) {
      quickButton(title: NEChatUIKitSwiftUIBundle.localized("weekday_today", value: "Today"), type: .today, daysOffset: 0)
      quickButton(title: NEChatUIKitSwiftUIBundle.localized("weekday_last7day", value: "Last 7 Days"), type: .last7Days, daysOffset: -7)
      quickButton(title: NEChatUIKitSwiftUIBundle.localized("weekday_last30day", value: "Last 30 Days"), type: .last30Days, daysOffset: -30)
    }
    .padding(.horizontal, 16)
    .frame(height: 40)
  }

  private func quickButton(title: String, type: HistoryQuickDateSelection, daysOffset: Int) -> some View {
    let targetDate = Calendar.current.date(byAdding: .day, value: daysOffset, to: Date()) ?? Date()
    let isSelected = quickSelectType == type
    return Button {
      let start = Calendar.current.startOfDay(for: targetDate)
      selectedDate = start
      currentDisplayMonth = Calendar.current.startOfMonth(for: start)
      scrollTargetMonth = currentDisplayMonth
      quickSelectType = type
    } label: {
      Text(title)
        .font(.system(size: 14))
        .foregroundColor(isSelected ? .white : token.incomingTextColor)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(isSelected ? token.accentColor : Color.white)
        .overlay(
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(isSelected ? token.accentColor : Color(hex: 0xD9D9D9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var monthSelector: some View {
    Button {
      showsMonthPicker = true
    } label: {
      HStack(spacing: 0) {
        Text(Self.monthYearText(currentDisplayMonth))
          .font(.system(size: 14))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(1)
        NEChatCommonPresentation.iconView(
          imageName: "history_search_date_arrow_down",
          token: token,
          renderingMode: .original,
          size: CGSize(width: 12, height: 12),
          accessibilityLabel: Self.monthYearText(currentDisplayMonth)
        )
        Spacer()
      }
      .frame(width: 100, height: 30, alignment: .leading)
      .padding(.horizontal, 16)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var weekdayHeader: some View {
    let titles = [
      NEChatUIKitSwiftUIBundle.localized("weekday_sun", value: "Sun"),
      NEChatUIKitSwiftUIBundle.localized("weekday_mon", value: "Mon"),
      NEChatUIKitSwiftUIBundle.localized("weekday_tue", value: "Tue"),
      NEChatUIKitSwiftUIBundle.localized("weekday_wed", value: "Wed"),
      NEChatUIKitSwiftUIBundle.localized("weekday_thu", value: "Thu"),
      NEChatUIKitSwiftUIBundle.localized("weekday_fri", value: "Fri"),
      NEChatUIKitSwiftUIBundle.localized("weekday_sat", value: "Sat"),
    ]
    return HStack(spacing: 0) {
      ForEach(titles, id: \.self) { title in
        Text(title)
          .font(.system(size: 14))
          .foregroundColor(token.secondaryTextColor)
          .frame(maxWidth: .infinity, minHeight: 30)
      }
    }
    .padding(.horizontal, 16)
  }

  private var monthList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(months) { month in
            HistoryMonthSectionView(
              month: month.date,
              selectedDate: selectedDate,
              token: token,
              onSelect: { date in
                let selectedStart = Calendar.current.startOfDay(for: date)
                NEChatSwiftUILogger.log(
                  "messageJump datePicker select selectedTime=\(selectedStart.timeIntervalSince1970) selectedDay=\(Self.dateComponentsDescription(selectedStart))"
                )
                selectedDate = selectedStart
                currentDisplayMonth = Calendar.current.startOfMonth(for: date)
                updateQuickSelection(for: date)
              }
            )
            .id(month.id)
            .onAppear {
              if didInitialScroll {
                currentDisplayMonth = month.date
              }
            }
          }
        }
        .padding(.horizontal, 16)
      }
      .onAppear {
        didInitialScroll = false
        if let selectedDate {
          currentDisplayMonth = Calendar.current.startOfMonth(for: selectedDate)
          DispatchQueue.main.async {
            proxy.scrollTo(monthId(selectedDate), anchor: .top)
            DispatchQueue.main.async {
              proxy.scrollTo(dayId(selectedDate), anchor: .center)
            }
            currentDisplayMonth = Calendar.current.startOfMonth(for: selectedDate)
            didInitialScroll = true
          }
          return
        }
        let scrollDate = currentDisplayMonth
        currentDisplayMonth = Calendar.current.startOfMonth(for: scrollDate)
        DispatchQueue.main.async {
          proxy.scrollTo(monthId(scrollDate), anchor: .top)
          currentDisplayMonth = Calendar.current.startOfMonth(for: scrollDate)
          didInitialScroll = true
        }
      }
      .onChange(of: scrollTargetMonth) { month in
        guard let month else {
          return
        }
        DispatchQueue.main.async {
          proxy.scrollTo(monthId(month), anchor: .top)
          scrollTargetMonth = nil
        }
      }
    }
  }

  private var months: [HistoryMonthModel] {
    let calendar = Calendar.current
    guard var cursor = calendar.date(from: DateComponents(year: 1970, month: 1, day: 1)) else {
      return []
    }
    let end = calendar.startOfMonth(for: Date())
    var result = [HistoryMonthModel]()
    while cursor <= end {
      result.append(HistoryMonthModel(date: cursor))
      guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
        break
      }
      cursor = next
    }
    return result
  }

  private func monthId(_ date: Date) -> String {
    HistoryMonthModel(date: Calendar.current.startOfMonth(for: date)).id
  }

  private func dayId(_ date: Date) -> String {
    let calendar = Calendar.current
    let month = calendar.startOfMonth(for: date)
    let day = calendar.component(.day, from: date)
    return "\(HistoryMonthModel(date: month).id)-day-\(day)"
  }

  private func updateQuickSelection(for date: Date) {
    let calendar = Calendar.current
    let today = Date()
    if calendar.isDate(date, inSameDayAs: today) {
      quickSelectType = .today
    } else if let last7 = calendar.date(byAdding: .day, value: -7, to: today),
              calendar.isDate(date, inSameDayAs: last7) {
      quickSelectType = .last7Days
    } else if let last30 = calendar.date(byAdding: .day, value: -30, to: today),
              calendar.isDate(date, inSameDayAs: last30) {
      quickSelectType = .last30Days
    } else {
      quickSelectType = .none
    }
  }

  private static func monthYearText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = NECommonUIKitSwiftUIBundle.localized("ym")
    return formatter.string(from: date)
  }

  private static func dateComponentsDescription(_ date: Date) -> String {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0) timeZone=\(calendar.timeZone.identifier)"
  }
}

private enum HistoryQuickDateSelection {
  case none
  case today
  case last7Days
  case last30Days
}

private struct HistoryMonthModel: Identifiable {
  var date: Date

  var id: String {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return "month-\(components.year ?? 0)-\(components.month ?? 0)"
  }
}

private struct HistoryCalendarDay: Identifiable {
  var id: String
  var date: Date?
}

private struct HistoryMonthSectionView: View {
  var month: Date
  var selectedDate: Date?
  var token: ChatThemeToken
  var onSelect: (Date) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HistoryMonthHeaderView(title: Self.monthTitle(month), token: token)
      LazyVGrid(columns: calendarColumns, spacing: 0) {
        ForEach(monthDays) { day in
          HistoryDateCell(
            day: day.date.map { Calendar.current.component(.day, from: $0) },
            isToday: day.date.map { Calendar.current.isDateInToday($0) } ?? false,
            isSelected: day.date.map { date in
              guard let selectedDate else {
                return false
              }
              return Calendar.current.isDate(date, inSameDayAs: selectedDate)
            } ?? false,
            isFuture: day.date.map { $0 > Date() && !Calendar.current.isDateInToday($0) } ?? false,
            token: token
          )
          .frame(height: 70)
          .id(day.id)
          .contentShape(Rectangle())
          .onTapGesture {
            guard let date = day.date,
                  date <= Date() || Calendar.current.isDateInToday(date) else {
              return
            }
            onSelect(date)
          }
        }
      }
    }
  }

  private var calendarColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
  }

  private var monthDays: [HistoryCalendarDay] {
    let calendar = Calendar.current
    let start = calendar.startOfMonth(for: month)
    let firstWeekday = calendar.component(.weekday, from: start) - 1
    let daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
    var days = (0..<firstWeekday).map { HistoryCalendarDay(id: "\(HistoryMonthModel(date: start).id)-empty-\($0)", date: nil) }
    for day in 1...daysInMonth {
      var components = calendar.dateComponents([.year, .month], from: start)
      components.day = day
      if let date = calendar.date(from: components) {
        days.append(HistoryCalendarDay(id: "\(HistoryMonthModel(date: start).id)-day-\(day)", date: date))
      }
    }
    return days
  }

  private static func monthTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = NEChatUIKitSwiftUIBundle.localized("m", value: "M")
    return formatter.string(from: date)
  }
}

private struct HistoryMonthHeaderView: View {
  var title: String
  var token: ChatThemeToken

  var body: some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(Color(hex: 0xD5D5D5))
        .frame(height: 0.5)
      HStack {
        Text(title)
          .font(.system(size: 16))
          .foregroundColor(token.secondaryTextColor)
        Spacer()
      }
      .frame(height: 49, alignment: .bottom)
      .padding(.bottom, 8)
    }
  }
}

private struct HistoryDateCell: View {
  var day: Int?
  var isToday: Bool
  var isSelected: Bool
  var isFuture: Bool
  var token: ChatThemeToken

  var body: some View {
    VStack(spacing: 2) {
      ZStack {
        Circle()
          .fill(isSelected ? token.accentColor : Color.clear)
          .frame(width: 40, height: 40)
        if let day {
          Text("\(day)")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(dayColor)
        }
      }
      .frame(height: 45, alignment: .top)
      if isToday {
        Text(NEChatUIKitSwiftUIBundle.localized("weekday_today", value: "Today"))
          .font(.system(size: 10))
          .foregroundColor(isSelected ? token.accentColor : token.secondaryTextColor)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .opacity(isFuture ? 0.35 : 1)
  }

  private var dayColor: Color {
    if isFuture {
      return token.secondaryTextColor
    }
    return isSelected ? .white : token.incomingTextColor
  }
}

private struct HistoryMonthYearPickerOverlay: View {
  var currentDate: Date
  var maxDate: Date
  var token: ChatThemeToken
  var onCancel: () -> Void
  var onConfirm: (Date) -> Void

  @State private var selectedYear: Int
  @State private var selectedMonth: Int

  init(currentDate: Date,
       maxDate: Date,
       token: ChatThemeToken,
       onCancel: @escaping () -> Void,
       onConfirm: @escaping (Date) -> Void) {
    self.currentDate = currentDate
    self.maxDate = maxDate
    self.token = token
    self.onCancel = onCancel
    self.onConfirm = onConfirm
    _selectedYear = State(initialValue: Calendar.current.component(.year, from: currentDate))
    _selectedMonth = State(initialValue: Calendar.current.component(.month, from: currentDate))
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.5)
        .ignoresSafeArea()
        .onTapGesture {
          onCancel()
        }

      VStack(spacing: 0) {
        HStack {
          Button(action: onCancel) {
            Image(systemName: "xmark")
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.black)
              .frame(width: 26, height: 26)
          }
          .buttonStyle(.plain)

          Spacer()

          Text(NEChatUIKitSwiftUIBundle.localized("choose_date_year_month", value: "Select Chat date"))
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(token.incomingTextColor)
            .lineLimit(1)

          Spacer()

          Button {
            confirmSelection()
          } label: {
            Text(NEChatUIKitSwiftUIBundle.localized("complete", value: "Done"))
              .font(.system(size: 16))
              .foregroundColor(token.accentColor)
              .frame(minWidth: 26, minHeight: 26)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(height: 62)

        Rectangle()
          .fill(token.dividerColor)
          .frame(height: 0.5)

        HStack(spacing: 0) {
          Picker("", selection: $selectedYear) {
            ForEach(years, id: \.self) { year in
              Text("\(year)")
                .font(.system(size: 20, weight: .medium))
                .tag(year)
            }
          }
          .pickerStyle(.wheel)
          .frame(maxWidth: .infinity)
          .onChange(of: selectedYear) { _ in
            clampSelectedMonth()
          }

          Picker("", selection: $selectedMonth) {
            ForEach(monthsForSelectedYear, id: \.self) { month in
              Text(String(format: "%02d", month))
                .font(.system(size: 20, weight: .medium))
                .tag(month)
            }
          }
          .pickerStyle(.wheel)
          .frame(maxWidth: .infinity)
        }
        .padding(.top, 10)
        .padding(.bottom, 34)
      }
      .frame(height: 350)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }

  private var years: [Int] {
    let maxYear = Calendar.current.component(.year, from: maxDate)
    return Array(1970...maxYear)
  }

  private var monthsForSelectedYear: [Int] {
    let calendar = Calendar.current
    let maxYear = calendar.component(.year, from: maxDate)
    let maxMonth = calendar.component(.month, from: maxDate)
    if selectedYear == maxYear {
      return Array(1...maxMonth)
    }
    return Array(1...12)
  }

  private func clampSelectedMonth() {
    let months = monthsForSelectedYear
    if !months.contains(selectedMonth) {
      selectedMonth = months.last ?? 1
    }
  }

  private func confirmSelection() {
    var components = DateComponents()
    components.year = selectedYear
    components.month = selectedMonth
    components.day = 1
    let date = Calendar.current.date(from: components) ?? currentDate
    onConfirm(date)
  }
}

private struct HistoryMemberSelectionView: View {
  @StateObject private var viewModel: HistoryMemberSelectionViewModel
  var token: ChatThemeToken
  var onBack: () -> Void
  var onSelect: (HistoryMemberSelectionItem) -> Void

  init(teamId: String,
       teamType: V2NIMTeamType,
       token: ChatThemeToken,
       onBack: @escaping () -> Void,
       onSelect: @escaping (HistoryMemberSelectionItem) -> Void) {
    _viewModel = StateObject(wrappedValue: HistoryMemberSelectionViewModel(teamId: teamId, teamType: teamType))
    self.token = token
    self.onBack = onBack
    self.onSelect = onSelect
  }

  var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: NEChatUIKitSwiftUIBundle.localized("group_memmber", value: "Group Member"),
        token: token,
        backAction: onBack,
        trailingAction: NEChatCommonPresentation.textNavigationAction(
          id: "sure",
          title: viewModel.confirmTitle
        ),
        onTrailingAction: {
          guard let member = viewModel.selectedMember else {
            viewModel.showMemberEmptyToast()
            return
          }
          onSelect(member)
        },
        backgroundColor: token.styleMode == .fun ? token.navigationBackground : .white,
        showsSeparator: token.styleMode == .normal
      )

      NEChatCommonPresentation.searchField(
        text: $viewModel.query,
        placeholder: NEChatUIKitSwiftUIBundle.localized("search_member", value: "Search Member"),
        token: token,
        height: 34
      )
      .padding(.horizontal, 16)
      .padding(.top, 10)

      content
    }
    .background((token.styleMode == .fun ? token.pageBackground : Color.white).ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      viewModel.loadIfNeeded()
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
    .neCommonTransientOverlay(
      viewModel.toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
  }

  private var content: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(viewModel.visibleMembers) { member in
          Button {
            viewModel.toggle(member)
          } label: {
            HistoryMemberSelectionRow(
              member: member,
              token: token,
              isSelected: viewModel.selectedAccountId == member.accountId
            )
          }
          .buttonStyle(.plain)

          if member.id != viewModel.visibleMembers.last?.id {
            NEChatCommonPresentation.separator(token: token, leadingInset: 68)
              .background(token.panelItemBackground)
          }
        }
      }
      .padding(.top, 10)
    }
    .scrollDismissesKeyboard(.immediately)
  }
}

private struct HistoryMemberSelectionRow: View {
  var member: HistoryMemberSelectionItem
  var token: ChatThemeToken
  var isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      NEChatCommonPresentation.selectionIndicator(
        isSelected: isSelected,
        token: token,
        size: 18
      )
      .frame(width: token.styleMode == .fun ? 22 : 18, height: token.styleMode == .fun ? 22 : 18)

      NEChatCommonPresentation.avatarView(
        imageURL: ChatAvatarURLResolver.url(from: member.avatarURL),
        initials: ChatAvatarDisplayResolver.initials(displayName: member.avatarName, accountId: member.accountId),
        token: token,
        size: token.styleMode == .fun ? 42 : 32,
        cornerRadius: token.styleMode == .fun ? 4 : 16,
        hashID: member.accountId
      )
      Text(member.displayName)
        .font(.system(size: 16))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
      Spacer()
    }
    .frame(height: token.styleMode == .fun ? 64 : 52)
    .padding(.leading, 18)
    .padding(.trailing, 16)
    .background(token.panelItemBackground)
  }
}

@MainActor
private final class HistoryMemberSelectionViewModel: ObservableObject {
  @Published var phase: NEChatKitLoadPhase = .idle
  @Published var query = ""
  @Published var selectedAccountId: String?
  @Published var toast: ChatToastState?
  @Published private(set) var members: [HistoryMemberSelectionItem] = []

  var selectedMember: HistoryMemberSelectionItem? {
    guard let selectedAccountId else {
      return nil
    }
    return members.first { $0.accountId == selectedAccountId }
  }

  var confirmTitle: String {
    let title = NEChatUIKitSwiftUIBundle.localized("sure", value: "OK")
    return selectedAccountId == nil ? title : "\(title)(1)"
  }

  var visibleMembers: [HistoryMemberSelectionItem] {
    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      return members
    }
    return members.filter { member in
      member.displayName.localizedCaseInsensitiveContains(keyword)
    }
  }

  private let teamId: String
  private let teamType: V2NIMTeamType
  private let teamRepo: TeamRepo

  init(teamId: String,
       teamType: V2NIMTeamType,
       teamRepo: TeamRepo = .shared) {
    self.teamId = teamId
    self.teamType = teamType
    self.teamRepo = teamRepo
  }

  func loadIfNeeded() {
    guard phase == .idle else {
      return
    }
    load()
  }

  func load() {
    phase = .loading
    selectedAccountId = nil
    loadMembers(nextToken: "", loaded: [])
  }

  func toggle(_ member: HistoryMemberSelectionItem) {
    if selectedAccountId == member.accountId {
      selectedAccountId = nil
    } else {
      selectedAccountId = member.accountId
    }
  }

  func showMemberEmptyToast() {
    toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("member_empty_tip", value: "Select Member"),
      style: .warning
    )
  }

  func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  private func loadMembers(nextToken: String, loaded: [V2NIMTeamMember]) {
    let option = V2NIMTeamMemberQueryOption()
    option.limit = 100
    option.direction = .QUERY_DIRECTION_ASC
    option.onlyChatBanned = false
    option.nextToken = nextToken
    option.roleQueryType = .TEAM_MEMBER_ROLE_QUERY_TYPE_ALL

    teamRepo.getTeamMemberList(teamId, teamType, option) { [weak self] result, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.phase = .failed(
            NEChatErrorMessageMapper.errorState(
              for: error,
              fallbackKey: "chat_history_member_failed",
              fallbackValue: "Member loading failed"
            )
          )
          return
        }
        let nextLoaded = loaded + (result?.memberList ?? [])
        guard result?.finished == false,
              let next = result?.nextToken,
              !next.isEmpty else {
          self.enrich(nextLoaded)
          return
        }
        self.loadMembers(nextToken: next, loaded: nextLoaded)
      }
    }
  }

  private func enrich(_ loadedMembers: [V2NIMTeamMember]) {
    let accountIds = loadedMembers.map(\.accountId)
    guard !accountIds.isEmpty else {
      members = []
      phase = .empty
      return
    }

    teamRepo.swiftUITeamMemberDisplayInfos(teamId: teamId, teamType: teamType, accountIds: accountIds) { [weak self] infos, _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        let infoMap = Dictionary(uniqueKeysWithValues: infos.map { ($0.accountId, $0) })
        self.members = loadedMembers
          .filter(\.inTeam)
          .sorted(by: Self.memberOrder)
          .map { member in
            let info = infoMap[member.accountId]
            return HistoryMemberSelectionItem(
              accountId: member.accountId,
              displayName: info?.displayName ?? member.teamNick ?? member.accountId,
              avatarName: info?.avatarName,
              avatarURL: info?.avatarURL,
              teamNick: member.teamNick
            )
          }
        self.phase = self.members.isEmpty ? .empty : .loaded
      }
    }
  }

  private static func memberOrder(_ left: V2NIMTeamMember,
                                  _ right: V2NIMTeamMember) -> Bool {
    let leftPriority = memberRolePriority(left)
    let rightPriority = memberRolePriority(right)
    if leftPriority != rightPriority {
      return leftPriority < rightPriority
    }
    if left.joinTime != right.joinTime {
      return left.joinTime < right.joinTime
    }
    return left.accountId.localizedCompare(right.accountId) == .orderedAscending
  }

  private static func memberRolePriority(_ member: V2NIMTeamMember) -> Int {
    if NEAIUserManager.shared.isAIUser(member.accountId) {
      return 0
    }
    switch member.memberRole {
    case .TEAM_MEMBER_ROLE_OWNER:
      return 1
    case .TEAM_MEMBER_ROLE_MANAGER:
      return 2
    default:
      return 3
    }
  }
}

private struct HistoryMemberSelectionItem: Identifiable, Equatable {
  var id: String { accountId }
  var accountId: String
  var displayName: String
  var avatarName: String?
  var avatarURL: String?
  var teamNick: String?
}

private struct HistoryResultRowView: View {
  var row: MessageRowState
  var token: ChatThemeToken
  var scope: HistorySearchScope
  var onSelect: () -> Void
  var onOpenURL: (URL, String) -> Void

  var body: some View {
    VStack(spacing: token.rowVerticalSpacing) {
      if let timeDividerText = row.timeDividerText, !timeDividerText.isEmpty {
        timeDivider(timeDividerText)
      }

      MessageBubbleView(
        row: row,
        token: token,
        showsAvatar: row.direction != .system,
        showsSenderName: row.direction == .incoming,
        onOpenURL: { url, displayText, _, _ in
          onOpenURL(url, displayText)
        },
        onBodyTap: { _ in
          onSelect()
        },
        keywordHighlightColor: token.accentColor,
        showsAIResponseActions: false
      )
    }
    .background(token.messageListBackground)
  }

  private func timeDivider(_ text: String) -> some View {
    Text(text)
      .font(.system(size: token.timeDividerFontSize))
      .foregroundColor(token.secondaryTextColor)
      .padding(.horizontal, 10)
      .frame(height: token.timeCellHeight)
      .background {
        Capsule()
          .fill(token.dividerColor.opacity(0.35))
      }
      .frame(maxWidth: .infinity)
  }
}

private struct HistoryMessageSection: Identifiable {
  var id: String { title }
  var title: String
  var rows: [MessageRowState]

  static func group(rows: [MessageRowState], scope: HistorySearchScope) -> [HistoryMessageSection] {
    var sections = [HistoryMessageSection]()
    for row in rows {
      let title = scope == .file
        ? monthText(row.timestamp)
        : dayText(row.timestamp)
      if let index = sections.firstIndex(where: { $0.title == title }) {
        sections[index].rows.append(row)
      } else {
        sections.append(HistoryMessageSection(title: title, rows: [row]))
      }
    }
    return sections
  }

  private static func monthText(_ timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }
    let formatter = DateFormatter()
    formatter.dateFormat = NEChatUIKitSwiftUIBundle.localized("ym", value: "yyyy/MM")
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
  }

  private static func dayText(_ timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }
    return ChatUnitFormatter.historyMediaDateText(timestamp)
  }
}

private extension HistorySearchScope {
  var quickTitle: String {
    switch self {
    case .member:
      return NEChatUIKitSwiftUIBundle.localized("group_memmber", value: "Group Member")
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("images", value: "Images")
    case .video:
      return NEChatUIKitSwiftUIBundle.localized("videos", value: "Videos")
    case .date:
      return NEChatUIKitSwiftUIBundle.localized("operation_date", value: "Date")
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("chat_file", value: "File")
    case .keyword:
      return title
    }
  }

  var mediaTitle: String {
    switch self {
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("images", value: "Images")
    case .video:
      return NEChatUIKitSwiftUIBundle.localized("videos", value: "Videos")
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("chat_file", value: "File")
    default:
      return title
    }
  }

  var iconImageName: String {
    switch self {
    case .keyword:
      return "textField_search_icon"
    case .image:
      return "photo"
    case .video:
      return "op_video"
    case .file:
      return "op_file"
    case .date:
      return "op_date"
    case .member:
      return "op_teamMember"
    }
  }
}

private extension MessageMediaState {
  var localFileURL: URL? {
    guard let localPath,
          !localPath.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: localPath)
  }
}


private extension Calendar {
  func startOfMonth(for date: Date) -> Date {
    let components = dateComponents([.year, .month], from: date)
    return self.date(from: components) ?? startOfDay(for: date)
  }
}
