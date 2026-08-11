// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import NEChatKit
import Combine
import NECommonUIKitSwiftUI

/// Global application environment, managing login state, theme mode, and current account.
@MainActor
final class AppEnvironment: ObservableObject {

    static let shared = AppEnvironment()

    /// Whether the user is currently logged in.
    @Published var isLoggedIn: Bool = false

    /// True during initial auto-login check.
    @Published var isAuthenticating: Bool = true

    /// The current theme mode: normal or fun.
    @Published var themeMode: ThemeMode = .normal

    /// The currently logged-in account ID, if any.
    @Published var currentAccount: String?

    /// Changes after every successful login so account-scoped UI state is rebuilt,
    /// including when the same account logs in again.
    @Published private(set) var loginSessionID = UUID()

    /// Error message to display on login screen.
    @Published var loginErrorMessage: String?

    /// Bumped after in-app language changes so visible SwiftUI text recomputes.
    @Published var languageRevision: Int = 0

    /// App-level transient feedback, used for system permission prompts owned by
    /// the SwiftUI host rather than a feature module.
    @Published var toast: NECommonToastState?

    /// App-level system settings prompt for denied iOS permissions.
    @Published var settingsPrompt: AppSettingsPrompt?

    private var didSetup = false

    // MARK: - Initial setup

    func setup() {
        guard !didSetup else {
            return
        }
        didSetup = true

        themeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKey.themeMode) ?? "") ?? .normal

        AppBootstrap.onLoginSuccess = { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                AppBootstrap.initAfterLogin()
                self.currentAccount = IMKitClient.instance.account()
                self.loginSessionID = UUID()
                self.isLoggedIn = true
                self.isAuthenticating = false
            }
        }
        AppBootstrap.onLoginFailure = { [weak self] message in
            Task { @MainActor in
                self?.loginErrorMessage = message
                self?.isAuthenticating = false
            }
        }

        AppBootstrap.setup { [weak self] in
            Task { @MainActor in
                if self?.isLoggedIn == false {
                    self?.isAuthenticating = false
                }
            }
        }
    }

    // MARK: - Login actions

    func loginWithPOC(account: String, token: String) {
        isAuthenticating = true
        loginErrorMessage = nil
        AppBootstrap.loginPOC(account: account, token: token)
    }

    func logout() {
        AppBootstrap.logout()
        markLoggedOut()
    }

    func markLoggedOut() {
        currentAccount = nil
        isLoggedIn = false
        isAuthenticating = false
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: AppConstants.UserDefaultsKey.themeMode)
        AppBootstrap.syncSwiftUIModuleTheme(mode)
    }

    func showToast(_ message: String, level: NECommonToastLevel = .info) {
        toast = NECommonToastState(fallbackText: message, level: level)
    }

    func consumeToast(_ toast: NECommonToastState) {
        if self.toast?.id == toast.id {
            self.toast = nil
        }
    }

    func showSettingsPrompt(_ prompt: AppSettingsPrompt) {
        settingsPrompt = prompt
    }

    func dismissSettingsPrompt() {
        settingsPrompt = nil
    }
}

struct AppSettingsPrompt: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
}

// MARK: - ThemeMode

enum ThemeMode: String, CaseIterable {
    case normal
    case fun

    var displayName: String {
        switch self {
        case .normal: return "普通模式"
        case .fun: return "娱乐模式"
        }
    }
}
