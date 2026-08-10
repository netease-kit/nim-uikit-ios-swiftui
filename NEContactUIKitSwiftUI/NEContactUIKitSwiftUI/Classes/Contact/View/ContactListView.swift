// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NETeamUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct ContactListView: View {
  @StateObject private var viewModel: ContactListViewModel
  @State private var searchText = ""
  @State private var fallbackRoute: ContactRouteRequest?
  @State private var lastIndexScrollTitle: String?
  @State private var chatPushAccountId: String?
  @State private var chatPushTitle: String?
  @State private var teamChatPushTeamId: String?
  @State private var teamChatPushTitle: String?
  private let token: ContactThemeToken

  @MainActor
  public init(viewModel: ContactListViewModel,
              token: ContactThemeToken? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token ?? viewModel.config.themeToken
  }

  public var body: some View {
    VStack(spacing: 0) {
      if viewModel.config.showTitleBar {
        ContactHeaderView(
          title: viewModel.config.title ?? NEContactUIKitSwiftUIBundle.localized("contact", value: "Contacts"),
          config: viewModel.config,
          token: token,
          onSearch: viewModel.openSearchContact,
          onAdd: viewModel.openAddFriend
        )
      }

      if shouldShowInlineSearchEntry {
        searchField
      }

      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(token.pageBackground)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(isPresented: fallbackRouteIsPresentedBinding) {
      if let route = fallbackRoute {
        ContactRouteDestinationView(request: route, token: token, onRouteRequest: { kind in
          switch kind {
          case .chat(let accountId, let title):
            chatPushAccountId = accountId
            chatPushTitle = title
          case .teamChat(let teamId, let title):
            teamChatPushTeamId = teamId
            teamChatPushTitle = title
            return
          default:
            break
          }
          fallbackRoute = nil
        })
          .neContactHideTabBarOnSubpage()
      }
    }
    .navigationDestination(isPresented: chatPushIsPresentedBinding) {
      if let accountId = chatPushAccountId {
        let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) ?? accountId
        let chatConfig = makeChatConfig()
        ChatView(
          viewModel: ChatSessionViewModel(
            context: ChatSessionContext(kind: .p2p, conversationId: conversationId, title: chatPushTitle ?? accountId, sessionId: accountId, sessionName: chatPushTitle ?? accountId),
            config: chatConfig
          ),
          token: chatConfig.themeToken
        )
          .neContactHideTabBarOnSubpage()
      }
    }
    .navigationDestination(isPresented: teamChatPushIsPresentedBinding) {
      if let teamId = teamChatPushTeamId {
        let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) ?? teamId
        let chatConfig = makeChatConfig()
        ChatView(
          viewModel: ChatSessionViewModel(
            context: ChatSessionContext(kind: .team, conversationId: conversationId, title: teamChatPushTitle, sessionId: teamId, sessionName: teamChatPushTitle),
            config: chatConfig
          ),
          token: chatConfig.themeToken
        )
          .neContactHideTabBarOnSubpage()
      }
    }
    .onAppear { viewModel.onAppear() }
    .onDisappear { viewModel.onDisappear() }
    .onChange(of: searchText) { text in
      viewModel.setSearchText(text)
    }
    .onChange(of: viewModel.state.pendingRoute) { route in
      guard let route else {
        return
      }
      fallbackRoute = route
      viewModel.consumePendingRoute()
    }
    .neCommonTransientOverlay(
      viewModel.state.toast,
      placement: .top,
      topPadding: 52,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      Text(toast.message)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func makeChatConfig() -> ChatSwiftUIConfig {
    var config = ChatSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }

  private var fallbackRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { fallbackRoute != nil },
      set: { isPresented in
        if !isPresented {
          fallbackRoute = nil
        }
      }
    )
  }

  private var chatPushIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { chatPushAccountId != nil },
      set: { isPresented in
        if !isPresented {
          chatPushAccountId = nil
          chatPushTitle = nil
        }
      }
    )
  }

  private var teamChatPushIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { teamChatPushTeamId != nil },
      set: { isPresented in
        if !isPresented {
          teamChatPushTeamId = nil
          teamChatPushTitle = nil
        }
      }
    )
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle, .loading:
      NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .failed(let message):
      NECommonErrorStateView(
        state: NECommonErrorState(
          textKey: "network_error",
          fallbackText: message,
          severity: .warning,
          retryable: true
        ),
        retry: {
          viewModel.loadInitial()
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
    case .loaded:
      list
    }
  }

  private var list: some View {
    let visibleSections = viewModel.state.visibleSections
    let showsFriendEmptyOverlay = !visibleSections.contains { section in
      section.entries.contains { $0.kind == .friend }
    }
    let isSearchEmpty = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    return ScrollViewReader { proxy in
      ZStack(alignment: .trailing) {
        ScrollView {
          LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(visibleSections) { section in
              Section {
                ForEach(section.entries, id: \.contactListRenderID) { entry in
                  ContactRowView(
                    entry: entry,
                    token: token,
                    showsOnlineStatus: viewModel.showsOnlineStatus
                  )
                    .onTapGesture {
                      viewModel.select(entry)
                    }
                    .overlay(alignment: .bottom) {
                      Rectangle()
                        .fill(token.rowSeparatorColor)
                        .frame(height: 1)
                        .padding(.leading, token.rowHorizontalPadding + token.avatarSize + 12)
                    }
                }
              } header: {
                if !section.title.isEmpty {
                  ContactSectionHeaderView(title: section.title, token: token)
                    .id(section.title)
                }
              }
            }

            Color.clear
              .frame(height: 12)
          }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(token.pageBackground)

        if showsFriendEmptyOverlay {
          NECommonEmptyStateView(
            state: NECommonEmptyState(
              titleKey: "no_friend",
              fallbackTitle: NEContactUIKitSwiftUIBundle.localized("no_friend", value: "No Contact"),
              imageKind: .user
            )
          )
          .allowsHitTesting(false)
          .padding(.top, emptyFriendOverlayTopPadding)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .neCommonTheme(NEContactCommonPresentation.commonTheme(for: token))
        }

        if !viewModel.state.indexTitles.isEmpty && isSearchEmpty {
          ContactIndexBarView(titles: viewModel.state.indexTitles, token: token) { title in
            if let scrollTitle = ContactSectionBuilder.scrollTitle(
              for: title,
              sections: visibleSections,
              previousTitle: lastIndexScrollTitle
            ) {
              lastIndexScrollTitle = scrollTitle
              withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(scrollTitle, anchor: .top)
              }
            }
          }
          .padding(.trailing, 2)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyFriendOverlayTopPadding: CGFloat {
    UIScreen.main.bounds.width / 2
  }

  private var shouldShowInlineSearchEntry: Bool {
    token.styleMode == .fun && viewModel.config.showSearchEntry
  }

  private var searchField: some View {
    Button {
      viewModel.openSearchContact()
    } label: {
      HStack(spacing: 8) {
        Image("fun_search", bundle: NECommonUIKitSwiftUIBundle.bundle)
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)

        Text(NEContactUIKitSwiftUIBundle.localized("search", value: "Search"))
          .font(.system(size: 16))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 36)
      .padding(.horizontal, 12)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.top, 12)
    .padding(.bottom, 12)
    .neCommonTheme(NEContactCommonPresentation.searchTheme(for: token))
  }
}

private extension View {
  func neContactHideTabBarOnSubpage() -> some View {
    self.neCommonRequestsTabBarHidden()
  }
}

private struct ContactRouteDestinationView: View {
  var request: ContactRouteRequest
  var token: ContactThemeToken
  var onRouteRequest: ((ContactRouteRequest.Kind) -> Void)?

  var body: some View {
    switch request.kind {
    case .addFriend:
      ContactFindFriendView(token: token, onOpenChat: { chatAccountId, chatTitle in
        onRouteRequest?(.chat(accountId: chatAccountId, title: chatTitle))
      })
    case .searchContact:
      ContactSearchView(viewModel: ContactSearchViewModel(), token: token, onOpenChat: { chatAccountId, chatTitle in
        onRouteRequest?(.chat(accountId: chatAccountId, title: chatTitle))
      })
    case .validation:
      ValidationListView(viewModel: ValidationListViewModel(), token: token)
    case .blackList:
      BlackListView(viewModel: BlackListViewModel(), token: token)
    case .teamList:
      ContactTeamListChatHostView(token: token)
    case .aiUserList:
      AIUserListView(viewModel: AIUserListViewModel(), token: token, onOpenChat: { chatAccountId, chatTitle in
        onRouteRequest?(.chat(accountId: chatAccountId, title: chatTitle))
      })
    case .aiRobotList:
      ContactAIRobotListHostView(token: token)
    case .userInfo(let accountId, let isCurrentUser):
      ContactUserInfoView(
        viewModel: ContactUserInfoViewModel(accountId: accountId, isCurrentUser: isCurrentUser),
        token: token,
        onOpenChat: { chatAccountId, chatTitle in
          onRouteRequest?(.chat(accountId: chatAccountId, title: chatTitle))
        }
      )
    case .team(let teamId):
      let teamConfig = currentTeamConfig()
      TeamSettingView(
        teamId: teamId,
        style: teamConfig.styleMode,
        token: teamConfig.themeToken,
        config: teamConfig
      )
    case .teamChat(let teamId, let title):
      let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) ?? teamId
      let chatConfig = currentChatConfig()
      ChatView(
        viewModel: ChatSessionViewModel(
          context: ChatSessionContext(kind: .team, conversationId: conversationId, title: title, sessionId: teamId, sessionName: title),
          config: chatConfig
        ),
        token: chatConfig.themeToken
      )
    case .chat(let accountId, let title):
      let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) ?? accountId
      let chatConfig = currentChatConfig()
      ChatView(
        viewModel: ChatSessionViewModel(
          context: ChatSessionContext(kind: .p2p, conversationId: conversationId, title: title, sessionId: accountId, sessionName: title),
          config: chatConfig
        ),
        token: chatConfig.themeToken
      )
    }
  }

  private func currentTeamConfig() -> NETeamSwiftUIConfig {
    var config = NETeamSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }

  private func currentChatConfig() -> ChatSwiftUIConfig {
    var config = ChatSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }
}

