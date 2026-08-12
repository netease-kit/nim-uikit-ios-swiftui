// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import Combine
import NEChatKit

public final class NEAISearchSwiftUIClient: NSObject, ObservableObject {
  public static let shared = NEAISearchSwiftUIClient()

  @Published public var activeRoute: AIWordSearchRoute?
  @Published public var toastMessage: String?

  public let serviceName: String = NEAISearchPlugin
  public let versionName: String = NEAISearchSwiftUIConstants.pluginVersion
  public let appKey: String = IMKitClient.instance.appKey()
  private let setupLock = NSLock()
  private var didSetup = false

  override private init() {
    super.init()
  }

  public func setupInit() {
    setupLock.lock()
    let shouldSetup = !didSetup
    if shouldSetup {
      didSetup = true
    }
    setupLock.unlock()
    guard shouldSetup else {
      return
    }

    IMKitPluginManager.shared.registerSwiftPlugin(serviceName, self)
    ChatKitClient.shared.buryDataPoints(
      NEAISearchSwiftUIConstants.telemetryComponentName,
      language: NEAISearchSwiftUIConstants.telemetryLanguage
    )
  }

  public func open(query: String,
                   source: AIWordSearchSource = .messageMenu,
                   conversationId: String? = nil,
                   messageClientId: String? = nil) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard NEChatDetectNetworkTool.shareInstance.manager?.isReachable != false else {
      showToast(NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.networkError, value: "Network error"))
      return
    }
    guard !trimmed.isEmpty else {
      showToast(NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.notSupported, value: "Not supported"))
      return
    }

    updateOnMain {
      self.activeRoute = AIWordSearchRoute(
        query: trimmed,
        source: source,
        conversationId: conversationId,
        messageClientId: messageClientId
      )
    }
  }

  public func dismissActiveRoute() {
    updateOnMain {
      self.activeRoute = nil
    }
  }

  public func showToast(_ message: String) {
    updateOnMain {
      self.toastMessage = message
    }
  }

  public func consumeToast() {
    updateOnMain {
      self.toastMessage = nil
    }
  }

  private func updateOnMain(_ update: @escaping () -> Void) {
    if Thread.isMainThread {
      update()
    } else {
      DispatchQueue.main.async(execute: update)
    }
  }
}

extension NEAISearchSwiftUIClient: IMKitSwiftPluginService {
  public func registerSwiftPlugin(_ text: String) -> OperationItem? {
    OperationItem(
      text: NEAISearchSwiftUIBundle.localized(NEAISearchLocalizableKey.operationAIWordSearch, value: "AI Search"),
      imageName: NEAISearchSwiftUIConstants.operationIconName,
      imageResource: NEAISearchSwiftUIBundle.imageResource(named: NEAISearchSwiftUIConstants.operationIconName),
      type: .plugin
    ) { [weak self] in
      self?.open(query: text, source: .messageMenu)
    }
  }
}
