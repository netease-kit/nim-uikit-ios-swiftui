// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct BotSubSessionListView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  @StateObject private var viewModel: BotSubSessionListViewModel
  private let token: ChatThemeToken
  private let onRoute: (NEChatSwiftUIRoute) -> Void

  @MainActor
  public init(viewModel: BotSubSessionListViewModel,
              token: ChatThemeToken = .normal,
              onRoute: @escaping (NEChatSwiftUIRoute) -> Void = { _ in }) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onRoute = onRoute
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: viewModel.title,
        token: token,
        backAction: {
          if let chatRouteBackAction {
            chatRouteBackAction()
          } else {
            dismiss()
          }
        },
        trailingWidth: 74
      ) {
        HStack(spacing: 6) {
          Button {
            if let route = viewModel.routeForCreate() {
              onRoute(route)
            }
          } label: {
            NEChatCommonPresentation.commonIconView(
              imageName: "three_point",
              token: token,
              renderingMode: .original,
              size: CGSize(width: 32, height: 32),
              accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_create_conversation", value: "Create conversation")
            )
          }
          .buttonStyle(.plain)

          Button {
            onRoute(viewModel.routeForSetting())
          } label: {
            NEChatCommonPresentation.iconView(
              imageName: "add_black",
              token: token,
              renderingMode: .original,
              size: CGSize(width: 32, height: 32),
              accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_setting", value: "Chat Setting")
            )
          }
          .buttonStyle(.plain)
        }
      }

      List {
        Section {
          NEChatCommonPresentation.searchField(
            text: Binding(
              get: { viewModel.query },
              set: { viewModel.updateQuery($0) }
            ),
            placeholder: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_search_hint", value: "Search sub-sessions"),
            token: token
          )
          .listRowSeparator(.hidden)
          .listRowBackground(token.groupedPageBackground)
        }

        ForEach(viewModel.rows) { row in
          Button {
            onRoute(viewModel.routeForTopic(row))
          } label: {
            BotSubSessionRowView(row: row, token: token)
          }
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
          .listRowSeparator(.hidden)
          .listRowBackground(token.panelItemBackground)
          .swipeActions {
            Button(role: .destructive) {
              viewModel.beginDelete(row: row)
            } label: {
              NEChatLocalIconLabel(
                title: NEChatUIKitSwiftUIBundle.localized("operation_delete", value: "Delete"),
                imageName: "op_delete",
                token: token
              )
            }
            .tint(token.secondaryTextColor.opacity(0.85))

            Button {
              viewModel.beginRename(row: row)
            } label: {
              NEChatLocalIconLabel(
                title: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_rename_action", value: "Rename"),
                imageName: "ai_edit",
                token: token,
                renderingMode: .original
              )
            }
            .tint(token.accentColor)
          }
        }
      }
      .listStyle(.plain)
      .scrollDismissesKeyboard(.immediately)
      .scrollContentBackground(.hidden)
      .background(token.groupedPageBackground)
    }
    .background(token.groupedPageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .overlay {
      switch viewModel.phase {
      case .loading, .refreshing:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty:
        emptyView
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.load(reset: true)
        }
      default:
        EmptyView()
      }
    }
    .sheet(item: Binding(
      get: { viewModel.renameState },
      set: { state in
        if state == nil {
          viewModel.cancelRename()
        }
      }
    )) { _ in
      BotSubSessionRenameView(viewModel: viewModel, token: token)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
    .neCommonConfirmationDialog(
      deleteDialogState,
      onAction: handleDeleteDialogAction,
      onDismiss: {
        viewModel.cancelDelete()
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
    .onAppear { viewModel.onAppear() }
    .onDisappear { viewModel.onDisappear() }
    .environment(\.neChatChildRouteBackAction, nil)
  }

  @ViewBuilder
  private var emptyView: some View {
    VStack(spacing: 16) {
      NEChatCommonPresentation.inlineEmptyView(
        title: viewModel.shouldShowSearchEmpty
          ? NEChatUIKitSwiftUIBundle.localized("bot_sub_session_search_empty", value: "No related sub-sessions found")
          : NEChatUIKitSwiftUIBundle.localized("bot_sub_session_empty", value: "No topics yet. Send a message to start one."),
        token: token,
        imageName: viewModel.shouldShowSearchEmpty ? "bot_sub_session_guide" : "bot_sub_session_icon",
        message: nil
      )

      if !viewModel.shouldShowSearchEmpty {
        NEChatCommonPresentation.actionButton(
          title: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_create_conversation", value: "Create conversation"),
          token: token,
          imageName: "add_black",
          renderingMode: .original,
          minHeight: 36
        ) {
          if let route = viewModel.routeForCreate() {
            onRoute(route)
          }
        }
        .frame(maxWidth: 220)
      }
    }
    .padding(.horizontal, 24)
  }

  private var deleteDialogState: NECommonDialogState? {
    guard let deleteState = viewModel.deleteState else {
      return nil
    }

    return NECommonDialogState(
      id: "botSubSessionDelete:\(deleteState.row.id)",
      title: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_delete_title", value: "Topic deletion"),
      message: String(
        format: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_delete_topic", value: "Delete topic \"%@\"?"),
        deleteState.row.title
      ),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel,
          isEnabled: !deleteState.isDeleting
        ),
        NECommonDialogAction(
          id: "delete",
          title: deleteState.isDeleting
            ? NEChatUIKitSwiftUIBundle.localized("deleting", value: "Deleting")
            : NEChatUIKitSwiftUIBundle.localized("operation_delete", value: "Delete"),
          imageName: "op_delete",
          imageBundle: NEChatUIKitSwiftUIBundle.bundle,
          role: .destructive,
          isEnabled: !deleteState.isDeleting
        ),
      ]
    )
  }

  private func handleDeleteDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "delete":
      viewModel.confirmDelete()
    default:
      viewModel.cancelDelete()
    }
  }
}

