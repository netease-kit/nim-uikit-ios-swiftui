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

@MainActor
final class LegacyRouteBridge: ObservableObject {
    static let shared = LegacyRouteBridge()

    @Published var route: LegacyRoute?
    private var didRegisterRoutes = false
    private var isCreatingTeam = false

    private init() {}

    func registerRoutesIfNeeded() {
        guard !didRegisterRoutes else {
            return
        }
        didRegisterRoutes = true

        registerPush(SearchContactPageRouter) { _ in
            .conversationSearch
        }
        registerPush(ConversationPageRouter) { _ in
            .conversationList()
        }
        registerPush(LocalConversationPageRouter) { _ in
            .conversationList(mode: .local)
        }
        registerPush(ContactPageRouter) { _ in
            .contactList
        }
        registerPush(ForwardMultiSelectRouter) { _ in
            .forwardSelection
        }
        registerPush(ContactUserSelectRouter) { params in
            .contactSelection(Self.contactSelectionContext(from: params, allowsAIUsers: false))
        }
        registerPush(ContactFusionSelectRouter) { params in
            .contactSelection(Self.contactSelectionContext(from: params, allowsAIUsers: true))
        }
        registerPush(ContactAddFriendRouter) { _ in
            .contactAddFriend
        }
        registerPush(ValidationMessageRouter) { _ in
            .contactValidation
        }
        registerPush(ContactBlackListRouter) { _ in
            .contactBlackList
        }
        registerPush(ContactTeamListRouter) { _ in
            .contactTeamList
        }
        registerPush(ContactAIUserListRouter) { _ in
            .contactAIUserList
        }
        registerPush(ContactAIRobotListRouter) { _ in
            .aiRobotList
        }
        registerPush(ContactUserInfoPageRouter) { params in
            guard let accountId = Self.accountId(from: params) else {
                return nil
            }
            return .contactUserInfo(accountId: accountId, isRobot: params["isRobot"] as? Bool ?? false)
        }
        registerPush(MeSettingRouter) { _ in
            .mineProfile
        }
        registerPush(TeamJoinTeamRouter) { params in
            .teamJoin(teamId: params["teamId"] as? String ?? params["teamid"] as? String)
        }
        registerPush(TeamDetailInfoPageRouter) { params in
            guard let teamId = Self.teamId(from: params) else {
                return nil
            }
            return .teamDetail(teamId: teamId)
        }
        registerPush(TeamSettingViewRouter) { params in
            guard let teamId = params["teamid"] as? String ?? params["teamId"] as? String else {
                return nil
            }
            return .teamSetting(teamId: teamId)
        }
        registerPush(TeamMemberSelectViewRouter) { params in
            guard let teamId = params["teamId"] as? String ?? params["teamid"] as? String else {
                return nil
            }
            return .teamMemberSelect(teamId: teamId)
        }

        Router.shared.register(ChatAddFriendRouter) { params in
            guard let text = params["text"] as? String,
                  let conversationId = params["conversationId"] as? String else {
                return
            }
            let message = V2NIMMessageCreator.createTextMessage(text)
            ChatRepo.shared.sendMessage(message: message, conversationId: conversationId) { _, error, _ in
                if let error {
                    NEALog.errorLog("ChatAddFriendRouter", desc: "send hello message error:\(error.localizedDescription)")
                }
            }
        }

        Router.shared.register(TeamCreateDisuss) { params in
            Task { @MainActor [weak self] in
                self?.createDiscussionTeam(params)
            }
        }

        Router.shared.register(TeamCreateSenior) { params in
            Task { @MainActor [weak self] in
                self?.createSeniorTeam(params)
            }
        }
    }

    private func registerPush(_ url: String,
                              makeRoute: @escaping ([String: Any]) -> LegacyRoute?) {
        Router.shared.register(url) { [weak self] params in
            guard let route = makeRoute(params) else {
                return
            }
            Task { @MainActor in
                self?.route = route
            }
        }
    }

