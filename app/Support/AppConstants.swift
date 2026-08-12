// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

/// App-wide constants used throughout the application.
enum AppConstants {

    /// Default API configuration.
    static let appKey: String = AppKey.appKey

    /// Bundle identifier for the application.
    static let bundleID: String = "com.netease.NIM.demo2.swiftui"

    /// Default values.
    static let defaultMaxRetryCount = 3
    static let defaultRequestTimeout: TimeInterval = 30.0

    /// UserDefaults keys.
    enum UserDefaultsKey {
        static let themeMode = "app.themeMode"
        static let loggedAccount = "app.loggedAccount"
    }
}
