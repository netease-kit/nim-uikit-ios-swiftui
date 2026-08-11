// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NERtcCallKit
import NERtcCallUIKit
import NIMSDK
import ObjectiveC
import PushKit
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, NERecordProvider {
    static weak var active: AppDelegate?
    private static var pendingPushUserInfos = [[String: Any]]()
    private var pushRegistry: PKPushRegistry?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Self.active = self
        NECommonClipboardServiceCenter.shared.configure(ExampleCommonClipboardService())
        NEAIUserManager.shared.setProvider(provider: self)
        DemoNavigationGestureInstaller.install()
        DemoKeyboardDismissalInstaller.install()
        configureTabBarBadgeAppearance()
        configureKeyboardDismissalAppearance()
        registerAPNS()
        if let userInfo = launchOptions?[.remoteNotification] as? [String: Any] {
            pushToChat(userInfo)
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        DemoKeyboardDismissalInstaller.install()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NIMSDK.shared().updateApnsToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

    // MARK: - NIMSDK Setup

    static func setupIM(_ appkey: String? = nil,
                        listener: NEIMKitClientListener? = AppDelegate.active) {
        let option = NIMSDKOption()
        option.appKey = appkey ?? AppKey.appKey
        option.apnsCername = AppKey.apnsCername
        option.pkCername = AppKey.pkCerName

        let v2Option = V2NIMSDKOption()
        // Must use the same NEChatKit key written by the setting page. The
        // previous literal was a different key, so the SDK always restarted
        // in local-conversation mode.
        v2Option.enableV2CloudConversation = UserDefaults.standard.value(forKey: keyEnableCloudConversation) as? Bool ?? false

        IMKitClient.instance.config.fcsEnable = false
        IMKitClient.instance.config.shouldSyncStickTopSessionInfos = true
        IMKitClient.instance.config.teamReceiptEnabled = true
        IMKitClient.instance.config.shouldSyncUnreadCount = true
        IMKitClient.instance.config.fetchAttachmentAutomaticallyAfterReceiving = true
        IMKitClient.instance.config.shouldConsiderRevokedMessageUnreadCount = true

        IMKitClient.instance.setupIM2(option, v2Option)
        if let listener {
            IMKitClient.instance.addLoginListener(listener)
        }
    }

    // MARK: - CallUIKit

    static func setupCallUIKit() {
        AppDelegate.active?.setupCallUIKit()
    }

    private func setupCallUIKit() {
      let setupConfig = NESetupConfig(appkey: ServerConfig.getAppkey())
      NECallEngine.sharedInstance().setup(setupConfig)
      NECallEngine.sharedInstance().setTimeout(30)
      NECallEngine.sharedInstance().setCall(self)
      
      let uiConfig = NECallUIKitConfig()
      NERtcCallUIKit.sharedInstance().setup(with: uiConfig)
      
      let registry = PKPushRegistry(queue: DispatchQueue.global())
      registry.delegate = self
      registry.desiredPushTypes = [PKPushType.voIP]
      DispatchQueue.main.async {
        self.pushRegistry = registry
      }

        Router.shared.register(CallViewRouter) { param in
            NotificationCenter.default.post(name: .neChatMediaPlaybackShouldStop, object: nil)
            if NEChatDetectNetworkTool.shareInstance.manager?.isReachable == false {
                NotificationCenter.default.post(name: .appToast, object: localizable("network_error"))
                return
            }

            let callParam = NEUICallParam()
            callParam.remoteUserAccid = param["remoteUserAccid"] as? String ?? ""
            callParam.remoteShowName = param["remoteShowName"] as? String ?? ""
            callParam.remoteAvatar = param["remoteAvatar"] as? String ?? ""
            if (param["type"] as? NSNumber)?.intValue == 1 {
                callParam.callType = .audio
            } else {
                callParam.callType = .video
            }

            NERtcCallUIKit.sharedInstance().call(with: callParam)
        }
    }

    func onRecordSend(_ config: NERecordConfig) {
        if NEChatDetectNetworkTool.shareInstance.manager?.isReachable == false,
           NECallEngine.sharedInstance().callStatus == .calling {
            return
        }

        guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(config.accId) else {
            return
        }
        let message = ChatRepo.shared.makeCallMessage(
            type: Int(config.callType.rawValue),
            status: Int(config.callState.rawValue)
        )
        ChatRepo.shared.sendMessage(message: message, conversationId: conversationId) { _, _, _ in }
    }

    // MARK: - APNs

    private func registerAPNS() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .appToast, object: localizable("open_push"))
                }
            }
        }
        UIApplication.shared.registerForRemoteNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    private func configureTabBarBadgeAppearance() {
        if #available(iOS 26.0, *) {
            return
        }
        let redDotTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.red,
            .font: UIFont.systemFont(ofSize: 8),
        ]
        let redDotPosition = UIOffset(horizontal: 6, vertical: 2)

        UITabBarItem.appearance().badgeColor = .clear
        UITabBarItem.appearance().setBadgeTextAttributes(redDotTextAttributes, for: .normal)
        UITabBarItem.appearance().setBadgeTextAttributes(redDotTextAttributes, for: .selected)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        [tabBarAppearance.stackedLayoutAppearance,
         tabBarAppearance.inlineLayoutAppearance,
         tabBarAppearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.badgeBackgroundColor = .clear
            itemAppearance.normal.badgeTextAttributes = redDotTextAttributes
            itemAppearance.normal.badgePositionAdjustment = redDotPosition
            itemAppearance.selected.badgeBackgroundColor = .clear
            itemAppearance.selected.badgeTextAttributes = redDotTextAttributes
            itemAppearance.selected.badgePositionAdjustment = redDotPosition
        }
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    private func configureKeyboardDismissalAppearance() {
        UIScrollView.appearance().keyboardDismissMode = .onDrag
    }

    func flushPendingPushNotifications() {
        guard !Self.pendingPushUserInfos.isEmpty else {
            return
        }
        let userInfos = Self.pendingPushUserInfos
        Self.pendingPushUserInfos.removeAll()
        userInfos.forEach { pushToChat($0) }
    }
}

