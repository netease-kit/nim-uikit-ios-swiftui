// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

/// Central navigation helper. Provides convenience methods for navigating
/// between top-level app destinations.
@MainActor
enum AppNavigator {

    /// Presents a specific view in the active window scene.
    static func navigateToLogin() {
        AppEnvironment.shared.markLoggedOut()
    }

    /// Switches to the main tab interface after a successful login.
    static func navigateToMain() {
        // Handled reactively via AppEnvironment.isLoggedIn in RootContainerView.
    }
}
