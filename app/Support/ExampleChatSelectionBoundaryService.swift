// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NEContactUIKitSwiftUI
import NEConversationUIKitSwiftUI
import NETeamUIKitSwiftUI
import NIMSDK
import SwiftUI

enum ExampleForwardSourceNameResolver {
    static func displayName(for context: ChatSessionContext) -> String? {
        let targetId = V2NIMConversationIdUtil.conversationTargetId(context.conversationId)
            ?? context.sessionId
        let identifiers = Set([
            context.conversationId,
            context.sessionId,
            targetId,
        ].compactMap(nonEmpty))
        if let explicitName = [context.sessionName, context.title]
            .compactMap(nonEmpty)
            .first(where: { !identifiers.contains($0) }) {
            return explicitName
        }
        guard let targetId = nonEmpty(targetId) else {
            return nil
        }

        switch V2NIMConversationIdUtil.conversationType(context.conversationId) {
        case .CONVERSATION_TYPE_P2P:
            return nonIdentifierName(
                NEFriendUserCache.shared.getFriendInfo(targetId)?.showName(true),
                identifiers: identifiers
            )
        case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
            let teamType: V2NIMTeamType = V2NIMConversationIdUtil.conversationType(context.conversationId) == .CONVERSATION_TYPE_SUPER_TEAM
                ? .TEAM_TYPE_SUPER
                : .TEAM_TYPE_NORMAL
            var error: NSError?
            let teamName = TeamRepo.shared.getTeamInfoLocal(
                teamId: targetId,
                teamType: teamType,
                error: &error
            )?.name
            return nonIdentifierName(teamName, identifiers: identifiers)
        default:
            return nil
        }
    }