    private static func accountId(from params: [String: Any]) -> String? {
        if let accountId = params["uid"] as? String, !accountId.isEmpty {
            return accountId
        }
        if let user = params["user"] as? NEUserWithFriend,
           let accountId = user.user?.accountId ?? user.friend?.accountId,
           !accountId.isEmpty {
            return accountId
        }
        if let user = params["nim_user"] as? V2NIMUser,
           let accountId = user.accountId,
           !accountId.isEmpty {
            return accountId
        }
        return nil
    }

    private static func teamId(from params: [String: Any]) -> String? {
        if let teamId = params["teamId"] as? String ?? params["teamid"] as? String,
           !teamId.isEmpty {
            return teamId
        }
        if let team = params["team"] as? V2NIMTeam,
           !team.teamId.isEmpty {
            let teamId = team.teamId
            return teamId
        }
        return nil
    }

    private static func contactSelectionContext(from params: [String: Any],
                                                allowsAIUsers: Bool) -> LegacyContactSelectionContext {
        let filters = params["filters"] as? Set<String> ?? []
        let limit = params["limit"] as? Int ?? 10
        let uid = params["uid"] as? String
        return LegacyContactSelectionContext(
            title: NEContactUIKitSwiftUIBundle.localized("select", value: "Select"),
            filterAccountIds: filters,
            limit: limit > 0 ? limit : 10,
            allowsAIUsers: allowsAIUsers,
            extraAccountId: uid
        )
    }

    fileprivate static func contactSelectionParameters(from result: ContactSelectionResult,
                                                       extraAccountId: String?,
                                                       completion: @escaping ([String: Any]) -> Void) {
        let selectedAccountIds = result.accountIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let selectedNames = result.names
            .split(separator: "、")
            .map(String.init)
        let myAccountId = IMKitClient.instance.account()

        func buildParameters(myName: String) -> [String: Any] {
            var names = [myName]
            names.append(contentsOf: selectedNames)
            var accountIds = selectedAccountIds
            if let extraAccountId = extraAccountId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !extraAccountId.isEmpty {
                accountIds.append(extraAccountId)
            }
            return [
                "accids": accountIds,
                "names": names.joined(separator: "、"),
                "im_user": [V2NIMUser](),
            ]
        }

        if let mine = NEFriendUserCache.shared.getFriendInfo(myAccountId) {
            completion(buildParameters(myName: mine.showName() ?? myAccountId))
            return
        }

        ContactRepo.shared.getUserListFromCloud(accountIds: [myAccountId]) { users, _ in
            let myName = users?.first?.showName() ?? myAccountId
            completion(buildParameters(myName: myName))
        }
    }

    private func createDiscussionTeam(_ params: [String: Any]) {
        guard !isCreatingTeam,
              let accountIds = params["accids"] as? [String] else {
            return
        }
        isCreatingTeam = true
        var name = params["names"] as? String
            ?? NETeamUIKitSwiftUIBundle.localized("normal_team", value: "Temp Group")
        name = NECommonTextLimit.limitedUTF16(name, limit: 30)
        let iconURL = (params["url"] as? String) ?? TeamCreateViewModel.defaultAdvancedTeamAvatarURL

        let createParams = V2NIMCreateTeamParams()
        createParams.name = name
        createParams.teamType = .TEAM_TYPE_NORMAL
        createParams.avatar = iconURL
        createParams.joinMode = .TEAM_JOIN_MODE_FREE
        createParams.inviteMode = .TEAM_INVITE_MODE_ALL
        createParams.agreeMode = .TEAM_AGREE_MODE_NO_AUTH
        createParams.updateInfoMode = .TEAM_UPDATE_INFO_MODE_ALL
        createParams.updateExtensionMode = .TEAM_UPDATE_EXTENSION_MODE_ALL
        createParams.serverExtension = NECommonUtil.getJSONStringFromDictionary([discussTeamKey: true])

        TeamRepo.shared.createTeam(createParams, members: accountIds, postscript: nil) { [weak self] createResult, error in
            Task { @MainActor in
                self?.isCreatingTeam = false
                var result = [String: Any]()
                if let error {
                    result["code"] = error.code
                    result["msg"] = DemoNetworkPresentation.message(for: error)
                } else {
                    result["code"] = 0
                    result["msg"] = "ok"
                    result["teamId"] = createResult?.team?.teamId
                }
                Router.shared.use(TeamCreateDiscussResult, parameters: result, closure: nil)
            }
        }
    }

