// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI
import UIKit

/// Main tab bar interface with Conversation, Contact, and Mine tabs.
/// Uses the same tab ordering and Normal/Fun assets as IMUIKitSwift NETabBarController.
struct MainTabView: View {
    @StateObject private var routeState = AppRouteState()
    @EnvironmentObject var environment: AppEnvironment
    private let chatBoundaryService = ExampleChatNativeBoundaryService.shared
    private let sessionOwnerID: UUID?
    @State private var activationOwnerID: UUID?

    init(sessionOwnerID: UUID? = nil) {
        self.sessionOwnerID = sessionOwnerID
    }

    private var resolvedSessionOwnerID: UUID {
        sessionOwnerID ?? environment.loginSessionID
    }

    var body: some View {
        TabView(selection: $routeState.selectedTab) {
            ConversationTabRootView(
                isActive: routeState.selectedTab == .conversation,
                sessionOwnerID: resolvedSessionOwnerID
            )
                .tabItem {
                    tabIcon(.conversation)
                    Text(AppTab.conversation.title())
                }
                .modifier(ModernTabBadgeModifier(showsBadge: routeState.conversationHasUnread))
                .tag(AppTab.conversation)

            ContactTabRootView(
                isActive: routeState.selectedTab == .contact,
                sessionOwnerID: resolvedSessionOwnerID
            )
                .tabItem {
                    tabIcon(.contact)
                    Text(AppTab.contact.title())
                }
                .modifier(ModernTabBadgeModifier(showsBadge: routeState.contactHasUnread))
                .tag(AppTab.contact)

            MineTabRootView(
                isActive: routeState.selectedTab == .mine,
                sessionOwnerID: resolvedSessionOwnerID
            )
                .tabItem {
                    tabIcon(.mine)
                    Text(AppTab.mine.title())
                }
                .tag(AppTab.mine)
        }
        .accentColor(environment.themeMode == .normal ? NEUIKitSwiftUIStyle.ColorToken.normalTheme : NEUIKitSwiftUIStyle.ColorToken.funTheme)
        .modifier(ExampleChatMediaPickerModifier(service: chatBoundaryService))
        .modifier(ExampleChatLocationPickerModifier(service: chatBoundaryService))
        .modifier(ExampleChatCameraCaptureModifier(service: chatBoundaryService))
        .modifier(ExampleChatVideoPreviewModifier(service: chatBoundaryService))
        .modifier(ExampleChatFilePreviewModifier(service: chatBoundaryService))
        .background {
            if #available(iOS 26.0, *) {
                ModernTabBarRedDotBridge(
                    showsConversationDot: routeState.conversationHasUnread,
                    showsContactDot: routeState.contactHasUnread
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            activateCurrentSessionOwnerIfNeeded()
            routeState.onAppear()
        }
        .onChange(of: environment.loginSessionID) { _ in
            activateCurrentSessionOwnerIfNeeded()
        }
        .onChange(of: routeState.selectedTab) { selectedTab in
            guard resolvedSessionOwnerID == environment.loginSessionID else {
                return
            }
            ExampleChatRouteHostActivation.activate(
                selectedTab,
                ownerID: resolvedSessionOwnerID
            )
        }
        .onDisappear {
            if let activationOwnerID {
                ExampleChatRouteHostActivation.reset(ownerID: activationOwnerID)
            }
            routeState.onDisappear()
        }
    }

    private func activateCurrentSessionOwnerIfNeeded() {
        let ownerID = resolvedSessionOwnerID
        guard ownerID == environment.loginSessionID else {
            return
        }
        activationOwnerID = ownerID
        ExampleChatRouteHostActivation.begin(ownerID: ownerID)
        ExampleChatRouteHostActivation.activate(
            routeState.selectedTab,
            ownerID: ownerID
        )
    }

    private func tabIcon(_ tab: AppTab) -> some View {
        ExampleAssetIcon(
            name: tab.imageName(style: environment.themeMode, selected: routeState.selectedTab == tab),
            size: 24
        )
    }
}

private struct ModernTabBadgeModifier: ViewModifier {
    var showsBadge: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.badge(showsBadge ? "●" : nil)
        }
    }
}

