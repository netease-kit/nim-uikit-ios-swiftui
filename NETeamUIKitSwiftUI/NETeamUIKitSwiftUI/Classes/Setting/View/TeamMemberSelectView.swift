// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamMemberSelectView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamMemberSelectViewModel
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let teamType: NETeamSwiftUITeamType
  private let config: NETeamSwiftUIConfig
  private let onSubmit: () -> Void

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              config: NETeamSwiftUIConfig? = nil,
              onSubmit: @escaping () -> Void = {}) {
    let resolvedConfig = config ?? NETeamSwiftUIConfigCenter.shared.current()
    _viewModel = StateObject(wrappedValue: TeamMemberSelectViewModel(teamId: teamId, teamType: teamType))
    self.token = token ?? Self.resolvedToken(style: style, config: resolvedConfig, hasExplicitConfig: config != nil)
    self.style = style
    self.teamType = teamType
    self.config = resolvedConfig
    self.onSubmit = onSubmit
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberSelect, value: "Select Member"),
          token: token,
          backAction: {
            dismiss()
          },
          trailingWidth: 90,
          showsSeparator: false
        ) {
          Button {
            guard !viewModel.state.isSubmitting else {
              return
            }
            viewModel.submit()
          } label: {
            Text(confirmTitle)
              .font(.system(size: 16))
              .foregroundColor(token.accent)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          }
          .buttonStyle(.plain)
          .disabled(viewModel.state.isSubmitting)
          .opacity(viewModel.state.isSubmitting ? 0.45 : 1)
          .accessibilityIdentifier("confirm")
        }

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      viewModel.refreshIfNeeded()
    }
    .onChange(of: viewModel.state.didSubmit) { didSubmit in
      guard didSubmit else {
        return
      }
      onSubmit()
      dismiss()
    }
    .neCommonBlockingLoadingOverlay(
      NETeamCommonPresentation.blockingLoading(
        id: "teamMemberSelectSubmitting",
        isPresented: viewModel.state.isSubmitting
      )
    )
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
      VStack(spacing: 10) {
        searchField
        if viewModel.state.visibleMembers.isEmpty {
          emptyView
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(viewModel.state.visibleMembers) { member in
                Button {
                  viewModel.toggle(member)
                } label: {
                  TeamMemberRowView(
                    member: member,
                    token: token,
                    showsOwnerBadge: false,
                    style: style,
                    teamType: teamType,
                    displayScope: .selection,
                    config: config
                  ) {
                    NETeamCommonPresentation.selectionIndicator(
                      isSelected: viewModel.state.selectedAccountIds.contains(member.accountId),
                      token: token
                    )
                  }
                }
                .buttonStyle(.plain)
                if member.id != viewModel.state.visibleMembers.last?.id {
                  NETeamCommonPresentation.separator(token: token, leadingInset: 68)
                }
              }
            }
            .padding(.bottom, 12)
          }
          .scrollDismissesKeyboard(.immediately)
        }
      }
      .padding(.top, 10)
    }
  }

  private var searchField: some View {
    NETeamCommonPresentation.searchField(
      text: Binding(
        get: { viewModel.state.searchText },
        set: { viewModel.updateSearchText($0) }
      ),
      placeholder: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.searchMember, value: "Search Member"),
      token: token
    )
    .padding(.horizontal, 16)
  }

  private var emptyView: some View {
    NETeamCommonPresentation.inlineEmptyView(
      title: viewModel.state.isSearching
        ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noResult, value: "No results")
        : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.memberSelectNoMember, value: "No member"),
      imageKind: .user,
      token: token
    )
  }

  private var confirmTitle: String {
    let count = viewModel.state.selectedAccountIds.count
    guard count > 0 else {
      return NETeamUIKitSwiftUIBundle.localized("sure", value: "OK")
    }
    return "\(NETeamUIKitSwiftUIBundle.localized("sure", value: "OK"))(\(count))"
  }

  private static func resolvedToken(style: NETeamSwiftUIStyleMode,
                                    config: NETeamSwiftUIConfig,
                                    hasExplicitConfig: Bool) -> NETeamThemeToken {
    if hasExplicitConfig || config.styleMode != .normal || config.styleMode == style {
      return config.themeToken
    }
    return style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default
  }
}
