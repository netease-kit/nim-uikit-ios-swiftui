// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamMemberListView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamMemberListViewModel
  @State private var pushedRoute: NETeamSwiftUIRoute?
  @State private var pushedMemberProfile: TeamMemberProfileRequest?
  private let token: NETeamThemeToken
  private let scope: NETeamSwiftUIMemberListScope
  private let style: NETeamSwiftUIStyleMode
  private let teamType: NETeamSwiftUITeamType
  private let config: NETeamSwiftUIConfig
  private let onBack: (() -> Void)?

  public init(teamId: String,
              scope: NETeamSwiftUIMemberListScope = .all,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              config: NETeamSwiftUIConfig? = nil,
              onBack: (() -> Void)? = nil) {
    let resolvedConfig = config ?? NETeamSwiftUIConfigCenter.shared.current()
    _viewModel = StateObject(wrappedValue: TeamMemberListViewModel(teamId: teamId, scope: scope, teamType: teamType))
    self.token = token ?? Self.resolvedToken(style: style, config: resolvedConfig, hasExplicitConfig: config != nil)
    self.scope = scope
    self.style = style
    self.teamType = teamType
    self.config = resolvedConfig
    self.onBack = onBack
  }

  public var body: some View {
    ZStack(alignment: .top) {
      memberListToken.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: navigationTitle,
          token: memberListToken,
          backAction: closeCurrentView,
          trailingWidth: 44,
          showsSeparator: false
        ) {
          Color.clear.frame(width: 44, height: 32)
        }

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      viewModel.refreshIfNeeded()
    }
    .navigationDestination(isPresented: pushedRouteIsPresentedBinding) {
      pushedRouteDestination
    }
    .navigationDestination(isPresented: pushedMemberProfileIsPresentedBinding) {
      pushedMemberProfileDestination
    }
    .onChange(of: viewModel.state.route?.id) { _ in
      syncRoutePresentation()
    }
    .neCommonConfirmationDialog(
      removeManagerDialogState,
      onAction: handleRemoveManagerDialogAction,
      onDismiss: {
        viewModel.dismissRemoveManager()
      }
    )
    .neCommonConfirmationDialog(
      removeMemberDialogState,
      onAction: handleRemoveMemberDialogAction,
      onDismiss: {
        viewModel.dismissRemoveMember()
      }
    )
    .neCommonBlockingLoadingOverlay(
      NETeamCommonPresentation.blockingLoading(
        id: "teamMemberInviteLoading",
        isPresented: viewModel.state.isInviting
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
      let members = viewModel.state.visibleMembers
      loadedContent(members: members)
    }
  }

  private func loadedContent(members: [NETeamSwiftUIMemberState]) -> some View {
    VStack(spacing: 10) {
      searchField

      if scope == .managers {
        ZStack(alignment: .top) {
          memberList(members: members)
          if members.isEmpty {
            emptyView
              .padding(.top, 80)
              .allowsHitTesting(false)
          }
        }
      } else if members.isEmpty {
        emptyView
      } else {
        memberList(members: members)
      }
    }
    .padding(.top, 8)
  }

  private func memberList(members: [NETeamSwiftUIMemberState]) -> some View {
    let lastMemberID = members.last?.id
    return List {
      if showsManagerAddRow {
        managerAddListRow
      }
      ForEach(members) { member in
        memberListRow(member, isLast: member.id == lastMemberID)
      }
    }
    .listStyle(.plain)
    .environment(\.defaultMinListRowHeight, 0)
    .scrollDismissesKeyboard(.immediately)
    .scrollContentBackground(.hidden)
    .background(memberListToken.pageBackground)
    .transaction { transaction in
      transaction.animation = nil
    }
  }

  private var showsManagerAddRow: Bool {
    scope == .managers && viewModel.state.canManageManagers
  }

  private var managerAddListRow: some View {
    Button {
      viewModel.openManagerSelection()
      syncRoutePresentation()
    } label: {
      HStack(spacing: 8) {
        Text(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.addManager, value: "Promote Member"))
          .font(.system(size: 16))
          .foregroundStyle(memberListToken.primaryText)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        NETeamCommonPresentation.chevron(token: memberListToken, isEnabled: true)
      }
      .padding(.leading, managerAddHorizontalInset)
      .padding(.trailing, managerAddHorizontalInset)
      .frame(maxWidth: .infinity, minHeight: managerAddRowHeight, alignment: .center)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    .listRowSeparator(.hidden)
    .listRowBackground(memberListToken.rowBackground)
    .accessibilityIdentifier(managerAddRowAccessibilityID(id: "addManager"))
  }

  private func managerAddRowAccessibilityID(id: String) -> String {
    id
  }

  private func memberListRow(_ member: NETeamSwiftUIMemberState,
                             isLast: Bool) -> some View {
    VStack(spacing: 0) {
      TeamMemberRowView(
        member: member,
        token: memberListToken,
        showsOwnerBadge: !viewModel.state.kind.isDiscuss,
        style: style,
        teamType: teamType,
        displayScope: NETeamMemberDisplayScope(listScope: scope),
        config: config,
        onTap: {
          openMemberProfile(member)
        }
      ) {
        managerTrailingAction(for: member)
      }

      if !isLast {
        memberListSeparator
      }
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    .listRowSeparator(.hidden)
    .listRowBackground(memberListToken.rowBackground)
  }

  @ViewBuilder
  private var memberListSeparator: some View {
    if style == .fun {
      NETeamCommonPresentation.separator(token: memberListToken, leadingInset: 20)
    }
  }

  @ViewBuilder
  private var pushedRouteDestination: some View {
    if let route = pushedRoute {
      TeamRouteDestinationView(
        route: route,
        token: token,
        style: style,
        config: config,
        onBack: closePushedRoute
      ) { completedRoute in
        if case .memberSelect = completedRoute {
          viewModel.managerSelectionDidComplete()
        } else {
          viewModel.dismissRoute(reload: true)
        }
      }
    } else {
      EmptyView()
    }
  }

  private var pushedRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { pushedRoute != nil },
      set: { isPresented in
        if !isPresented {
          closePushedRoute()
        }
      }
    )
  }

  @ViewBuilder
  private var pushedMemberProfileDestination: some View {
    if let request = pushedMemberProfile,
       let view = config.memberProfilePushViewProvider?(request, style) {
      view
        .environment(\.neCommonLocalBackAction, {
          pushedMemberProfile = nil
        })
    } else {
      EmptyView()
    }
  }

  private var pushedMemberProfileIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { pushedMemberProfile != nil },
      set: { isPresented in
        if !isPresented {
          pushedMemberProfile = nil
        }
      }
    )
  }

  private func syncRoutePresentation() {
    guard let route = viewModel.state.route else {
      pushedRoute = nil
      return
    }
    pushedRoute = route
  }

  private func closePushedRoute() {
    guard pushedRoute != nil || viewModel.state.route != nil else {
      return
    }
    pushedRoute = nil
    viewModel.dismissRoute()
  }

  private func closeCurrentView() {
    if let onBack {
      onBack()
    } else {
      dismiss()
    }
  }

  private func openMemberProfile(_ member: NETeamSwiftUIMemberState) {
    let request = TeamMemberProfileRequest(
      teamId: viewModel.teamId,
      accountId: member.accountId,
      isCurrentUser: member.isCurrentUser,
      source: scope == .managers ? .managerList : .memberList,
      teamType: teamType
    )
    if config.memberProfilePushViewProvider != nil {
      pushedMemberProfile = request
    } else {
      viewModel.openMemberProfile(member)
    }
  }

  private var navigationTitle: String {
    switch scope {
    case .managers:
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.groupManager, value: "Group Manager")
    case .all:
      return viewModel.state.kind.isDiscuss
        ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussMember, value: "Temp Group Member")
        : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.members, value: "Members")
    }
  }

  @ViewBuilder
  private func managerTrailingAction(for member: NETeamSwiftUIMemberState) -> some View {
    if scope == .managers, viewModel.state.canManageManagers {
      Button(role: .destructive) {
        viewModel.requestRemoveManager(member)
      } label: {
        removeActionLabel
      }
      .buttonStyle(.plain)
    } else if scope == .all, viewModel.state.canRemove(member) {
      Button(role: .destructive) {
        viewModel.requestRemoveMember(member)
      } label: {
        removeActionLabel
      }
      .buttonStyle(.plain)
    }
  }

  private var removeActionLabel: some View {
    Text(NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamMemberRemove, value: "Remove"))
      .font(.system(size: style == .fun ? 14 : 12))
      .foregroundStyle(style == .fun ? Color(hex: 0x505D75) : memberListToken.destructive)
      .lineLimit(1)
      .frame(width: removeActionWidth, height: 22)
      .background(
        Group {
          if style == .normal {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .stroke(memberListToken.destructive, lineWidth: 1)
          }
        }
      )
  }

  private var searchField: some View {
    NETeamCommonPresentation.searchField(
      text: Binding(
        get: { viewModel.state.searchText },
        set: { viewModel.updateSearchText($0) }
      ),
      placeholder: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.search, value: "Search"),
      token: memberListToken,
      height: 32
    )
    .padding(.horizontal, 20)
  }

  private var emptyView: some View {
    NETeamCommonPresentation.inlineEmptyView(
      title: viewModel.state.isSearching
        ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noResult, value: "No results")
        : emptyMessage,
      imageKind: .user,
      token: memberListToken
    )
  }

  private var memberListToken: NETeamThemeToken {
    var adjustedToken = token
    if style == .normal {
      adjustedToken.pageBackground = .white
    }
    if style == .fun {
      adjustedToken.searchBackground = .white
      adjustedToken.separator = Color(hex: 0xE4E9F2)
    }
    return adjustedToken
  }

  private var removeActionWidth: CGFloat {
    if style == .fun {
      return isEnglish ? 60 : 40
    }
    return isEnglish ? 60 : 40
  }

  private var managerAddHorizontalInset: CGFloat {
    style == .fun ? 16 : 36
  }

  private var managerAddRowHeight: CGFloat {
    style == .fun ? 56 : 46
  }

  private var isEnglish: Bool {
    let languageCode = Locale.current.languageCode?.lowercased() ?? ""
    return languageCode.hasPrefix("en")
  }

  private var emptyMessage: String {
    scope == .managers
      ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noManagerMember, value: "No managers")
      : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.noResult, value: "No results")
  }

  private var removeManagerDialogState: NECommonDialogState? {
    guard viewModel.state.pendingRemoveManager != nil else {
      return nil
    }
    return removeDialogState(
      id: "teamRemoveManager",
      message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.removeManagerTip, value: "Less permission after demotion.")
    )
  }

  private var removeMemberDialogState: NECommonDialogState? {
    guard viewModel.state.pendingRemoveMember != nil else {
      return nil
    }
    return removeDialogState(
      id: "teamRemoveMember",
      message: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.removeMemberTip, value: "This member will leave group after remove")
    )
  }

  private func removeDialogState(id: String, message: String) -> NECommonDialogState {
    NECommonDialogState(
      id: id,
      title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.removeManagerTitle, value: "Remove or not?"),
      message: message,
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NETeamUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "confirm",
          title: NETeamUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal
        ),
      ]
    )
  }

  private func handleRemoveManagerDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "confirm":
      viewModel.confirmRemoveManager()
    default:
      viewModel.dismissRemoveManager()
    }
  }

  private func handleRemoveMemberDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "confirm":
      viewModel.confirmRemoveMember()
    default:
      viewModel.dismissRemoveMember()
    }
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
