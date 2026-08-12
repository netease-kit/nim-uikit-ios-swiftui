// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI
import Combine

/// Manages the visual theme/style mode across the application.
@MainActor
final class ThemeState: ObservableObject {

    /// The current theme mode.
    @Published var mode: ThemeMode = .normal

    /// Returns a display-friendly name for the current mode.
    var currentModeName: String {
        mode.displayName
    }

    func switchTo(_ newMode: ThemeMode) {
        mode = newMode
        AppEnvironment.shared.setThemeMode(newMode)
    }

    func toggle() {
        switch mode {
        case .normal:
            switchTo(.fun)
        case .fun:
            switchTo(.normal)
        }
    }
}
