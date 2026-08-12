// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEAISearchKitSwiftUI
import NECommonUIKitSwiftUI
import SwiftUI
import UIKit

/// Root view that observes login state and switches between
/// splash, login flow, and main tab interface.
struct RootContainerView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        Group {
            if environment.isAuthenticating {
                SplashView()
            } else if environment.isLoggedIn {
                MainTabView(sessionOwnerID: environment.loginSessionID)
                    .id(environment.loginSessionID)
                    .aiWordSearchPresenter()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: environment.isLoggedIn)
        .onReceive(NotificationCenter.default.publisher(for: .logout)) { _ in
            environment.markLoggedOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appToast)) { notification in
            guard let message = notification.object as? String else {
                return
            }
            environment.showToast(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsPrompt)) { notification in
            guard let prompt = notification.object as? AppSettingsPrompt else {
                return
            }
            environment.showSettingsPrompt(prompt)
        }
        .neCommonToastOverlay(environment.toast, placement: .top, topPadding: 52) { toast in
            environment.consumeToast(toast)
        }
        .alert(item: Binding(
            get: { environment.settingsPrompt },
            set: { prompt in
                if prompt == nil {
                    environment.dismissSettingsPrompt()
                }
            }
        )) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text(localizable("go_to_settings"))) {
                    environment.dismissSettingsPrompt()
                    openAppSettings()
                },
                secondaryButton: .cancel(Text(localizable("cancel"))) {
                    environment.dismissSettingsPrompt()
                }
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url)
        else {
            return
        }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
struct RootContainerView_Previews: PreviewProvider {
    static var previews: some View {
        RootContainerView()
            .environmentObject(PreviewMocks.mockEnvironment(loggedIn: true))
    }
}
#endif
