// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import Combine
import NEChatKit
import NIMSDK

/// Manages app-level navigation routes.
/// Drives which screens are currently active in the navigation hierarchy.
@MainActor
final class AppRouteState: ObservableObject {

    /// The main tab currently selected.
    @Published var selectedTab: AppTab = .conversation

    /// Whether the login view should be presented.
    @Published var showLogin: Bool = false

    @Published private(set) var conversationHasUnread: Bool = false
    @Published private(set) var contactHasUnread: Bool = false

    private var listenerTokens = [NEChatKitListenerToken]()

    func onAppear() {
        installListenersIfNeeded()
        refreshBadges()
    }

    func onDisappear() {}

    private func installListenersIfNeeded() {
        guard listenerTokens.isEmpty else {
            return
        }

        if IMKitClient.instance.isV2CloudConversationEnabled {
            listenerTokens.append(
                ConversationRepo.shared.addConversationEventListener(
                    NEConversationEvent(
                        conversationCreated: { [weak self] _ in Task { @MainActor in self?.refreshConversationBadge() } },
                        conversationDeleted: { [weak self] _ in Task { @MainActor in self?.refreshConversationBadge() } },
                        conversationChanged: { [weak self] _ in Task { @MainActor in self?.refreshConversationBadge() } },
                        totalUnreadCountChanged: { [weak self] count in
                            Task { @MainActor in self?.conversationHasUnread = count > 0 }
                        }
                    )
                )
            )
        } else {
            listenerTokens.append(
                LocalConversationRepo.shared.addLocalConversationEventListener(
                    NELocalConversationEvent(
                        conversationCreated: { [weak self] _ in Task { @MainActor in self?.refreshConversationBadge() } },
                        conversationDeleted: { [weak self] _ in Task { @MainActor in self?.refreshConversationBadge() } },
                        conversationChanged: { [weak self] _ in Task { @MainActor in self?.refreshConversationBadge() } },
                        totalUnreadCountChanged: { [weak self] count in
                            Task { @MainActor in self?.conversationHasUnread = count > 0 }
                        }
                    )
                )
            )
        }

        listenerTokens.append(
            ContactRepo.shared.addContactEventListener(
                NEContactEvent(
                    friendAddApplication: { [weak self] _ in Task { @MainActor in self?.refreshContactBadge() } },
                    friendAddRejected: { [weak self] _ in Task { @MainActor in self?.refreshContactBadge() } }
                )
            )
        )

        listenerTokens.append(
            TeamRepo.shared.addTeamEventListener(
                NETeamEvent(receiveJoinAction: { [weak self] _ in Task { @MainActor in self?.refreshContactBadge() } })
            )
        )

        NotificationCenter.default.addObserver(
            forName: NENotificationName.clearValidationMessageUnreadCount,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.contactHasUnread = false }
        }
    }

    private func refreshBadges() {
        refreshConversationBadge()
        refreshContactBadge()
    }

    private func refreshConversationBadge() {
        if IMKitClient.instance.isV2CloudConversationEnabled {
            conversationHasUnread = ConversationRepo.shared.getTotalUnreadCount() > 0
        } else {
            conversationHasUnread = LocalConversationRepo.shared.getTotalUnreadCount() > 0
        }
    }

    private func refreshContactBadge() {
        ContactRepo.shared.getUnreadApplicationCount { [weak self] friendUnread, _ in
            guard IMKitConfigCenter.shared.enableTeamJoinAgreeModelAuth else {
                Task { @MainActor in
                    self?.contactHasUnread = friendUnread > 0
                }
                return
            }

            let option = V2NIMTeamJoinActionInfoQueryOption()
            option.offset = 0
            option.limit = 100
            TeamRepo.shared.getTeamJoinActionInfoList(option) { result, _ in
                let readTime = UserDefaults.standard.double(forKey: keyTeamJoinActionReadTime)
                let teamUnread = result?.infos?.filter { $0.timestamp > readTime }.count ?? 0
                Task { @MainActor in
                    self?.contactHasUnread = (friendUnread + teamUnread) > 0
                }
            }
        }
    }
}

/// Top-level tabs available in the main interface.
enum AppTab: Int, CaseIterable, Identifiable {
    case conversation
    case contact
    case mine

    var id: Int { rawValue }

    func title() -> String {
        switch self {
        case .conversation: return localizable("message")
        case .contact: return localizable("contact")
        case .mine: return localizable("mine")
        }
    }

    func imageName(style: ThemeMode, selected: Bool) -> String {
        switch self {
        case .conversation:
            return style == .fun ? (selected ? "funChatSelect" : "funChat") : (selected ? "chatSelect" : "chat")
        case .contact:
            return style == .fun ? (selected ? "funContactSelect" : "funContact") : (selected ? "contactSelect" : "contact")
        case .mine:
            return style == .fun ? (selected ? "funPersonSelect" : "funPerson") : (selected ? "personSelect" : "person")
        }
    }
}
