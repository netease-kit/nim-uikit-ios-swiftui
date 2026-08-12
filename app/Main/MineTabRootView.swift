// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NEConversationUIKitSwiftUI
import NIMSDK
import SwiftUI

/// Root view for the Mine tab. Mirrors IMUIKitExample MeViewController layout.
struct MineTabRootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var user: NEUserWithFriend?
    @State private var legacyRoutePath = [LegacyRoute]()
    private let isActive: Bool
    private let sessionOwnerID: UUID?

    init(isActive: Bool = true, sessionOwnerID: UUID? = nil) {
        self.isActive = isActive
        self.sessionOwnerID = sessionOwnerID
    }

    private var accountId: String {
        environment.currentAccount ?? IMKitClient.instance.account()
    }

    private var displayName: String {
        user?.showName() ?? accountId
    }

    private var avatarName: String {
        user?.showName(false) ?? accountId
    }

    private var teamSettingViewProvider: ((String, ChatSessionContext) -> AnyView?)? {
        ChatSwiftUIConfigCenter.shared.current().teamSettingViewProvider
    }

    var body: some View {
        NavigationStack(path: $legacyRoutePath) {
            LegacyRouteHostView(routePath: $legacyRoutePath, isActive: isActive) {
                ChatRouteHostView(
                    tab: .mine,
                    isActive: isActive,
                    sessionOwnerID: sessionOwnerID,
                    onOpenChatRoute: {
                        if !legacyRoutePath.isEmpty {
                            legacyRoutePath.removeAll()
                        }
                    }
                ) {
                    VStack(spacing: 0) {
                        NavigationLink(destination: MineView().demoHidesTabBar()) {
                            header
                        }
                        .buttonStyle(.plain)

                        Color.clear
                            .frame(height: 6)

                        mineHomeList
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DemoSettingStyle.pageBackground(environment.themeMode).ignoresSafeArea())
                    .toolbar(.hidden, for: .navigationBar)
                    .id(environment.languageRevision)
                    .onAppear(perform: loadUser)
                } // ChatRouteHostView
            } // LegacyRouteHostView
        } // NavigationStack
    }

    private var mineHomeList: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: DemoSettingsView().demoHidesTabBar()) {
                MineHomeRow(title: localizable("setting"), iconName: "mine_setting")
            }
            .buttonStyle(.plain)

            if IMKitConfigCenter.shared.enableCollectionMessage {
                NavigationLink(destination: MineCollectionMessagesView().demoHidesTabBar()) {
                    MineHomeRow(title: localizable("mine_collection"), iconName: "mine_collection")
                }
                .buttonStyle(.plain)
            }

            NavigationLink(destination: AboutYunxinView().demoHidesTabBar()) {
                MineHomeRow(title: localizable("about_yunxin"), iconName: "about_yunxin")
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(environment.themeMode == .normal ? Color.white : Color.clear)
    }

    private var header: some View {
        HStack(spacing: 15) {
            DemoAvatarView(name: avatarName, accountId: accountId, url: user?.user?.avatar, size: 60, mode: environment.themeMode)
            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 22))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                    .lineLimit(1)
                Text("\(localizable("account")):\(accountId)")
                    .font(.system(size: 16))
                    .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                    .lineLimit(1)
            }
            Spacer()
            NECommonChevronView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 32)
        .background(Color.white.ignoresSafeArea(edges: .top))
    }

    private func loadUser() {
        if let cached = NEFriendUserCache.shared.getFriendInfo(accountId) {
            user = cached
        }
        ContactRepo.shared.getUserListFromCloud(accountIds: [accountId]) { users, _ in
            Task { @MainActor in
                if let loaded = users?.first {
                    user = loaded
                    NEFriendUserCache.shared.updateFriendInfo(loaded.user)
                }
            }
        }
    }
}

