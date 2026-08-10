// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public final class NEConversationUIKitSwiftUIClient {
  public static let shared = NEConversationUIKitSwiftUIClient()

  public private(set) var config = ConversationSwiftUIConfig()
  private var didReportInitialization = false
  private var didRegisterLegacyRoutes = false

  private init() {}

  public func setup(config: ConversationSwiftUIConfig = ConversationSwiftUIConfig(),
                    registerLegacyRoutes: Bool = true) {
    self.config = config
    ConversationSwiftUIConfigCenter.shared.update(config)
    NEConversationAtMessageStore.shared.setup()
    reportInitializationIfNeeded()
    if registerLegacyRoutes {
      registerLegacyRoutesIfNeeded()
    }
  }

  public func updateConfig(_ config: ConversationSwiftUIConfig) {
    self.config = config
    ConversationSwiftUIConfigCenter.shared.update(config)
  }

  private func reportInitializationIfNeeded() {
    guard !didReportInitialization else {
      return
    }
    ChatKitClient.shared.buryDataPoints(
      NEConversationUIKitSwiftUIConstants.telemetryComponentName,
      language: NEConversationUIKitSwiftUIConstants.telemetryLanguage
    )
    didReportInitialization = true
  }

  private func registerLegacyRoutesIfNeeded() {
    guard !didRegisterLegacyRoutes else {
      return
    }
    didRegisterLegacyRoutes = true
    Router.shared.register(NEConversationUIKitSwiftUIConstants.clearAtMessageRoute) { params in
      guard let conversationId = params["sessionId"] as? String else {
        return
      }
      NEConversationAtMessageStore.shared.clearAtRecord(conversationId)
    }
  }
}
