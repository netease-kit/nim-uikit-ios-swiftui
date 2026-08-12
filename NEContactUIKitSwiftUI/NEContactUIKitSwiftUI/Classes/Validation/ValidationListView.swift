// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NEChatUIKitSwiftUI
import SwiftUI

public struct ValidationListView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var viewModel: ValidationListViewModel
  @State private var isClearConfirmPresented = false
  private let token: ContactThemeToken

  public init(viewModel: ValidationListViewModel,
              token: ContactThemeToken) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("validation_message", value: "Verifications"),
        token: token,
        onBack: { dismiss() }
      ) {
        Button {
          isClearConfirmPresented = true
        } label: {
          Text(NEContactUIKitSwiftUIBundle.localized("clear", value: "Clear"))
            .font(.system(size: token.styleMode == .fun ? 16 : 14))
            .foregroundColor(Color(hex: 0x333333))
        }
        .buttonStyle(.plain)
      }
      if viewModel.showsTabs {
        ValidationTabBar(
          tabs: viewModel.tabs,
          selection: $viewModel.selectedTab,
          token: token
        )
      }
      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .onDisappear { viewModel.onDisappear() }
    .onChange(of: scenePhase) { phase in
      if phase == .background {
        viewModel.markRead()
      }
    }
    .neCommonTransientOverlay(viewModel.toast, placement: .top, topPadding: 52, onDismiss: { viewModel.consumeToast($0) }) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .neCommonConfirmationDialog(
      clearDialogState,
      onAction: handleClearDialogAction,
      onDismiss: { isClearConfirmPresented = false }
    )
  }

  private var clearDialogState: NECommonDialogState? {
    guard isClearConfirmPresented else {
      return nil
    }
    let message: String
    switch viewModel.selectedTab {
    case .friend:
      message = NEContactUIKitSwiftUIBundle.localized("clear_all_add_application", value: "Whether to clear all add application？")
    case .team:
      message = NEContactUIKitSwiftUIBundle.localized("clear_all_team_join_action", value: "Whether to clear all team join action？")
    }
    return NECommonDialogState(
      id: "clearValidation",
      title: NEContactUIKitSwiftUIBundle.localized("alert_tip", value: "Tip"),
      message: message,
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "sure",
          title: NECommonUIKitSwiftUIBundle.localized("sure", fallback: "Sure"),
          role: .normal
        ),
      ]
    )
  }

  private func handleClearDialogAction(_ action: NECommonDialogAction) {
    defer { isClearConfirmPresented = false }
    guard action.id == "sure" else {
      return
    }
    viewModel.clearAll()
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(state: NECommonErrorState(textKey: "network_error", fallbackText: message, severity: .warning, retryable: true), retry: { viewModel.load() })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .loaded:
      if viewModel.rows.isEmpty {
        NECommonEmptyStateView(state: NECommonEmptyState(titleKey: "no_add_application", fallbackTitle: NEContactUIKitSwiftUIBundle.localized("no_add_application", value: "No Verifications"), imageKind: .user))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(viewModel.rows) { row in
              ValidationRowView(row: row, token: token, onAccept: { viewModel.accept(row) }, onReject: { viewModel.reject(row) })
            }
          }
        }
      }
    }
  }
}

private struct ValidationRowView: View {
  var row: ValidationRowState
  var token: ContactThemeToken
  var onAccept: () -> Void
  var onReject: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      avatarWithUnreadBadge
      VStack(alignment: .leading, spacing: 5) {
        Text(row.title)
          .font(.system(size: token.titleFontSize))
          .foregroundColor(token.primaryTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(row.subtitle)
          .font(.system(size: token.subtitleFontSize))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if row.canHandle {
        HStack(spacing: 10) {
          Button(action: onReject) {
            Text(NEContactUIKitSwiftUIBundle.localized("refuse", value: "Decline"))
              .font(.system(size: 14))
              .foregroundColor(Color(hex: 0x333333))
              .frame(width: 60, height: 32)
              .background(Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xD9D9D9), lineWidth: 1))
          }
          .buttonStyle(.plain)

          Button(action: onAccept) {
            Text(NEContactUIKitSwiftUIBundle.localized("agree", value: "Accept"))
              .font(.system(size: 14))
              .foregroundColor(agreeTitleColor)
              .frame(width: 60, height: 32)
              .background(agreeBackgroundColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 4).stroke(token.accentColor, lineWidth: 1))
          }
          .buttonStyle(.plain)
        }
      } else if let status = row.statusText, row.showsResult {
        Text(status)
          .font(.system(size: 14))
          .foregroundColor(token.tertiaryTextColor)
      }
    }
    .frame(minHeight: 68)
    .padding(.horizontal, 20)
    .background(row.unreadCount > 0 ? unreadBackgroundColor : token.rowBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(token.rowSeparatorColor)
        .frame(height: 1)
        .padding(.leading, token.rowHorizontalPadding + token.avatarSize + 12)
    }
  }

  private var avatarWithUnreadBadge: some View {
    ZStack(alignment: .topTrailing) {
      NECommonAvatarView(
        imageURL: NECommonAvatarDisplayResolver.url(from: row.avatarURL),
        initials: initials(for: row),
        size: token.avatarSize,
        cornerRadius: token.avatarCornerRadius,
        hashID: row.accountId
      )
      if row.unreadCount > 1 {
        Text(row.unreadCount > 99 ? "99+" : "\(row.unreadCount)")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.horizontal, 5)
          .frame(height: 18)
          .background(Color(hex: 0xF24957), in: Capsule())
          .offset(x: 6, y: -6)
      }
    }
    .frame(width: token.avatarSize, height: token.avatarSize)
  }

  private var unreadBackgroundColor: Color {
    Color(hex: 0xF3F5F7)
  }

  private var agreeTitleColor: Color {
    token.styleMode == .fun ? .white : token.accentColor
  }

  private var agreeBackgroundColor: Color {
    token.styleMode == .fun ? token.accentColor : .clear
  }

  private func initials(for row: ValidationRowState) -> String {
    NECommonAvatarDisplayResolver.initials(
      displayName: row.avatarName,
      fallbackID: row.accountId,
      defaultText: "#"
    )
  }

}

private struct ValidationTabBar: View {
  var tabs: [ValidationListTab]
  @Binding var selection: ValidationListTab
  var token: ContactThemeToken

  var body: some View {
    HStack(spacing: 0) {
      ForEach(tabs) { tab in
        Button {
          selection = tab
        } label: {
          VStack(spacing: 0) {
            Text(tab.title)
              .font(.system(size: 15))
              .foregroundColor(selection == tab ? token.accentColor : token.primaryTextColor)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
              .fill(selection == tab ? token.accentColor : Color.clear)
              .frame(height: 2)
          }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
      }
    }
    .frame(height: 44)
    .background(token.rowBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(token.rowSeparatorColor)
        .frame(height: 1)
    }
  }
}
