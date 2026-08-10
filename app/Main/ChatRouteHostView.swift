// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import NEChatKit
import NEChatUIKitSwiftUI
import NEContactUIKitSwiftUI
import NETeamUIKitSwiftUI
import NIMSDK
import SwiftUI

struct ExampleWebRoute: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let url: URL

    init(title: String, url: URL) {
        id = UUID().uuidString
        self.title = title
        self.url = url
    }
}

@MainActor
final class ExampleWebRouteCenter: ObservableObject {
    static let shared = ExampleWebRouteCenter()

    @Published var route: ExampleWebRoute?

    private init() {}

    func open(title: String, url: URL) {
        route = ExampleWebRoute(title: title, url: url)
    }
}

struct ExampleCompatibleNavigationDestinationModifier<Item: Hashable, Destination: View>: ViewModifier {
    @Binding var item: Item?
    let destination: (Item) -> Destination

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.navigationDestination(item: $item, destination: destination)
        } else {
            content.background {
                NavigationLink(isActive: Binding(
                    get: { item != nil },
                    set: { isPresented in
                        if !isPresented {
                            item = nil
                        }
                    }
                )) {
                    if let item {
                        destination(item)
                    } else {
                        EmptyView()
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
    }
}

extension View {
    func exampleCompatibleNavigationDestination<Item: Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        modifier(ExampleCompatibleNavigationDestinationModifier(item: item, destination: destination))
    }
}

struct ChatRouteHostView<Content: View>: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var chatSelectionService = ExampleChatSelectionBoundaryService.shared
    @StateObject private var webRouteCenter = ExampleWebRouteCenter.shared
    @StateObject private var collectionInteractionViewModel = MineCollectionInteractionViewModel(usesForwardSelectionHandler: false)
    @State private var hostID = UUID()
    @State private var pushedRoute: PushedRoute?
    @State private var presentedMediaPreview: ChatMediaPreviewState?
    private let tab: AppTab
    private let isActive: Bool
    private let sessionOwnerID: UUID?
    private let onOpenChatRoute: (() -> Void)?
    private let content: Content

    init(tab: AppTab,
         isActive: Bool = true,
         sessionOwnerID: UUID? = nil,
         onOpenChatRoute: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.tab = tab
        self.isActive = isActive
        self.sessionOwnerID = sessionOwnerID
        self.onOpenChatRoute = onOpenChatRoute
        self.content = content()
    }

    var body: some View {
        routePresentationContent
            .sheet(isPresented: mentionSelectionRouteIsPresentedBinding) {
                selectionDestination
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: discussSelectionRouteIsPresentedBinding) {
                selectionDestination
            }
            .fullScreenCover(isPresented: teamInviteSelectionRouteIsPresentedBinding) {
                selectionDestination
            }
            .sheet(isPresented: forwardSelectionRouteIsPresentedBinding) {
                selectionDestination
            }
            .sheet(item: $collectionInteractionViewModel.forwardSelection) { selection in
                MineCollectionForwardSelectionView(
                    token: ChatSwiftUIConfigCenter.shared.current().themeToken,
                    request: selection.request,
                    onComplete: collectionInteractionViewModel.completeForwardSelection
                )
            }
            .neCommonTransientOverlay(
                collectionInteractionViewModel.toast,
                placement: .top,
                topPadding: 52,
                onDismiss: { collectionInteractionViewModel.consumeToast($0) }
            ) { toast in
                ChatToastView(toast: toast, token: ChatSwiftUIConfigCenter.shared.current().themeToken)
            }
            .fullScreenCover(item: $presentedMediaPreview) { preview in
                let config = ChatSwiftUIConfigCenter.shared.current()
                ChatMediaPreviewView(
                    preview: preview,
                    token: config.themeToken,
                    onSaveImage: config.mediaImageSaveHandler
                )
                .ignoresSafeArea()
                .demoHidesTabBar()
            }
            .navigationDestination(isPresented: rootWebRouteIsPresentedBinding) {
                webDestination
            }
            .exampleCompatibleNavigationDestination(item: $collectionInteractionViewModel.route) { route in
                collectionInteractionDestination(
                    route: route,
                    token: ChatSwiftUIConfigCenter.shared.current().themeToken
                )
            }
            .fullScreenCover(item: $collectionInteractionViewModel.presentedPreview) { preview in
                collectionInteractionPresentedPreview(preview, token: ChatSwiftUIConfigCenter.shared.current().themeToken)
                    .demoHidesTabBar()
            }
            .onAppear {
                registerRouteHandler()
            }
            .onChange(of: isActive) { _ in
                registerRouteHandler()
            }
            .onReceive(NotificationCenter.default.publisher(for: NENotificationName.popGroupChatVC)) { notification in
                closeTeamChatRouteIfNeeded(notification)
            }
    }

    @ViewBuilder
    private var routePresentationContent: some View {
        if #available(iOS 17.0, *) {
            content
                .navigationDestination(item: $pushedRoute) { pushedRoute in
                    destination(for: pushedRoute.route)
                        .id(pushedRoute.uuid)
                }
        } else {
            content
                .background {
                    NavigationLink(isActive: pushedRouteIsPresentedBinding) {
                        if let pushedRoute {
                            destination(for: pushedRoute.route)
                                .id(pushedRoute.uuid)
                        }
                    } label: {
                        EmptyView()
                    }
                    .hidden()
                }
        }
    }

    @ViewBuilder
    private func destination(for route: NEChatSwiftUIRoute) -> some View {
        let config = ChatSwiftUIConfigCenter.shared.current()
        let token = config.themeToken
        Group {
            switch route {
                case let .p2pChat(context):
                    ChatView(
                        viewModel: ChatSessionViewModel(
                            context: context,
                            config: config
                        ),
                        browserDestination: demoBrowserDestination,
                        onReplaceChatRoute: { route in
                            openChatRoute(route)
                        }
                    )
                    .id(chatViewIdentity(for: context))
                    .toolbar(.hidden, for: .tabBar)
                case let .teamChat(context):
                    ChatView(
                        viewModel: ChatSessionViewModel(
                            context: context,
                            config: config
                        ),
                        browserDestination: demoBrowserDestination,
                        onReplaceChatRoute: { route in
                            openChatRoute(route)
                        },
                        onTeamLifecycleExit: { teamId in
                            requestTeamChatRouteClosure(teamId: teamId)
                        }
                    )
                    .id(chatViewIdentity(for: context))
                    .toolbar(.hidden, for: .tabBar)
                case let .botSubSessionList(context):
                    BotSubSessionListView(
                        viewModel: BotSubSessionListViewModel(context: context, config: config),
                        token: token,
                        onRoute: openNestedRoute
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .botSubSessionChat(context):
                    ChatView(
                        viewModel: ChatSessionViewModel(context: context, config: config),
                        token: token,
                        browserDestination: demoBrowserDestination,
                        onReplaceChatRoute: { route in
                            openChatRoute(route)
                        }
                    )
                    .id(chatViewIdentity(for: context))
                    .toolbar(.hidden, for: .tabBar)
                case let .pinMessages(conversationId):
                    PinMessagesView(
                        viewModel: PinMessagesViewModel(conversationId: conversationId),
                        token: token,
                        onContentSelect: { row in
                            collectionInteractionViewModel.open(row)
                        },
                        onSelectMessage: { selection in
                            openPinnedMessage(selection, fallbackConversationId: conversationId)
                        },
                        onCopy: { row in
                            collectionInteractionViewModel.copy(row)
                        },
                        onForward: { row in
                            collectionInteractionViewModel.forward(row)
                        },
                        onForwardMessage: { row, sourceMessage in
                            collectionInteractionViewModel.forward(row, sourceMessage: sourceMessage)
                        },
                        onOpenURL: { url, displayText, source, row in
                            collectionInteractionViewModel.openURL(
                                url,
                                displayText: displayText,
                                source: source,
                                message: row
                            )
                        },
                        onBack: closePushedRoute,
                        canCopy: { row in
                            MineCollectionInteractionViewModel.canCopy(row)
                        },
                        canForward: { row in
                            MineCollectionInteractionViewModel.canForward(row)
                        },
                        playingAudioMessageId: collectionInteractionViewModel.playingAudioMessageId,
                        onStopAudioPlayback: collectionInteractionViewModel.stopAudioPlayback
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .historySearch(conversationId):
                    HistorySearchView(
                        viewModel: HistorySearchViewModel(
                            conversationId: conversationId,
                            fileInteractionHandler: config.fileInteractionHandler,
                            mediaPreviewHandler: config.mediaPreviewHandler
                        ),
                        token: token,
                        onSelectMessage: { selection in
                            openPinnedMessage(selection, fallbackConversationId: conversationId)
                        },
                        onForward: { row in
                            collectionInteractionViewModel.forward(row)
                        },
                        onForwardMessage: { row, sourceMessage in
                            collectionInteractionViewModel.forward(row, sourceMessage: sourceMessage)
                        },
                        onForwardMessageWithToast: { row, sourceMessage, presentToast in
                            collectionInteractionViewModel.forward(
                                row,
                                sourceMessage: sourceMessage,
                                resultToastHandler: presentToast
                            )
                        },
                        onOpenURL: { url, displayText, source, row in
                            collectionInteractionViewModel.openURL(url, displayText: displayText, source: source, message: row)
                        },
                        onSaveMedia: config.mediaImageSaveHandler,
                        onBack: closePushedRoute,
                        canForward: { row in
                            MineCollectionInteractionViewModel.canForward(row)
                        }
                    )
                    .toolbar(.hidden, for: .tabBar)
                case .collectionMessages:
                    CollectionMessagesView(
                        viewModel: CollectionMessagesViewModel(
                            networkOperationGuard: { DemoNetworkPresentation.allowsNetworkOperation }
                        ),
                        token: token,
                        onSelect: { _ in
                        },
                        onContentSelect: { row in
                            collectionInteractionViewModel.open(row)
                        },
                        onSelectMessage: { selection in
                            openPinnedMessage(selection, fallbackConversationId: selection.row.conversationId ?? "")
                        },
                        onCopy: { row in
                            collectionInteractionViewModel.copy(row)
                        },
                        onForward: { row in
                            collectionInteractionViewModel.forward(row, showsSuccessToast: false)
                        },
                        onForwardMessage: { row, sourceMessage in
                            collectionInteractionViewModel.forward(row, sourceMessage: sourceMessage, showsSuccessToast: false)
                        },
                        onOpenURL: { url, displayText, source, row in
                            collectionInteractionViewModel.openURL(url, displayText: displayText, source: source, row: row)
                        },
                        onBack: closePushedRoute,
                        canCopy: { row in
                            MineCollectionInteractionViewModel.canCopy(row)
                        },
                        canForward: { row in
                            MineCollectionInteractionViewModel.canForward(row)
                        },
                        playingAudioMessageId: collectionInteractionViewModel.playingAudioMessageId,
                        onStopAudioPlayback: collectionInteractionViewModel.stopAudioPlayback
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .readReceipt(messageId, _):
                    ReadReceiptView(
                        viewModel: ReadReceiptViewModel(messageId: messageId),
                        token: token
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .aiRobot(state):
                    switch state.kind {
                    case .list:
                        AIRobotEntryView(token: token, onRoute: openNestedRoute)
                            .toolbar(.hidden, for: .tabBar)
                    default:
                        AIRobotRouteView(
                            state: state,
                            token: token,
                            avatarSelectionHandler: config.avatarSelectionHandler,
                            configClipboardHandler: config.aiRobotConfigClipboardHandler,
                            onRoute: openNestedRoute,
                            onDismiss: closePushedRoute
                        )
                        .toolbar(.hidden, for: .tabBar)
                    }
                case let .mediaPreview(preview):
                    if preview.kind == .image {
                        EmptyView()
                            .onAppear {
                                presentedMediaPreview = preview
                                closePushedRoute()
                            }
                    } else {
                        ChatMediaPreviewView(
                            preview: preview,
                            token: token,
                            onSaveImage: config.mediaImageSaveHandler
                        )
                        .toolbar(.hidden, for: .tabBar)
                    }
                case let .filePreview(preview):
                    ChatFilePreviewView(
                        preview: preview,
                        token: token
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .textPreview(preview):
                    ChatTextPreviewView(
                        preview: preview,
                        token: token,
                        browserDestination: demoBrowserDestination
                    ) { url, displayText, textPreview in
                        collectionInteractionViewModel.openURL(
                            url,
                            displayText: displayText,
                            source: .textPreview,
                            preview: textPreview
                        )
                    }
                        .toolbar(.hidden, for: .tabBar)
                case let .multiForwardPreview(preview):
                    MultiForwardMessagesView(
                        viewModel: MultiForwardMessagesViewModel(preview: preview),
                        token: token,
                        onSelect: { row in
                            collectionInteractionViewModel.open(row)
                        },
                        onOpenURL: { url, displayText, source, row in
                            collectionInteractionViewModel.openURL(url, displayText: displayText, source: source, message: row)
                        },
                        browserDestination: demoBrowserDestination,
                        onSaveMedia: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .locationDetail(location):
                    LocationDetailView(location: location, token: token)
                        .toolbar(.hidden, for: .tabBar)
                case let .forwardMessages(_, messageIds, merged):
                    ChatRouteUnsupportedView(
                        title: merged
                            ? NEChatUIKitSwiftUIBundle.localized("chat_forward_merged", value: "Merged Forward")
                            : NEChatUIKitSwiftUIBundle.localized("chat_forward_one_by_one", value: "Forward One by One"),
                        reason: String(format: NEChatUIKitSwiftUIBundle.localized("chat_forward_missing_state_format", value: "Forward state is missing for %d messages."), messageIds.count),
                        token: token
                    )
                    .toolbar(.hidden, for: .tabBar)
                case let .userSetting(context):
                    P2PSettingView(
                        context: context,
                        config: config,
                        token: token,
                        onPinMessageSelect: { selection in
                            openPinnedMessage(selection, fallbackConversationId: context.conversationId)
                        },
                        onOpenUtilityMessageContent: { row in
                            collectionInteractionViewModel.open(row)
                        },
                        onCopy: { row in
                            collectionInteractionViewModel.copy(row)
                        },
                        onForward: { row in
                            collectionInteractionViewModel.forward(row)
                        },
                        onForwardMessage: { row, sourceMessage in
                            collectionInteractionViewModel.forward(row, sourceMessage: sourceMessage)
                        },
                        canCopy: { row in
                            MineCollectionInteractionViewModel.canCopy(row)
                        },
                        canForward: { row in
                            MineCollectionInteractionViewModel.canForward(row)
                        },
                        onOpenTeamChat: { context in
                            openCreatedTeamChat(context)
                        }
                    )
                        .toolbar(.hidden, for: .tabBar)
                case let .userProfile(request):
                    if request.source == .selfAvatar {
                        MineView()
                            .toolbar(.hidden, for: .tabBar)
                    } else {
                        ContactUserInfoView(
                            viewModel: ContactUserInfoViewModel(
                                accountId: request.accountId,
                                isCurrentUser: request.accountId == IMKitClient.instance.account(),
                                isRobot: request.isRobot
                            ),
                            token: contactToken(for: token),
                            onOpenChat: { accountId, title in
                                openP2PChat(accountId: accountId, title: title)
                            }
                        )
                        .toolbar(.hidden, for: .tabBar)
                    }
                case let .teamSetting(teamId, context):
                    if let provider = config.teamSettingViewProvider,
                       let teamSettingView = provider(teamId, context)
                    {
                        teamSettingView
                            .toolbar(.hidden, for: .tabBar)
                    } else {
                        ChatRouteUnsupportedView(
                            title: NEChatUIKitSwiftUIBundle.localized("chat_setting", value: "Chat Setting"),
                            reason: String(format: NEChatUIKitSwiftUIBundle.localized("chat_team_setting_requires_team_host_format", value: "Team setting for %@ should be handled by the Team SwiftUI module or the SwiftUI app route host."), teamId),
                            token: token
                        )
                        .toolbar(.hidden, for: .tabBar)
                    }
                case let .unsupported(url, reason):
                    ChatRouteUnsupportedView(title: url, reason: reason, token: token)
                        .toolbar(.hidden, for: .tabBar)
                default:
                    ChatRouteUnsupportedView(
                        title: route.id,
                        reason: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                        token: token
                    )
                    .toolbar(.hidden, for: .tabBar)
                }
            }
            .navigationDestination(isPresented: nestedWebRouteIsPresentedBinding) {
                webDestination
            }
            .exampleCompatibleNavigationDestination(item: $collectionInteractionViewModel.webRoute) { route in
                DemoWebPageView(title: route.title, url: route.url)
                    .demoHidesTabBar()
            }
            .demoHidesTabBar()
    }

    @ViewBuilder
    private var webDestination: some View {
        if let route = webRouteCenter.route {
            DemoWebPageView(title: route.title, url: route.url)
                .demoHidesTabBar()
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectionDestination: some View {
        if let route = chatSelectionService.route {
            ExampleChatSelectionDestinationView(
                route: route,
                chatToken: ChatSwiftUIConfigCenter.shared.current().themeToken,
                service: chatSelectionService
            )
            .demoHidesTabBar()
        } else {
            EmptyView()
        }
    }

    private var mentionSelectionRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                guard isCurrentSelectionPresenter else {
                    return false
                }
                guard let route = chatSelectionService.route else {
                    return false
                }
                if case .mention = route {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, isCurrentSelectionPresenter {
                    chatSelectionService.cancelCurrentRoute()
                }
            }
        )
    }

    private var discussSelectionRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                guard isCurrentSelectionPresenter else {
                    return false
                }
                guard let route = chatSelectionService.route else {
                    return false
                }
                if case .p2pDiscuss = route {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, isCurrentSelectionPresenter {
                    chatSelectionService.cancelCurrentRoute()
                }
            }
        )
    }

    private var teamInviteSelectionRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                guard isCurrentSelectionPresenter else {
                    return false
                }
                guard let route = chatSelectionService.route else {
                    return false
                }
                if case .teamInvite = route {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, isCurrentSelectionPresenter {
                    chatSelectionService.cancelCurrentRoute()
                }
            }
        )
    }

    private var forwardSelectionRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                guard isCurrentSelectionPresenter else {
                    return false
                }
                guard let route = chatSelectionService.route else {
                    return false
                }
                if case .forward = route {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, isCurrentSelectionPresenter {
                    chatSelectionService.cancelCurrentRoute()
                }
            }
        )
    }

    private var isCurrentSelectionPresenter: Bool {
        isActive && ExampleChatRouteHostActivation.activeHostID == hostID
    }

    private var rootWebRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { isCurrentWebRoutePresenter && webRouteCenter.route != nil && pushedRoute == nil },
            set: { isPresented in
                if !isPresented {
                    webRouteCenter.route = nil
                }
            }
        )
    }

    private var nestedWebRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { isCurrentWebRoutePresenter && webRouteCenter.route != nil && pushedRoute != nil },
            set: { isPresented in
                if !isPresented {
                    webRouteCenter.route = nil
                }
            }
        )
    }

    private var isCurrentWebRoutePresenter: Bool {
        isActive && ExampleChatRouteHostActivation.activeHostID == hostID
    }

    private func demoBrowserDestination(url: URL, title: String) -> AnyView {
        AnyView(
            DemoWebPageView(title: title, url: url)
                .demoHidesTabBar()
        )
    }

    @ViewBuilder
    private func collectionInteractionDestination(route: NEChatSwiftUIRoute,
                                                  token: ChatThemeToken) -> some View {
        switch route {
        case let .mediaPreview(preview):
            ChatMediaPreviewView(
                preview: preview,
                token: token,
                onSaveImage: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
            )
        case let .filePreview(preview):
            ChatFilePreviewView(preview: preview, token: token)
        case let .textPreview(preview):
            ChatTextPreviewView(
                preview: preview,
                token: token,
                browserDestination: demoBrowserDestination
            ) { url, displayText, preview in
                collectionInteractionViewModel.openURL(
                    url,
                    displayText: displayText,
                    source: .textPreview,
                    preview: preview
                )
            }
        case let .multiForwardPreview(preview):
            MultiForwardMessagesView(
                viewModel: MultiForwardMessagesViewModel(preview: preview),
                token: token,
                onSelect: { row in
                    collectionInteractionViewModel.open(row)
                },
                onOpenURL: { url, displayText, source, row in
                    collectionInteractionViewModel.openURL(url, displayText: displayText, source: source, message: row)
                },
                browserDestination: demoBrowserDestination,
                onSaveMedia: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
            )
        case let .locationDetail(location):
            LocationDetailView(location: location, token: token)
        case let .forwardMessages(_, messageIds, merged):
            ChatRouteUnsupportedView(
                title: merged
                    ? NEChatUIKitSwiftUIBundle.localized("chat_forward_merged", value: "Merged Forward")
                    : NEChatUIKitSwiftUIBundle.localized("chat_forward_one_by_one", value: "Forward One by One"),
                reason: String(format: NEChatUIKitSwiftUIBundle.localized("chat_forward_missing_state_format", value: "Forward state is missing for %d messages."), messageIds.count),
                token: token
            )
        default:
            ChatRouteUnsupportedView(
                title: route.id,
                reason: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                token: token
            )
        }
    }

    @ViewBuilder
    private func collectionInteractionPresentedPreview(_ preview: CollectionPresentedPreview, token: ChatThemeToken) -> some View {
        switch preview {
        case let .text(previewState):
            NavigationStack {
                ChatTextPreviewView(
                    preview: previewState,
                    token: token,
                    browserDestination: demoBrowserDestination
                ) { url, displayText, textPreview in
                    collectionInteractionViewModel.openURL(
                        url,
                        displayText: displayText,
                        source: .textPreview,
                        preview: textPreview
                    )
                }
            }
        case let .media(previewState):
            ChatMediaPreviewView(
                preview: previewState,
                token: token,
                onSaveImage: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
            )
            .ignoresSafeArea()
        case let .file(previewState):
            ChatFilePreviewView(preview: previewState, token: token)
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

    private func registerRouteHandler() {
        let ownerID = sessionOwnerID ?? environment.loginSessionID
        guard ownerID == environment.loginSessionID else {
            return
        }
        let registeredHostID = hostID
        ExampleChatRouteHostActivation.register(
            hostID: registeredHostID,
            for: tab,
            ownerID: ownerID
        ) { route in
            guard ExampleChatRouteHostActivation.activeHostID == registeredHostID else {
                return
            }
            openRoute(route)
        }
    }

    private func openNestedRoute(_ route: NEChatSwiftUIRoute) {
        openRoute(route)
    }

    private func openP2PChat(accountId: String, title: String) {
        guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
            return
        }
        openRoute(.p2pChat(ChatSessionContext(
            kind: .p2p,
            conversationId: conversationId,
            title: title,
            sessionId: accountId,
            sessionName: title
        )))
    }

    private func closePushedRoute() {
        pushedRoute = nil
    }

    private func openCreatedTeamChat(_ context: ChatSessionContext) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            closePushedRoute()
            onOpenChatRoute?()
            clearTransientRoutesBeforeOpeningChat()
            replacePushedRouteWithChatRoute(PushedRoute(.teamChat(context)))
        }
    }

    private func closeTeamChatRouteIfNeeded(_ notification: Notification) {
        guard let teamId = notification.userInfo?["teamId"] as? String else {
            return
        }
        requestTeamChatRouteClosure(teamId: teamId)
    }

    private func requestTeamChatRouteClosure(teamId: String) {
        guard let route = pushedRoute?.route,
              route.matchesTeamChat(teamId: teamId) else {
            return
        }
        closeTeamChatRoute(teamId: teamId)
    }

    private func closeTeamChatRoute(teamId: String) {
        guard let route = pushedRoute?.route,
              route.matchesTeamChat(teamId: teamId) else {
            return
        }
        presentedMediaPreview = nil
        pushedRoute = nil
    }

    private func openPinnedMessage(_ selection: PinMessageSelection, fallbackConversationId: String) {
        guard let route = chatRoute(for: selection, fallbackConversationId: fallbackConversationId) else {
            return
        }
        openRoute(route)
    }

    private func openRoute(_ route: NEChatSwiftUIRoute) {
        if case let .mediaPreview(preview) = route,
           preview.kind == .image {
            presentedMediaPreview = preview
            return
        }
        if route.isChatRoute {
            openChatRoute(route)
            return
        }
        // Non-chat utility routes can replace in place because they are already on
        // a pushed destination. Chat routes decide below whether they are a fresh
        // root push or an in-place replacement from an existing utility page.
        pushedRoute = PushedRoute(route)
    }

    private func openChatRoute(_ route: NEChatSwiftUIRoute) {
        onOpenChatRoute?()
        clearTransientRoutesBeforeOpeningChat()
        if shouldDeferFreshChatPush(for: route) {
            pushFreshChatRoute(PushedRoute(route))
            return
        }
        replacePushedRouteWithChatRoute(PushedRoute(route))
    }

    private func clearTransientRoutesBeforeOpeningChat() {
        collectionInteractionViewModel.clearRoute()
        collectionInteractionViewModel.clearPresentedPreview()
        collectionInteractionViewModel.forwardSelection = nil
        webRouteCenter.route = nil
        chatSelectionService.cancelCurrentRoute()
        NETeamUIKitSwiftUIClient.shared.dismissRoute()
        presentedMediaPreview = nil
    }

    private func replacePushedRouteWithChatRoute(_ nextRoute: PushedRoute) {
        // Keep the app-level destination mounted while replacing its route. Clearing
        // it first tears down the current ChatView before its nested contact-card
        // navigation finishes dismissing, which can leave the first replacement chat
        // without a navigation host or timeline.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pushedRoute = nextRoute
        }
    }

    private func shouldDeferFreshChatPush(for route: NEChatSwiftUIRoute) -> Bool {
        pushedRoute == nil && !route.hasAnchorMessage
    }

    private func pushFreshChatRoute(_ nextRoute: PushedRoute) {
        DispatchQueue.main.async {
            pushedRoute = nextRoute
        }
    }

    private func chatRoute(for selection: PinMessageSelection, fallbackConversationId: String) -> NEChatSwiftUIRoute? {
        let anchorMessage = selection.anchorMessage
        let conversationId = anchorMessage?.conversationId ?? selection.row.conversationId ?? fallbackConversationId
        guard !conversationId.isEmpty else {
            return nil
        }
        let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId)
        let context = ChatSessionContext(
            kind: chatKind(for: anchorMessage, conversationId: conversationId),
            conversationId: conversationId,
            sessionId: targetId,
            anchorMessage: anchorMessage,
            pendingMessages: selection.pendingMessages
        )
        switch context.kind {
        case .p2p:
            return .p2pChat(context)
        case .team:
            return .teamChat(context)
        default:
            return nil
        }
    }

    private func chatKind(for message: V2NIMMessage?, conversationId: String) -> ChatSessionKind {
        switch message?.conversationType ?? V2NIMConversationIdUtil.conversationType(conversationId) {
        case .CONVERSATION_TYPE_P2P:
            return .p2p
        case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
            return .team
        default:
            return .history
        }
    }

    private func chatViewIdentity(for context: ChatSessionContext) -> String {
        [
            context.id,
            context.anchorMessage?.messageClientId,
            context.anchorMessage?.messageServerId
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: ":")
    }

    private func contactToken(for token: ChatThemeToken) -> ContactThemeToken {
        token.styleMode == .fun ? .fun : .normal
    }
}

