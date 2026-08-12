// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NEChatUIKitSwiftUI
import SwiftUI

public struct ContactTeamListView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: ContactTeamListViewModel
  private let token: ContactThemeToken
  private let onOpenTeamChat: (String, String) -> Void

  public init(viewModel: ContactTeamListViewModel,
              token: ContactThemeToken,
              onOpenTeamChat: @escaping (String, String) -> Void) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onOpenTeamChat = onOpenTeamChat
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("my_teams", value: "My Groups"),
        token: token,
        onBack: { dismiss() }
      )
      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
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
        NECommonEmptyStateView(state: NECommonEmptyState(titleKey: "team_empty", fallbackTitle: NEContactUIKitSwiftUIBundle.localized("team_empty", value: "No Group"), imageKind: .user))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(viewModel.rows) { row in
              ContactRowView(entry: row, token: token)
                .onTapGesture {
                  guard let teamId = row.accountId else { return }
                  onOpenTeamChat(teamId, row.title)
                }
            }
          }
        }
      }
    }
  }
}