    private static func nonIdentifierName(_ value: String?,
                                          identifiers: Set<String>) -> String? {
        guard let value = nonEmpty(value), !identifiers.contains(value) else {
            return nil
        }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

@MainActor
final class ExampleChatSelectionBoundaryService: ObservableObject {
    static let shared = ExampleChatSelectionBoundaryService()

    @Published var route: ExampleChatSelectionRoute?

    private var mentionCompletions = [String: (Result<ChatMentionSelectionResult, Error>) -> Void]()
    private var discussCompletions = [String: (Result<ChatP2PDiscussSelectionResult, Error>) -> Void]()
    private var forwardCompletions = [String: (Result<ChatForwardSelectionResult, Error>) -> Void]()
    private var teamInviteCompletions = [String: (Result<TeamMemberInviteSelectionResult, Error>) -> Void]()

    private init() {}

    var mentionSelectionHandler: ChatMentionSelectionHandling {
        ChatMentionSelectionHandler { [weak self] request, completion in
            Task { @MainActor in
                let route = ExampleChatSelectionRoute.mention(request)
                self?.mentionCompletions[route.id] = completion
                self?.route = route
            }
        }
    }

    var p2pDiscussSelectionHandler: ChatP2PDiscussSelectionHandling {
        ExampleChatP2PDiscussSelectionHandler { [weak self] request, completion in
            Task { @MainActor in
                let route = ExampleChatSelectionRoute.p2pDiscuss(request)
                self?.discussCompletions[route.id] = completion
                self?.route = route
            }
        }
    }

    var forwardSelectionHandler: ChatForwardSelectionHandling {
        ChatForwardSelectionHandler { [weak self] request, completion in
            Task { @MainActor in
                let route = ExampleChatSelectionRoute.forward(request)
                self?.forwardCompletions[route.id] = completion
                self?.route = route
            }
        }
    }

    var teamMemberInviteSelectionHandler: TeamMemberInviteSelectionHandling {
        TeamMemberInviteSelectionHandler { [weak self] request, completion in
            Task { @MainActor in
                let route = ExampleChatSelectionRoute.teamInvite(request)
                self?.teamInviteCompletions[route.id] = completion
                self?.route = route
            }
        }
    }

    func completeMention(routeId: String, result: ChatMentionSelectionResult?) {
        let completion = mentionCompletions.removeValue(forKey: routeId)
        if route?.id == routeId {
            route = nil
        }
        DispatchQueue.main.async {
            completion?(.success(result ?? ChatMentionSelectionResult(targets: [])))
        }
    }

    func completeDiscuss(routeId: String, result: ChatP2PDiscussSelectionResult?) {
        discussCompletions.removeValue(forKey: routeId)?(.success(result ?? ChatP2PDiscussSelectionResult(selectedAccountIds: [])))
        if route?.id == routeId {
            route = nil
        }
    }

    func completeForward(routeId: String, result: ChatForwardSelectionResult?) {
        let completion = forwardCompletions.removeValue(forKey: routeId)
        if route?.id == routeId {
            route = nil
        }
        DispatchQueue.main.async {
            completion?(.success(result ?? ChatForwardSelectionResult(targets: [])))
        }
    }

    func completeTeamInvite(routeId: String, result: TeamMemberInviteSelectionResult?) {
        teamInviteCompletions.removeValue(forKey: routeId)?(.success(result ?? .cancelled))
        if route?.id == routeId {
            route = nil
        }
    }

    func cancelCurrentRoute() {
        guard let route else {
            return
        }
        switch route {
        case .mention:
            completeMention(routeId: route.id, result: nil)
        case .p2pDiscuss:
            completeDiscuss(routeId: route.id, result: nil)
        case .forward:
            completeForward(routeId: route.id, result: nil)
        case .teamInvite:
            completeTeamInvite(routeId: route.id, result: nil)
        }
    }
}

enum ExampleChatSelectionRoute: Identifiable, Equatable {
    case mention(ChatMentionSelectionRequest, id: String = UUID().uuidString)
    case p2pDiscuss(ChatP2PDiscussSelectionRequest, id: String = UUID().uuidString)
    case forward(ChatForwardRequest, id: String = UUID().uuidString)
    case teamInvite(TeamMemberInviteSelectionRequest, id: String = UUID().uuidString)

    var id: String {
        switch self {
        case let .mention(_, id), let .p2pDiscuss(_, id), let .forward(_, id), let .teamInvite(_, id):
            return id
        }
    }
}

private struct ExampleChatP2PDiscussSelectionHandler: ChatP2PDiscussSelectionHandling {
    private let handler: (ChatP2PDiscussSelectionRequest, @escaping (Result<ChatP2PDiscussSelectionResult, Error>) -> Void) -> Void

    init(_ handler: @escaping (ChatP2PDiscussSelectionRequest, @escaping (Result<ChatP2PDiscussSelectionResult, Error>) -> Void) -> Void) {
        self.handler = handler
    }

    func selectDiscussMembers(request: ChatP2PDiscussSelectionRequest,
                              completion: @escaping (Result<ChatP2PDiscussSelectionResult, Error>) -> Void) {
        handler(request, completion)
    }
}

struct ExampleChatSelectionDestinationView: View {
    var route: ExampleChatSelectionRoute
    var chatToken: ChatThemeToken
    var service: ExampleChatSelectionBoundaryService

    var body: some View {
        switch route {
        case let .mention(request, id):
            mentionSelectionView(request: request, routeId: id)
        case let .p2pDiscuss(request, id):
            discussSelectionView(request: request, routeId: id)
        case let .forward(request, id):
            forwardSelectionView(request: request, routeId: id)
        case let .teamInvite(request, id):
            teamInviteSelectionView(request: request, routeId: id)
        }
    }

    private func mentionSelectionView(request: ChatMentionSelectionRequest,
                                      routeId: String) -> AnyView {
        switch request.source {
        case .teamMembers:
            return AnyView(
                ExampleTeamMentionSelectionView(
                    routeId: routeId,
                    request: request,
                    token: teamToken
                ) { result in
                    service.completeMention(routeId: routeId, result: result)
                }
                .toolbar(.hidden, for: .tabBar)
            )
        case .aiUsers:
            return AnyView(
                ExampleAIMentionSelectionView(
                    routeId: routeId,
                    chatToken: chatToken
                ) { result in
                    service.completeMention(routeId: routeId, result: result)
                }
                .toolbar(.hidden, for: .tabBar)
            )
        }
    }

    private func discussSelectionView(request: ChatP2PDiscussSelectionRequest,
                                      routeId: String) -> some View {
        ContactSelectionView(
            viewModel: ContactSelectionViewModel(
                context: ContactSelectionContext(
                    title: NEContactUIKitSwiftUIBundle.localized("select", value: "Select"),
                    filterAccountIds: Set(request.filterAccountIds + [request.peerAccountId, IMKitClient.instance.account()]),
                    limit: request.limit,
                    allowsAIUsers: request.allowsAIUser
                )
            ),
            token: contactToken,
            dismissOnComplete: false
        ) { result in
            service.completeDiscuss(
                routeId: routeId,
                result: ChatP2PDiscussSelectionResult(
                    selectedAccountIds: result.accountIds,
                    selectedNames: result.names.split(separator: "、").map(String.init)
                )
            )
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func forwardSelectionView(request: ChatForwardRequest,
                                      routeId: String) -> some View {
        ExampleForwardSelectionView(
            routeId: routeId,
            request: request,
            token: conversationToken
        ) { result in
            service.completeForward(routeId: routeId, result: result)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func teamInviteSelectionView(request: TeamMemberInviteSelectionRequest,
                                         routeId: String) -> some View {
        ContactSelectionView(
            viewModel: ContactSelectionViewModel(
                context: ContactSelectionContext(
                    title: NETeamUIKitSwiftUIBundle.localized("invite_member", value: "Invite Member"),
                    filterAccountIds: Set(request.existingAccountIds + [IMKitClient.instance.account()]),
                    limit: min(request.remainingInviteCount, inviteNumberLimit),
                    allowsAIUsers: request.allowsAIUserInvite
                )
            ),
            token: contactToken,
            dismissOnComplete: false
        ) { result in
            service.completeTeamInvite(
                routeId: routeId,
                result: .selected(accountIds: result.accountIds)
            )
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var contactToken: ContactThemeToken {
        chatToken.styleMode == .fun ? .fun : .normal
    }

    private var conversationToken: ConversationThemeToken {
        chatToken.styleMode == .fun ? .fun : .normal
    }

    private var teamToken: NETeamThemeToken {
        chatToken.styleMode == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default
    }
}

struct ExampleForwardSelectionView: View {
    private let selectionLimit = 9

    var routeId: String
    var request: ChatForwardRequest
    var token: ConversationThemeToken
    var onComplete: (ChatForwardSelectionResult?) -> Void

    @StateObject private var viewModel = ExampleForwardSelectionViewModel()
    @State private var pendingForwardRoute: ConversationRouteContext?
    @State private var pendingForwardRow: ExampleForwardSelectionRow?
    @State private var pendingForwardRows = [ExampleForwardSelectionRow]()
    @State private var isMultiSelecting = false
    @State private var selectedRows = [ExampleForwardSelectionRow]()
    @State private var forwardComment = ""
    @State private var showsSelectedRows = false

    var body: some View {
        ZStack(alignment: .top) {
            token.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                searchField
                selectedForwardStrip
                recentForwardStrip
                tabs
                content
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // The UIKit selector keeps its navigation controls pinned when the
        // search field becomes first responder.  The keyboard only covers the
        // result list; it must not move the title bar outside the screen.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            viewModel.load()
        }
        .neCommonTransientOverlay(viewModel.toast, placement: .top, topPadding: 52, onDismiss: { viewModel.consumeToast($0) }) { toast in
            Text(toast.message)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .overlay {
            if let pendingForwardRow, pendingForwardRoute != nil {
                ExampleForwardConfirmOverlay(
                    rows: [pendingForwardRow],
                    request: request,
                    token: token,
                    comment: $forwardComment,
                    onCancel: {
                        pendingForwardRoute = nil
                        self.pendingForwardRow = nil
                        forwardComment = ""
                    },
                    onSend: {
                        sendPendingForward()
                    }
                )
            } else if !pendingForwardRows.isEmpty {
                ExampleForwardConfirmOverlay(
                    rows: pendingForwardRows,
                    request: request,
                    token: token,
                    comment: $forwardComment,
                    onCancel: {
                        pendingForwardRows = []
                        forwardComment = ""
                    },
                    onSend: {
                        sendPendingForward()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showsSelectedRows) {
            ExampleForwardSelectedRowsView(
                rows: selectedRows,
                token: token,
                onRemove: { row in
                    selectedRows.removeAll { $0.route.conversationId == row.route.conversationId }
                }
            )
        }
    }

    private var titleBar: some View {
        ZStack {
            HStack {
                Button {
                    finish(nil)
                } label: {
                    Text(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"))
                        .font(.system(size: 16))
                        .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.greyText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if isMultiSelecting {
                    Button {
                        confirmSelectedRows()
                    } label: {
                        Text(sureButtonTitle)
                            .font(.system(size: 16))
                            .foregroundColor(selectedRows.isEmpty ? token.tertiaryTextColor : token.accentColor)
                            .frame(minWidth: 76, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedRows.isEmpty)
                    .accessibilityIdentifier("id.sureButton")
                } else {
                    Button {
                        isMultiSelecting = true
                    } label: {
                        Text(NEContactUIKitSwiftUIBundle.localized("multi_select", value: "Multi-select"))
                            .font(.system(size: 16))
                            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.greyText)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("id.multiSelect")
                }
            }
            .padding(.horizontal, 16)

            Text(NEContactUIKitSwiftUIBundle.localized("select", value: "Select"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(token.primaryTextColor)
                .lineLimit(1)
        }
        .frame(height: 50)
        .background(token.navigationBackground)
    }

    private var searchField: some View {
        NECommonSearchFieldView(
            text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            ),
            placeholder: NECommonUIKitSwiftUIBundle.localized("search", fallback: "Search"),
            height: 32,
            horizontalPadding: 12,
            onClear: { viewModel.clearQuery() }
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .neCommonTheme(exampleForwardSearchTheme)
        .background(token.navigationBackground)
    }

    @ViewBuilder
    private var selectedForwardStrip: some View {
        if isMultiSelecting, !selectedRows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(selectedRows) { row in
                            NECommonAvatarView(
                                imageURL: row.avatarURL,
                                initials: row.initials,
                                size: 36,
                                cornerRadius: token.avatarCornerRadius,
                                hashID: row.hashID
                            )
                            .neCommonTheme(exampleForwardCommonTheme)
                            .frame(width: 46, height: 59)
                        }
                    }
                    .padding(.horizontal, 5)
            }
            .padding(.trailing, 30)
            .contentShape(Rectangle())
            .onTapGesture { showsSelectedRows = true }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(token.tertiaryTextColor)
                    .frame(width: 30, height: 59)
                    .allowsHitTesting(false)
            }
            .frame(height: 59)
            .padding(.horizontal, 20)
            .background(token.navigationBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(token.rowSeparatorColor)
                    .frame(height: 3)
                    .padding(.horizontal, -20)
            }
        }
    }

    @ViewBuilder
    private var recentForwardStrip: some View {
        if !viewModel.recentForwardRows.isEmpty && viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(NEContactUIKitSwiftUIBundle.localized("recent_forward", value: "Forwarded"))
                    .font(.system(size: 12))
                    .foregroundColor(token.tertiaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.recentForwardRows) { row in
                            Button {
                                if isMultiSelecting {
                                    toggleSelection(row)
                                } else {
                                    pendingForwardRoute = row.route
                                    pendingForwardRow = row
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
                                        NECommonAvatarView(
                                            imageURL: row.avatarURL,
                                            initials: row.initials,
                                            size: 40,
                                            cornerRadius: token.avatarCornerRadius,
                                            hashID: row.hashID
                                        )
                                        .neCommonTheme(exampleForwardCommonTheme)

                                        if isMultiSelecting {
                                            ExampleForwardSelectionIndicator(isSelected: isSelected(row), token: token)
                                                .background(Color.white, in: Circle())
                                                .offset(x: 3, y: 3)
                                        }
                                    }
                                    .frame(width: 46, height: 46)

                                    Text(row.title)
                                        .font(.system(size: 12))
                                        .foregroundColor(token.primaryTextColor)
                                        .lineLimit(1)
                                        .frame(width: 64)
                                }
                                .frame(width: 72, height: 72, alignment: .top)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(token.navigationBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(token.rowSeparatorColor)
                    .frame(height: 3)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.availableTabs) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(viewModel.selectedTab == tab ? token.accentColor : token.primaryTextColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? token.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 48)
            }
        }
        .background(token.navigationBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(token.rowSeparatorColor)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .neCommonTheme(exampleForwardCommonTheme)
        case let .failed(message):
            NECommonErrorStateView(
                state: NECommonErrorState(textKey: "network_error", fallbackText: message, severity: .warning, retryable: true),
                retry: { viewModel.load() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .neCommonTheme(exampleForwardCommonTheme)
        case .loaded:
            forwardTabContent(viewModel.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func forwardTabContent(_ tab: ExampleForwardSelectionTab) -> some View {
        let rows = viewModel.visibleRows(for: tab)
        if rows.isEmpty {
            forwardEmptyState(for: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            if isMultiSelecting {
                                toggleSelection(row)
                            } else {
                                pendingForwardRoute = row.route
                                pendingForwardRow = row
                            }
                        } label: {
                            ExampleForwardSelectionRowView(
                                row: row,
                                token: token,
                                showsSelection: isMultiSelecting,
                                isSelected: isSelected(row)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(token.pageBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sureButtonTitle: String {
        let title = NECommonUIKitSwiftUIBundle.localized("sure", fallback: "OK")
        guard !selectedRows.isEmpty else {
            return title
        }
        return "\(title)(\(selectedRows.count))"
    }

    private func toggleSelection(_ row: ExampleForwardSelectionRow) {
        if let index = selectedRows.firstIndex(where: { $0.route.conversationId == row.route.conversationId }) {
            selectedRows.remove(at: index)
        } else if selectedRows.count >= selectionLimit {
            viewModel.showSelectionLimitToast(selectionLimit)
        } else {
            selectedRows.append(row)
        }
    }

    private func isSelected(_ row: ExampleForwardSelectionRow) -> Bool {
        selectedRows.contains { $0.route.conversationId == row.route.conversationId }
    }

    private func confirmSelectedRows() {
        guard !selectedRows.isEmpty else {
            return
        }
        pendingForwardRows = selectedRows
    }

    private func sendPendingForward() {
        guard DemoNetworkPresentation.allowsNetworkOperation else {
            viewModel.toast = NECommonToast(message: DemoNetworkPresentation.networkMessage())
            return
        }
        if let row = pendingForwardRow {
            finish(row, comment: forwardComment)
        } else {
            finish(pendingForwardRows, comment: forwardComment)
        }
    }

    @ViewBuilder
    private func forwardEmptyState(for tab: ExampleForwardSelectionTab) -> some View {
        let query = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            NECommonEmptyStateView(
                state: NECommonEmptyState(
                    titleKey: emptyTitleKey(for: tab),
                    fallbackTitle: emptyTitle(for: tab),
                    imageKind: .user
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .neCommonTheme(exampleForwardCommonTheme)
        } else {
            VStack(spacing: 12) {
                Image(NECommonPlaceholderImage.emptyImageName(kind: .user, styleMode: exampleForwardCommonTheme.styleMode),
                      bundle: NECommonUIKitSwiftUIBundle.bundle)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 122, height: 91)

                Text(highlightedNoSearchResult(query))
                    .font(.system(size: 14))
                    .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.emptyTitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 176)
            .padding(.horizontal, 20)
        }
    }

    private func emptyTitleKey(for tab: ExampleForwardSelectionTab) -> String {
        switch tab {
        case .friends:
            return "forward_no_friends"
        case .teams:
            return "forward_no_teams"
        case .recent:
            return "user_empty"
        }
    }

    private func emptyTitle(for tab: ExampleForwardSelectionTab) -> String {
        switch tab {
        case .friends:
            return localizable("forward_no_friends")
        case .teams:
            return localizable("forward_no_teams")
        case .recent:
            return NEContactUIKitSwiftUIBundle.localized("user_not_exist", value: "User not found")
        }
    }

    private func finish(_ row: ExampleForwardSelectionRow?, comment: String? = nil) {
        guard let row else {
            onComplete(nil)
            return
        }
        finish([row], comment: comment)
    }

    private func finish(_ rows: [ExampleForwardSelectionRow], comment: String? = nil) {
        guard !rows.isEmpty else {
            onComplete(nil)
            return
        }
        SettingRepo.shared.updateRecentForward(rows.map(\.route.conversationId))
        onComplete(ChatForwardSelectionResult(targets: rows.map { row in
            ChatForwardTargetState(
                conversationId: row.route.conversationId,
                title: row.route.title,
                avatarName: row.initials,
                avatarURL: row.avatarURL
            )
        }, comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func highlightedNoSearchResult(_ query: String) -> AttributedString {
        let format = NECommonUIKitSwiftUIBundle.localized(
            "no_search_result",
            fallback: "No results related to \"%@\""
        )
        var result = AttributedString(String(format: format, query))
        if let range = result.range(of: query) {
            result[range].foregroundColor = token.accentColor
        }
        return result
    }

    private var exampleForwardCommonTheme: NECommonThemeToken {
        ExampleForwardSelectionTheme.commonTheme(for: token)
    }

    private var exampleForwardSearchTheme: NECommonThemeToken {
        ExampleForwardSelectionTheme.searchTheme(for: token)
    }
}

private struct ExampleForwardSelectedRowsView: View {
    var rows: [ExampleForwardSelectionRow]
    var token: ConversationThemeToken
    var onRemove: (ExampleForwardSelectionRow) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(token.primaryTextColor)
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .buttonStyle(.plain)
                    .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("back", value: "Back"))
                    Spacer()
                }
                .padding(.horizontal, 20)

                Text(NEContactUIKitSwiftUIBundle.localized("selected", value: "Selected"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(token.primaryTextColor)
            }
            .frame(height: 58)
            .background(token.navigationBackground)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                HStack(spacing: 12) {
                    NECommonAvatarView(
                        imageURL: row.avatarURL,
                        initials: row.initials,
                        size: 40,
                        cornerRadius: token.avatarCornerRadius,
                        hashID: row.hashID
                    )
                    .neCommonTheme(ExampleForwardSelectionTheme.commonTheme(for: token))
                    HStack(spacing: 0) {
                        Text(row.title)
                            .font(.system(size: 16))
                            .foregroundColor(token.primaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        if row.memberCount > 0 {
                            Text(" (\(row.memberCount))")
                                .font(.system(size: 16))
                                .foregroundColor(token.secondaryTextColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    Spacer()
                    Button {
                        onRemove(row)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(token.tertiaryTextColor)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 62)
                .padding(.horizontal, 20)
                .background(token.rowBackground)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(token.rowSeparatorColor)
                        .frame(height: 1)
                }
                    }
                }
            }
            .background(token.pageBackground)
        }
        .background(token.pageBackground.ignoresSafeArea())
    }
}

private struct ExampleForwardConfirmOverlay: View {
    var rows: [ExampleForwardSelectionRow]
    var request: ChatForwardRequest
    var token: ConversationThemeToken
    @Binding var comment: String
    var onCancel: () -> Void
    var onSend: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 0) {
                Text(NEChatUIKitSwiftUIBundle.localized("send_to", value: "Send to"))
                    .font(.system(size: 16))
                    .foregroundColor(token.primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                forwardTargetsView
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Text(forwardContentText)
                    .font(.system(size: 14))
                    .foregroundColor(token.primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: 0xF2F4F5), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                TextField(
                    NEChatUIKitSwiftUIBundle.localized("leave_message", value: "Leave a message"),
                    text: $comment
                )
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(hex: 0xE1E6E8), lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .accessibilityIdentifier("id.messageInput")

                Spacer(minLength: 0)

                Rectangle()
                    .fill(Color(hex: 0xE1E6E8))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text(NECommonUIKitSwiftUIBundle.localized("cancel", fallback: "Cancel"))
                            .font(.system(size: 16))
                            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.greyText)
                            .frame(maxWidth: .infinity, minHeight: 51)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("id.forwardCancelBtn")

                    Rectangle()
                        .fill(Color(hex: 0xE1E6E8))
                        .frame(width: 1, height: 51)

                    Button(action: onSend) {
                        Text(NEChatUIKitSwiftUIBundle.localized("send", value: "Send"))
                            .font(.system(size: 16))
                            .foregroundColor(token.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 51)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("id.forwardSendBtn")
                }
            }
            .frame(width: 276, height: 250)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var displayTitle: String {
        if rows.count > 1 {
            return rows.map(\.confirmationTitle).joined(separator: "、")
        }
        return rows.first?.confirmationTitle
            ?? NEChatUIKitSwiftUIBundle.localized("chat_forward_target", value: "Forward target")
    }

    private var displayTargetId: String {
        guard let route = rows.first?.route else {
            return "forward"
        }
        guard let targetId = route.targetId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetId.isEmpty else {
            return route.conversationId
        }
        return targetId
    }

    private var displayAvatarURL: URL? {
        rows.count == 1 ? rows.first?.avatarURL : nil
    }

    @ViewBuilder
    private var forwardTargetsView: some View {
        if rows.count == 1 {
            HStack(spacing: 8) {
                NECommonAvatarView(
                    imageURL: displayAvatarURL,
                    initials: rows.first?.initials ?? displayTargetId,
                    size: 32,
                    cornerRadius: token.avatarCornerRadius,
                    hashID: displayTargetId
                )
                .neCommonTheme(ExampleForwardSelectionTheme.commonTheme(for: token))

                Text(displayTitle)
                    .font(.system(size: 14))
                    .foregroundColor(token.primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9.5) {
                    ForEach(rows) { row in
                        NECommonAvatarView(
                            imageURL: row.avatarURL,
                            initials: row.initials,
                            size: 32,
                            cornerRadius: token.avatarCornerRadius,
                            hashID: row.hashID
                        )
                        .neCommonTheme(ExampleForwardSelectionTheme.commonTheme(for: token))
                    }
                }
            }
        }
    }

    private var forwardContentText: String {
        let type: String
        if request.merged {
            type = NEChatUIKitSwiftUIBundle.localized("chat_forward_merged", value: "Merged Forward")
        } else if request.isFromMessageMultiSelect {
            type = NEChatUIKitSwiftUIBundle.localized("chat_forward_one_by_one", value: "Forward One by One")
        } else {
            type = NEChatUIKitSwiftUIBundle.localized("operation_forward", value: "Forward")
        }
        let record = NEChatUIKitSwiftUIBundle.localized("session_record", value: "`s chat history")
        let source = ExampleForwardSourceNameResolver.displayName(for: request.context)
            ?? NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History")
        return "[\(type)]\(source)\(record)"
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private enum ExampleForwardSelectionTab: String, CaseIterable, Identifiable {
    case recent
    case friends
    case teams

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return NEContactUIKitSwiftUIBundle.localized("recent_session", value: "Recent")
        case .friends:
            return NEContactUIKitSwiftUIBundle.localized("my_friends", value: "Friends")
        case .teams:
            return NEContactUIKitSwiftUIBundle.localized("my_teams", value: "My Groups")
        }
    }
}

private struct ExampleForwardSelectionRow: Identifiable, Equatable {
    var id: String
    var route: ConversationRouteContext
    var title: String
    var subtitle: String?
    var memberCount: Int
    var avatarURL: URL?
    var initials: String
    var hashID: String
    var sortOrder: Int64

    var confirmationTitle: String {
        let identifiers = Set([route.targetId, route.conversationId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        let candidates = [route.title, title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !identifiers.contains($0) }
        if let name = candidates.first {
            return name
        }
        if route.kind == .p2p,
           let accountId = route.targetId,
           let user = NEFriendUserCache.shared.getFriendInfo(accountId),
           let alias = user.showName(true)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !alias.isEmpty,
           !identifiers.contains(alias) {
            return alias
        }
        return NEChatUIKitSwiftUIBundle.localized("chat_forward_target", value: "Forward target")
    }
}

private struct ExampleForwardSelectionRowView: View {
    var row: ExampleForwardSelectionRow
    var token: ConversationThemeToken
    var showsSelection: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if showsSelection {
                ExampleForwardSelectionIndicator(isSelected: isSelected, token: token)
                    .frame(width: 24)
            }

            NECommonAvatarView(
                imageURL: row.avatarURL,
                initials: row.initials,
                size: token.avatarSize,
                cornerRadius: token.avatarCornerRadius,
                hashID: row.hashID
            )
            .neCommonTheme(ExampleForwardSelectionTheme.commonTheme(for: token))

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: token.styleMode == .fun ? 17 : 14))
                    .foregroundColor(token.primaryTextColor)
                    .lineLimit(1)
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(token.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            if row.memberCount > 0 {
                Text("(\(row.memberCount))")
                    .font(.system(size: 14))
                    .foregroundColor(token.secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .frame(height: token.styleMode == .fun ? 64 : 56)
        .padding(.leading, token.rowHorizontalPadding)
        .padding(.trailing, 16)
        .background(token.rowBackground)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(token.rowSeparatorColor)
                .frame(height: token.styleMode == .fun ? 0.5 : 1)
                .padding(.leading, token.rowHorizontalPadding + token.avatarSize + 12)
        }
    }
}

private struct ExampleForwardSelectionIndicator: View {
    var isSelected: Bool
    var token: ConversationThemeToken

    var body: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? token.accentColor : token.tertiaryTextColor, lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if isSelected {
                Circle()
                    .fill(token.accentColor)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(isSelected ? "selected" : "unselected")
    }
}

private enum ExampleForwardSelectionTheme {
    static func commonTheme(for token: ConversationThemeToken) -> NECommonThemeToken {
        var commonToken = token.styleMode == .fun ? NECommonThemeToken.fun : NECommonThemeToken.normal
        commonToken.palette = NECommonThemePalette(
            pageBackground: token.pageBackground,
            rowBackground: token.rowBackground,
            elevatedBackground: token.rowBackground,
            primaryText: token.primaryTextColor,
            secondaryText: token.secondaryTextColor,
            tertiaryText: token.tertiaryTextColor,
            accent: token.accentColor,
            destructive: token.destructiveColor,
            warning: token.destructiveColor,
            separator: token.rowSeparatorColor,
            disabled: token.rowSeparatorColor.opacity(0.72)
        )
        commonToken.badge = NECommonBadgeToken(
            background: token.unreadBackgroundColor,
            foreground: token.unreadTextColor,
            minSize: token.unreadMinHeight
        )
        commonToken.avatar = NECommonAvatarToken(
            size: token.avatarSize,
            cornerRadius: token.avatarCornerRadius,
            background: token.accentColor,
            foreground: .white
        )
        commonToken.overlay = NECommonOverlayToken(
            toastBackground: Color.black.opacity(0.78),
            toastForeground: .white,
            scrim: Color.black.opacity(0.18),
            cornerRadius: 8
        )
        return commonToken
    }

    static func searchTheme(for token: ConversationThemeToken) -> NECommonThemeToken {
        var commonToken = commonTheme(for: token)
        commonToken.palette.rowBackground = token.searchBackground
        commonToken.palette.elevatedBackground = token.searchBackground
        return commonToken
    }
}

@MainActor
private final class ExampleForwardSelectionViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var selectedTab: ExampleForwardSelectionTab = .recent
    @Published var query = ""
    @Published var toast: NECommonToast?

    private var recentRows = [ExampleForwardSelectionRow]()
    private var friendRows = [ExampleForwardSelectionRow]()
    private var teamRows = [ExampleForwardSelectionRow]()
    private var didLoad = false
    private let pageSize = 100

    var availableTabs: [ExampleForwardSelectionTab] {
        IMKitConfigCenter.shared.enableTeam
            ? ExampleForwardSelectionTab.allCases
            : [.recent, .friends]
    }

    var visibleRows: [ExampleForwardSelectionRow] {
        visibleRows(for: selectedTab)
    }

    func visibleRows(for tab: ExampleForwardSelectionTab) -> [ExampleForwardSelectionRow] {
        let source: [ExampleForwardSelectionRow]
        switch tab {
        case .recent:
            source = recentRows
        case .friends:
            source = friendRows
        case .teams:
            source = teamRows
        }
        return filter(rows: source)
    }

    var recentForwardRows: [ExampleForwardSelectionRow] {
        let recentForwardIds = SettingRepo.shared.getRecentForward() ?? []
        let rowsByConversationId = Dictionary(
            recentRows.map { ($0.route.conversationId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return recentForwardIds.compactMap { rowsByConversationId[$0] }
    }

    func load() {
        guard !didLoad else {
            return
        }
        didLoad = true
        phase = .loading
        if selectedTab == .teams, !availableTabs.contains(.teams) {
            selectedTab = .recent
        }

        loadAllDataLikeUIKit()
    }

    func updateQuery(_ text: String) {
        query = text
    }

    func clearQuery() {
        query = ""
    }

    func consumeToast(_ toast: NECommonToast) {
        if self.toast?.id == toast.id {
            self.toast = nil
        }
    }

    func showSelectionLimitToast(_ limit: Int) {
        toast = NECommonToast(message: String(
            format: NEContactUIKitSwiftUIBundle.localized("choose_max_limit", value: "You can select up to %d"),
            limit
        ))
    }

    private func loadFriends(_ completion: @escaping ([ExampleForwardSelectionRow], NSError?) -> Void) {
        let finish: ([NEUserWithFriend], NSError?) -> Void = { friends, error in
            let rows = friends.compactMap { user -> ExampleForwardSelectionRow? in
                guard let accountId = user.user?.accountId ?? user.friend?.accountId,
                      !NEFriendUserCache.shared.isBlockAccount(accountId),
                      let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
                    return nil
                }
                let title = user.showName(true) ?? accountId
                let avatarName = user.showName(false) ?? accountId
                return ExampleForwardSelectionRow(
                    id: "friend.\(accountId)",
                    route: ConversationRouteContext(
                        conversationId: conversationId,
                        targetId: accountId,
                        kind: .p2p,
                        title: title
	                    ),
	                    title: title,
	                    subtitle: nil,
	                    memberCount: 0,
	                    avatarURL: NECommonAvatarDisplayResolver.url(from: user.user?.avatar),
                    initials: NECommonAvatarDisplayResolver.initials(displayName: avatarName, fallbackID: accountId),
                    hashID: accountId,
                    sortOrder: 0
                )
            }
            let contactOrder = ContactSectionBuilder.groupedFriendSections(
                friends: friends,
                onlineStatus: [:],
                selectedAccountIds: [],
                disabledAccountIds: []
            )
            .flatMap(\.entries)
            .compactMap(\.accountId)
            let rowsByAccountId = Dictionary(rows.map { ($0.route.targetId ?? "", $0) }, uniquingKeysWith: { first, _ in first })
            let orderedRows = contactOrder.compactMap { rowsByAccountId[$0] }
            completion(orderedRows, error)
        }

        if !NEFriendUserCache.shared.isEmpty() {
            finish(NEFriendUserCache.shared.getFriendListNotInBlocklist().map(\.value), nil)
            return
        }

        ContactRepo.shared.getContactList { friends, error in
            finish(friends ?? [], error)
        }
    }

    private func loadAllDataLikeUIKit() {
        if IMKitConfigCenter.shared.enableTeam {
            loadTeams { [weak self] rows, error in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.teamRows = rows
                    if let error {
                        self.completeLoad(error)
                        return
                    }
                    self.loadFriendsLikeUIKit()
                }
            }
        } else {
            teamRows = []
            loadFriendsLikeUIKit()
        }
    }

    private func loadFriendsLikeUIKit() {
        loadFriends { [weak self] rows, error in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.friendRows = rows
                if let error {
                    self.completeLoad(error)
                    return
                }
                self.loadRecentConversationsLikeUIKit()
            }
        }
    }

    private func loadRecentConversationsLikeUIKit() {
        loadRecentConversations { [weak self] rows, error in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.recentRows = rows
                self.completeLoad(error)
            }
        }
    }

    private func completeLoad(_ error: NSError?) {
        recentRows = enrichRecentRows(recentRows)
        phase = .loaded
        if let error {
            toast = NECommonToast(message: Self.errorMessage(for: error))
        }
    }

    private func loadTeams(_ completion: @escaping ([ExampleForwardSelectionRow], NSError?) -> Void) {
        TeamRepo.shared.getTeamList { teams, error in
            let rows = (teams ?? [])
                .sorted { $0.createTime > $1.createTime }
                .compactMap { team -> ExampleForwardSelectionRow? in
                    let teamId = team.teamId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !teamId.isEmpty,
                          let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) else {
                        return nil
                    }
                    let trimmedName = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = trimmedName.isEmpty ? teamId : trimmedName
                    return ExampleForwardSelectionRow(
                        id: "team.\(teamId)",
                        route: ConversationRouteContext(
                            conversationId: conversationId,
                            targetId: teamId,
                            kind: .team,
                            title: title
	                        ),
	                        title: title,
	                        subtitle: nil,
	                        memberCount: Int(team.memberCount),
	                        avatarURL: NECommonAvatarDisplayResolver.url(from: team.avatar),
                        initials: NECommonAvatarDisplayResolver.initials(displayName: title, fallbackID: teamId),
                        hashID: teamId,
                        sortOrder: Int64(team.createTime)
                    )
                }
            completion(rows, error as NSError?)
        }
    }

    private func loadRecentConversations(_ completion: @escaping ([ExampleForwardSelectionRow], NSError?) -> Void) {
        if NIMSDK.shared().v2Option?.enableV2CloudConversation == false {
            LocalConversationRepo.shared.getConversationList(0, pageSize) { conversations, _, _, error in
                completion((conversations ?? []).compactMap(Self.row(from:)), error)
            }
        } else {
            ConversationRepo.shared.getConversationList(0, pageSize) { conversations, _, _, error in
                completion((conversations ?? []).compactMap(Self.row(from:)), error)
            }
        }
    }

    private static func row(from conversation: V2NIMConversation) -> ExampleForwardSelectionRow? {
        row(
            conversationId: conversation.conversationId,
            type: conversation.type,
            title: conversation.name,
            shortName: conversation.shortName(),
            avatar: conversation.avatar,
            sortOrder: conversation.sortOrder
        )
    }

    private static func row(from conversation: V2NIMLocalConversation) -> ExampleForwardSelectionRow? {
        row(
            conversationId: conversation.conversationId,
            type: conversation.type,
            title: conversation.name,
            shortName: conversation.shortName(),
            avatar: conversation.avatar,
            sortOrder: conversation.sortOrder
        )
    }

    private static func row(conversationId: String,
                            type: V2NIMConversationType,
                            title: String?,
                            shortName: String?,
                            avatar: String?,
                            sortOrder: Int64) -> ExampleForwardSelectionRow? {
        guard let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId) else {
            return nil
        }
        let kind: ChatSessionKind
        switch type {
        case .CONVERSATION_TYPE_P2P:
            kind = .p2p
        case .CONVERSATION_TYPE_TEAM:
            kind = .team
        default:
            return nil
        }
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title ?? targetId
            : targetId
        let avatarName = kind == .p2p ? targetId : shortName ?? resolvedTitle
        return ExampleForwardSelectionRow(
            id: "recent.\(conversationId)",
            route: ConversationRouteContext(
                conversationId: conversationId,
                targetId: targetId,
                kind: kind,
                title: resolvedTitle
	            ),
	            title: resolvedTitle,
	            subtitle: nil,
	            memberCount: 0,
	            avatarURL: NECommonAvatarDisplayResolver.url(from: avatar),
            initials: NECommonAvatarDisplayResolver.initials(displayName: avatarName, fallbackID: targetId),
            hashID: targetId,
            sortOrder: sortOrder
        )
    }

    private func enrichRecentRows(_ rows: [ExampleForwardSelectionRow]) -> [ExampleForwardSelectionRow] {
        rows.map { row in
            guard let targetId = row.route.targetId else {
                return row
            }
            switch row.route.kind {
            case .p2p:
                guard let user = NEFriendUserCache.shared.getFriendInfo(targetId) else {
                    return row
                }
                var next = row
                let title = user.showName(true) ?? row.title
                next.title = title
                next.route.title = title
                next.avatarURL = NECommonAvatarDisplayResolver.url(from: user.user?.avatar) ?? row.avatarURL
                next.initials = NECommonAvatarDisplayResolver.initials(
                    displayName: user.showName(false),
                    fallbackID: targetId
                )
                return next
            case .team:
                guard let team = teamRows.first(where: { $0.route.targetId == targetId }) else {
                    return row
                }
                var next = row
                next.title = team.title
                next.route.title = team.title
                next.avatarURL = team.avatarURL ?? row.avatarURL
                next.initials = team.initials
                next.memberCount = team.memberCount
                return next
            case .botSubSession, .topic, .history:
                return row
            }
        }
        .sorted { $0.sortOrder > $1.sortOrder }
    }

    private func filter(rows: [ExampleForwardSelectionRow]) -> [ExampleForwardSelectionRow] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return rows
        }
        let lowercased = keyword.lowercased()
        return rows.filter { row in
            row.title.lowercased().contains(lowercased) ||
                (row.subtitle?.lowercased().contains(lowercased) ?? false) ||
                (row.route.targetId?.lowercased().contains(lowercased) ?? false)
        }
    }

    private static func errorMessage(for error: NSError) -> String {
        DemoNetworkPresentation.message(for: error)
    }
}

private struct ExampleAIMentionSelectionView: View {
    var routeId: String
    var chatToken: ChatThemeToken
    var onComplete: (ChatMentionSelectionResult?) -> Void

    var body: some View {
        let rows = NEAIUserManager.shared.getAIChatUserList().compactMap(ExampleAIMentionRow.init(aiUser:))
        ZStack(alignment: .top) {
            chatToken.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                NECommonNavigationBarView(
                    title: NEChatUIKitSwiftUIBundle.localized("user_select", value: "Select User"),
                    backAction: { finish(nil) },
                    backIcon: NECommonNavigationIconResource(
                        assetName: "arrowDown",
                        bundle: NEChatUIKitSwiftUIBundle.bundle
                    ),
                    backgroundColor: chatToken.navigationBackground,
                    separatorColor: chatToken.dividerColor,
                    showsSeparator: false
                )
                .neCommonTheme(commonToken)

                if rows.isEmpty {
                    NECommonErrorStateView(
                        state: NECommonErrorState(
                            textKey: "no_ai_user",
                            fallbackText: NEContactUIKitSwiftUIBundle.localized("no_ai_user", value: "No AI User"),
                            severity: .info,
                            retryable: false
                        )
                    )
                    .neCommonTheme(commonToken)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                Button {
                                    finish(ChatMentionSelectionResult(targets: [
                                        ChatMentionTargetState(accountId: row.accountId, displayName: row.displayName),
                                    ]))
                                } label: {
                                    HStack(spacing: 12) {
                                        NECommonAvatarView(
                                            imageURL: NECommonAvatarDisplayResolver.url(from: row.avatarURL),
                                            initials: NECommonAvatarDisplayResolver.initials(
                                                displayName: row.displayName,
                                                fallbackID: row.accountId
                                            ),
                                            size: 40,
                                            cornerRadius: 8,
                                            hashID: row.accountId
                                        )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(row.displayName)
                                                .font(.system(size: chatToken.incomingMessageFontSize))
                                                .foregroundColor(chatToken.incomingTextColor)
                                                .lineLimit(1)
                                            Text(row.accountId)
                                                .font(.system(size: 12))
                                                .foregroundColor(chatToken.secondaryTextColor)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(chatToken.navigationBackground)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var commonToken: NECommonThemeToken {
        chatToken.styleMode == .fun ? .fun : .normal
    }

    private func finish(_ result: ChatMentionSelectionResult?) {
        onComplete(result)
    }
}

private struct ExampleAIMentionRow: Identifiable {
    var id: String { accountId }
    var accountId: String
    var displayName: String
    var avatarURL: String?

    init?(aiUser: V2NIMAIUser) {
        guard let accountId = aiUser.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountId.isEmpty else {
            return nil
        }
        self.accountId = accountId
        displayName = aiUser.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? aiUser.name ?? accountId
            : accountId
        avatarURL = aiUser.avatar
    }
}

private struct ExampleTeamMentionSelectionView: View {
    var routeId: String
    var request: ChatMentionSelectionRequest
    var token: NETeamThemeToken
    var onComplete: (ChatMentionSelectionResult?) -> Void

    @StateObject private var viewModel: ExampleTeamMentionSelectionViewModel

    init(routeId: String,
         request: ChatMentionSelectionRequest,
         token: NETeamThemeToken,
         onComplete: @escaping (ChatMentionSelectionResult?) -> Void) {
        self.routeId = routeId
        self.request = request
        self.token = token
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: ExampleTeamMentionSelectionViewModel(request: request))
    }

    var body: some View {
        ZStack(alignment: .top) {
            token.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                NECommonNavigationBarView(
                    title: NEChatUIKitSwiftUIBundle.localized("user_select", value: "Select User"),
                    backAction: { finish(nil) },
                    backIcon: NECommonNavigationIconResource(
                        assetName: "arrowDown",
                        bundle: NEChatUIKitSwiftUIBundle.bundle
                    ),
                    backgroundColor: token.styleMode == .fun ? token.rowBackground : token.pageBackground,
                    separatorColor: token.separator,
                    showsSeparator: false
                )
                .neCommonTheme(commonToken)

                content
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.load()
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            NECommonLoadingView(title: NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .neCommonTheme(commonToken)
        case let .failed(message):
            NECommonErrorStateView(
                state: NECommonErrorState(
                    textKey: "network_error",
                    fallbackText: message,
                    severity: .warning,
                    retryable: true
                ),
                retry: { viewModel.load() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .neCommonTheme(commonToken)
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 0) {
                    if request.allowsAllMembers {
                        mentionButton(
                            title: NEChatUIKitSwiftUIBundle.localized("user_select_all", value: "All"),
                            subtitle: nil,
                            avatarURL: nil,
                            avatarName: nil,
                            avatarImageName: token.styleMode == .fun ? "fun_at_all" : "chat_at_all",
                            hashID: ChatMentionTargetState.allMembersAccountId
                        ) {
                            finish(ChatMentionSelectionResult(targets: [
                                ChatMentionTargetState(accountId: ChatMentionTargetState.allMembersAccountId, isAllMembers: true),
                            ]))
                        }
                    }

                    ForEach(viewModel.members) { member in
                        mentionButton(
                            title: member.displayName,
                            subtitle: member.accountId,
                            avatarURL: member.avatarURL,
                            avatarName: member.avatarName,
                            hashID: member.accountId
                        ) {
                            finish(ChatMentionSelectionResult(targets: [
                                ChatMentionTargetState(
                                    accountId: member.accountId,
                                    displayName: viewModel.mentionDisplayName(for: member)
                                ),
                            ]))
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(token.rowBackground)
        }
    }

    private func mentionButton(title: String,
                               subtitle: String?,
                               avatarURL: String?,
                               avatarName: String?,
                               avatarImageName: String? = nil,
                               hashID: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let avatarImageName {
                    NECommonIconView(
                        imageName: avatarImageName,
                        bundle: NEChatUIKitSwiftUIBundle.bundle,
                        renderingMode: .original,
                        size: CGSize(width: avatarSize, height: avatarSize),
                        accessibilityLabel: title
                    )
                } else {
                    NECommonAvatarView(
                        imageURL: NECommonAvatarDisplayResolver.url(from: avatarURL),
                        initials: NECommonAvatarDisplayResolver.initials(
                            displayName: avatarName,
                            fallbackID: hashID
                        ),
                        size: avatarSize,
                        cornerRadius: token.styleMode == .fun ? 8 : avatarSize / 2,
                        hashID: hashID
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(token.titleFont)
                        .foregroundColor(token.primaryText)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(token.detailFont)
                            .foregroundColor(token.detailText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(token.rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func finish(_ result: ChatMentionSelectionResult?) {
        onComplete(result)
    }

    private var avatarSize: CGFloat {
        token.styleMode == .fun ? 40 : 42
    }

    private var commonToken: NECommonThemeToken {
        token.styleMode == .fun ? .fun : .normal
    }
}

@MainActor
private final class ExampleTeamMentionSelectionViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var members: [NETeamSwiftUIMemberState] = []
    @Published var toast: NECommonToast?

    private let request: ChatMentionSelectionRequest
    private var loadGeneration = UUID()

    init(request: ChatMentionSelectionRequest) {
        self.request = request
    }

    func load() {
        guard let teamId = resolvedTeamId else {
            phase = .failed(NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"))
            return
        }

        let generation = UUID()
        loadGeneration = generation
        phase = .loading
        TeamRepo.shared.loadSwiftUIMemberList(
            teamId: teamId,
            teamType: .normal,
            scope: .all,
            fetchUserInfo: false
        ) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else {
                    return
                }
                if let error {
                    let message = DemoNetworkPresentation.message(for: error)
                    self.phase = .failed(message)
                    self.toast = NECommonToast(message: message)
                    return
                }
                let teamMembers = snapshot?.members.filter { !$0.isCurrentUser } ?? []
                let aiMembers = IMKitConfigCenter.shared.enableAIUser
                    ? NEAIUserManager.shared.getAIChatUserList().compactMap { aiUser -> NETeamSwiftUIMemberState? in
                        guard let accountId = aiUser.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !accountId.isEmpty else {
                            return nil
                        }
                        let displayName = aiUser.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? aiUser.name ?? accountId
                            : accountId
                        return NETeamSwiftUIMemberState(
                            teamId: teamId,
                            accountId: accountId,
                            displayName: displayName,
                            avatarURL: aiUser.avatar,
                            avatarName: displayName,
                            role: .unknown,
                            teamNick: nil,
                            joinTime: 0,
                            isChatBanned: false,
                            isCurrentUser: false
                        )
                    }
                    : []
                let aiAccountIds = Set(aiMembers.map(\.accountId))
                let nonAIMembers = teamMembers.filter { !aiAccountIds.contains($0.accountId) }
                TeamRepo.shared.swiftUITeamMemberDisplayInfos(
                    teamId: teamId,
                    accountIds: nonAIMembers.map(\.accountId),
                    showAlias: true
                ) { [weak self] infos, _ in
                    Task { @MainActor in
                        guard let self, self.loadGeneration == generation else { return }
                        let infoByAccountId = Dictionary(
                            infos.map { ($0.accountId, $0) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        let resolvedMembers = nonAIMembers.map { member -> NETeamSwiftUIMemberState in
                            guard let info = infoByAccountId[member.accountId] else { return member }
                            var next = member
                            next.displayName = info.displayName
                            next.avatarURL = info.avatarURL ?? next.avatarURL
                            next.avatarName = info.avatarName ?? member.accountId
                            return next
                        }
                        self.members = aiMembers + resolvedMembers
                        self.phase = .loaded
                    }
                }
            }
        }
    }

    func consumeToast(_ toast: NECommonToast) {
        if self.toast?.id == toast.id {
            self.toast = nil
        }
    }

    func mentionDisplayName(for member: NETeamSwiftUIMemberState) -> String {
        if let aiName = NEAIUserManager.shared.getShowName(member.accountId)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !aiName.isEmpty {
            return aiName
        }
        if let teamNick = member.teamNick?.trimmingCharacters(in: .whitespacesAndNewlines),
           !teamNick.isEmpty {
            return teamNick
        }
        if let userName = ChatRepo.cachedSwiftUIDisplayUser(accountId: member.accountId)?
            .showName(false)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !userName.isEmpty {
            return userName
        }
        return member.accountId
    }

    private var resolvedTeamId: String? {
        if let sessionId = request.context.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionId.isEmpty {
            return sessionId
        }
        return V2NIMConversationIdUtil.conversationTargetId(request.context.conversationId)
    }
}
