// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NEContactUIKitSwiftUI
import NEConversationUIKitSwiftUI
import NEAISearchKitSwiftUI
import NETeamUIKitSwiftUI
import NIMSDK
import SwiftUI
import UIKit
import YXLogin

/// Coordinates app initialization, NIMSDK setup, and YXLogin auth.
/// Coordinates the IMUIKitExample startup flow in a SwiftUI app shell.
@MainActor
enum AppBootstrap {
    static var onLoginSuccess: (() -> Void)?
    static var onLoginFailure: ((String) -> Void)?

    // MARK: - Full setup flow

    static func setup(completion: @escaping () -> Void) {
        setupIM()
        IMKitConfigCenter.shared.enableTeamJoinAgreeModelAuth = true
        setupCallUIKit()
        setupYXLogin()
        setupSwiftUIModules()

        // Try auto-login first
        AuthorManager.shareInstance()?.autoLogin { userInfo, error in
            if let err = error as? NSError {
                if err.code > 0 {
                    onLoginFailure?(DemoNetworkPresentation.message(for: err, fallbackKey: "login_failed"))
                }
                completion()
            } else if let userInfo,
                      let accid = userInfo.imAccid,
                      let token = userInfo.imToken
            {
                loginIM(accid: accid, token: token) {
                    completion()
                }
            } else {
                completion()
            }
        }
    }

    // MARK: - NIMSDK Setup

    private static func setupIM() {
        ServerConfig.configServer()
        AppDelegate.setupIM(ServerConfig.getAppkey(), listener: AppDelegate.active)
    }

    private static func setupCallUIKit() {
        AppDelegate.setupCallUIKit()
    }