private struct ContactTeamListChatHostView: View {
  var token: ContactThemeToken
  @State private var chatTeamId: String?
  @State private var chatTitle: String?

  var body: some View {
    ContactTeamListView(
      viewModel: ContactTeamListViewModel(),
      token: token,
      onOpenTeamChat: { teamId, title in
        chatTeamId = teamId
        chatTitle = title
      }
    )
    .navigationDestination(isPresented: chatIsPresentedBinding) {
      if let teamId = chatTeamId {
        let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) ?? teamId
        let config = currentChatConfig()
        ChatView(
          viewModel: ChatSessionViewModel(
            context: ChatSessionContext(
              kind: .team,
              conversationId: conversationId,
              title: chatTitle,
              sessionId: teamId,
              sessionName: chatTitle
            ),
            config: config
          ),
          token: config.themeToken
        )
        .neContactHideTabBarOnSubpage()
      }
    }
  }

  private var chatIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { chatTeamId != nil },
      set: { isPresented in
        if !isPresented {
          chatTeamId = nil
          chatTitle = nil
        }
      }
    )
  }

  private func currentChatConfig() -> ChatSwiftUIConfig {
    var config = ChatSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }
}

private extension ContactEntryState {
  var contactListRenderID: String {
    "\(id)|\(title)"
  }
}

