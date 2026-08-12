// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NEContactUIKitSwiftUI
import NEConversationUIKitSwiftUI
import NETeamUIKitSwiftUI
import SwiftUI

struct ConversationActionRouteHostView<Content: View>: View {
    @EnvironmentObject var environment: AppEnvironment
    @StateObject private var teamClient = NETeamUIKitSwiftUIClient.shared
    @State private var route: ConversationActionRoute?
    @State private var toast: ConversationActionToast?
    @State private var isCreatingTeam = false
    @State private var pendingCreatedTeamChat: ChatSessionContext?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .navigationDestination(isPresented: routeIsPresentedBinding) {
                destination
            }
            .onAppear {
                installConversationActionHandler()
                handleTeamRoute(teamClient.route)
            }
            .onChange(of: teamClient.route?.id) { _ in
                handleTeamRoute(teamClient.route)
            }
            .neCommonTransientOverlay(toast, placement: .top, topPadding: 52, onDismiss: { value in
                if toast?.id == value.id {
                    toast = nil
                }
            }) { toast in
                Text(toast.message)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
    }

    @ViewBuilder
    private var destination: some View {
        if let route {
            switch route {
            case .scanQR:
                ConversationQRScannerView(token: conversationToken)
            case .addFriend:
                ContactFindFriendView(token: contactToken)
                    .demoHidesTabBar()
            case .joinTeam:
                TeamJoinView(
                    style: teamStyle,
                    token: teamToken,
                    onOpenTeamChat: openJoinedTeamChat
                )
                    .demoHidesTabBar()
            case .createDiscussion:
                ContactSelectionView(
                    viewModel: ContactSelectionViewModel(
                        context: ContactSelectionContext(
                            title: NEContactUIKitSwiftUIBundle.localized("select", value: "Select"),
                            filterAccountIds: [IMKitClient.instance.account()],
                            limit: inviteNumberLimit,
                            allowsAIUsers: IMKitConfigCenter.shared.enableAIUser
                        )
                    ),
                    token: contactToken,
                    dismissOnComplete: false,
                    onComplete: createDiscussion
                )
                .onDisappear(perform: openPendingCreatedTeamChatIfNeeded)
                .demoHidesTabBar()
            case .createAdvancedTeam:
                ContactSelectionView(
                    viewModel: ContactSelectionViewModel(
                        context: ContactSelectionContext(
                            title: NEContactUIKitSwiftUIBundle.localized("select", value: "Select"),
                            filterAccountIds: [IMKitClient.instance.account()],
                            limit: inviteNumberLimit,
                            allowsAIUsers: IMKitConfigCenter.shared.enableAIUser
                        )
                    ),
                    token: contactToken,
                    dismissOnComplete: false,
                    onComplete: createAdvancedTeam
                )
                .onDisappear(perform: openPendingCreatedTeamChatIfNeeded)
                .demoHidesTabBar()
            case let .team(route):
                teamDestination(route)
                    .demoHidesTabBar()
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func teamDestination(_ route: NETeamSwiftUIRoute) -> some View {
        switch route {
        case let .setting(teamId, style, teamType):
            TeamSettingView(teamId: teamId, style: style, teamType: teamType, token: teamToken, config: NETeamSwiftUIConfigCenter.shared.current())
        case let .teamInfo(teamId, teamType):
            TeamInfoView(teamId: teamId, style: teamStyle, teamType: teamType, token: teamToken)
        case let .memberList(teamId, teamType):
            TeamMemberListView(teamId: teamId, scope: .all, style: teamStyle, teamType: teamType, token: teamToken, config: NETeamSwiftUIConfigCenter.shared.current())
        case let .memberSelect(teamId, teamType):
            TeamMemberSelectView(teamId: teamId, style: teamStyle, teamType: teamType, token: teamToken, config: NETeamSwiftUIConfigCenter.shared.current())
        case let .manager(teamId, teamType):
            TeamManageView(teamId: teamId, style: teamStyle, teamType: teamType, token: teamToken)
        case let .managerList(teamId, teamType):
            TeamMemberListView(teamId: teamId, scope: .managers, style: teamStyle, teamType: teamType, token: teamToken, config: NETeamSwiftUIConfigCenter.shared.current())
        case let .transferOwner(teamId, teamType):
            TeamTransferOwnerView(teamId: teamId, style: teamStyle, teamType: teamType, token: teamToken, config: NETeamSwiftUIConfigCenter.shared.current())
        case let .teamDetail(teamId, teamType):
            TeamDetailView(
                teamId: teamId,
                style: teamStyle,
                teamType: teamType,
                token: teamToken,
                onOpenTeamChat: openJoinedTeamChat
            )
        case let .editName(teamId, teamType):
            TeamTextEditView(teamId: teamId, field: .name, style: teamStyle, teamType: teamType, token: teamToken)
        case let .editNick(teamId, teamType):
            TeamTextEditView(teamId: teamId, field: .nick, style: teamStyle, teamType: teamType, token: teamToken)
        case let .editAvatar(teamId, teamType):
            TeamAvatarEditView(teamId: teamId, style: teamStyle, teamType: teamType, token: teamToken)
        case let .editIntroduce(teamId, teamType):
            TeamTextEditView(teamId: teamId, field: .introduce, style: teamStyle, teamType: teamType, token: teamToken)
        case let .joinTeam(teamId, teamType):
            TeamJoinView(teamId: teamId, style: teamStyle, teamType: teamType, token: teamToken)
        case .createAdvancedTeam:
            ContactSelectionView(
                viewModel: ContactSelectionViewModel(
                    context: ContactSelectionContext(
                        title: NEContactUIKitSwiftUIBundle.localized("select", value: "Select"),
                        filterAccountIds: [IMKitClient.instance.account()],
                        limit: inviteNumberLimit,
                        allowsAIUsers: IMKitConfigCenter.shared.enableAIUser
                    )
                ),
                token: contactToken,
                dismissOnComplete: false,
                onComplete: createAdvancedTeam
            )
        @unknown default:
            EmptyView()
        }
    }

    private var routeIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { route != nil },
            set: { isPresented in
                if !isPresented {
                    route = nil
                    NETeamUIKitSwiftUIClient.shared.dismissRoute()
                }
            }
        )
    }

    private var contactToken: ContactThemeToken {
        environment.themeMode == .fun ? .fun : .normal
    }

    private var conversationToken: ConversationThemeToken {
        environment.themeMode == .fun ? .fun : .normal
    }

    private var teamStyle: NETeamSwiftUIStyleMode {
        environment.themeMode == .fun ? .fun : .normal
    }

    private var teamToken: NETeamThemeToken {
        teamStyle == .fun ? FunTeamThemeToken.default : NormalTeamThemeToken.default
    }

    private func installConversationActionHandler() {
        var config = ConversationSwiftUIConfigCenter.shared.current()
        config.actionHandler = { action in
            Task { @MainActor in
                open(action)
            }
        }
        config.qrScanHandler = {
            Task { @MainActor in
                route = .scanQR
            }
        }
        NEConversationUIKitSwiftUIClient.shared.updateConfig(config)
    }

    private func handleTeamRoute(_ value: NETeamSwiftUIRoute?) {
        guard let value else {
            return
        }
        route = .team(value)
    }

    private func openJoinedTeamChat(_ conversationId: String) {
        teamClient.onOpenTeamChat?(conversationId)
    }

    private func open(_ action: ConversationAction) {
        switch action {
        case .addFriend:
            route = .addFriend
        case .joinTeam:
            route = .joinTeam
        case .createDiscussion:
            route = .createDiscussion
        case .createSeniorTeam:
            route = .createAdvancedTeam
        case .scanQR:
            route = .scanQR
        @unknown default:
            toast = ConversationActionToast(
                message: NEConversationUIKitSwiftUIBundle.localized("scan_qr_no_result", value: "No valid content recognized")
            )
        }
    }

    private func createDiscussion(_ result: ContactSelectionResult) {
        guard !isCreatingTeam else {
            return
        }
        let accountIds = result.accountIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != IMKitClient.instance.account() }
        guard !accountIds.isEmpty else {
            toast = ConversationActionToast(message: NEContactUIKitSwiftUIBundle.localized("select_contact", value: "Please select Contact"))
            return
        }
        guard DemoNetworkPresentation.allowsNetworkOperation else {
            toast = ConversationActionToast(message: DemoNetworkPresentation.networkMessage())
            return
        }

        isCreatingTeam = true
        let fallbackName = NEConversationUIKitSwiftUIBundle.localized("discussion_group", value: "Temperature Group")
        resolveUIKitTeamName(selectedNames: result.names, fallback: fallbackName) { resolvedName in
            let name = NECommonTextLimit.limitedUTF16(resolvedName, limit: 30)
            let params = V2NIMCreateTeamParams()
            params.name = name
            params.teamType = .TEAM_TYPE_NORMAL
            params.avatar = TeamCreateViewModel.defaultAdvancedTeamAvatarURL
            params.joinMode = .TEAM_JOIN_MODE_FREE
            params.inviteMode = .TEAM_INVITE_MODE_ALL
            params.agreeMode = .TEAM_AGREE_MODE_NO_AUTH
            params.updateInfoMode = .TEAM_UPDATE_INFO_MODE_ALL
            params.updateExtensionMode = .TEAM_UPDATE_EXTENSION_MODE_ALL
            params.serverExtension = NECommonUtil.getJSONStringFromDictionary([discussTeamKey: true])

            TeamRepo.shared.createTeam(params, members: accountIds, postscript: nil) { createResult, error in
                Task { @MainActor in
                    isCreatingTeam = false
                    if let error {
                        toast = ConversationActionToast(message: DemoNetworkPresentation.message(for: error))
                        return
                    }
                    guard let teamId = createResult?.team?.teamId,
                          let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId)
                    else {
                        toast = ConversationActionToast(message: NEConversationUIKitSwiftUIBundle.localized("scan_qr_no_result", value: "No valid content recognized"))
                        return
                    }
                    pendingCreatedTeamChat = ChatSessionContext(
                        kind: .team,
                        conversationId: conversationId,
                        title: name,
                        sessionId: teamId,
                        sessionName: name
                    )
                    route = nil
                }
            }
        }
    }

    private func createAdvancedTeam(_ result: ContactSelectionResult) {
        guard !isCreatingTeam else {
            return
        }
        let accountIds = result.accountIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != IMKitClient.instance.account() }
        guard !accountIds.isEmpty else {
            toast = ConversationActionToast(message: NEContactUIKitSwiftUIBundle.localized("select_contact", value: "Please select Contact"))
            return
        }
        guard DemoNetworkPresentation.allowsNetworkOperation else {
            toast = ConversationActionToast(message: DemoNetworkPresentation.networkMessage())
            return
        }

        isCreatingTeam = true
        let fallbackName = NETeamUIKitSwiftUIBundle.localized("senior_team", value: "Group")
        resolveUIKitTeamName(selectedNames: result.names, fallback: fallbackName) { name in
            let request = NETeamSwiftUICreateAdvancedTeamRequest(
                name: name,
                avatarURL: TeamCreateViewModel.defaultAdvancedTeamAvatarURL,
                inviteeAccountIds: accountIds,
                createTipText: NETeamUIKitSwiftUIBundle.localized("create_senior_team_noti", value: "Group created")
            )

            TeamRepo.shared.createSwiftUIAdvancedTeam(request: request) { createResult, error in
                Task { @MainActor in
                    isCreatingTeam = false
                    if let error {
                        toast = ConversationActionToast(message: DemoNetworkPresentation.message(for: error))
                        return
                    }
                    guard let createResult else {
                        toast = ConversationActionToast(message: NEConversationUIKitSwiftUIBundle.localized("scan_qr_no_result", value: "No valid content recognized"))
                        return
                    }
                    pendingCreatedTeamChat = ChatSessionContext(
                        kind: .team,
                        conversationId: createResult.conversationId,
                        title: createResult.name,
                        sessionId: createResult.teamId,
                        sessionName: createResult.name
                    )
                    route = nil
                }
            }
        }
    }

    private func openPendingCreatedTeamChatIfNeeded() {
        guard let context = pendingCreatedTeamChat else {
            return
        }
        pendingCreatedTeamChat = nil
        NEChatUIKitSwiftUIClient.shared.router.enqueue(.teamChat(context))
    }

    private func resolveUIKitTeamName(selectedNames: String,
                                      fallback: String,
                                      completion: @escaping (String) -> Void) {
        let selected = selectedNames
            .split(separator: "、")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        resolveCurrentUserDisplayName { myName in
            var names = [myName.trimmingCharacters(in: .whitespacesAndNewlines)]
            names.append(contentsOf: selected)
            let joined = names.filter { !$0.isEmpty }.joined(separator: "、")
            completion(joined.isEmpty ? fallback : joined)
        }
    }

    private func resolveCurrentUserDisplayName(completion: @escaping (String) -> Void) {
        let accountId = IMKitClient.instance.account()
        if let mine = NEFriendUserCache.shared.getFriendInfo(accountId) {
            completion(mine.showName() ?? accountId)
            return
        }

        ContactRepo.shared.getUserListFromCloud(accountIds: [accountId]) { users, _ in
            let name = users?.first?.showName() ?? accountId
            Task { @MainActor in
                completion(name)
            }
        }
    }
}

private enum ConversationActionRoute: Identifiable {
    case scanQR
    case addFriend
    case joinTeam
    case createDiscussion
    case createAdvancedTeam
    case team(NETeamSwiftUIRoute)

    var id: String {
        switch self {
        case .scanQR:
            return "scanQR"
        case .addFriend:
            return "addFriend"
        case .joinTeam:
            return "joinTeam"
        case .createDiscussion:
            return "createDiscussion"
        case .createAdvancedTeam:
            return "createAdvancedTeam"
        case let .team(route):
            return "team-\(route.id)"
        }
    }
}

private struct ConversationActionToast: Identifiable, Equatable {
    var id = UUID().uuidString
    var message: String
}
