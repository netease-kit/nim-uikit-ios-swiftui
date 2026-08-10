// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamManageView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamManageViewModel
  @State private var pushedRoute: NETeamSwiftUIRoute?
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onBack: (() -> Void)?

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              onBack: (() -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: TeamManageViewModel(teamId: teamId, teamType: teamType))
    self.style = style
    self.token = token ?? (style == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default)
    self.onBack = onBack
  }

  public var body: some View {
    ZStack(alignment: .top) {
      token.pageBackground
        .ignoresSafeArea()
      VStack(spacing: 0) {
        NETeamCommonPresentation.navigationBar(
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.manageTeam, value: "Manage Group"),
          token: token,
          backAction: {
            if let onBack {
              onBack()
            } else {
              dismiss()
            }
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
    .navigationDestination(isPresented: pushedRouteIsPresentedBinding) {
      pushedRouteDestination
    }
    .onChange(of: viewModel.state.route?.id) { _ in
      syncRoutePresentation()
    }
    .neCommonConfirmationDialog(
      permissionDialogState,
      onAction: handlePermissionDialogAction,
      onDismiss: {
        viewModel.dismissPermissionOptions()
      }
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
      ScrollView {
        VStack(spacing: 12) {
          ForEach(viewModel.state.sections) { section in
            sectionView(section)
          }
        }
        .padding(.vertical, 12)
      }
    }
  }

  private func sectionView(_ section: TeamManageSectionState) -> some View {
    VStack(spacing: 0) {
      ForEach(section.rows) { row in
        TeamManageRowView(row: row, token: token, style: style) { selected in
          viewModel.select(selected)
          syncRoutePresentation()
        } onToggle: { kind, isOn in
          viewModel.setToggle(kind, isOn: isOn)
        }
        if row.id != section.rows.last?.id {
          NETeamCommonPresentation.settingSeparator(token: token, leadingInset: rowDividerLeadingInset)
        }
      }
    }
    .background(token.rowBackground)
    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
    .padding(.horizontal, sectionHorizontalMargin)
  }

  @ViewBuilder
  private var pushedRouteDestination: some View {
    if let route = pushedRoute {
      TeamRouteDestinationView(
        route: route,
        token: token,
        style: style,
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

  private func syncRoutePresentation() {
    guard let route = viewModel.state.route else {
      pushedRoute = nil
      return
    }
    pushedRoute = route
  }

  private func closePushedRoute() {
    let closingRoute = pushedRoute ?? viewModel.state.route
    guard closingRoute != nil else {
      return
    }
    pushedRoute = nil
    viewModel.dismissRoute()
    if case .managerList? = closingRoute {
      viewModel.refresh()
    }
  }

  private var rowDividerLeadingInset: CGFloat {
    style == .fun ? 16 : 36
  }

  private var sectionHorizontalMargin: CGFloat {
    style == .fun ? 0 : 20
  }

  private var sectionCornerRadius: CGFloat {
    style == .fun ? 0 : 8
  }

  private var permissionDialogState: NECommonDialogState? {
    guard viewModel.state.pendingPermissionKind != nil else {
      return nil
    }

    return NECommonDialogState(
      id: "teamPermissionOptions",
      title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.remind, value: "Tip"),
      showsTitle: false,
      actions: [
        NECommonDialogAction(
          id: "all",
          title: viewModel.title(for: .all)
        ),
        NECommonDialogAction(
          id: "ownerAndManager",
          title: viewModel.title(for: .ownerAndManager)
        ),
        NECommonDialogAction(
          id: "cancel",
          title: NETeamUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
      ]
    )
  }

  private func handlePermissionDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "all":
      viewModel.setPermission(.all)
    case "ownerAndManager":
      viewModel.setPermission(.ownerAndManager)
    default:
      viewModel.dismissPermissionOptions()
    }
  }
}