    private static func setupSwiftUIModules() {
        warmUpSharedCaches()

        let chatBoundaryService = ExampleChatNativeBoundaryService.shared
        var chatConfig = ChatSwiftUIConfig()
        chatConfig.isApplicationActiveProvider = {
            UIApplication.shared.applicationState == .active
        }
        chatConfig.conversationAtReminderClearHandler = { conversationId in
            Router.shared.use(
                "ClearAtMessageRemind",
                parameters: ["sessionId": conversationId],
                closure: nil
            )
        }
        chatConfig.nativeBoundaryHandler = chatBoundaryService.nativeBoundaryHandler
        chatConfig.mediaPreviewHandler = chatBoundaryService.mediaPreviewHandler
        chatConfig.mediaImageSaveHandler = { item in
            try await chatBoundaryService.saveImageToPhotoLibrary(item)
        }
        chatConfig.audioRecordingHandler = chatBoundaryService.audioRecordingHandler
        chatConfig.audioPlaybackHandler = chatBoundaryService.audioPlaybackHandler
        chatConfig.clipboardHandler = chatBoundaryService.clipboardHandler
        chatConfig.urlInteractionHandler = chatBoundaryService.urlInteractionHandler
        chatConfig.fileInteractionHandler = chatBoundaryService.fileInteractionHandler
        chatConfig.locationInteractionHandler = chatBoundaryService.locationInteractionHandler
        chatConfig.callInteractionHandler = chatBoundaryService.callInteractionHandler
        chatConfig.avatarSelectionHandler = chatBoundaryService.avatarSelectionHandler
        chatConfig.aiRobotConfigClipboardHandler = chatBoundaryService.aiRobotConfigClipboardHandler
        chatConfig.securityWarningContentProvider = { context in
            AnyView(
                ChatSecurityWarningBannerView(
                    message: localizable("security_warning"),
                    reportTitle: localizable("click_to_report"),
                    token: ChatSwiftUIConfigCenter.shared.current().themeToken,
                    onReport: {
                        openSecurityReportPage()
                    },
                    onDismiss: context.dismiss
                )
            )
        }
        chatConfig.userProfilePushViewProvider = { request, chatToken in
            if request.source == .selfAvatar {
                return AnyView(
                    MineView()
                        .environmentObject(AppEnvironment.shared)
                )
            }
            return AnyView(ContactUserInfoView(
                viewModel: ContactUserInfoViewModel(
                    accountId: request.accountId,
                    isCurrentUser: request.accountId == IMKitClient.instance.account(),
                    isRobot: request.isRobot
                ),
                token: chatToken.styleMode == .fun ? .fun : .normal,
                onOpenChat: { accountId, title in
                    enqueueP2PChat(accountId: accountId, title: title)
                }
            ))
        }
        chatConfig.userProfilePushViewProviderWithChatRoute = { request, chatToken, openP2PChat in
            if request.source == .selfAvatar {
                return AnyView(
                    MineView()
                        .environmentObject(AppEnvironment.shared)
                )
            }
            return AnyView(ContactUserInfoView(
                viewModel: ContactUserInfoViewModel(
                    accountId: request.accountId,
                    isCurrentUser: request.accountId == IMKitClient.instance.account(),
                    isRobot: request.isRobot
                ),
                token: chatToken.styleMode == .fun ? .fun : .normal,
                onOpenChat: openP2PChat
            ))
        }
        chatConfig.userProfileRouter = ChatUserProfileRouter { request, completion in
            completion(.success(.route(.userProfile(request))))
        }
        chatConfig.mentionSelectionHandler = ExampleChatSelectionBoundaryService.shared.mentionSelectionHandler
        chatConfig.p2pDiscussSelectionHandler = ExampleChatSelectionBoundaryService.shared.p2pDiscussSelectionHandler
        chatConfig.forwardSelectionHandler = ExampleChatSelectionBoundaryService.shared.forwardSelectionHandler
        chatConfig.p2pSettingPinMessagesViewProvider = { conversationId, token, networkOperationGuard, onSelectMessage, onBack in
            AnyView(ExamplePinMessagesHostView(
                conversationId: conversationId,
                token: token,
                networkOperationGuard: networkOperationGuard,
                onSelectMessage: onSelectMessage,
                onBack: onBack
            ))
        }
        chatConfig.teamSettingViewProvider = { teamId, _ in
            let chatStyle = ChatSwiftUIConfigCenter.shared.current().styleMode
            if chatStyle == .fun {
                return AnyView(FunTeamSettingView(
                    teamId: teamId,
                    teamType: .normal,
                    config: NETeamSwiftUIConfigCenter.shared.current()
                ))
            }
            return AnyView(NormalTeamSettingView(
                teamId: teamId,
                teamType: .normal,
                config: NETeamSwiftUIConfigCenter.shared.current()
            ))
        }
        chatConfig.teamSettingViewProviderWithBackAction = { teamId, _, onBack in
            let chatStyle = ChatSwiftUIConfigCenter.shared.current().styleMode
            if chatStyle == .fun {
                return AnyView(FunTeamSettingView(
                    teamId: teamId,
                    teamType: .normal,
                    config: NETeamSwiftUIConfigCenter.shared.current(),
                    onBack: onBack
                ))
            }
            return AnyView(NormalTeamSettingView(
                teamId: teamId,
                teamType: .normal,
                config: NETeamSwiftUIConfigCenter.shared.current(),
                onBack: onBack
            ))
        }
        chatConfig.teamSettingViewProviderWithActions = { teamId, _, actions in
            let chatStyle = ChatSwiftUIConfigCenter.shared.current().styleMode
            var embeddedTeamConfig = NETeamSwiftUIConfigCenter.shared.current()
            embeddedTeamConfig.pinMessagesPushViewProvider = { conversationId, context, onBack in
                AnyView(ExamplePinMessagesHostView(
                    conversationId: conversationId,
                    token: context.style == .fun ? .fun : .normal,
                    networkOperationGuard: { DemoNetworkPresentation.allowsNetworkOperation },
                    onSelectMessage: actions.onSelectMessage,
                    onBack: onBack
                ))
            }
            embeddedTeamConfig.historySearchPushViewProvider = { conversationId, context, onBack in
                AnyView(TeamHistorySearchHostView(
                    conversationId: conversationId,
                    conversationName: context.snapshot.name,
                    token: context.style == .fun ? .fun : .normal,
                    fileInteractionHandler: chatBoundaryService.fileInteractionHandler,
                    mediaPreviewHandler: chatBoundaryService.mediaPreviewHandler,
                    onSelectMessage: actions.onSelectMessage,
                    onBack: onBack
                ))
            }
            if chatStyle == .fun {
                return AnyView(FunTeamSettingView(
                    teamId: teamId,
                    teamType: .normal,
                    config: embeddedTeamConfig,
                    onBack: actions.onBack
                ))
            }
            return AnyView(NormalTeamSettingView(
                teamId: teamId,
                teamType: .normal,
                config: embeddedTeamConfig,
                onBack: actions.onBack
            ))
        }

        ChatSwiftUIConfigCenter.shared.update(chatConfig)
        NEChatUIKitSwiftUIClient.shared.setup(
            config: chatConfig,
            registerLegacyRoutes: true
        )
        DemoPushConfigStore.applySavedConfig()
        NEChatUIKitSwiftUIClient.shared.installPushRoutePayloadBeforeSend()

        var conversationConfig = ConversationSwiftUIConfig()
        conversationConfig.showScanQREntry = false
        conversationConfig.searchHandler = {
            Router.shared.use(SearchContactPageRouter)
        }
        conversationConfig.bodyTopContentProvider = { _ in
            AnyView(ConversationSecurityWarningBannerView(message: localizable("security_warning")))
        }
        NEConversationUIKitSwiftUIClient.shared.setup(config: conversationConfig)

        var contactConfig = ContactSwiftUIConfig()
        contactConfig.title = NEContactUIKitSwiftUIBundle.localized("contact", value: "Contacts")
        contactConfig.showTitleBar = true
        contactConfig.showSearchEntry = true
        contactConfig.showAddEntry = true
        contactConfig.showsAIRobotEntry = false
        contactConfig.currentUserInfoViewProvider = { _ in
            AnyView(
                MineView()
                    .environmentObject(AppEnvironment.shared)
            )
        }
        NEContactUIKitSwiftUIClient.shared.setup(config: contactConfig)

        NETeamUIKitSwiftUIClient.shared.setup()
        NETeamUIKitSwiftUIClient.shared.avatarSelectionHandler = chatBoundaryService.teamAvatarSelectionHandler
        NETeamUIKitSwiftUIClient.shared.memberInviteSelectionHandler = ExampleChatSelectionBoundaryService.shared.teamMemberInviteSelectionHandler
        NEAISearchSwiftUIClient.shared.setupInit()

        NETeamUIKitSwiftUIClient.shared.memberProfileRouter = TeamMemberProfileRouter { request, completion in
            completion(.success(.cancelled))
        }
        NETeamUIKitSwiftUIClient.shared.onOpenTeamChat = { conversationId in
            guard let teamId = V2NIMConversationIdUtil.conversationTargetId(conversationId) else {
                return
            }
            NEChatUIKitSwiftUIClient.shared.router.enqueue(.teamChat(ChatSessionContext(
                kind: .team,
                conversationId: conversationId,
                sessionId: teamId
            )))
        }
        var teamConfig = NETeamSwiftUIConfig()
        teamConfig.pinMessagesPushViewProvider = { conversationId, context, onBack in
            AnyView(ExamplePinMessagesHostView(
                conversationId: conversationId,
                token: context.style == .fun ? .fun : .normal,
                networkOperationGuard: { DemoNetworkPresentation.allowsNetworkOperation },
                onSelectMessage: { selection in
                    openPinnedMessage(selection, fallbackConversationId: conversationId)
                },
                onBack: onBack
            ))
        }
        teamConfig.historySearchPushViewProvider = { conversationId, context, onBack in
            let token: ChatThemeToken = context.style == .fun ? .fun : .normal
            return AnyView(TeamHistorySearchHostView(
                conversationId: conversationId,
                conversationName: context.snapshot.name,
                token: token,
                fileInteractionHandler: chatConfig.fileInteractionHandler,
                mediaPreviewHandler: chatConfig.mediaPreviewHandler,
                onSelectMessage: { selection in
                    openPinnedMessage(selection, fallbackConversationId: conversationId)
                },
                onBack: onBack
            ))
        }
        teamConfig.memberProfilePushViewProvider = { request, style in
            if request.isCurrentUser {
                return AnyView(
                    MineView()
                        .environmentObject(AppEnvironment.shared)
                )
            }
            return AnyView(ContactUserInfoView(
                viewModel: ContactUserInfoViewModel(
                    accountId: request.accountId,
                    isCurrentUser: request.isCurrentUser
                ),
                token: style == .fun ? .fun : .normal,
                onOpenChat: { accountId, title in
                    enqueueP2PChat(accountId: accountId, title: title)
                }
            ))
        }
        NETeamSwiftUIConfigCenter.shared.update(teamConfig)

        syncSwiftUIModuleTheme(AppEnvironment.shared.themeMode)
    }

