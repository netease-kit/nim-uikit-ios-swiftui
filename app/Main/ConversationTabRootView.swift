// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import NEChatKit
import NEChatUIKitSwiftUI
import NEConversationUIKitSwiftUI
import NETeamUIKitSwiftUI

/// Root view for the Conversation tab.
struct ConversationTabRootView: View {
    @EnvironmentObject var environment: AppEnvironment
    @StateObject private var viewModel: ConversationListViewModel
    @State private var legacyRoutePath = [LegacyRoute]()
    private let isActive: Bool
    private let sessionOwnerID: UUID?

    @MainActor
    init(isActive: Bool = true, sessionOwnerID: UUID? = nil) {
        self.isActive = isActive
        self.sessionOwnerID = sessionOwnerID
        let mode = IMKitClient.instance.isV2CloudConversationEnabled ? ConversationMode.cloud : .local
        _viewModel = StateObject(wrappedValue: ConversationListViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack(path: $legacyRoutePath) {
            LegacyRouteHostView(routePath: $legacyRoutePath, isActive: isActive) {
                ChatRouteHostView(
                    tab: .conversation,
                    isActive: isActive,
                    sessionOwnerID: sessionOwnerID,
                    onOpenChatRoute: {
                        if !legacyRoutePath.isEmpty {
                            legacyRoutePath.removeAll()
                        }
                    }
                ) {
                    ConversationActionRouteHostView {
                        makeConversationView()
                    }
                }
            }
        }
        .onAppear {
            installTeamChatRouteHandlers()
        }
    }

    @MainActor
    private func makeConversationView() -> some View {
        let style = environment.themeMode.conversationStyleMode
        let token: ConversationThemeToken = style == .fun ? .fun : .normal
        return ConversationListView(viewModel: viewModel, token: token)
    }

    private func installTeamChatRouteHandlers() {
        NETeamUIKitSwiftUIClient.shared.onOpenPinMessages = { conversationId in
            NEChatUIKitSwiftUIClient.shared.router.enqueue(.pinMessages(conversationId: conversationId))
        }
        NETeamUIKitSwiftUIClient.shared.onOpenHistorySearch = { conversationId in
            NEChatUIKitSwiftUIClient.shared.router.enqueue(.historySearch(conversationId: conversationId))
        }
    }
}

private extension ConversationSwiftUIConfig {
    func resolvingMode(_ mode: ConversationMode) -> ConversationSwiftUIConfig {
        var next = self
        next.mode = mode
        return next
    }
}

private extension ThemeMode {
    var conversationStyleMode: ConversationStyleMode {
        switch self {
        case .normal:
            return .normal
        case .fun:
            return .fun
        }
    }
}

#if DEBUG
struct ConversationTabRootView_Previews: PreviewProvider {
    static var previews: some View {
        ConversationTabRootView()
    }
}
#endif
