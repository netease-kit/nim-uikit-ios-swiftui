// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamSettingView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamSettingViewModel
  @State private var pushedRoute: NETeamSwiftUIRoute?
  @State private var pushedHostRoute: TeamSettingHostAction?
  @State private var pushedMemberProfile: TeamMemberProfileRequest?
  @State private var identifierCopyToast: NECommonToastState?
  private let token: NETeamThemeToken
  private let config: NETeamSwiftUIConfig
  private let teamType: NETeamSwiftUITeamType
  private let clipboardService: NECommonClipboardService
  private let onBack: (() -> Void)?

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              config: NETeamSwiftUIConfig? = nil,
              clipboardService: NECommonClipboardService = NECommonClipboardServiceCenter.shared.current(),
              onBack: (() -> Void)? = nil) {
    let resolvedConfig = config ?? NETeamSwiftUIConfigCenter.shared.current()
    _viewModel = StateObject(
      wrappedValue: TeamSettingViewModel(
        teamId: teamId,
        style: style,
        teamType: teamType,
        config: resolvedConfig
      )
    )
    self.config = resolvedConfig
    self.teamType = teamType
    self.clipboardService = clipboardService
    self.token = token ?? Self.resolvedToken(
      style: style,
      config: resolvedConfig,
      hasExplicitConfig: config != nil
    )
    self.onBack = onBack
    Self.trace(
      "init teamId=\(teamId) style=\(style) teamType=\(teamType) explicitConfig=\(config != nil) main=\(Thread.isMainThread)"
    )
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: navigationTitle,
          token: token,
          backAction: {
            if let onBack { onBack() } else { dismiss() }
          },
          showsSeparator: viewModel.style == .fun
        )

        content
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      Self.trace(
        "onAppear teamId=\(viewModel.teamId) phase=\(Self.phaseTraceName(viewModel.state.phase)) route=\(viewModel.state.route?.id ?? "nil") snapshot=\(viewModel.state.snapshot != nil) main=\(Thread.isMainThread)"
      )
      viewModel.refreshIfNeeded()
      Self.trace(
        "onAppear refreshIfNeededReturned teamId=\(viewModel.teamId) phase=\(Self.phaseTraceName(viewModel.state.phase)) snapshot=\(viewModel.state.snapshot != nil)"
      )
    }
    .onDisappear {
      Self.trace(
        "onDisappear teamId=\(viewModel.teamId) phase=\(Self.phaseTraceName(viewModel.state.phase)) route=\(viewModel.state.route?.id ?? "nil") snapshot=\(viewModel.state.snapshot != nil) main=\(Thread.isMainThread)"
      )
    }
    .navigationDestination(isPresented: pushedRouteIsPresentedBinding) {
      pushedRouteDestination
    }
    .navigationDestination(isPresented: pushedHostRouteIsPresentedBinding) {
      pushedHostRouteDestination
    }
    .navigationDestination(isPresented: pushedMemberProfileIsPresentedBinding) {
      pushedMemberProfileDestination
    }
    .onChange(of: viewModel.state.route?.id) { _ in
      Self.trace(
        "routeIdChanged teamId=\(viewModel.teamId) next=\(viewModel.state.route?.id ?? "nil") pushed=\(pushedRoute?.id ?? "nil")"
      )
      syncRoutePresentation()
    }
    .onChange(of: viewModel.state.didLeaveTeam) { didLeaveTeam in
      guard didLeaveTeam else {
        return
      }
      closeAfterTeamLifecycleExit()
    }
    .neCommonConfirmationDialog(
      destructiveDialogState,
      onAction: handleDestructiveDialogAction,
      onDismiss: {
        viewModel.dismissConfirmation()
      }
    )
    .neCommonConfirmationDialog(
      remoteTeamDismissedDialogState,
      onAction: { action in
        guard action.id == "confirm" else { return }
        viewModel.confirmRemoteTeamDismissal()
      },
      onDismiss: {}
    )
    .neCommonBlockingLoadingOverlay(
      NETeamCommonPresentation.blockingLoading(
        id: "teamSettingDestructiveLoading",
        isPresented: viewModel.state.isSubmittingDestructiveAction || viewModel.state.isInviting
      )
    )
    .neCommonToastOverlay(
      NETeamCommonPresentation.toast(viewModel.state.toast),
      placement: .top,
      topPadding: 10,
      onDismiss: { _ in viewModel.consumeToast() }
    )
    .neCommonToastOverlay(
      identifierCopyToast,
      placement: .top,
      topPadding: 10,
      onDismiss: { toast in
        if identifierCopyToast?.id == toast.id {
          identifierCopyToast = nil
        }
      }
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
      GeometryReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            if let snapshot = viewModel.state.snapshot {
              settingHeader(snapshot)
            }

            ForEach(viewModel.state.sections) { section in
              sectionView(section)
            }
          }
          .frame(width: proxy.size.width)
          .padding(.bottom, 12)
          .onAppear {
            Self.trace(
              "loadedContent appear teamId=\(viewModel.teamId) sections=\(viewModel.state.sections.count) preview=\(viewModel.state.snapshot?.memberPreview.count ?? -1) memberCount=\(viewModel.state.snapshot?.memberCount ?? -1) main=\(Thread.isMainThread)"
            )
          }
        }
      }
    }
  }

  private func settingHeader(_ snapshot: NETeamSwiftUISettingSnapshot) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
        .frame(height: viewModel.style == .fun ? 0 : 12)

      settingHeaderCard(snapshot)
    }
    .frame(height: settingHeaderOuterHeight, alignment: .bottom)
  }

  private var settingHeaderOuterHeight: CGFloat {
    viewModel.style == .fun ? 188 : 172
  }

  private func settingHeaderCard(_ snapshot: NETeamSwiftUISettingSnapshot) -> some View {
    VStack(spacing: 0) {
      TeamSettingHeaderView(
        title: snapshot.name,
        subtitle: headerSubtitle(for: snapshot),
        avatarURL: snapshot.avatarURL,
        hashID: snapshot.teamId,
        token: token,
        style: viewModel.style,
        onLongPressSubtitle: {
          copyIdentifier(snapshot.teamId)
        },
        onOpenInfo: {
          viewModel.select(
            TeamSettingRowState(
              id: "teamInfo",
              title: title(for: snapshot),
              value: snapshot.name,
              kind: .navigation(.teamInfo(teamId: snapshot.teamId, teamType: teamType))
            )
          )
          syncRoutePresentation()
        }
      )

      NETeamCommonPresentation.settingSeparator(token: token, leadingInset: 16)

      TeamSettingMemberPreviewView(
        snapshot: snapshot,
        token: token,
        style: viewModel.style,
        onOpenMembers: {
          viewModel.select(
            TeamSettingRowState(
              id: "members",
              title: snapshot.kind.isDiscuss
                ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussMember, value: "Temp Group Member")
                : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.members, value: "Members"),
              value: "\(snapshot.memberCount)",
              kind: .navigation(.memberList(teamId: snapshot.teamId, teamType: teamType))
            )
          )
          syncRoutePresentation()
        },
        onInvite: {
          viewModel.openMemberInviteSelection()
        },
        onMemberTap: { member in
          openMemberProfile(member)
        }
      )
    }
    .frame(height: settingHeaderCardHeight)
    .background(token.rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: headerCornerRadius, style: .continuous))
    .padding(.horizontal, headerHorizontalMargin)
    .onAppear {
      Self.trace(
        "headerCard appear teamId=\(snapshot.teamId) preview=\(snapshot.memberPreview.count) memberCount=\(snapshot.memberCount) main=\(Thread.isMainThread)"
      )
    }
  }

  private func sectionView(_ section: TeamSettingSectionState) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
        .frame(height: 12)

      if section.id == "actions" {
        destructiveSectionView(section)
      } else {
        regularSectionView(section)
      }
    }
  }

  private func regularSectionView(_ section: TeamSettingSectionState) -> some View {
    VStack(spacing: 0) {
      ForEach(section.rows) { row in
        TeamSettingRowView(
          row: row,
          token: token,
          style: viewModel.style,
          customContent: settingRowContent(for: row)
        ) { selected in
          selectRow(selected)
        } onToggle: { kind, isOn in
          viewModel.setToggle(kind, isOn: isOn)
        }
        if row.id != section.rows.last?.id {
          NETeamCommonPresentation.settingSeparator(token: token, leadingInset: settingRowDividerLeadingInset)
        }
      }
    }
    .background(token.rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
    .padding(.horizontal, sectionHorizontalMargin)
  }

  private func destructiveSectionView(_ section: TeamSettingSectionState) -> some View {
    VStack(spacing: 0) {
      ForEach(section.rows) { row in
        TeamSettingRowView(
          row: row,
          token: token,
          style: viewModel.style,
          customContent: settingRowContent(for: row)
        ) { selected in
          selectRow(selected)
        } onToggle: { kind, isOn in
          viewModel.setToggle(kind, isOn: isOn)
        }
        .frame(height: token.destructiveButtonHeight)
        .clipShape(RoundedRectangle(cornerRadius: token.sectionCornerRadius, style: .continuous))
      }
    }
    .background(token.rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
    .padding(.horizontal, destructiveSectionHorizontalMargin)
  }

  @ViewBuilder
  private var pushedRouteDestination: some View {
    if let route = pushedRoute {
      TeamRouteDestinationView(
        route: route,
        token: token,
        style: viewModel.style,
        config: config,
        onBack: closePushedRoute
      ) { _ in
        viewModel.load()
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
  private var pushedHostRouteDestination: some View {
    if let route = pushedHostRoute,
       let snapshot = viewModel.state.snapshot {
      let context = settingContext(for: snapshot)
      switch route {
      case let .pinMessages(conversationId):
        if let view = pinMessagesDestination(conversationId: conversationId, context: context) {
          view
        } else {
          EmptyView()
        }
      case let .historySearch(conversationId):
        if let view = historySearchDestination(conversationId: conversationId, context: context) {
          view
        } else {
          EmptyView()
        }
      }
    } else {
      EmptyView()
    }
  }

  private func pinMessagesDestination(conversationId: String,
                                      context: NETeamSettingContext) -> AnyView? {
    if let provider = config.pinMessagesPushViewProvider,
       let view = provider(conversationId, context, closeHostRoute) {
      return view
    }
    return config.pinMessagesViewProvider?(conversationId, context)
  }

  private func historySearchDestination(conversationId: String,
                                        context: NETeamSettingContext) -> AnyView? {
    if let provider = config.historySearchPushViewProvider,
       let view = provider(conversationId, context, closeHostRoute) {
      return view
    }
    return config.historySearchViewProvider?(conversationId, context)
  }

  private func canPushHostAction(_ action: TeamSettingHostAction) -> Bool {
    switch action {
    case .pinMessages:
      return config.pinMessagesPushViewProvider != nil || config.pinMessagesViewProvider != nil
    case .historySearch:
      return config.historySearchPushViewProvider != nil || config.historySearchViewProvider != nil
    }
  }

  private var pushedHostRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { pushedHostRoute != nil },
      set: { isPresented in
        if !isPresented {
          pushedHostRoute = nil
        }
      }
    )
  }

  @ViewBuilder
  private var pushedMemberProfileDestination: some View {
    if let request = pushedMemberProfile,
       let view = config.memberProfilePushViewProvider?(request, viewModel.style) {
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

  private func selectRow(_ row: TeamSettingRowState) {
    if case let .hostAction(action) = row.kind,
       canPushHostAction(action) {
      pushedHostRoute = action
      return
    }
    viewModel.select(row)
    syncRoutePresentation()
  }

  private func openMemberProfile(_ member: NETeamSwiftUIMemberState) {
    let request = TeamMemberProfileRequest(
      teamId: viewModel.teamId,
      accountId: member.accountId,
      isCurrentUser: member.isCurrentUser,
      source: .settingPreview,
      teamType: teamType
    )
    if config.memberProfilePushViewProvider != nil {
      pushedMemberProfile = request
    } else {
      viewModel.openMemberProfile(member)
    }
  }

  private func closeHostRoute() {
    pushedHostRoute = nil
  }

  private func closeAfterTeamLifecycleExit() {
    if let onBack {
      onBack()
    } else {
      dismiss()
    }
  }

  private var navigationTitle: String {
    guard let snapshot = viewModel.state.snapshot else {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.setting, value: "Setting")
    }
    return config.titleProvider?(settingContext(for: snapshot))
      ?? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.setting, value: "Setting")
  }

  private func headerSubtitle(for snapshot: NETeamSwiftUISettingSnapshot) -> String {
    config.headerSubtitleProvider?(settingContext(for: snapshot))
      ?? defaultHeaderSubtitle(for: snapshot)
  }

  private func settingContext(for snapshot: NETeamSwiftUISettingSnapshot) -> NETeamSettingContext {
    NETeamSettingContext(snapshot: snapshot, style: viewModel.style, teamType: teamType)
  }

  private var sectionHorizontalMargin: CGFloat {
    viewModel.style == .fun ? 0 : 20
  }

  private var sectionCornerRadius: CGFloat {
    viewModel.style == .fun ? 0 : 8
  }

  private var destructiveSectionHorizontalMargin: CGFloat {
    viewModel.style == .fun ? 0 : 20
  }

  private var settingRowDividerLeadingInset: CGFloat {
    viewModel.style == .fun ? 16 : 36
  }

  private var settingHeaderCardHeight: CGFloat {
    viewModel.style == .fun ? 188 : 160
  }

  private var headerHorizontalMargin: CGFloat {
    viewModel.style == .fun ? 0 : 20
  }

  private var headerCornerRadius: CGFloat {
    viewModel.style == .fun ? 0 : 8
  }

  private func defaultHeaderSubtitle(for snapshot: NETeamSwiftUISettingSnapshot) -> String {
    let title = NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.teamId, value: "team id")
    return "\(title): \(snapshot.teamId)"
  }

  private func copyIdentifier(_ identifier: String) {
    Task { @MainActor in
      guard case .success = await clipboardService.copyText(identifier) else {
        return
      }
      identifierCopyToast = NECommonToastState(
        textKey: "copy_success",
        fallbackText: NECommonUIKitSwiftUIBundle.localized("copy_success", fallback: "Copied!"),
        level: .success
      )
    }
  }

  private func title(for snapshot: NETeamSwiftUISettingSnapshot) -> String {
    snapshot.kind.isDiscuss
      ? NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussInfo, value: "Temp Group Info")
      : NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.groupInfo, value: "Group Info")
  }

  private func settingRowContent(for row: TeamSettingRowState) -> AnyView? {
    guard let snapshot = viewModel.state.snapshot else {
      return nil
    }

    return config.settingRowContentProvider?(
      NETeamSettingRowContext(
        row: row,
        settingContext: settingContext(for: snapshot)
      )
    )
  }

  private var confirmationTitle: String {
    guard let snapshot = viewModel.state.snapshot else {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.quitTeamChat, value: "Whether to leave Group")
    }
    if snapshot.currentRole == .owner && !snapshot.kind.isDiscuss {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.dissoluteTeamChat, value: "Whether to disband Group")
    }
    if snapshot.kind.isDiscuss {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.quitDiscussChat, value: "Whether to leave Temp Group")
    }
    return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.quitTeamChat, value: "Whether to leave Group")
  }

  private var destructiveDialogState: NECommonDialogState? {
    guard viewModel.state.pendingDestructiveAction != nil else {
      return nil
    }

    return NECommonDialogState(
      id: "teamSettingDestructiveAction",
      title: confirmationTitle,
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NETeamUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel,
          isEnabled: !viewModel.state.isSubmittingDestructiveAction
        ),
        NECommonDialogAction(
          id: "confirm",
          title: NETeamUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal,
          isEnabled: !viewModel.state.isSubmittingDestructiveAction
        ),
      ]
    )
  }

  private var remoteTeamDismissedDialogState: NECommonDialogState? {
    guard viewModel.state.isRemoteTeamDismissedAlertPresented else {
      return nil
    }
    return NECommonDialogState(
      id: "teamSettingRemoteTeamDismissed",
      title: NETeamUIKitSwiftUIBundle.localized(
        NETeamLocalizableKey.teamHasBeenRemoved,
        value: "This group is disbanded"
      ),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "confirm",
          title: NETeamUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal
        ),
      ]
    )
  }

  private func handleDestructiveDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "confirm":
      viewModel.confirmDestructiveAction()
    default:
      viewModel.dismissConfirmation()
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

  private static func trace(_ message: @autoclosure () -> String) {
    debugPrint("[NETeamUIKitSwiftUI] groupSettingTrace TeamSettingView \(message())")
  }

  private static func phaseTraceName(_ phase: NETeamAsyncPhase) -> String {
    switch phase {
    case .idle:
      return "idle"
    case .loading:
      return "loading"
    case .loaded:
      return "loaded"
    case .failed:
      return "failed"
    }
  }
}