private struct ContactAIRobotListHostView: View {
  var token: ContactThemeToken
  @State private var pushedRoute: ContactAIRobotPushedRoute?

  var body: some View {
    let chatToken: ChatThemeToken = token.styleMode == .fun ? .fun : .normal
    AIRobotEntryView(token: chatToken) { route in
      openRoute(route)
    }
    .navigationDestination(isPresented: pushedRouteIsPresentedBinding) {
      if let pushedRoute {
        destination(for: pushedRoute.route, token: chatToken)
          .id(pushedRoute.id)
      }
    }
  }

  private var pushedRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { pushedRoute != nil },
      set: { isPresented in
        if !isPresented {
          pushedRoute = nil
        }
      }
    )
  }

  @ViewBuilder
  private func destination(for route: NEChatSwiftUIRoute, token: ChatThemeToken) -> some View {
    switch route {
    case let .aiRobot(state):
      let config = ChatSwiftUIConfigCenter.shared.current()
      ContactAIRobotRouteStackView(
        state: state,
        token: token,
        avatarSelectionHandler: config.avatarSelectionHandler,
        configClipboardHandler: config.aiRobotConfigClipboardHandler,
        onRoute: openRoute,
        onDismiss: {
          pushedRoute = nil
        }
      )
      .neCommonRequestsTabBarHidden()
    case let .botSubSessionList(context):
      BotSubSessionListView(
        viewModel: BotSubSessionListViewModel(context: context, config: currentChatConfig()),
        token: token,
        onRoute: openRoute
      )
      .neCommonRequestsTabBarHidden()
    case let .botSubSessionChat(context):
      ChatView(
        viewModel: ChatSessionViewModel(context: context, config: currentChatConfig()),
        token: token
      )
      .neCommonRequestsTabBarHidden()
    case .p2pChat, .teamChat:
      EmptyView()
        .onAppear {
          NEChatUIKitSwiftUIClient.shared.router.enqueue(route)
          pushedRoute = nil
        }
    default:
      EmptyView()
    }
  }

  private func openRoute(_ route: NEChatSwiftUIRoute) {
    pushedRoute = ContactAIRobotPushedRoute(route: route)
  }

  private func currentChatConfig() -> ChatSwiftUIConfig {
    var config = ChatSwiftUIConfigCenter.shared.current()
    config.styleMode = token.styleMode == .fun ? .fun : .normal
    return config
  }
}