    private func createSeniorTeam(_ params: [String: Any]) {
        guard !isCreatingTeam,
              let accountIds = params["accids"] as? [String] else {
            return
        }
        isCreatingTeam = true
        let name = params["names"] as? String
            ?? NETeamUIKitSwiftUIBundle.localized("senior_team", value: "Group")
        let iconURL = (params["url"] as? String) ?? TeamCreateViewModel.defaultAdvancedTeamAvatarURL
        let request = NETeamSwiftUICreateAdvancedTeamRequest(
            name: name,
            avatarURL: iconURL,
            inviteeAccountIds: accountIds,
            createTipText: NETeamUIKitSwiftUIBundle.localized("create_senior_team_noti", value: "Group created")
        )

        TeamRepo.shared.createSwiftUIAdvancedTeam(request: request) { [weak self] createResult, error in
            Task { @MainActor in
                self?.isCreatingTeam = false
                var result = [String: Any]()
                if let error {
                    result["code"] = error.code
                    result["msg"] = DemoNetworkPresentation.message(for: error)
                } else {
                    result["code"] = 0
                    result["msg"] = "ok"
                    result["teamId"] = createResult?.teamId
                }
                Router.shared.use(TeamCreateSeniorResult, parameters: result, closure: nil)
            }
        }
    }
}

enum LegacyRoute: Hashable, Identifiable {
    case conversationSearch
    case conversationChat(LegacyConversationChatRoute)
    case conversationList(mode: ConversationMode? = nil)
    case forwardSelection
    case contactList
    case contactSelection(LegacyContactSelectionContext)
    case contactAddFriend
    case contactValidation
    case contactBlackList
    case contactTeamList
    case contactAIUserList
    case contactUserInfo(accountId: String, isRobot: Bool)
    case aiRobotList
    case mineProfile
    case teamJoin(teamId: String?)
    case teamDetail(teamId: String)
    case teamSetting(teamId: String)
    case teamMemberSelect(teamId: String)

    var id: String {
        switch self {
        case .conversationSearch:
            return "conversationSearch"
        case let .conversationChat(route):
            return "conversationChat-\(route.id)"
        case let .conversationList(mode):
            return "conversationList-\(mode?.rawValue ?? "current")"
        case .forwardSelection:
            return "forwardSelection"
        case .contactList:
            return "contactList"
        case let .contactSelection(context):
            return "contactSelection-\(context.id)"
        case .contactAddFriend:
            return "contactAddFriend"
        case .contactValidation:
            return "contactValidation"
        case .contactBlackList:
            return "contactBlackList"
        case .contactTeamList:
            return "contactTeamList"
        case .contactAIUserList:
            return "contactAIUserList"
        case let .contactUserInfo(accountId, isRobot):
            return "contactUserInfo-\(accountId)-\(isRobot)"
        case .aiRobotList:
            return "aiRobotList"
        case .mineProfile:
            return "mineProfile"
        case let .teamJoin(teamId):
            return "teamJoin-\(teamId ?? "manual")"
        case let .teamDetail(teamId):
            return "teamDetail-\(teamId)"
        case let .teamSetting(teamId):
            return "teamSetting-\(teamId)"
        case let .teamMemberSelect(teamId):
            return "teamMemberSelect-\(teamId)"
        }
    }
}

struct LegacyConversationChatRoute: Hashable {
    enum Kind: String, Hashable {
        case p2p
        case team
    }

    var kind: Kind
    var conversationId: String
    var title: String?
    var sessionId: String?

    init?(_ route: ConversationRouteContext) {
        guard !route.isRobot else {
            return nil
        }
        switch route.kind {
        case .p2p:
            kind = .p2p
        case .team:
            kind = .team
        default:
            return nil
        }
        conversationId = route.conversationId
        title = route.title
        sessionId = route.targetId
    }

