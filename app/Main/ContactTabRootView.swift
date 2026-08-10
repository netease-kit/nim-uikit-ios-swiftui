// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import NEContactUIKitSwiftUI

/// Root view for the Contact tab.
struct ContactTabRootView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var legacyRoutePath = [LegacyRoute]()
    private let isActive: Bool
    private let sessionOwnerID: UUID?

    init(isActive: Bool = true, sessionOwnerID: UUID? = nil) {
        self.isActive = isActive
        self.sessionOwnerID = sessionOwnerID
    }

    var body: some View {
        NavigationStack(path: $legacyRoutePath) {
            LegacyRouteHostView(routePath: $legacyRoutePath, isActive: isActive) {
                ChatRouteHostView(
                    tab: .contact,
                    isActive: isActive,
                    sessionOwnerID: sessionOwnerID,
                    onOpenChatRoute: {
                        if !legacyRoutePath.isEmpty {
                            if legacyRoutePath.last != .contactTeamList {
                                legacyRoutePath.removeAll()
                            }
                        }
                    }
                ) {
                    switch environment.themeMode {
                    case .normal:
                        NormalContactListView(
                            viewModel: ContactListViewModel(
                                config: ContactSwiftUIConfigCenter.shared.config.resolvingStyle(.normal)
                            )
                        )
                    case .fun:
                        FunContactListView(
                            viewModel: ContactListViewModel(
                                config: ContactSwiftUIConfigCenter.shared.config.resolvingStyle(.fun)
                            )
                        )
                    }
                }
            }
        }
    }
}

private extension ContactSwiftUIConfig {
    func resolvingStyle(_ style: ContactStyleMode) -> ContactSwiftUIConfig {
        var next = self
        next.styleMode = style
        return next
    }
}

#if DEBUG
struct ContactTabRootView_Previews: PreviewProvider {
    static var previews: some View {
        ContactTabRootView()
            .environmentObject(PreviewMocks.mockEnvironment(loggedIn: true))
    }
}
#endif
