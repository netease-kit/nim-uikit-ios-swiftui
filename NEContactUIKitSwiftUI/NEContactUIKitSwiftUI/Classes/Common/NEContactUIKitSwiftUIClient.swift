// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public final class NEContactUIKitSwiftUIClient {
  public static let shared = NEContactUIKitSwiftUIClient()

  public private(set) var config = ContactSwiftUIConfig()
  private var didReportInitialization = false

  private init() {}

  public func setup(config: ContactSwiftUIConfig = ContactSwiftUIConfig()) {
    self.config = config
    ContactSwiftUIConfigCenter.shared.update(config)
    reportInitializationIfNeeded()
  }

  public func updateConfig(_ config: ContactSwiftUIConfig) {
    self.config = config
    ContactSwiftUIConfigCenter.shared.update(config)
  }

  private func reportInitializationIfNeeded() {
    guard !didReportInitialization else {
      return
    }
    ChatKitClient.shared.buryDataPoints(
      NEContactUIKitSwiftUIConstants.telemetryComponentName,
      language: NEContactUIKitSwiftUIConstants.telemetryLanguage
    )
    didReportInitialization = true
  }
}