@MainActor
enum ExampleChatRouteHostActivation {
    private struct Host {
        let id: UUID
        let ownerID: UUID
        let openRoute: (NEChatSwiftUIRoute) -> Void
    }

    private static var activeTab: AppTab = .conversation
    private static var hosts = [AppTab: Host]()
    private static var activeOwnerID: UUID?

    static var activeHostID: UUID? {
        hosts[activeTab]?.id
    }

    static func register(hostID: UUID,
                         for tab: AppTab,
                         ownerID: UUID,
                         openRoute: @escaping (NEChatSwiftUIRoute) -> Void) {
        adoptOwnerIfNeeded(ownerID)
        hosts[tab] = Host(id: hostID, ownerID: ownerID, openRoute: openRoute)
        installRouterCallbacks()
        if tab == activeTab {
            consumeLatestPendingRequestIfPossible()
        }
    }

    static func activate(_ tab: AppTab) {
        activeTab = tab
        installRouterCallbacks()
        consumeLatestPendingRequestIfPossible()
    }

    static func activate(_ tab: AppTab, ownerID: UUID) {
        guard activeOwnerID == ownerID else {
            return
        }
        activate(tab)
    }

    static func begin(ownerID: UUID) {
        adoptOwnerIfNeeded(ownerID)
    }

