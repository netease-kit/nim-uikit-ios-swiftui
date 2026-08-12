// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

/// Simple dependency injection container that holds shared services.
/// Services are registered at startup and resolved throughout the app.
@MainActor
final class AppDependencyContainer: ObservableObject {

    static let shared = AppDependencyContainer()

    /// Access the global application environment.
    let environment: AppEnvironment

    init(environment: AppEnvironment = .shared) {
        self.environment = environment
    }
}