    static func syncSwiftUIModuleTheme(_ mode: ThemeMode) {
        let chatStyle: ChatStyleMode = mode == .fun ? .fun : .normal
        let conversationStyle: ConversationStyleMode = mode == .fun ? .fun : .normal
        let contactStyle: ContactStyleMode = mode == .fun ? .fun : .normal
        let teamStyle: NETeamSwiftUIStyleMode = mode == .fun ? .fun : .normal

        var chatConfig = ChatSwiftUIConfigCenter.shared.current()
        chatConfig.styleMode = chatStyle
        NEChatUIKitSwiftUIClient.shared.updateConfig(chatConfig)

        var conversationConfig = ConversationSwiftUIConfigCenter.shared.current()
        conversationConfig = conversationConfig.resolvingStyle(conversationStyle)
        NEConversationUIKitSwiftUIClient.shared.updateConfig(conversationConfig)

        var contactConfig = ContactSwiftUIConfigCenter.shared.config
        contactConfig.styleMode = contactStyle
        NEContactUIKitSwiftUIClient.shared.updateConfig(contactConfig)

        var teamConfig = NETeamSwiftUIConfigCenter.shared.current()
        teamConfig.styleMode = teamStyle
        NETeamSwiftUIConfigCenter.shared.update(teamConfig)
    }