private struct MineHomeRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    var title: String
    var iconName: String

    var body: some View {
        HStack(spacing: 0) {
            ExampleAssetIcon(name: iconName, size: 20)
                .padding(.leading, 20)

            Text(title)
                .font(.system(size: 16))
                .foregroundColor(DemoSettingStyle.titleColor(environment.themeMode))
                .lineLimit(1)
                .padding(.leading, 14)

            Spacer(minLength: 12)

            NECommonChevronView()
                .padding(.trailing, 25)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: 0xDBE0E8))
                .frame(height: 0.5)
                .padding(.leading, 20)
        }
        .contentShape(Rectangle())
    }
}

private struct MineCollectionMessagesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var interactionViewModel = MineCollectionInteractionViewModel()

    var body: some View {
        let token: ChatThemeToken = environment.themeMode == .fun ? .fun : .normal
        CollectionMessagesView(
            viewModel: CollectionMessagesViewModel(
                networkOperationGuard: { DemoNetworkPresentation.allowsNetworkOperation }
            ),
            token: token,
            onSelect: { row in
                interactionViewModel.open(row)
            },
            onContentSelect: { row in
                interactionViewModel.open(row)
            },
            onCopy: { row in
                interactionViewModel.copy(row)
            },
            onForward: { row in
                interactionViewModel.forward(row, showsSuccessToast: false)
            },
            onForwardMessage: { row, sourceMessage in
                interactionViewModel.forward(row, sourceMessage: sourceMessage, showsSuccessToast: false)
            },
            onOpenURL: { url, displayText, source, row in
                interactionViewModel.openURL(url, displayText: displayText, source: source, row: row)
            },
            canCopy: { row in
                MineCollectionInteractionViewModel.canCopy(row)
            },
            canForward: { row in
                MineCollectionInteractionViewModel.canForward(row)
            },
            playingAudioMessageId: interactionViewModel.playingAudioMessageId,
            onStopAudioPlayback: interactionViewModel.stopAudioPlayback
        )
        .demoHidesTabBar()
        .exampleCompatibleNavigationDestination(item: $interactionViewModel.route) { route in
            mineCollectionRouteDestination(route: route, token: token)
        }
        .exampleCompatibleNavigationDestination(item: $interactionViewModel.webRoute) { route in
            DemoWebPageView(title: route.title, url: route.url)
                .demoHidesTabBar()
        }
        .fullScreenCover(item: $interactionViewModel.presentedPreview) { preview in
            mineCollectionPresentedPreview(preview, token: token)
        }
        .sheet(item: $interactionViewModel.forwardSelection) { selection in
            MineCollectionForwardSelectionView(
                token: token,
                request: selection.request,
                onComplete: interactionViewModel.completeForwardSelection
            )
        }
        .neCommonTransientOverlay(
            interactionViewModel.toast,
            placement: .top,
            topPadding: 52,
            onDismiss: { interactionViewModel.consumeToast($0) }
        ) { toast in
            ChatToastView(toast: toast, token: token)
        }
    }

    @ViewBuilder
    private func mineCollectionRouteDestination(route: NEChatSwiftUIRoute,
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
                browserDestination: mineBrowserDestination
            ) { url, displayText, preview in
                interactionViewModel.openURL(
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
                    interactionViewModel.open(row)
                },
                onOpenURL: { url, displayText, source, row in
                    interactionViewModel.openURL(url, displayText: displayText, source: source, message: row)
                },
                browserDestination: mineBrowserDestination,
                onSaveMedia: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
            )
        case let .locationDetail(location):
            LocationDetailView(location: location, token: token)
        case let .forwardMessages(_, messageIds, merged):
            MineCollectionUnsupportedRouteView(
                title: merged
                    ? NEChatUIKitSwiftUIBundle.localized("chat_forward_merged", value: "Merged Forward")
                    : NEChatUIKitSwiftUIBundle.localized("chat_forward_one_by_one", value: "Forward One by One"),
                reason: String(format: NEChatUIKitSwiftUIBundle.localized("chat_forward_missing_state_format", value: "Forward state is missing for %d messages."), messageIds.count),
                token: token
            )
        default:
            MineCollectionUnsupportedRouteView(
                title: route.id,
                reason: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                token: token
            )
        }
    }

    @ViewBuilder
    private func mineCollectionPresentedPreview(_ preview: CollectionPresentedPreview, token: ChatThemeToken) -> some View {
        switch preview {
        case let .text(previewState):
            NavigationStack {
                ChatTextPreviewView(
                    preview: previewState,
                    token: token,
                    browserDestination: mineBrowserDestination
                ) { url, displayText, textPreview in
                    interactionViewModel.openURL(
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

    private func mineBrowserDestination(url: URL, title: String) -> AnyView {
        AnyView(
            DemoWebPageView(title: title, url: url)
                .demoHidesTabBar()
        )
    }
}

struct MineCollectionForwardSelectionState: Identifiable, Equatable {
    let id: String
    let request: ChatForwardRequest
    let showsSuccessToast: Bool
    let sourceMessages: [V2NIMMessage]

    init(request: ChatForwardRequest,
         showsSuccessToast: Bool = true,
         sourceMessages: [V2NIMMessage] = []) {
        self.request = request
        self.showsSuccessToast = showsSuccessToast
        self.sourceMessages = sourceMessages
        id = "utilityForward:\(request.context.conversationId):\(request.messageIds.joined(separator: ",")):\(UUID().uuidString)"
    }

    static func == (lhs: MineCollectionForwardSelectionState, rhs: MineCollectionForwardSelectionState) -> Bool {
        lhs.id == rhs.id
    }
}

struct MineCollectionForwardSelectionView: View {
    var token: ChatThemeToken
    var request: ChatForwardRequest
    var onComplete: (ChatForwardSelectionResult?) -> Void

    var body: some View {
        ExampleForwardSelectionView(
            routeId: "utilityForwardSelection",
            request: request,
            token: conversationToken,
            onComplete: onComplete
        )
    }

    private var conversationToken: ConversationThemeToken {
        token.styleMode == .fun ? .fun : .normal
    }
}

private struct MineCollectionUnsupportedRouteView: View {
    var title: String
    var reason: String
    var token: ChatThemeToken

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 30))
                .foregroundColor(token.warningColor)
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

enum CollectionPresentedPreview: Identifiable, Equatable {
    case text(ChatTextPreviewState)
    case media(ChatMediaPreviewState)
    case file(ChatFilePreviewState)

    var id: String {
        switch self {
        case .text(let p): "text:\(p.id)"
        case .media(let p): "media:\(p.id)"
        case .file(let p): "file:\(p.id)"
        }
    }
}

@MainActor
final class MineCollectionInteractionViewModel: ObservableObject {
    @Published var route: NEChatSwiftUIRoute?
    @Published var webRoute: ExampleWebRoute?
    @Published var presentedPreview: CollectionPresentedPreview?
    @Published var toast: ChatToastState?
    @Published var forwardSelection: MineCollectionForwardSelectionState?
    @Published private(set) var playingAudioMessageId: String?

    private let configProvider: () -> ChatSwiftUIConfig
    private let operationPerformer: ChatMessageOperationPerforming
    private let usesForwardSelectionHandler: Bool
    private var forwardToastPresenters: [String: (ChatToastState) -> Void] = [:]
    private var activeAudioPlaybackRequest: ChatAudioPlaybackRequest?
    private static let defaultTeamConversationId = "338920520839424|2|338920520839424"
    private static let defaultTeamId = "338920520839424"

    init(configProvider: @escaping () -> ChatSwiftUIConfig = { ChatSwiftUIConfigCenter.shared.current() },
         operationPerformer: ChatMessageOperationPerforming = NEChatKitMessageOperationPerformer(),
         usesForwardSelectionHandler: Bool = true) {
        self.configProvider = configProvider
        self.operationPerformer = operationPerformer
        self.usesForwardSelectionHandler = usesForwardSelectionHandler
    }

    static func canCopy(_ row: MessageRowState) -> Bool {
        copyableText(from: row.content) != nil
    }

    static func canForward(_ row: MessageRowState) -> Bool {
        switch row.content {
        case .tip, .revoke, .unsupported:
            return false
        case .aiStream(_, let isFinished, _):
            return isFinished
        default:
            return true
        }
    }

    func open(_ collectionRow: CollectionMessageRowState) {
        guard let row = collectionRow.messageRow else {
            toast = ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("chat_collection_message_unavailable", value: "Collection message is unavailable"),
                style: .warning
            )
            return
        }
        open(row)
    }

    func open(_ row: MessageRowState) {
        switch row.content {
        case let .text(text):
            openTextPreview(ChatTextPreviewState(messageId: row.id, body: text, source: .utility))
        case let .richText(title, body):
            openTextPreview(ChatTextPreviewState(messageId: row.id, title: title, body: body, source: .utility))
        case let .image(media):
            presentedPreview = .media(ChatMediaPreviewState(id: row.id, kind: .image, media: media, title: ChatMessageMapper.previewText(for: row.content)))
        case let .video(media):
            presentedPreview = .media(ChatMediaPreviewState(id: row.id, kind: .video, media: media, title: ChatMessageMapper.previewText(for: row.content)))
        case let .file(file):
            openFilePreview(row: row, file: file)
        case let .location(location):
            route = .locationDetail(location)
        case let .multiForward(multiForward):
            route = .multiForwardPreview(ChatMultiForwardPreviewState(messageId: row.id, multiForward: multiForward))
        case let .audio(audio):
            toggleAudio(row, audio: audio)
        case let .reply(_, boxed):
            open(MessageRowState(
                id: row.id,
                serverId: row.serverId,
                conversationId: row.conversationId,
                senderId: row.senderId,
                senderName: row.senderName,
                direction: row.direction,
                content: boxed.value,
                deliveryState: row.deliveryState,
                timestamp: row.timestamp
            ))
        case let .aiStream(text, _, error):
            openTextPreview(ChatTextPreviewState(
                messageId: row.id,
                body: [text, error].compactMap { $0 }.joined(separator: "\n"),
                source: .utility
            ))
        default:
            toast = ChatToastState(message: ChatMessageMapper.previewText(for: row.content), style: .info)
        }
    }

    private func openFilePreview(row: MessageRowState, file: MessageFileState) {
        if let media = file.imageMediaState {
            presentedPreview = .media(ChatMediaPreviewState(
                id: row.id,
                kind: .image,
                media: media,
                title: ChatMessageMapper.previewText(for: row.content)
            ))
            return
        }

        if let media = file.videoMediaState {
            presentedPreview = .media(ChatMediaPreviewState(
                id: row.id,
                kind: .video,
                media: media,
                title: ChatMessageMapper.previewText(for: row.content)
            ))
            return
        }

        let preview = ChatFilePreviewState(id: row.id, file: file)
        guard let handler = configProvider().fileInteractionHandler else {
            presentedPreview = .file(preview)
            return
        }

        handler.handleFileInteraction(
            ChatFileInteractionRequest(preview: preview, message: row, context: utilityContext(for: row))
        ) { [weak self] result in
            Task { @MainActor in
                self?.handleFileInteractionResult(result, fallbackPreview: preview)
            }
        }
    }

    private func handleFileInteractionResult(_ result: Result<ChatNativeBoundaryResult, Error>,
                                             fallbackPreview: ChatFilePreviewState) {
        switch result {
        case let .success(boundaryResult):
            switch boundaryResult {
            case let .route(route):
                self.route = route
            case let .toast(toast):
                self.toast = toast
            case .none:
                break
            case .send, .sendMultiple:
                toast = ChatToastState(
                    message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                    style: .warning
                )
            @unknown default:
                break
            }
        case let .failure(error):
            route = .filePreview(fallbackPreview)
            toast = ChatToastState(
                message: DemoNetworkPresentation.chatMessage(
                    for: error,
                    fallbackKey: "chat_file_unavailable",
                    fallbackValue: "File unavailable"
                ),
                style: .error
            )
        }
    }

    private func toggleAudio(_ row: MessageRowState, audio: MessageAudioState) {
        guard let handler = configProvider().audioPlaybackHandler else {
            toast = ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("chat_audio_playback_requires_service", value: "Audio playback service is not connected yet"),
                style: .info
            )
            return
        }
        let request = ChatAudioPlaybackRequest(messageId: row.id, audio: audio, context: utilityContext(for: row))
        let completion: (Result<ChatAudioPlaybackResult, Error>) -> Void = { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(playbackResult):
                    switch playbackResult {
                    case .playing:
                        self?.playingAudioMessageId = row.id
                        self?.activeAudioPlaybackRequest = request
                    case .stopped:
                        if self?.playingAudioMessageId == row.id {
                            self?.playingAudioMessageId = nil
                            self?.activeAudioPlaybackRequest = nil
                        }
                    @unknown default:
                        if self?.playingAudioMessageId == row.id {
                            self?.playingAudioMessageId = nil
                            self?.activeAudioPlaybackRequest = nil
                        }
                    }
                case let .failure(error):
                    if self?.playingAudioMessageId == row.id {
                        self?.playingAudioMessageId = nil
                        self?.activeAudioPlaybackRequest = nil
                    }
                    self?.toast = ChatToastState(
                        message: DemoNetworkPresentation.chatMessage(
                            for: error,
                            fallbackKey: "chat_audio_playback_failed",
                            fallbackValue: "Audio playback failed"
                        ),
                        style: .error
                    )
                }
            }
        }
        if playingAudioMessageId == row.id {
            handler.stopAudio(request, completion: completion)
        } else {
            handler.playAudio(request, completion: completion)
        }
    }

    func stopAudioPlayback() {
        guard let request = activeAudioPlaybackRequest,
              let handler = configProvider().audioPlaybackHandler else {
            playingAudioMessageId = nil
            activeAudioPlaybackRequest = nil
            return
        }
        playingAudioMessageId = nil
        activeAudioPlaybackRequest = nil
        handler.stopAudio(request) { _ in }
    }

    func copy(_ row: MessageRowState) {
        guard let text = Self.copyableText(from: row.content) else {
            toast = ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            )
            return
        }
        guard let clipboardHandler = configProvider().clipboardHandler else {
            toast = ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("chat_copy_requires_boundary", value: "Copy requires a SwiftUI clipboard handler."),
                style: .info
            )
            return
        }
        clipboardHandler.copyText(ChatClipboardRequest(text: text, message: row, context: utilityContext(for: row))) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(boundaryResult):
                    switch boundaryResult {
                    case let .toast(toast):
                        self?.toast = toast
                    case let .route(route):
                        self?.route = route
                    case .send, .sendMultiple:
                        self?.toast = ChatToastState(
                            message: NEChatUIKitSwiftUIBundle.localized("chat_copy_ignores_send_result", value: "Copy does not support sending messages."),
                            style: .warning
                        )
                    case .none:
                        self?.toast = ChatToastState(
                            message: NEChatUIKitSwiftUIBundle.localized("chat_copied", value: "Copied"),
                            style: .success
                        )
                    @unknown default:
                        break
                    }
                case let .failure(error):
                    self?.toast = ChatToastState(
                        message: DemoNetworkPresentation.chatMessage(
                            for: error,
                            fallbackKey: "chat_copy_failed",
                            fallbackValue: "Copy failed"
                        ),
                        style: .error
                    )
                }
            }
        }
    }

    private static func copyableText(from content: MessageContentState) -> String? {
        switch content {
        case let .text(text), let .aiStream(text, _, _):
            return nonEmptyCopyText(text)
        case let .richText(title, body):
            return nonEmptyCopyText(body.isEmpty ? title ?? "" : body)
        case let .reply(_, boxed):
            return copyableText(from: boxed.value)
        default:
            return nil
        }
    }

    private static func nonEmptyCopyText(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    func forward(_ row: MessageRowState, showsSuccessToast: Bool = true) {
        forward(row, sourceMessage: nil, showsSuccessToast: showsSuccessToast, resultToastHandler: nil)
    }

    func forward(_ row: MessageRowState,
                 sourceMessage: V2NIMMessage?,
                 showsSuccessToast: Bool = true,
                 resultToastHandler: ((ChatToastState) -> Void)? = nil) {
        guard DemoNetworkPresentation.allowsNetworkOperation else {
            presentForwardToast(ChatToastState(
                message: DemoNetworkPresentation.networkMessage(),
                style: .warning
            ), using: resultToastHandler)
            return
        }
        guard Self.canForward(row) else {
            presentForwardToast(ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
                style: .warning
            ), using: resultToastHandler)
            return
        }
        let request = ChatForwardRequest(context: utilityContext(for: row), messageIds: [row.id], merged: false)
        let sourceMessages = sourceMessage.map { [$0] } ?? []
        if usesForwardSelectionHandler, let handler = configProvider().forwardSelectionHandler {
            handler.selectForwardTargets(request) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case let .success(selection):
                        guard !selection.targets.isEmpty else {
                            return
                        }
                        self?.performForward(
                            request: request,
                            selection: selection,
                            sourceMessages: sourceMessages,
                            showsSuccessToast: showsSuccessToast,
                            resultToastHandler: resultToastHandler
                        )
                    case let .failure(error):
                        self?.presentForwardToast(ChatToastState(
                            message: DemoNetworkPresentation.chatMessage(for: error),
                            style: .error
                        ), using: resultToastHandler)
                    }
                }
            }
            return
        }
        let selectionState = MineCollectionForwardSelectionState(
            request: request,
            showsSuccessToast: showsSuccessToast,
            sourceMessages: sourceMessages
        )
        if let resultToastHandler {
            forwardToastPresenters[selectionState.id] = resultToastHandler
        }
        forwardSelection = selectionState
    }

    func openURL(_ url: URL,
                 displayText: String,
                 source: ChatURLInteractionSource,
                 row: CollectionMessageRowState) {
        openURL(url, displayText: displayText, source: source, message: row.messageRow)
    }

    func openURL(_ url: URL,
                 displayText: String,
                 source: ChatURLInteractionSource,
                 message: MessageRowState? = nil,
                 preview: ChatTextPreviewState? = nil) {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            webRoute = ExampleWebRoute(
                title: displayText.isEmpty ? url.absoluteString : displayText,
                url: url
            )
            return
        }
        guard let handler = configProvider().urlInteractionHandler else {
            toast = ChatToastState(
                message: NEChatUIKitSwiftUIBundle.localized("chat_url_open_requires_boundary", value: "Opening links requires a SwiftUI URL handler."),
                style: .info
            )
            return
        }
        let context = message.map(utilityContext(for:)) ?? ChatSessionContext(kind: .history, conversationId: preview?.id ?? "collection")
        handler.handleURLInteraction(
            ChatURLInteractionRequest(
                url: url,
                displayText: displayText,
                source: source,
                message: message,
                preview: preview,
                context: context
            )
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(boundaryResult):
                    switch boundaryResult {
                    case let .route(route):
                        self?.route = route
                    case let .toast(toast):
                        self?.toast = toast
                    default:
                        break
                    }
                case let .failure(error):
                    self?.toast = ChatToastState(
                        message: DemoNetworkPresentation.chatMessage(
                            for: error,
                            fallbackKey: "chat_url_open_failed",
                            fallbackValue: "Open link failed"
                        ),
                        style: .error
                    )
                }
            }
        }
    }

    func clearRoute() {
        route = nil
    }

    func clearPresentedPreview() {
        presentedPreview = nil
    }

    func consumeToast(_ toast: ChatToastState) {
        if self.toast?.id == toast.id {
            self.toast = nil
        }
    }

    func completeForwardSelection(_ selection: ChatForwardSelectionResult?) {
        guard let forwardSelection else {
            return
        }
        let resultToastHandler = forwardToastPresenters.removeValue(forKey: forwardSelection.id)
        self.forwardSelection = nil
        guard let selection, !selection.targets.isEmpty else {
            return
        }
        performForward(
            request: forwardSelection.request,
            selection: selection,
            sourceMessages: forwardSelection.sourceMessages,
            showsSuccessToast: shouldShowForwardSuccessToast(forwardSelection),
            resultToastHandler: resultToastHandler
        )
    }

    private func shouldShowForwardSuccessToast(_ forwardSelection: MineCollectionForwardSelectionState) -> Bool {
        guard forwardSelection.showsSuccessToast else {
            return false
        }
        return true
    }

    private func performForward(request: ChatForwardRequest,
                                selection: ChatForwardSelectionResult,
                                sourceMessages: [V2NIMMessage] = [],
                                showsSuccessToast: Bool,
                                resultToastHandler: ((ChatToastState) -> Void)? = nil) {
        let completion: (Result<ChatOperationResult, Error>) -> Void = { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(operationResult):
                    guard showsSuccessToast else {
                        return
                    }
                    if let message = operationResult.message {
                        self?.presentForwardToast(
                            ChatToastState(message: message, style: .success),
                            using: resultToastHandler
                        )
                    }
                case let .failure(error):
                    let nsError = error as NSError
                    let message: String
                    if nsError.code == protocolSendFailed || nsError.code == protocolTimeout {
                        message = NEChatUIKitSwiftUIBundle.localized("forward_network_error", value: "Network error. Please check your network settings.")
                    } else {
                        message = DemoNetworkPresentation.chatMessage(for: error)
                    }
                    self?.presentForwardToast(ChatToastState(
                        message: message,
                        style: .error
                    ), using: resultToastHandler)
                }
            }
        }

        if sourceMessages.isEmpty {
            operationPerformer.forwardMessages(
                ids: request.messageIds,
                targets: selection.targets,
                comment: selection.comment,
                merged: request.merged,
                sourceConversationId: request.context.conversationId,
                sourceConversationName: request.context.sessionName ?? request.context.title,
                depth: request.depth,
                completion: completion
            )
        } else {
            operationPerformer.forwardMessages(
                messages: sourceMessages,
                targets: selection.targets,
                comment: selection.comment,
                merged: request.merged,
                sourceConversationId: request.context.conversationId,
                sourceConversationName: request.context.sessionName ?? request.context.title,
                depth: request.depth,
                completion: completion
            )
        }
    }

    private func presentForwardToast(_ toast: ChatToastState,
                                     using resultToastHandler: ((ChatToastState) -> Void)?) {
        if let resultToastHandler {
            resultToastHandler(toast)
        } else {
            self.toast = toast
        }
    }

    private func openTextPreview(_ preview: ChatTextPreviewState) {
        guard !preview.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            preview.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        presentedPreview = .text(preview)
    }

    private func utilityContext(for row: MessageRowState) -> ChatSessionContext {
        let conversationId = row.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedConversationId = conversationId?.isEmpty == false ? conversationId ?? Self.defaultTeamConversationId : Self.defaultTeamConversationId
        let chatKind = Self.chatKind(for: resolvedConversationId)
        let resolvedTeamIdForChat = Self.teamId(for: resolvedConversationId) ?? Self.defaultTeamId
        let targetId = Self.teamId(for: resolvedConversationId)
        var context = ChatSessionContext(
            kind: chatKind,
            conversationId: resolvedConversationId,
            sessionId: chatKind == .team ? resolvedTeamIdForChat : targetId
        )
        let sourceName = ExampleForwardSourceNameResolver.displayName(for: context)
        context.title = sourceName
        context.sessionName = sourceName
        return context
    }

    private static func teamId(for conversationId: String) -> String? {
        V2NIMConversationIdUtil.conversationTargetId(conversationId)
    }

    private static func chatKind(for conversationId: String) -> ChatSessionKind {
        switch V2NIMConversationIdUtil.conversationType(conversationId) {
        case .CONVERSATION_TYPE_P2P:
            return .p2p
        case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
            return .team
        default:
            return .history
        }
    }
}

#if DEBUG
struct MineTabRootView_Previews: PreviewProvider {
    static var previews: some View {
        MineTabRootView()
            .environmentObject(PreviewMocks.mockEnvironment(loggedIn: true))
    }
}
#endif
