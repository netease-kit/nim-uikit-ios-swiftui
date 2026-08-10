// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import Combine

/// Manages the current session state: logged-in user info and the active conversation.
@MainActor
final class SessionState: ObservableObject {

    /// The currently logged-in user account ID.
    @Published var currentAccount: String?

    /// The ID of the conversation currently being viewed.
    @Published var currentConversationID: String?

    /// Whether the user is currently in an active session.
    var isActive: Bool {
        currentAccount != nil
    }

    func startSession(account: String) {
        currentAccount = account
    }

    func endSession() {
        currentAccount = nil
        currentConversationID = nil
    }
}