private struct BotSubSessionRowView: View {
  var row: BotSubSessionRowState
  var token: ChatThemeToken

  var body: some View {
    HStack(spacing: 12) {
      botSubSessionIcon

      VStack(alignment: .leading, spacing: 6) {
        Text(row.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)

        MessageEmoticonTextView(
          text: row.summary.isEmpty ? NEChatUIKitSwiftUIBundle.localized("bot_sub_session_no_preview", value: "No preview") : row.summary,
          token: token,
          baseColor: token.secondaryTextColor
        )
          .font(.system(size: 14))
          .lineLimit(1)
          .truncationMode(.tail)
      }

      Spacer(minLength: 12)

      VStack(alignment: .trailing, spacing: 8) {
        if row.updateTime > 0 {
          Text(Self.dateText(row.updateTime))
            .font(.system(size: 12))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
        }

        if row.hasUnread {
          Circle()
            .fill(token.warningColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_message_unread", value: "Unread"))
        }
      }
      .frame(minWidth: 52, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 68)
    .background(token.panelItemBackground)
  }

  @ViewBuilder
  private var botSubSessionIcon: some View {
    Image("bot_sub_session_icon", bundle: NEChatUIKitSwiftUIBundle.bundle)
      .resizable()
      .scaledToFit()
    .frame(width: 40, height: 40)
    .accessibilityHidden(true)
  }

  private static func dateText(_ time: TimeInterval) -> String {
    ChatUnitFormatter.conversationTimeText(time)
  }
}

private struct BotSubSessionRenameView: View {
  @ObservedObject var viewModel: BotSubSessionListViewModel
  var token: ChatThemeToken

  var body: some View {
    VStack(spacing: 16) {
      Text(NEChatUIKitSwiftUIBundle.localized("bot_sub_session_rename", value: "Rename"))
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(token.incomingTextColor)
        .frame(maxWidth: .infinity, alignment: .leading)

      NEChatCommonPresentation.formTextField(
        title: nil,
        text: Binding(
          get: { viewModel.renameState?.name ?? "" },
          set: { viewModel.updateRenameName($0) }
        ),
        placeholder: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_input_name", value: "Please enter a name"),
        token: token,
        error: viewModel.renameState?.error,
        isEnabled: viewModel.renameState?.isSaving != true,
        submitLabel: .done,
        backgroundCornerRadius: token.controlCornerRadius,
        characterLimit: 20
      ) {
        viewModel.submitRename()
      }

      HStack(spacing: 12) {
        NEChatCommonPresentation.actionButton(
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          token: token,
          style: .secondary,
          isEnabled: viewModel.renameState?.isSaving != true,
          minHeight: 40
        ) {
          viewModel.cancelRename()
        }

        NEChatCommonPresentation.actionButton(
          title: NEChatUIKitSwiftUIBundle.localized("confirm", value: "Confirm"),
          token: token,
          isEnabled: viewModel.renameState?.isSaving != true,
          isLoading: viewModel.renameState?.isSaving == true,
          minHeight: 40
        ) {
          viewModel.submitRename()
        }
      }
    }
    .padding(20)
    .background(token.panelItemBackground)
  }
}
