// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import SwiftUI

public struct ContactFindFriendView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var accountId = ""
  @State private var phase: ContactListPhase = .idle
  @State private var foundUser: NEUserWithFriend?
  @State private var route: ContactRouteRequest?
  @State private var toast: NECommonToast?
  private let token: ContactThemeToken
  private let onOpenChat: ((String, String) -> Void)?

  public init(token: ContactThemeToken,
              onOpenChat: ((String, String) -> Void)? = nil) {
    self.token = token
    self.onOpenChat = onOpenChat
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts"),
        token: token,
        onBack: { dismiss() }
      )

      NECommonSearchFieldView(
        text: $accountId,
        placeholder: NEContactUIKitSwiftUIBundle.localized("input_userId", value: "Enter Account"),
        height: 32,
        horizontalPadding: 12,
        onSubmit: search,
        onClear: {
          foundUser = nil
          phase = .idle
        }
      )
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .neCommonTheme(NEContactCommonPresentation.searchTheme(for: token))

      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(token.pageBackground)
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(isPresented: routeIsPresentedBinding) {
      if case .userInfo(let accountId, let isCurrentUser) = route?.kind {
        if isCurrentUser, let provider = ContactSwiftUIConfigCenter.shared.config.currentUserInfoViewProvider {
          provider(token)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
        } else {
          ContactUserInfoView(viewModel: ContactUserInfoViewModel(accountId: accountId, isCurrentUser: isCurrentUser, user: foundUser), token: token, onOpenChat: onOpenChat)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
        }
      }
    }
    .neCommonTransientOverlay(toast, placement: .top, topPadding: 52, onDismiss: { value in
      if toast?.id == value.id {
        toast = nil
      }
    }) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
  private var content: some View {
    switch phase {
    case .loading:
      NECommonInlineLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .padding(.top, 32)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .loaded:
      if let foundUser {
        let account = foundUser.user?.accountId ?? foundUser.friend?.accountId ?? accountId
        ContactRowView(
          entry: ContactEntryState(
            id: "found.\(account)",
            kind: .friend,
            accountId: account,
            title: ContactSectionBuilder.displayName(for: foundUser),
            subtitle: account,
            avatarURL: foundUser.user?.avatar,
            avatarName: foundUser.showName(false),
            user: foundUser
          ),
          token: token
        )
        .padding(.top, 16)
        .onTapGesture {
          route = ContactRouteRequest(kind: .userInfo(accountId: account, isCurrentUser: IMKitClient.instance.isMe(account)))
        }
      } else {
        NECommonEmptyStateView(state: NECommonEmptyState(titleKey: "contact_user_not_exist", fallbackTitle: NEContactUIKitSwiftUIBundle.localized("user_not_exist", value: "User not found"), imageKind: .user))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
      }
    default:
      Spacer()
    }
  }

  private func search() {
    let text = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return
    }
    if text.trimmingCharacters(in: .whitespaces).isEmpty {
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("space_not_support", value: "All Spaces are not supported"))
      return
    }
    guard NEContactNetworkGuard.allowsNetworkOperation else {
      toast = NECommonToast(message: NEContactErrorMessageMapper.networkMessage())
      return
    }
    if IMKitClient.instance.isMe(text) {
      route = ContactRouteRequest(kind: .userInfo(accountId: text, isCurrentUser: true))
      return
    }
    phase = .loading
    ContactRepo.shared.getUserWithFriend(accountIds: [text]) { users, error in
      Task { @MainActor in
        if let error {
          let message = NEContactErrorMessageMapper.message(for: error)
          phase = .failed(message)
          toast = NECommonToast(message: message)
        } else {
          if let user = users?.first,
             user.user != nil || user.friend != nil {
            foundUser = user
            let account = user.user?.accountId ?? user.friend?.accountId ?? text
            route = ContactRouteRequest(kind: .userInfo(accountId: account, isCurrentUser: IMKitClient.instance.isMe(account)))
            phase = .idle
          } else {
            foundUser = nil
            phase = .loaded
          }
        }
      }
    }
  }
}