    init(teamId: String, conversationId: String, title: String?) {
        kind = .team
        self.conversationId = conversationId
        self.title = title
        sessionId = teamId
    }

    var id: String {
        "\(kind.rawValue)-\(conversationId)"
    }

    var context: ChatSessionContext {
        ChatSessionContext(
            kind: kind == .team ? .team : .p2p,
            conversationId: conversationId,
            title: title,
            sessionId: sessionId,
            sessionName: title
        )
    }
}

struct LegacyContactSelectionContext: Hashable {
    var title: String
    var filterAccountIds: Set<String>
    var limit: Int
    var allowsAIUsers: Bool
    var extraAccountId: String?

    var id: String {
        let filters = filterAccountIds.sorted().joined(separator: ",")
        return "\(allowsAIUsers)-\(limit)-\(extraAccountId ?? "")-\(filters)"
    }

    var selectionContext: ContactSelectionContext {
        ContactSelectionContext(
            title: title,
            filterAccountIds: filterAccountIds,
            limit: limit,
            allowsAIUsers: allowsAIUsers
        )
    }
}

struct LegacyRouteHostView<Content: View>: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var bridge = LegacyRouteBridge.shared
    @Binding private var routePath: [LegacyRoute]
    private let isActive: Bool
    private let content: Content

    init(routePath: Binding<[LegacyRoute]>,
         isActive: Bool,
         @ViewBuilder content: () -> Content) {
        _routePath = routePath
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        content
            .navigationDestination(for: LegacyRoute.self) { route in
                destination(for: route)
                    .demoHidesTabBar()
            }
            .onAppear {
                bridge.registerRoutesIfNeeded()
                appendPendingRouteIfNeeded()
            }
            .onChange(of: bridge.route?.id) { _ in
                appendPendingRouteIfNeeded()
            }
            .onChange(of: isActive) { _ in
                appendPendingRouteIfNeeded()
            }
    }

    @ViewBuilder
    private func destination(for route: LegacyRoute) -> some View {
        switch route {
        case .conversationSearch:
            ConversationSearchView(token: conversationToken) { route in
                openChatRoute(route)
            }
        case let .conversationChat(route):
            let config = ChatSwiftUIConfigCenter.shared.current()
            ChatView(
                viewModel: ChatSessionViewModel(
                    context: route.context,
                    config: config
                ),
                browserDestination: { url, title in
                    AnyView(
                        DemoWebPageView(title: title, url: url)
                            .demoHidesTabBar()
                    )
                }
            )
            .id(route.id)
            .toolbar(.hidden, for: .tabBar)
        case let .conversationList(mode):
            ConversationListView(viewModel: ConversationListViewModel(mode: mode ?? currentConversationMode), token: conversationToken)
        case .forwardSelection:
            ConversationSearchView(
                viewModel: ConversationSearchViewModel(showsAllWhenQueryEmpty: true),
                token: conversationToken
            ) { route in
                completeForwardSelection(route)
            }
        case .contactList:
            ContactListView(viewModel: ContactListViewModel(config: currentContactConfig), token: contactToken)
        case let .contactSelection(context):
            ContactSelectionView(
                viewModel: ContactSelectionViewModel(context: context.selectionContext),
                token: contactToken
            ) { result in
                LegacyRouteBridge.contactSelectionParameters(from: result, extraAccountId: context.extraAccountId) { params in
                    Router.shared.use(ContactSelectedUsersRouter, parameters: params, closure: nil)
                }
            }
        case .contactAddFriend:
            ContactFindFriendView(token: contactToken)
        case .contactValidation:
            ValidationListView(viewModel: ValidationListViewModel(), token: contactToken)
        case .contactBlackList:
            BlackListView(viewModel: BlackListViewModel(), token: contactToken)
        case .contactTeamList:
            ContactTeamListView(
                viewModel: ContactTeamListViewModel(),
                token: contactToken,
                onOpenTeamChat: { teamId, title in
                    let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) ?? teamId
                    let chatRoute = LegacyConversationChatRoute(
                        teamId: teamId,
                        conversationId: conversationId,
                        title: title
                    )
                    let destination = LegacyRoute.conversationChat(chatRoute)
                    if routePath.last != destination {
                        routePath.append(destination)
                    }
                }
            )
        case .contactAIUserList:
            AIUserListView(viewModel: AIUserListViewModel(), token: contactToken)
        case let .contactUserInfo(accountId, isRobot):
            ContactUserInfoView(
                viewModel: ContactUserInfoViewModel(
                    accountId: accountId,
                    isCurrentUser: accountId == IMKitClient.instance.account(),
                    isRobot: isRobot
                ),
                token: contactToken
            )
        case .aiRobotList:
            AIRobotEntryView(token: chatToken) { route in
                NEChatUIKitSwiftUIClient.shared.router.enqueue(route)
            }
        case .mineProfile:
            MineView()
                .environmentObject(environment)
        case let .teamJoin(teamId):
            TeamJoinView(
                teamId: teamId,
                style: teamStyle,
                token: teamToken,
                onOpenTeamChat: legacyOpenTeamChat
            )
        case let .teamDetail(teamId):
            TeamDetailView(
                teamId: teamId,
                style: teamStyle,
                token: teamToken,
                onOpenTeamChat: legacyOpenTeamChat
            )
        case let .teamSetting(teamId):
            TeamSettingView(
                teamId: teamId,
                style: teamStyle,
                token: teamToken,
                config: NETeamSwiftUIConfigCenter.shared.current()
            )
        case let .teamMemberSelect(teamId):
            TeamMemberSelectView(
                teamId: teamId,
                style: teamStyle,
                token: teamToken,
                config: NETeamSwiftUIConfigCenter.shared.current()
            )
        }
    }

    private func appendPendingRouteIfNeeded() {
        guard isActive, let route = bridge.route else {
            return
        }
        if routePath.last != route {
            routePath.append(route)
        }
        bridge.route = nil
    }

    private func legacyOpenTeamChat(_ conversationId: String) {
        let teamId = V2NIMConversationIdUtil.conversationTargetId(conversationId) ?? conversationId
        let chatRoute = LegacyConversationChatRoute(
            teamId: teamId,
            conversationId: conversationId,
            title: nil
        )
        let destination = LegacyRoute.conversationChat(chatRoute)
        if routePath.last != destination {
            routePath.append(destination)
        }
    }

    private func openChatRoute(_ route: ConversationRouteContext) {
        if let chatRoute = LegacyConversationChatRoute(route) {
            let destination = LegacyRoute.conversationChat(chatRoute)
            if routePath.last != destination {
                routePath.append(destination)
            }
            return
        }

        guard route.isRobot else {
            return
        }
        let context = ChatSessionContext(
            kind: .botSubSession,
            conversationId: route.conversationId,
            title: route.title,
            sessionId: route.targetId,
            sessionName: route.title
        )
        NEChatUIKitSwiftUIClient.shared.router.enqueue(.botSubSessionList(context))
    }

    private func completeForwardSelection(_ route: ConversationRouteContext) {
        let conversation: [String: Any] = [
            "conversationId": route.conversationId,
            "name": route.title as Any,
            "avatar": "",
        ]
        Router.shared.use(ForwardMultiSelectedRouter, parameters: ["conversations": [conversation]], closure: nil)
        if routePath.last == .forwardSelection {
            routePath.removeLast()
        }
    }

    private var currentConversationMode: ConversationMode {
        IMKitClient.instance.isV2CloudConversationEnabled ? .cloud : .local
    }

    private var currentContactConfig: ContactSwiftUIConfig {
        var config = ContactSwiftUIConfigCenter.shared.config
        config.styleMode = environment.themeMode == .fun ? .fun : .normal
        return config
    }

    private var chatToken: ChatThemeToken {
        environment.themeMode == .fun ? .fun : .normal
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
}
