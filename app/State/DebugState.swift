// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import Combine

/// Manages debug and development configuration state.
/// Provides toggles used during development and testing.
@MainActor
final class DebugState: ObservableObject {

    /// Whether debug mode is enabled.
    @Published var isDebugModeEnabled: Bool = false

    /// Whether to show debug overlays in the UI.
    @Published var showDebugOverlay: Bool = false

    /// The current SDK environment (e.g., production / test).
    @Published var sdkEnvironment: String = "production"

    func toggleDebugMode() {
        isDebugModeEnabled.toggle()
    }

    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }
}
