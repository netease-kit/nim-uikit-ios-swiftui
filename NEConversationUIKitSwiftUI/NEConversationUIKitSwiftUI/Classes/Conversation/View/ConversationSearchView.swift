// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct ConversationSearchView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: ConversationSearchViewModel
  private let token: ConversationThemeToken
  private let onSelect: (ConversationRouteContext) -> Void

  @MainActor
  public init(token: ConversationThemeToken,
              onSelect: @escaping (ConversationRouteContext) -> Void) {
    _viewModel = StateObject(wrappedValue: ConversationSearchViewModel())
    self.token = token
    self.onSelect = onSelect
  }

  public init(viewModel: ConversationSearchViewModel,
              token: ConversationThemeToken,
              onSelect: @escaping (ConversationRouteContext) -> Void) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onSelect = onSelect
  }

  public var body: some View {
    VStack(spacing: 0) {
      if token.styleMode == .normal {
        navigationBar
        searchField
      } else {
        funSearchHeader
      }
      content
    }
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { viewModel.onAppear() }
    .alert(
      viewModel.alert?.title ?? "",
      isPresented: Binding(
        get: { viewModel.alert != nil },
        set: { isPresented in
          if !isPresented {
            viewModel.dismissAlert()
          }
        }
      )
    ) {
      Button(NECommonUIKitSwiftUIBundle.localized("sure", fallback: "OK")) {
        viewModel.dismissAlert()
      }
    } message: {
      if let message = viewModel.alert?.message {
        Text(message)
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

  private var navigationBar: some View {
    NECommonNavigationBarView(
      title: NEConversationUIKitSwiftUIBundle.localized("search", value: "Search"),
      backAction: { dismiss() },
      backgroundColor: token.navigationBackground,
      separatorColor: token.rowSeparatorColor,
      showsSeparator: false
    )
    .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
  }

  private var searchField: some View {
    NECommonSearchFieldView(
      text: Binding(
        get: { viewModel.query },
        set: { viewModel.updateQuery($0) }
      ),
      placeholder: NEConversationUIKitSwiftUIBundle.localized("search_keyword", value: "Enter and search..."),
      height: 32,
      horizontalPadding: 12,
      onClear: { viewModel.clearQuery() }
    )
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 20)
    .neCommonTheme(NEConversationCommonPresentation.searchTheme(for: token))
  }

  private var funSearchHeader: some View {
    HStack(spacing: 8) {
      NECommonSearchFieldView(
        text: Binding(
          get: { viewModel.query },
          set: { viewModel.updateQuery($0) }
        ),
        placeholder: NEConversationUIKitSwiftUIBundle.localized("search", value: "Search"),
        height: 36,
        horizontalPadding: 12,
        onClear: { viewModel.clearQuery() }
      )
      .neCommonTheme(NEConversationCommonPresentation.searchTheme(for: token))

      Button {
        dismiss()
      } label: {
        Text(NEConversationUIKitSwiftUIBundle.localized("cancel", value: "Cancel"))
          .font(.system(size: 16))
          .foregroundColor(token.secondaryTextColor)
          .frame(width: 56, height: 44)
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
    }
    .padding(.leading, 8)
    .padding(.trailing, 5)
    .padding(.top, 12)
    .padding(.bottom, 12)
    .background(token.pageBackground)
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEConversationUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(
        state: NECommonErrorState(textKey: "network_error", fallbackText: message, severity: .warning, retryable: true),
        retry: { viewModel.load() }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
    case .loaded:
      if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         !viewModel.showsAllWhenQueryEmpty {
        Spacer()
      } else if viewModel.sections.isEmpty {
        NECommonEmptyStateView(
          state: NECommonEmptyState(
            titleKey: "user_not_exist",
            fallbackTitle: NEConversationUIKitSwiftUIBundle.localized("user_not_exist", value: "User not found"),
            imageKind: .user
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))
      } else {
        ScrollView {
          LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(viewModel.sections) { section in
              Section {
                ForEach(section.rows) { row in
                  ConversationSearchRowView(row: row, token: token)
                    .onTapGesture {
                      viewModel.select(row, completion: onSelect)
                    }
                    .overlay(alignment: .bottom) {
                      Rectangle()
                        .fill(token.rowSeparatorColor)
                        .frame(height: token.styleMode == .fun ? 0.5 : 1)
                        .padding(.leading, token.rowHorizontalPadding + token.avatarSize + 12)
                    }
                }
              } header: {
                ConversationSearchSectionHeaderView(title: section.title, token: token)
              }
            }
          }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(token.pageBackground)
      }
    }
  }
}

private struct ConversationSearchRowView: View {
  var row: ConversationSearchRowState
  var token: ConversationThemeToken

  var body: some View {
    HStack(spacing: 12) {
      NECommonAvatarView(
        imageURL: row.avatar.imageURL,
        initials: row.avatar.initials,
        size: token.avatarSize,
        cornerRadius: token.avatarCornerRadius,
        hashID: row.avatar.hashID
      )
      .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))

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
    .frame(height: token.searchRowHeight)
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

private struct ConversationSearchSectionHeaderView: View {
  var title: String
  var token: ConversationThemeToken

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
