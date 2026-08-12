// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamInfoView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamInfoViewModel
  @State private var pushedRoute: NETeamSwiftUIRoute?
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onBack: (() -> Void)?

  public init(teamId: String,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              onBack: (() -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: TeamInfoViewModel(teamId: teamId, style: style, teamType: teamType))
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
          title: title,
          token: token,
          backAction: closeCurrentView,
          showsSeparator: style == .fun
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
        VStack(spacing: 0) {
          ForEach(viewModel.state.rows) { row in
            TeamInfoRowView(row: row, token: token, style: style) { selected in
              viewModel.select(selected)
              syncRoutePresentation()
            }
            if row.id != viewModel.state.rows.last?.id {
              NETeamCommonPresentation.settingSeparator(token: token, leadingInset: style == .fun ? 16 : 36)
            }
          }
        }
        .background(token.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: token.sectionCornerRadius, style: .continuous))
        .padding(.horizontal, token.sectionHorizontalMargin)
      }
    }
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

  private var title: String {
    if viewModel.state.snapshot?.kind.isDiscuss == true {
      return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.discussInfo, value: "Temp Group Info")
    }
    return NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.groupInfo, value: "Group Info")
  }
}