private struct ContactAIRobotRouteStackView: View {
  var state: AIRobotRouteState
  var token: ChatThemeToken
  var avatarSelectionHandler: ChatAvatarSelectionHandling?
  var configClipboardHandler: AIRobotConfigClipboardHandling?
  var onRoute: (NEChatSwiftUIRoute) -> Void
  var onDismiss: () -> Void
  @State private var childRoute: ContactAIRobotPushedRoute?

  var body: some View {
    AIRobotRouteView(
      state: state,
      token: token,
      avatarSelectionHandler: avatarSelectionHandler,
      configClipboardHandler: configClipboardHandler,
      onRoute: openRoute,
      onDismiss: onDismiss
    )
    .navigationDestination(isPresented: childRouteIsPresentedBinding) {
      if let childRoute {
        destination(for: childRoute.route)
          .id(childRoute.id)
      }
    }
  }

  private var childRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { childRoute != nil },
      set: { isPresented in
        if !isPresented {
          childRoute = nil
        }
      }
    )
  }

  @ViewBuilder
  private func destination(for route: NEChatSwiftUIRoute) -> some View {
    switch route {
    case let .aiRobot(state):
      ContactAIRobotRouteStackView(
        state: state,
        token: token,
        avatarSelectionHandler: avatarSelectionHandler,
        configClipboardHandler: configClipboardHandler,
        onRoute: onRoute,
        onDismiss: onDismiss
      )
      .neCommonRequestsTabBarHidden()
    default:
      EmptyView()
        .onAppear {
          onRoute(route)
          childRoute = nil
        }
    }
  }

  private func openRoute(_ route: NEChatSwiftUIRoute) {
    if case .aiRobot = route {
      childRoute = ContactAIRobotPushedRoute(route: route)
    } else {
      onRoute(route)
    }
  }
}

private struct ContactAIRobotPushedRoute: Identifiable, Equatable {
  let id = UUID()
  var route: NEChatSwiftUIRoute
}