    static func reset(ownerID: UUID) {
        guard activeOwnerID == ownerID else {
            return
        }
        hosts.removeAll()
        activeTab = .conversation
        activeOwnerID = nil
        let router = NEChatUIKitSwiftUIClient.shared.router
        router.onRoute = nil
        router.onRouteRequest = nil
        router.clearPending()
    }

    private static func adoptOwnerIfNeeded(_ ownerID: UUID) {
        guard activeOwnerID != ownerID else {
            return
        }
        hosts.removeAll()
        activeOwnerID = ownerID
        activeTab = .conversation
    }

    private static var activeHost: Host? {
        hosts[activeTab]
    }

    private static func installRouterCallbacks() {
        let router = NEChatUIKitSwiftUIClient.shared.router
        router.onRoute = { route in
            Task { @MainActor in
                let router = NEChatUIKitSwiftUIClient.shared.router
                guard !router.pendingRequests.contains(where: { $0.route == route }) else {
                    return
                }
                activeHost?.openRoute(route)
            }
        }
        router.onRouteRequest = { request in
            Task { @MainActor in
                guard let host = activeHost else {
                    return
                }
                host.openRoute(request.route)
                NEChatUIKitSwiftUIClient.shared.router.complete(request.id)
            }
        }
    }

    private static func consumeLatestPendingRequestIfPossible() {
        guard let host = activeHost,
              let request = NEChatUIKitSwiftUIClient.shared.router.pendingRequests.last else {
            return
        }
        host.openRoute(request.route)
        NEChatUIKitSwiftUIClient.shared.router.complete(request.id)
    }
}

