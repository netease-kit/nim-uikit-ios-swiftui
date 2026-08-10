// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NETeamUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct ContactSearchView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: ContactSearchViewModel
  @State private var route: ContactRouteRequest?
  private let token: ContactThemeToken
  private let onOpenChat: ((String, String) -> Void)?

  @MainActor
  public init(token: ContactThemeToken) {
    _viewModel = StateObject(wrappedValue: ContactSearchViewModel())
    self.token = token
    self.onOpenChat = nil
  }

  public init(viewModel: ContactSearchViewModel,
              token: ContactThemeToken,
              onOpenChat: ((String, String) -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onOpenChat = onOpenChat
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("search", value: "Search"),
        token: token,
        onBack: { dismiss() }
      )

      searchField

      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .navigationDestination(isPresented: routeIsPresentedBinding) {
      if case .userInfo(let accountId, let isCurrentUser) = route?.kind {
        ContactUserInfoView(
          viewModel: ContactUserInfoViewModel(accountId: accountId, isCurrentUser: isCurrentUser),
          token: token,
          onOpenChat: onOpenChat
        )
        .toolbar(.hidden, for: .tabBar)
      } else if case .chat(let accountId, let title) = route?.kind {
        let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) ?? accountId
        let chatConfig = currentChatConfig()
        ChatView(
          viewModel: ChatSessionViewModel(
            context: ChatSessionContext(
              kind: .p2p,
              conversationId: conversationId,
              title: title,
              sessionId: accountId,
              sessionName: title
            ),
            config: chatConfig
          ),
          token: chatConfig.themeToken
        )
        .toolbar(.hidden, for: .tabBar)
      } else if case .teamChat(let teamId, let title) = route?.kind {
        let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) ?? teamId
        let chatConfig = currentChatConfig()
        ChatView(
          viewModel: ChatSessionViewModel(
            context: ChatSessionContext(
              kind: .team,
              conversationId: conversationId,
              title: title,
              sessionId: teamId,
              sessionName: title
            ),
            config: chatConfig
          ),
          token: chatConfig.themeToken
        )
        .toolbar(.hidden, for: .tabBar)
      } else if case .team(let teamId) = route?.kind {
        let teamConfig = currentTeamConfig()
        TeamSettingView(
          teamId: teamId,
          style: teamConfig.styleMode,
          token: teamConfig.themeToken,
          config: teamConfig
        )
        .toolbar(.hidden, for: .tabBar)
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
  }

  private var searchField: some View {
    NECommonSearchFieldView(
      text: Binding(
        get: { viewModel.query },
        set: { viewModel.updateQuery($0) }
      ),
      placeholder: NEContactUIKitSwiftUIBundle.localized("search_keyword", value: "Enter and search..."),
      height: token.styleMode == .fun ? 36 : 32,
      horizontalPadding: 12,
      onClear: { viewModel.clearQuery() }
    )
    .padding(.horizontal, token.styleMode == .fun ? 8 : 20)
    .padding(.top, token.styleMode == .fun ? 12 : 20)
    .padding(.bottom, token.styleMode == .fun ? 12 : 20)
    .neCommonTheme(NEContactCommonPresentation.searchTheme(for: token))
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(
        state: NECommonErrorState(textKey: "network_error", fallbackText: message, severity: .warning, retryable: true),
        retry: { viewModel.load() }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .loaded:
      if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Spacer()
      } else if viewModel.sections.isEmpty {
        NECommonEmptyStateView(
          state: NECommonEmptyState(
            titleKey: "contact_user_not_exist",
            fallbackTitle: NEContactUIKitSwiftUIBundle.localized("user_not_exist", value: "User not found"),
            imageKind: .user
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
      } else {
        ScrollView {
          LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(viewModel.sections) { section in
              Section {
                ForEach(section.rows) { row in
                  ContactSearchRowView(row: row, token: token)
                    .onTapGesture {
                      viewModel.select(row) { nextRoute in
                        route = nextRoute
                      }
                    }
                    .overlay(alignment: .bottom) {
                      Rectangle()
                        .fill(token.rowSeparatorColor)
                        .frame(height: token.styleMode == .fun ? 0.5 : 1)
                        .padding(.leading, token.rowHorizontalPadding + token.avatarSize + 12)
                    }
                }
              } header: {
                ContactSearchSectionHeaderView(title: section.title, token: token)
              }
            }
          }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(token.pageBackground)
      }
    }
  }

  private var routeIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { route != nil },
      set: { isPresented in
        if !isPresented {
          route = nil
        }
      }
    )
  }

  private func currentChatConfig() -> ChatSwiftUIConfig {
    var config = ChatSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }

  private func currentTeamConfig() -> NETeamSwiftUIConfig {
    var config = NETeamSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }
}

private struct ContactSearchRowView: View {
  var row: ContactSearchRowState
  var token: ContactThemeToken

  var body: some View {
    HStack(spacing: 12) {
      NECommonAvatarView(
        imageURL: row.avatar.imageURL,
        initials: row.avatar.initials,
        size: token.avatarSize,
        cornerRadius: token.avatarCornerRadius,
        hashID: row.avatar.hashID
      )
      .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))

      VStack(alignment: .leading, spacing: 4) {
        highlightedText(row.title, range: row.highlightedTitleRange, normalColor: token.primaryTextColor)
          .font(.system(size: token.styleMode == .fun ? 17 : 14))
          .lineLimit(1)
          .truncationMode(.tail)
        if let subtitle = row.subtitle, !subtitle.isEmpty {
          highlightedText(subtitle, range: row.highlightedSubtitleRange, normalColor: token.secondaryTextColor)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }

      Spacer(minLength: 8)
    }
    .frame(height: token.styleMode == .fun ? 74 : 60)
    .padding(.leading, token.rowHorizontalPadding)
    .padding(.trailing, 16)
    .background(token.rowBackground)
    .contentShape(Rectangle())
  }

  private func highlightedText(_ text: String,
                               range: Range<String.Index>?,
                               normalColor: Color) -> Text {
    guard let range, !range.isEmpty else {
      return Text(text)
        .foregroundColor(normalColor)
    }

    let prefix = String(text[..<range.lowerBound])
    let match = String(text[range])
    let suffix = String(text[range.upperBound...])
    return Text(prefix)
      .foregroundColor(normalColor)
      + Text(match)
      .foregroundColor(token.accentColor)
      + Text(suffix)
      .foregroundColor(normalColor)
  }
}

private struct ContactSearchSectionHeaderView: View {
  var title: String
  var token: ContactThemeToken

  var body: some View {
    Text(title)
      .font(.system(size: token.styleMode == .fun ? 14 : 13))
      .foregroundColor(token.tertiaryTextColor)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, token.styleMode == .fun ? 16 : 20)
      .frame(height: token.styleMode == .fun ? 38 : 30)
      .background(token.rowBackground)
  }
}
