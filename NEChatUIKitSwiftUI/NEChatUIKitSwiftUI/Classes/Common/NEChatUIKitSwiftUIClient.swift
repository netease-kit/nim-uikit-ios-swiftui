// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public final class NEChatUIKitSwiftUIClient {
  public static let shared = NEChatUIKitSwiftUIClient()

  public private(set) var config = ChatSwiftUIConfig()
  public private(set) var router = NEChatSwiftUIRouter()
  private var didReportInitialization = false
  private var pushRoutePayloadBeforeSendRestore: (() -> Void)?

  private init() {}

  public func setup(config: ChatSwiftUIConfig = ChatSwiftUIConfig(),
                    router: NEChatSwiftUIRouter = NEChatSwiftUIRouter(),
                    registerLegacyRoutes: Bool = false) {
    self.config = config
    self.router = router
    ChatSwiftUIConfigCenter.shared.update(config)
    reportInitializationIfNeeded()
    if registerLegacyRoutes {
      router.registerLegacyRoutes()
    }
  }

  public func updateConfig(_ config: ChatSwiftUIConfig) {
    self.config = config
    ChatSwiftUIConfigCenter.shared.update(config)
  }

  public func installPushRoutePayloadBeforeSend(chatRepo: ChatRepo = .shared,
                                                currentAccountProvider: @escaping () -> String? = {
                                                  IMKitClient.instance.account()
                                                }) {
    uninstallPushRoutePayloadBeforeSend()

    let previousBeforeSend = ChatKitClient.shared.beforeSendHandler
    let previousBeforeSendCompletion = ChatKitClient.shared.beforeSendCompletionHandler

    ChatKitClient.shared.beforeSendHandler = nil
    ChatKitClient.shared.beforeSendCompletionHandler = { param, completion in
      let applyPushRoutePayload: (MessageSendParams?) -> Void = { sendParams in
        guard let sendParams else {
          completion(nil)
          return
        }

        completion(chatRepo.swiftUIApplyPushRoutePayload(
          to: sendParams,
          currentAccountId: currentAccountProvider()
        ))
      }

      if let previousBeforeSend {
        applyPushRoutePayload(previousBeforeSend(param))
      } else if let previousBeforeSendCompletion {
        previousBeforeSendCompletion(param, applyPushRoutePayload)
      } else {
        applyPushRoutePayload(param)
      }
    }

    pushRoutePayloadBeforeSendRestore = {
      ChatKitClient.shared.beforeSendHandler = previousBeforeSend
      ChatKitClient.shared.beforeSendCompletionHandler = previousBeforeSendCompletion
    }
  }

  public func uninstallPushRoutePayloadBeforeSend() {
    guard let restore = pushRoutePayloadBeforeSendRestore else {
      return
    }
    restore()
    pushRoutePayloadBeforeSendRestore = nil
  }

  private func reportInitializationIfNeeded() {
    guard !didReportInitialization else {
      return
    }
    ChatKitClient.shared.buryDataPoints(
      NEChatUIKitSwiftUIConstants.telemetryComponentName,
      language: NEChatUIKitSwiftUIConstants.telemetryLanguage
    )
    didReportInitialization = true
  }
}
