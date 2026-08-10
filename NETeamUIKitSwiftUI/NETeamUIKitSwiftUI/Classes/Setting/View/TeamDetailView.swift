// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamDetailViewModel
  @State private var pendingTeamChatConversationId: String?
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onOpenTeamChat: ((String) -> Void)?

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              onOpenTeamChat: ((String) -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: TeamDetailViewModel(teamId: teamId, teamType: teamType))
    self.style = style
    self.token = token ?? (style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default)
    self.onOpenTeamChat = onOpenTeamChat
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          // UIKit's search-to-detail controller deliberately leaves this
          // navigation title empty and uses the team header as its title area.
          title: "",
          token: token,
          backAction: {
            dismiss()
          },
          showsSeparator: false
        )

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      viewModel.refreshIfNeeded()
    }
    .onDisappear(perform: openPendingTeamChatIfNeeded)
    .neCommonToastOverlay(
      NETeamCommonPresentation.toast(viewModel.state.toast),
      placement: .top,
      topPadding: 10,
      onDismiss: { _ in viewModel.consumeToast() }
    )
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle, .loading:
      NETeamCommonPresentation.loadingView()
    case .failed(let message):
      NETeamCommonPresentation.errorView(message) {
        viewModel.load()
      }
    case .loaded:
      if let snapshot = viewModel.state.snapshot {
        detail(snapshot)
      }
    }
  }

  private func detail(_ snapshot: NETeamSwiftUIDetailSnapshot) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        HStack(spacing: snapshot.kind.isDiscuss ? 16 : 20) {
          NETeamCommonPresentation.avatarView(
            imageURL: NECommonAvatarDisplayResolver.url(from: snapshot.avatarURL),
            initials: initials(for: snapshot.name),
            token: token,
            size: token.detailAvatarSize,
            cornerRadius: token.detailAvatarCornerRadius,
            hashID: snapshot.teamId
          )

          VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.name.isEmpty ? snapshot.teamId : snapshot.name)
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(token.primaryText)
              .lineLimit(1)
              .truncationMode(.tail)
            Text("\(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamId, value: "team id")): \(snapshot.teamId)")
              .font(.system(size: 16))
              .foregroundStyle(token.secondaryText)
              .lineLimit(1)
              .truncationMode(.middle)
            if !snapshot.kind.isDiscuss {
              Text("\(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamOwner, value: "team owner")): \(snapshot.ownerDisplayName ?? snapshot.ownerAccountId ?? "")")
                .font(.system(size: 16))
                .foregroundStyle(token.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 113, alignment: .leading)
        .padding(.horizontal, 20)
        .background(token.rowBackground)

        detailRow(
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamIntr, value: "Description"),
          value: snapshot.intro ?? ""
        )
        .background(token.rowBackground)

        NETeamCommonPresentation.actionButton(
          title: primaryTitle(for: snapshot),
          token: token,
          style: .secondary,
          isEnabled: true,
          isLoading: viewModel.state.isApplying,
          minHeight: 66
        ) {
          viewModel.primaryAction(onOpenTeamChat: prepareTeamChatHandoff)
        }
      }
    }
  }

  private func detailRow(title: String, value: String) -> some View {
    HStack(alignment: .center, spacing: 0) {
      Text(title)
        .font(.system(size: 16))
        .foregroundStyle(token.primaryText)
        .frame(width: 90, alignment: .leading)
      Text(value)
        .font(.system(size: 12))
        .foregroundStyle(token.secondaryText)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(NEUIKitSwiftUIStyle.ColorToken.greyLine)
        .frame(height: 1)
        .padding(.horizontal, 20)
    }
  }

  private func primaryTitle(for snapshot: NETeamSwiftUIDetailSnapshot) -> String {
    snapshot.isJoined
      ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.chat, value: "Go Chat")
      : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.joinTeam, value: "Join Team")
  }

  private func prepareTeamChatHandoff(_ conversationId: String) {
    guard pendingTeamChatConversationId == nil else {
      return
    }
    pendingTeamChatConversationId = conversationId
    // Match UIKit's immediate navigation: call onOpenTeamChat directly from the
    // join callback so concurrent joins don't rely on onDisappear timing.
    // The flag is consumed here so the onDisappear fallback becomes a no-op.
    if let onOpenTeamChat {
      onOpenTeamChat(conversationId)
      pendingTeamChatConversationId = nil
    }
    dismiss()
  }

  private func openPendingTeamChatIfNeeded() {
    guard let conversationId = pendingTeamChatConversationId else {
      return
    }
    pendingTeamChatConversationId = nil
    if let onOpenTeamChat {
      onOpenTeamChat(conversationId)
    } else {
      NETeamUIKitSwiftUIClient.shared.openTeamChat(conversationId: conversationId)
    }
  }

  private func initials(for title: String) -> String {
    NECommonAvatarDisplayResolver.initials(
      displayName: title,
      fallbackID: viewModel.state.snapshot?.teamId,
      defaultText: "#"
    )
  }
}
