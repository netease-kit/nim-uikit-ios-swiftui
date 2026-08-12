// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

/// Preview mock data and helpers used in Xcode previews.
enum PreviewMocks {

    /// A mock AppEnvironment suitable for SwiftUI previews.
    @MainActor
    static func mockEnvironment(loggedIn: Bool = false) -> AppEnvironment {
        let env = AppEnvironment()
        if loggedIn {
            env.isLoggedIn = true
            env.currentAccount = "testuser"
            env.isAuthenticating = false
        }
        return env
    }

    /// A mock session state for previews.
    @MainActor
    static let mockSessionState: SessionState = {
        let state = SessionState()
        state.currentAccount = "testuser"
        return state
    }()

    /// A mock debug state for previews.
    @MainActor
    static let mockDebugState: DebugState = {
        let state = DebugState()
        state.isDebugModeEnabled = true
        return state
    }()
}
