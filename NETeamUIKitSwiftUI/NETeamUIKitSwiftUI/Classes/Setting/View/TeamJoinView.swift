// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct TeamJoinView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: TeamJoinViewModel
  @State private var pushedRoute: NETeamSwiftUIRoute?
  private let token: NETeamThemeToken
  private let style: NETeamSwiftUIStyleMode
  private let onOpenTeamChat: ((String) -> Void)?

  public init(teamId: String? = nil,
              style: NETeamSwiftUIStyleMode = .normal,
              teamType: NETeamSwiftUITeamType = .normal,
              token: NETeamThemeToken? = nil,
              onOpenTeamChat: ((String) -> Void)? = nil) {
    _viewModel = StateObject(wrappedValue: TeamJoinViewModel(initialTeamId: teamId, teamType: teamType))
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
          title: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.joinTeam, value: "Join Team"),
          token: token,
          backAction: {
            dismiss()
          },
          showsSeparator: false
        )

        VStack(spacing: 18) {
          searchField
          stateContent
          Spacer(minLength: 0)
        }
        .padding(.top, 20)
      }
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
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

  private var searchField: some View {
    NETeamCommonPresentation.searchField(
      text: Binding(
        get: { viewModel.state.teamIdText },
        set: { viewModel.updateTeamIdText($0) }
      ),
      placeholder: NETeamUIKitSwiftUIBundle.localized(NETeamLocalizableKey.inputTeamId, value: "input team id"),
      token: token,
      height: 36,
      onSubmit: {
        viewModel.search()
        syncRoutePresentation()
      }
    )
    .padding(.horizontal, 20)
  }

  @ViewBuilder
  private var stateContent: some View {
    switch viewModel.state.phase {
    case .failed(let message):
      NETeamCommonPresentation.inlineEmptyView(
        title: message,
        imageKind: style == .fun ? .user : .generic,
        token: token
      )
      .padding(.top, 68)
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var pushedRouteDestination: some View {
    if let route = pushedRoute {
      TeamRouteDestinationView(
        route: route,
        token: token,
        style: style,
        onOpenTeamChat: onOpenTeamChat
      )
    } else {
      EmptyView()
    }
  }

  private var pushedRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { pushedRoute != nil },
      set: { isPresented in
        if !isPresented {
          pushedRoute = nil
          viewModel.dismissRoute()
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
}