private struct ExampleCommonClipboardService: NECommonClipboardService {
    func copyText(_ text: String) async -> NECommonBoundaryResult {
        await MainActor.run {
            UIPasteboard.general.string = text
        }
        return .success
    }
}

private enum DemoNavigationGestureInstaller {
    private static var didInstall = false

    static func install() {
        guard !didInstall else {
            return
        }
        didInstall = true
        UINavigationController.demoInstallInteractivePopGestureSupport()
    }
}

private enum DemoKeyboardDismissalInstaller {
    private static var handlerKey: UInt8 = 0
    private static var recognizerKey: UInt8 = 0

    static func install() {
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter { !$0.isHidden && $0.alpha > 0 }
                .forEach { install(in: $0) }
        }
    }

    private static func install(in window: UIWindow) {
        guard objc_getAssociatedObject(window, &recognizerKey) == nil else {
            return
        }

        let handler = DemoKeyboardDismissalGestureHandler()
        let recognizer = UITapGestureRecognizer(target: handler, action: #selector(DemoKeyboardDismissalGestureHandler.dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = handler
        window.addGestureRecognizer(recognizer)

        objc_setAssociatedObject(window, &handlerKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(window, &recognizerKey, recognizer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class DemoKeyboardDismissalGestureHandler: NSObject, UIGestureRecognizerDelegate {
    @objc func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else {
            return true
        }
        return !touchedView.demoIsInsideKeyboardInput
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private extension UIView {
    var demoIsInsideKeyboardInput: Bool {
        var view: UIView? = self
        while let current = view {
            if current is UITextField || current is UITextView {
                return true
            }
            view = current.superview
        }
        return false
    }
}

private final class DemoInteractivePopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else {
            return false
        }
        guard navigationController.viewControllers.count > 1 else {
            return false
        }
        return navigationController.transitionCoordinator == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

private var demoInteractivePopGestureDelegateKey: UInt8 = 0

private extension UINavigationController {
    static func demoInstallInteractivePopGestureSupport() {
        swizzleInstanceMethod(
            originalSelector: #selector(viewDidLoad),
            swizzledSelector: #selector(demo_interactivePop_viewDidLoad)
        )
        swizzleInstanceMethod(
            originalSelector: #selector(viewDidLayoutSubviews),
            swizzledSelector: #selector(demo_interactivePop_viewDidLayoutSubviews)
        )
        swizzleInstanceMethod(
            originalSelector: #selector(viewDidAppear(_:)),
            swizzledSelector: #selector(demo_interactivePop_viewDidAppear(_:))
        )
    }

    private static func swizzleInstanceMethod(originalSelector: Selector,
                                             swizzledSelector: Selector) {
        guard let originalMethod = class_getInstanceMethod(UINavigationController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UINavigationController.self, swizzledSelector)
        else {
            return
        }
        let didAddMethod = class_addMethod(
            UINavigationController.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        if didAddMethod {
            class_replaceMethod(
                UINavigationController.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    @objc func demo_interactivePop_viewDidLoad() {
        demo_interactivePop_viewDidLoad()
        demo_enableInteractivePopGesture()
    }

    @objc func demo_interactivePop_viewDidLayoutSubviews() {
        demo_interactivePop_viewDidLayoutSubviews()
        demo_enableInteractivePopGesture()
    }

    @objc func demo_interactivePop_viewDidAppear(_ animated: Bool) {
        demo_interactivePop_viewDidAppear(animated)
        demo_enableInteractivePopGesture()
    }

    func demo_enableInteractivePopGesture() {
        guard let gesture = interactivePopGestureRecognizer else {
            return
        }
        let popDelegate = demoInteractivePopGestureDelegate
        popDelegate.navigationController = self
        gesture.delegate = popDelegate
        gesture.isEnabled = true
    }

    private var demoInteractivePopGestureDelegate: DemoInteractivePopGestureDelegate {
        if let delegate = objc_getAssociatedObject(self, &demoInteractivePopGestureDelegateKey) as? DemoInteractivePopGestureDelegate {
            return delegate
        }
        let delegate = DemoInteractivePopGestureDelegate()
        objc_setAssociatedObject(
            self,
            &demoInteractivePopGestureDelegateKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return delegate
    }
}

// MARK: - AIUserAgentProvider

extension AppDelegate: AIUserAgentProvider {
    func getAISearchUser(_ users: [V2NIMAIUser]) -> V2NIMAIUser? {
        users.first { $0.accountId == "search" }
    }

    func getAITranslateUser(_ users: [V2NIMAIUser]) -> V2NIMAIUser? {
        users.first { $0.accountId == "translation" }
    }

    func getAITranslateLangs(_ users: [V2NIMAIUser]) -> [String] {
        ChatSwiftUIConfig.defaultInputTranslationLanguages().map(\.code)
    }
}

// MARK: - NEIMKitClientListener

extension AppDelegate: NEIMKitClientListener {
    func onLoginFailed(_ error: V2NIMError) {
        if error.code == userBannedCode {
            NotificationCenter.default.post(name: .appToast, object: localizable("account_forbidden"))
            NotificationCenter.default.post(name: .logout, object: nil)
        }
    }

    func onKickedOffline(_ detail: V2NIMKickedOfflineDetail) {
        if detail.reason == .KICKED_OFFLINE_REASON_SERVER {
            NotificationCenter.default.post(name: .appToast, object: localizable("account_kicked_offline"))
            NotificationCenter.default.post(name: .logout, object: nil)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let userInfo = response.notification.request.content.userInfo as? [String: Any] {
            pushToChat(userInfo)
        }
        completionHandler()
    }

    fileprivate func pushToChat(_ userInfo: [String: Any]) {
        guard !IMKitClient.instance.account().isEmpty,
              NEChatUIKitSwiftUIClient.shared.router.isLegacyRouteRegistered
        else {
            Self.pendingPushUserInfos.append(userInfo)
            return
        }

        guard let sessionId = userInfo["sessionId"] as? String,
              let sessionType = userInfo["sessionType"] as? String
        else {
            return
        }

        switch sessionType {
        case "p2p":
            guard let conversationId = V2NIMConversationIdUtil.p2pConversationId(sessionId) else {
                return
            }
            NEChatUIKitSwiftUIClient.shared.router.enqueue(.p2pChat(ChatSessionContext(
                kind: .p2p,
                conversationId: conversationId,
                sessionId: sessionId
            )))
        case "team":
            guard let conversationId = V2NIMConversationIdUtil.teamConversationId(sessionId) else {
                return
            }
            NEChatUIKitSwiftUIClient.shared.router.enqueue(.teamChat(ChatSessionContext(
                kind: .team,
                conversationId: conversationId,
                sessionId: sessionId
            )))
        default:
            break
        }
    }
}

// MARK: - PKPushRegistryDelegate

extension AppDelegate: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        guard !pushCredentials.token.isEmpty else {
            return
        }
        NIMSDK.shared().updatePushKitToken(pushCredentials.token)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard payload.dictionaryPayload["nim"] != nil else {
            completion()
            return
        }

        let param = NECallSystemIncomingCallParam()
        param.payload = payload.dictionaryPayload
        NotificationCenter.default.post(name: .neChatMediaPlaybackShouldStop, object: nil)

        if #available(iOS 17.4, *) {
            NECallEngine.sharedInstance().reportIncomingCall(with: param) { error, _ in
                if let error {
                    NEChatSwiftUILogger.log("callkit incoming accept failed: \(error.localizedDescription)")
                }
            } hangupCompletion: { error in
                if let error {
                    NEChatSwiftUILogger.log("callkit incoming hangup failed: \(error.localizedDescription)")
                }
            }
        }

        completion()
    }
}
