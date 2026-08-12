// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NEChatUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct AIUserListView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: AIUserListViewModel
  @State private var route: ContactRouteRequest?
  @State private var selectedAIUser: V2NIMAIUser?
  private let token: ContactThemeToken
  private let onOpenChat: ((String, String) -> Void)?

  public init(viewModel: AIUserListViewModel,
              token: ContactThemeToken,
              onOpenChat: ((String, String) -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onOpenChat = onOpenChat
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("my_ai_user", value: "My AI User"),
        token: token,
        onBack: { dismiss() }
      )
      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .onChange(of: viewModel.pendingRoute) { pending in
      route = pending
      viewModel.consumePendingRoute()
    }
    .onChange(of: route) { route in
      if route == nil {
        selectedAIUser = nil
      }
    }
    .navigationDestination(isPresented: routeIsPresentedBinding) {
      routeDestination
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

  @ViewBuilder
  private var routeDestination: some View {
    if let route,
       case .userInfo(let accountId, let isCurrentUser) = route.kind {
      ContactUserInfoView(
        viewModel: ContactUserInfoViewModel(
          accountId: accountId,
          isCurrentUser: isCurrentUser,
          aiUser: selectedAIUser
        ),
        token: token,
        onOpenChat: onOpenChat
      )
      .toolbar(.hidden, for: .tabBar)
    } else {
      EmptyView()
    }
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
        NECommonEmptyStateView(state: NECommonEmptyState(titleKey: "no_ai_user", fallbackTitle: NEContactUIKitSwiftUIBundle.localized("no_ai_user", value: "No AI User"), imageKind: .user))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(viewModel.rows) { row in
              ContactRowView(entry: row, token: token)
                .onTapGesture {
                  selectedAIUser = row.aiUser
                  if let accountId = row.accountId {
                    route = ContactRouteRequest(kind: .userInfo(accountId: accountId, isCurrentUser: false))
                  } else {
                    viewModel.select(row)
                  }
                }
            }
          }
        }
      }
    }
  }
}
