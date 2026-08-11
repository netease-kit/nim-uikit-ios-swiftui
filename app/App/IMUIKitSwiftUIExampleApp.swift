// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

@main
struct IMUIKitSwiftUIExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(environment)
                .onAppear {
                    DispatchQueue.main.async {
                        environment.setup()
                    }
                }
        }
    }
}
