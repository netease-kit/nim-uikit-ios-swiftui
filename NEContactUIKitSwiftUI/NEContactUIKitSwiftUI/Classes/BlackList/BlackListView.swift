// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import NEChatKit
import NEChatUIKitSwiftUI
import SwiftUI

public struct BlackListView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: BlackListViewModel
  @State private var isSelectionPresented = false
  private let token: ContactThemeToken

  public init(viewModel: BlackListViewModel,
              token: ContactThemeToken) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
  }

  public var body: some View {
    VStack(spacing: 0) {
      ContactSubpageHeaderView(
        title: NEContactUIKitSwiftUIBundle.localized("blacklist", value: "Blocklist"),
        token: token,
        onBack: { dismiss() }
      ) {
        addButton
      }
      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .navigationDestination(isPresented: $isSelectionPresented) {
      ContactSelectionView(
        viewModel: ContactSelectionViewModel(context: selectionContext),
        token: token
      ) { result in
        viewModel.addSelectedContacts(result)
      }
    }
    .onChange(of: viewModel.didFinishAddingSelection) { didFinish in
      guard didFinish else {
        return
      }
      isSelectionPresented = false
      viewModel.consumeDidFinishAddingSelection()
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

  private var addButton: some View {
    Button {
      isSelectionPresented = true
    } label: {
      ContactImageResource(name: "add_black", size: 18)
        .frame(width: 44, height: 44, alignment: .trailing)
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .accessibilityIdentifier("id.threePoint")
    .accessibilityLabel(NEContactUIKitSwiftUIBundle.localized("add_blackList", value: "Block"))
  }

  private var selectionContext: ContactSelectionContext {
    let filterAccountIds = Set(viewModel.rows.compactMap(\.accountId))
    return ContactSelectionContext(
      title: NEContactUIKitSwiftUIBundle.localized("select", value: "Select"),
      filterAccountIds: filterAccountIds,
      limit: 10,
      allowsAIUsers: false
    )
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
      blackListContent
    }
  }

  private var blackListContent: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        blackTipHeader

        ForEach(viewModel.rows) { row in
          BlackListRowView(entry: row, token: token) {
            viewModel.remove(row)
          }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button {
                viewModel.remove(row)
              } label: {
                Text(NEContactUIKitSwiftUIBundle.localized("remove_black", value: "Release"))
              }
              .tint(token.destructiveColor)
            }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(token.pageBackground)
    .scrollDismissesKeyboard(.immediately)
  }

  private var blackTipHeader: some View {
    Text(NEContactUIKitSwiftUIBundle.localized("black_tip", value: "You won't receive message from this memberlist"))
      .font(.system(size: 14))
      .foregroundColor(token.sectionTitleColor)
      .lineLimit(1)
      .truncationMode(.tail)
      .padding(.leading, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 40)
      .background(token.pageBackground)
      .accessibilityIdentifier("id.tips")
  }
}

private struct BlackListRowView: View {
  var entry: ContactEntryState
  var token: ContactThemeToken
  var onRemove: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      avatar

      Text(entry.title)
        .font(.system(size: token.styleMode == .fun ? token.titleFontSize : 16))
        .foregroundColor(token.primaryTextColor)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      Button(action: onRemove) {
        Text(NEContactUIKitSwiftUIBundle.localized("remove_black", value: "Release"))
          .font(.system(size: 14))
          .foregroundColor(buttonForeground)
          .lineLimit(1)
          .frame(width: 60, height: 32)
          .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .stroke(buttonBorder, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("id.relieve")
    }
    .frame(height: token.styleMode == .fun ? 64 : 62)
    .padding(.leading, 20)
    .padding(.trailing, 20)
    .background(token.rowBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(token.rowSeparatorColor)
        .frame(height: 1)
        .padding(.leading, 20)
        .padding(.trailing, 20)
    }
    .contentShape(Rectangle())
    .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
  }

  private var avatar: some View {
    NECommonAvatarView(
      imageURL: NECommonAvatarDisplayResolver.url(from: entry.avatarURL),
      initials: initials,
      size: avatarSize,
      cornerRadius: token.avatarCornerRadius,
      hashID: entry.accountId
    )
  }

  private var initials: String {
    NECommonAvatarDisplayResolver.initials(
      displayName: entry.avatarName,
      fallbackID: entry.accountId,
      defaultText: "#"
    )
  }

  private var avatarSize: CGFloat {
    token.styleMode == .fun ? 40 : 36
  }

  private var buttonForeground: Color {
    token.styleMode == .fun ? token.primaryTextColor : token.accentColor
  }

  private var buttonBorder: Color {
    token.styleMode == .fun ? Color(hex: 0xD9D9D9) : token.accentColor
  }
}