@available(iOS 26.0, *)
private struct ModernTabBarRedDotBridge: UIViewControllerRepresentable {
    var showsConversationDot: Bool
    var showsContactDot: Bool

    func makeUIViewController(context: Context) -> ModernTabBarRedDotController {
        ModernTabBarRedDotController()
    }

    func updateUIViewController(_ controller: ModernTabBarRedDotController, context: Context) {
        controller.updateDots([
            showsConversationDot,
            showsContactDot,
            false,
        ])
    }
}

@available(iOS 26.0, *)
private final class ModernTabBarRedDotController: UIViewController {
    private static let dotTagBase = 26_600
    private var visibleDots = [Bool]()
    private var updateGeneration = 0

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleDotUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scheduleDotUpdate()
    }

    func updateDots(_ visibleDots: [Bool]) {
        self.visibleDots = visibleDots
        scheduleDotUpdate()
    }

    private func scheduleDotUpdate() {
        updateGeneration += 1
        let generation = updateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.updateGeneration == generation else {
                return
            }
            self.applyDots()
        }
    }

    private func applyDots() {
        guard let tabBar = resolvedTabBar(), !visibleDots.isEmpty else {
            return
        }
        let itemCount = CGFloat(visibleDots.count)
        for (index, isVisible) in visibleDots.enumerated() {
            let tag = Self.dotTagBase + index
            guard isVisible else {
                tabBar.viewWithTag(tag)?.removeFromSuperview()
                continue
            }

            let dot = tabBar.viewWithTag(tag) ?? UIView(frame: .zero)
            dot.tag = tag
            dot.layer.cornerRadius = 3
            dot.backgroundColor = .red
            dot.isUserInteractionEnabled = false
            dot.accessibilityIdentifier = "id.bageDot"
            dot.frame = redDotFrame(
                itemIndex: index,
                itemCount: itemCount,
                tabBar: tabBar
            )
            if dot.superview == nil {
                tabBar.addSubview(dot)
            }
        }
    }

    private func redDotFrame(itemIndex: Int,
                             itemCount: CGFloat,
                             tabBar: UITabBar) -> CGRect {
        let size = tabBar.bounds.size
        var percentX = (CGFloat(itemIndex) + 0.59) / itemCount
        var x = CGFloat(ceilf(Float(percentX * size.width)))
        var y = CGFloat(ceilf(Float(0.015 * size.height)))
        let requiresCompatibility = Bundle.main.infoDictionary?["UIDesignRequiresCompatibility"] as? Bool
        if requiresCompatibility != true,
           let firstSubview = tabBar.subviews.first {
            percentX = (CGFloat(itemIndex) + 0.05) / itemCount
            x = size.width - firstSubview.frame.width + CGFloat(ceilf(Float(percentX * firstSubview.frame.width)))
            y = CGFloat(ceilf(Float(0.1 * size.height)))
        }
        return CGRect(x: x, y: y, width: 6, height: 6)
    }

    private func resolvedTabBar() -> UITabBar? {
        if let tabBar = tabBarController?.tabBar {
            return tabBar
        }
        guard let rootViewController = view.window?.rootViewController else {
            return nil
        }
        return findTabBarController(from: rootViewController)?.tabBar
    }

    private func findTabBarController(from viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        if let presented = viewController.presentedViewController,
           let tabBarController = findTabBarController(from: presented) {
            return tabBarController
        }
        for child in viewController.children {
            if let tabBarController = findTabBarController(from: child) {
                return tabBarController
            }
        }
        return nil
    }
}

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(PreviewMocks.mockEnvironment(loggedIn: true))
    }
}
#endif