    static func syncSwiftUIModuleLanguage() {
        var chatConfig = ChatSwiftUIConfigCenter.shared.current()
        chatConfig.translationLanguages = ChatSwiftUIConfig.defaultTranslationLanguages()
        NEChatUIKitSwiftUIClient.shared.updateConfig(chatConfig)

        var contactConfig = ContactSwiftUIConfigCenter.shared.config
        contactConfig.title = NEContactUIKitSwiftUIBundle.localized("contact", value: "Contacts")
        NEContactUIKitSwiftUIClient.shared.updateConfig(contactConfig)
    }

    private static func openSecurityReportPage() {
        guard let url = URL(string: "https://yunxin.163.com/survey/report") else {
            return
        }
        Task { @MainActor in
            ExampleWebRouteCenter.shared.open(title: url.absoluteString, url: url)
        }
    }

    // MARK: - YXLogin Setup

    private static func setupYXLogin() {
        let config = YXConfig()
        config.appKey = ServerConfig.getAppkey()
        config.parentScope = NSNumber(integerLiteral: 2)
        config.scope = NSNumber(integerLiteral: 7)
        #if DEBUG
            config.isOnline = false
        #else
            config.isOnline = true
        #endif
        AuthorManager.shareInstance()?.initAuthor(with: config)
    }

    // MARK: - IM SDK Login

    static func loginIM(accid: String, token: String, completion: @escaping () -> Void) {
        let option = V2NIMLoginOption()
        option.syncLevel = .DATA_SYNC_TYPE_LEVEL_BASIC
        IMKitClient.instance.login(accid, token, option) { error in
            if let error {
                if error.code == inValidTokenCode {
                    onLoginFailure?(localizable("login_token_expired"))
                } else if error.code == userBannedCode {
                    onLoginFailure?(localizable("account_forbidden"))
                } else {
                    onLoginFailure?(DemoNetworkPresentation.message(for: error, fallbackKey: "login_failed"))
                }
            } else {
                onLoginSuccess?()
            }
            completion()
        }
    }

    // MARK: - YXLogin phone/email login

    static func startYXLogin() {
        let config = YXConfig()
        config.appKey = ServerConfig.getAppkey()
        config.parentScope = NSNumber(integerLiteral: 2)
        config.scope = NSNumber(integerLiteral: 7)
        #if DEBUG
            config.isOnline = false
        #else
            config.isOnline = true
        #endif

        // Use phone login by default (matches IMUIKitExample)
        config.type = .phone
        config.supportInternationalize = true

        AuthorManager.shareInstance()?.initAuthor(with: config)
        AuthorManager.shareInstance()?.startLogin { userInfo, error in
            if let err = error as? NSError, err.code > 0 {
                onLoginFailure?(DemoNetworkPresentation.message(for: err, fallbackKey: "login_failed"))
                return
            }
            guard let userInfo,
                  let accid = userInfo.imAccid,
                  let token = userInfo.imToken
            else {
                return
            }
            loginIM(accid: accid, token: token) {}
        }
    }

    // MARK: - POC direct IM login

    static func loginPOC(account: String, token: String) {
        let option = V2NIMLoginOption()
        option.syncLevel = .DATA_SYNC_TYPE_LEVEL_BASIC
        IMKitClient.instance.login(account, token, option) { error in
            if let error {
                if error.code == inValidTokenCode {
                    onLoginFailure?(localizable("login_token_expired"))
                } else if error.code == userBannedCode {
                    onLoginFailure?(localizable("account_forbidden"))
                } else {
                    onLoginFailure?(DemoNetworkPresentation.message(for: error, fallbackKey: "login_failed"))
                }
            } else {
                onLoginSuccess?()
            }
        }
    }

    // MARK: - Post-login initialization

    static func initAfterLogin() {
        setupSwiftUIModules()
        warmUpSharedCaches()
        AppDelegate.active?.flushPendingPushNotifications()
    }

    // MARK: - Logout