private struct ChatRouteUnsupportedView: View {
    var title: String
    var reason: String
    var token: ChatThemeToken

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 30))
                .foregroundColor(token.warningColor)
                .accessibilityLabel(title)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(token.incomingTextColor)
                .multilineTextAlignment(.center)
            Text(reason)
                .font(.system(size: 14))
                .foregroundColor(token.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(token.pageBackground.ignoresSafeArea())
    }
}

private extension NEChatSwiftUIRoute {
    func matchesTeamChat(teamId: String) -> Bool {
        guard case let .teamChat(context) = self else {
            return false
        }
        if context.sessionId == teamId {
            return true
        }
        return V2NIMConversationIdUtil.teamConversationId(teamId) == context.conversationId
    }

    var isChatRoute: Bool {
        switch self {
        case .p2pChat, .teamChat, .botSubSessionChat:
            return true
        default:
            return false
        }
    }

    var hasAnchorMessage: Bool {
        switch self {
        case let .p2pChat(context), let .teamChat(context), let .botSubSessionChat(context):
            return context.anchorMessage != nil
        default:
            return false
        }
    }
}

/// Hashable wrapper that gives each app-level chat route its own navigation identity.
private struct PushedRoute: Hashable {
    let route: NEChatSwiftUIRoute
    let uuid = UUID()

    init(_ route: NEChatSwiftUIRoute) {
        self.route = route
    }

    static func == (lhs: PushedRoute, rhs: PushedRoute) -> Bool {
        lhs.uuid == rhs.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}
