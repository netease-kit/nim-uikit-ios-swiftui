// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct ReadReceiptView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  @StateObject private var viewModel: ReadReceiptViewModel
  @State private var selectedTab: ReadReceiptSectionKind = .read
  private let token: ChatThemeToken

  @MainActor
  public init(viewModel: ReadReceiptViewModel,
              token: ChatThemeToken = .normal) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: NEChatUIKitSwiftUIBundle.localized("message_read", value: "Read Status"),
        token: token,
        backAction: {
          if let chatRouteBackAction {
            chatRouteBackAction()
          } else {
            dismiss()
          }
        }
      )

      receiptTabs

      if currentMembers.isEmpty {
        receiptEmptyView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(currentMembers) { member in
              ReadReceiptMemberRow(member: member, token: token)
              Divider()
                .padding(.leading, 56)
            }
          }
        }
        .background(token.panelItemBackground)
      }
    }
    .background(token.panelItemBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty where viewModel.summary.isEmpty:
        receiptEmptyView
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
    .onAppear { viewModel.load() }
    .onChange(of: viewModel.sections) { _ in
      if section(for: selectedTab) == nil {
        selectedTab = viewModel.sections.first?.id ?? .read
      }
    }
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var receiptEmptyView: some View {
    NEChatCommonPresentation.emptyView(
      token: token,
      titleKey: "message_all_unread",
      fallbackTitle: NEChatUIKitSwiftUIBundle.localized("message_all_unread", value: "All members unread")
    )
  }

  private var receiptTabs: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        tabButton(kind: .read)
        tabButton(kind: .unread)
      }
      .frame(height: 48)

      GeometryReader { proxy in
        Rectangle()
          .fill(token.accentColor)
          .frame(width: max(0, proxy.size.width / 2), height: 1)
          .offset(x: selectedTab == .read ? 0 : proxy.size.width / 2)
          .animation(.easeInOut(duration: 0.2), value: selectedTab)
      }
      .frame(height: 1)
    }
    .background(token.panelItemBackground)
  }

  private func tabButton(kind: ReadReceiptSectionKind) -> some View {
    Button {
      selectedTab = kind
    } label: {
      Text(tabTitle(for: kind))
        .font(.system(size: 14))
        .foregroundColor(selectedTab == kind ? token.accentColor : token.incomingTextColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func tabTitle(for kind: ReadReceiptSectionKind) -> String {
    let fallback: String
    switch kind {
    case .read:
      fallback = NEChatUIKitSwiftUIBundle.localized("chat_read", value: "Read")
    case .unread:
      fallback = NEChatUIKitSwiftUIBundle.localized("chat_unread", value: "Unread")
    }
    let count = section(for: kind)?.members.count ?? 0
    return "\(fallback) (\(count))"
  }

  private var currentMembers: [ReadReceiptMemberState] {
    section(for: selectedTab)?.members ?? []
  }

  private func section(for kind: ReadReceiptSectionKind) -> ReadReceiptSectionState? {
    viewModel.sections.first { $0.id == kind }
  }
}

private struct ReadReceiptMemberRow: View {
  var member: ReadReceiptMemberState
  var token: ChatThemeToken

  var body: some View {
    HStack(spacing: 10) {
      ReadReceiptAvatar(member: member, token: token)

      VStack(alignment: .leading, spacing: 2) {
        Text(member.displayName)
          .font(.system(size: 15))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
        if let subtitle = member.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: token.styleMode == .fun ? 64 : 62, alignment: .center)
    .background(token.panelItemBackground)
  }
}

private struct ReadReceiptAvatar: View {
  var member: ReadReceiptMemberState
  var token: ChatThemeToken

  var body: some View {
    NEChatCommonPresentation.avatarView(
      imageURL: member.avatarURL,
      initials: ChatAvatarDisplayResolver.initials(
        displayName: member.avatarName,
        accountId: member.accountId
      ),
      token: token,
      size: 32,
      cornerRadius: 16,
      hashID: member.accountId
    )
  }
}