    static func logout(completion: ((NSError?) -> Void)? = nil) {
        guard let authorManager = AuthorManager.shareInstance() else {
            IMKitClient.instance.logoutIM { error in
                completion?(error)
            }
            return
        }

        authorManager.logout { _, _ in
            IMKitClient.instance.logoutIM { error in
                UserDefaults.standard.removeObject(forKey: "poc.accountId")
                UserDefaults.standard.removeObject(forKey: "poc.accountIdToken")
                NEFriendUserCache.shared.removeAllFriendInfo()
                NESubscribeManager.shared.cleanCache()
                completion?(error)
            }
        }
    }

    private static func warmUpSharedCaches() {
        _ = NEFriendUserCache.shared
        _ = ContactRepo.shared
        _ = TeamRepo.shared

        if !IMKitClient.instance.account().isEmpty,
           NEFriendUserCache.shared.isEmpty()
        {
            ContactRepo.shared.getContactList { _, error in
                if let error {
                    NEALog.infoLog("AppBootstrap", desc: "warmUpSharedCaches getContactList error: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func openPinnedMessage(_ selection: PinMessageSelection, fallbackConversationId: String) {
        guard let route = chatRoute(for: selection, fallbackConversationId: fallbackConversationId) else {
            return
        }
        NEChatUIKitSwiftUIClient.shared.router.enqueue(route)
    }

    private static func enqueueP2PChat(accountId: String, title: String) {
        guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
            return
        }
        let context = ChatSessionContext(
            kind: .p2p,
            conversationId: conversationId,
            title: title,
            sessionId: accountId,
            sessionName: title
        )
        NEChatUIKitSwiftUIClient.shared.router.enqueue(.p2pChat(context))
    }

    private static func chatRoute(for selection: PinMessageSelection, fallbackConversationId: String) -> NEChatSwiftUIRoute? {
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

    private static func chatKind(for message: V2NIMMessage?, conversationId: String) -> ChatSessionKind {
        switch message?.conversationType ?? V2NIMConversationIdUtil.conversationType(conversationId) {
        case .CONVERSATION_TYPE_P2P:
            return .p2p
        case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
            return .team
        default:
            return .history
        }
    }
}

struct DemoPushConfigModel: Equatable {
    var configMap: [String: AnyHashable] = [:]
    var customJson: String?
    var config = DemoPushBaseConfig()

    var pushEnabled: Bool {
        get { boolValue(configMap[#keyPath(V2NIMMessagePushConfig.pushEnabled)]) ?? config.pushEnabled }
        set { configMap[#keyPath(V2NIMMessagePushConfig.pushEnabled)] = newValue }
    }

    var pushNickEnabled: Bool {
        get { boolValue(configMap[#keyPath(V2NIMMessagePushConfig.pushNickEnabled)]) ?? config.pushNickEnabled }
        set { configMap[#keyPath(V2NIMMessagePushConfig.pushNickEnabled)] = newValue }
    }

    var pushContent: String {
        get { stringValue(configMap[#keyPath(V2NIMMessagePushConfig.pushContent)]) ?? config.pushContent }
        set { update(newValue, forKey: #keyPath(V2NIMMessagePushConfig.pushContent)) }
    }

    var pushPayload: String {
        get { stringValue(configMap[#keyPath(V2NIMMessagePushConfig.pushPayload)]) ?? config.pushPayload }
        set { update(newValue, forKey: #keyPath(V2NIMMessagePushConfig.pushPayload)) }
    }

    var forcePush: Bool {
        get { boolValue(configMap[#keyPath(V2NIMMessagePushConfig.forcePush)]) ?? config.forcePush }
        set { configMap[#keyPath(V2NIMMessagePushConfig.forcePush)] = newValue }
    }

    var forcePushContent: String {
        get { stringValue(configMap[#keyPath(V2NIMMessagePushConfig.forcePushContent)]) ?? config.forcePushContent }
        set { update(newValue, forKey: #keyPath(V2NIMMessagePushConfig.forcePushContent)) }
    }

    var forcePushAccountIds: String {
        get {
            stringValue(configMap[#keyPath(V2NIMMessagePushConfig.forcePushAccountIds)])
                ?? config.forcePushAccountIds.joined(separator: ",")
        }
        set { update(newValue, forKey: #keyPath(V2NIMMessagePushConfig.forcePushAccountIds)) }
    }

    mutating func update(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            configMap.removeValue(forKey: key)
        } else {
            configMap[key] = value
        }
    }

    func dictionaryRepresentation() -> [String: Any] {
        var configDictionary: [String: Any] = [
            "pushEnabled": config.pushEnabled,
            "pushNickEnabled": config.pushNickEnabled,
            "forcePush": config.forcePush,
        ]
        if !config.pushContent.isEmpty {
            configDictionary["pushContent"] = config.pushContent
        }
        if !config.pushPayload.isEmpty {
            configDictionary["pushPayload"] = config.pushPayload
        }
        if !config.forcePushContent.isEmpty {
            configDictionary["forcePushContent"] = config.forcePushContent
        }
        if !config.forcePushAccountIds.isEmpty {
            configDictionary["forcePushAccountIds"] = config.forcePushAccountIds
        }
        var dictionary: [String: Any] = [
            "configMap": configMap,
            "config": configDictionary,
        ]
        if let customJson, !customJson.isEmpty {
            dictionary["customJson"] = customJson
        }
        return dictionary
    }

    static func model(from dictionary: [String: Any]) -> DemoPushConfigModel {
        var model = DemoPushConfigModel()
        if let configMap = dictionary["configMap"] as? [String: Any] {
            model.configMap = configMap.reduce(into: [String: AnyHashable]()) { result, item in
                if let value = item.value as? AnyHashable {
                    result[item.key] = value
                }
            }
        }
        model.customJson = dictionary["customJson"] as? String
        if let configDictionary = dictionary["config"] as? [String: Any] {
            model.config = DemoPushBaseConfig.model(from: configDictionary)
        }
        return model
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let values = value as? [String] {
            return values.joined(separator: ",")
        }
        if let values = value as? [Any] {
            let strings = values.compactMap { $0 as? String }
            return strings.isEmpty ? nil : strings.joined(separator: ",")
        }
        return nil
    }
}

struct DemoPushBaseConfig: Equatable {
    var pushEnabled = true
    var pushNickEnabled = true
    var pushContent = ""
    var pushPayload = ""
    var forcePush = false
    var forcePushContent = ""
    var forcePushAccountIds = [String]()

    static func model(from dictionary: [String: Any]) -> DemoPushBaseConfig {
        var model = DemoPushBaseConfig()
        if let value = dictionary["pushEnabled"] as? Bool {
            model.pushEnabled = value
        }
        if let value = dictionary["pushNickEnabled"] as? Bool {
            model.pushNickEnabled = value
        }
        model.pushContent = dictionary["pushContent"] as? String ?? ""
        model.pushPayload = dictionary["pushPayload"] as? String ?? ""
        if let value = dictionary["forcePush"] as? Bool {
            model.forcePush = value
        }
        model.forcePushContent = dictionary["forcePushContent"] as? String ?? ""
        if let values = dictionary["forcePushAccountIds"] as? [String] {
            model.forcePushAccountIds = values
        }
        return model
    }
}

enum DemoPushConfigStore {
    private static let filename = "im_sdk_push_config"
    private static var cachedModel: DemoPushConfigModel?

    static func getConfig() -> DemoPushConfigModel {
        if let cachedModel {
            return cachedModel
        }
        let model = loadObjectFromDisk() ?? legacyUserDefaultsModel()
        cachedModel = model
        return model
    }

    static func saveConfig(_ model: DemoPushConfigModel) {
        cachedModel = model
        saveObjectToDisk(model)
        SettingRepo.shared.setMessagePushConfig(makePushConfig(from: model))
    }

    static func applySavedConfig() {
        SettingRepo.shared.setMessagePushConfig(makePushConfig(from: getConfig()))
    }

    static func makePushConfig(from model: DemoPushConfigModel = getConfig()) -> V2NIMMessagePushConfig {
        let config = V2NIMMessagePushConfig()
        var customMap = manualConfigMap(from: model)
        if let parsedMap = dictionary(fromJSONString: model.customJson ?? "") {
            customMap = parsedMap
        }
        apply(customMap, to: config)
        return config
    }

    private static func legacyUserDefaultsModel() -> DemoPushConfigModel {
        let defaults = UserDefaults.standard
        var model = DemoPushConfigModel()
        model.pushEnabled = defaults.object(forKey: "push.config.enabled") as? Bool ?? true
        model.pushNickEnabled = defaults.object(forKey: "push.config.nick") as? Bool ?? true
        model.forcePush = defaults.bool(forKey: "push.config.force")
        model.pushContent = defaults.string(forKey: "push.config.content") ?? ""
        model.pushPayload = defaults.string(forKey: "push.config.payload") ?? ""
        model.forcePushContent = defaults.string(forKey: "push.config.forceContent") ?? ""
        model.forcePushAccountIds = defaults.string(forKey: "push.config.forceAccounts") ?? ""
        model.customJson = defaults.string(forKey: "push.config.json")
        return model
    }

    private static func manualConfigMap(from model: DemoPushConfigModel) -> [String: Any] {
        var map: [String: Any] = [
            "pushEnabled": model.pushEnabled,
            "pushNickEnabled": model.pushNickEnabled,
            "forcePush": model.forcePush,
        ]
        if let value = nonEmpty(model.pushContent) {
            map["pushContent"] = value
        }
        if let value = nonEmpty(model.pushPayload) {
            map["pushPayload"] = value
        }
        if let value = nonEmpty(model.forcePushContent) {
            map["forcePushContent"] = value
        }
        if let value = nonEmpty(model.forcePushAccountIds) {
            map["forcePushAccountIds"] = value
        }
        return map
    }

    private static func saveObjectToDisk(_ object: DemoPushConfigModel) {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let archiveURL = documentsDirectory.appendingPathComponent(filename)
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: object.dictionaryRepresentation(),
                format: .binary,
                options: 0
            )
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            print("saveObjectToDisk error: \(error)")
        }
    }

    private static func loadObjectFromDisk() -> DemoPushConfigModel? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let archiveURL = documentsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            return nil
        }
        do {
            let retrievedData = try Data(contentsOf: archiveURL)
            let propertyList = try PropertyListSerialization.propertyList(from: retrievedData, options: [], format: nil)
            if let dictionary = propertyList as? [String: Any],
               dictionary["configMap"] != nil || dictionary["customJson"] != nil || dictionary["config"] != nil {
                return DemoPushConfigModel.model(from: dictionary)
            }
        } catch {
            print("loadObjectFromDisk error: \(error)")
        }
        try? FileManager.default.removeItem(at: archiveURL)
        return nil
    }

    private static func apply(_ map: [String: Any], to config: V2NIMMessagePushConfig) {
        if let value = boolValue(map["pushEnabled"]) {
            config.pushEnabled = value
        }
        if let value = boolValue(map["pushNickEnabled"]) {
            config.pushNickEnabled = value
        }
        if let value = nonEmpty(map["pushContent"] as? String) {
            config.pushContent = value
        }
        if let value = nonEmpty(map["pushPayload"] as? String) {
            config.pushPayload = value
        }
        if let value = boolValue(map["forcePush"]) {
            config.forcePush = value
        }
        if let value = nonEmpty(map["forcePushContent"] as? String) {
            config.forcePushContent = value
        }
        if let accounts = accountIds(from: map["forcePushAccountIds"]), !accounts.isEmpty {
            config.forcePushAccountIds = accounts
        }
    }

    private static func dictionary(fromJSONString string: String) -> [String: Any]? {
        guard let trimmed = nonEmpty(string),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func accountIds(from value: Any?) -> [String]? {
        if let accounts = value as? [String] {
            return accounts.compactMap(nonEmpty)
        }
        if let accounts = value as? [Any] {
            let values = accounts.compactMap { $0 as? String }.compactMap(nonEmpty)
            return values.isEmpty ? nil : values
        }
        if let string = value as? String {
            let values = string
                .split(whereSeparator: { ",;\n\r".contains($0) })
                .compactMap { nonEmpty(String($0)) }
            return values.isEmpty ? nil : values
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ExamplePinMessagesHostView: View {
    let conversationId: String
    let token: ChatThemeToken
    let networkOperationGuard: () -> Bool
    let onSelectMessage: (PinMessageSelection) -> Void
    let onBack: () -> Void
    @StateObject private var interactionViewModel = MineCollectionInteractionViewModel(usesForwardSelectionHandler: false)

    var body: some View {
        PinMessagesView(
            viewModel: PinMessagesViewModel(
                conversationId: conversationId,
                networkOperationGuard: networkOperationGuard
            ),
            token: token,
            onContentSelect: { row in
                interactionViewModel.open(row)
            },
            onSelectMessage: onSelectMessage,
            onCopy: { row in
                interactionViewModel.copy(row)
            },
            onForward: { row in
                interactionViewModel.forward(row)
            },
            onForwardMessage: { row, sourceMessage in
                interactionViewModel.forward(row, sourceMessage: sourceMessage)
            },
            onOpenURL: { url, displayText, source, row in
                interactionViewModel.openURL(
                    url,
                    displayText: displayText,
                    source: source,
                    message: row
                )
            },
            onBack: onBack,
            canCopy: { row in
                MineCollectionInteractionViewModel.canCopy(row)
            },
            canForward: { row in
                MineCollectionInteractionViewModel.canForward(row)
            },
            playingAudioMessageId: interactionViewModel.playingAudioMessageId,
            onStopAudioPlayback: interactionViewModel.stopAudioPlayback
        )
        .exampleCompatibleNavigationDestination(item: $interactionViewModel.route) { route in
            interactionDestination(route: route)
        }
        .exampleCompatibleNavigationDestination(item: $interactionViewModel.webRoute) { route in
            DemoWebPageView(title: route.title, url: route.url)
                .demoHidesTabBar()
        }
        .fullScreenCover(item: $interactionViewModel.presentedPreview) { preview in
            presentedPreviewDestination(preview, token: token)
                .demoHidesTabBar()
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
    private func interactionDestination(route: NEChatSwiftUIRoute) -> some View {
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
                browserDestination: pinBrowserDestination
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
                browserDestination: pinBrowserDestination,
                onSaveMedia: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
            )
        case let .locationDetail(location):
            LocationDetailView(location: location, token: token)
        default:
            EmptyView()
        }
    }

    private func pinBrowserDestination(url: URL, title: String) -> AnyView {
        AnyView(
            DemoWebPageView(title: title, url: url)
                .demoHidesTabBar()
        )
    }

    @ViewBuilder
    private func presentedPreviewDestination(_ preview: CollectionPresentedPreview, token: ChatThemeToken) -> some View {
        switch preview {
        case let .text(previewState):
            NavigationStack {
                ChatTextPreviewView(
                    preview: previewState,
                    token: token,
                    browserDestination: pinBrowserDestination
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
}

private struct TeamHistorySearchHostView: View {
    let conversationId: String
    let conversationName: String
    let token: ChatThemeToken
    let fileInteractionHandler: ChatFileInteractionHandling?
    let mediaPreviewHandler: ChatMediaPreviewHandling?
    let onSelectMessage: (PinMessageSelection) -> Void
    let onBack: () -> Void
    @StateObject private var interactionViewModel = MineCollectionInteractionViewModel(usesForwardSelectionHandler: false)

    var body: some View {
        HistorySearchView(
            viewModel: HistorySearchViewModel(
                conversationId: conversationId,
                fileInteractionHandler: fileInteractionHandler,
                mediaPreviewHandler: mediaPreviewHandler,
                conversationNameProvider: { conversationName }
            ),
            token: token,
            onSelectMessage: onSelectMessage,
            onForward: { row in
                interactionViewModel.forward(row)
            },
            onForwardMessage: { row, sourceMessage in
                interactionViewModel.forward(row, sourceMessage: sourceMessage)
            },
            onForwardMessageWithToast: { row, sourceMessage, presentToast in
                interactionViewModel.forward(
                    row,
                    sourceMessage: sourceMessage,
                    resultToastHandler: presentToast
                )
            },
            onOpenURL: { url, displayText, source, row in
                interactionViewModel.openURL(url, displayText: displayText, source: source, message: row)
            },
            onSaveMedia: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler,
            onBack: onBack,
            canForward: { row in
                MineCollectionInteractionViewModel.canForward(row)
            }
        )
        .navigationDestination(isPresented: interactionRouteIsPresentedBinding) {
            interactionDestination
        }
        .fullScreenCover(item: $interactionViewModel.presentedPreview) { preview in
            teamPresentedPreview(preview, token: token)
                .demoHidesTabBar()
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

    private var interactionRouteIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { interactionViewModel.route != nil },
            set: { isPresented in
                if !isPresented {
                    interactionViewModel.clearRoute()
                }
            }
        )
    }

    @ViewBuilder
    private var interactionDestination: some View {
        if let route = interactionViewModel.route {
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
                ChatTextPreviewView(preview: preview, token: token, onOpenURL: { url, displayText, preview in
                    interactionViewModel.openURL(
                        url,
                        displayText: displayText,
                        source: .textPreview,
                        preview: preview
                    )
                })
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
                    browserDestination: teamHistoryBrowserDestination,
                    onSaveMedia: ChatSwiftUIConfigCenter.shared.current().mediaImageSaveHandler
                )
            case let .locationDetail(location):
                LocationDetailView(location: location, token: token)
            default:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func teamHistoryBrowserDestination(url: URL, title: String) -> AnyView {
        AnyView(
            DemoWebPageView(title: title, url: url)
                .demoHidesTabBar()
        )
    }

    @ViewBuilder
    private func teamPresentedPreview(_ preview: CollectionPresentedPreview, token: ChatThemeToken) -> some View {
        switch preview {
        case let .text(previewState):
            ChatTextPreviewView(preview: previewState, token: token, onOpenURL: { url, displayText, textPreview in
                interactionViewModel.openURL(
                    url,
                    displayText: displayText,
                    source: .textPreview,
                    preview: textPreview
                )
            })
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
}
