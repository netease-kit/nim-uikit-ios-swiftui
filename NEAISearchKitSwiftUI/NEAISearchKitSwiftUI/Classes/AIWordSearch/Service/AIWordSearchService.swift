// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public struct AIWordSearchRequestToken: Equatable {
  public var requestId: String
  public var text: String

  public init(requestId: String, text: String) {
    self.requestId = requestId
    self.text = text
  }
}

public enum AIWordSearchRequestEvent {
  case completed(AIWordSearchResult)
}

public final class AIWordSearchService: NSObject {
  public typealias EventHandler = @MainActor (AIWordSearchRequestEvent) -> Void

  private let repo: AIRepo
  private let aiSearchAccountProvider: () -> String?
  private let pendingLock = NSLock()
  private var pendingRequestIds = Set<String>()
  private var eventHandler: EventHandler?
  private var listenerToken: NEChatKitListenerToken?
  private var isClosed = false

  public init(repo: AIRepo = .shared,
              aiSearchAccountProvider: @escaping () -> String? = { NEAIUserManager.shared.getSwiftUIAISearchAccountId() }) {
    self.repo = repo
    self.aiSearchAccountProvider = aiSearchAccountProvider
    super.init()
    listenerToken = repo.addAIModelCallEventListener(
      NEAIModelCallEvent(proxyModelCall: { [weak self] result in
        self?.handle(result)
      })
    )
  }

  deinit {
    close()
  }

  public var hasPendingRequests: Bool {
    pendingLock.lock()
    let hasPendingRequests = !pendingRequestIds.isEmpty
    pendingLock.unlock()
    return hasPendingRequests
  }

  public func setEventHandler(_ handler: EventHandler?) {
    eventHandler = handler
  }

  @discardableResult
  public func submit(text: String,
                     contextTexts: [String],
                     completion: @escaping (Result<AIWordSearchRequestToken, NSError>) -> Void) -> String? {
    guard !isClosed else {
      return nil
    }
    guard let accountId = aiSearchAccountProvider(),
          !accountId.isEmpty else {
      completion(.failure(requestException()))
      return nil
    }

    let requestId = UUID().uuidString
    let request = NEAIModelCallRequest(
      accountId: accountId,
      requestId: requestId,
      text: text,
      contextTexts: contextTexts,
      temperature: NEAISearchSwiftUIConstants.aiModelTemperature
    )

    repo.proxyAIModelCall(request) { [weak self] error in
      guard let self, !self.isClosed else {
        return
      }
      if let error {
        debugPrint("[NEAISearchKitSwiftUI] aiSearch submit failed requestId=\(requestId) error=\(error)")
        self.removePendingRequest(requestId)
        completion(.failure(error))
        return
      }

      self.insertPendingRequest(requestId)
      completion(.success(AIWordSearchRequestToken(requestId: requestId, text: text)))
    }

    return requestId
  }

  public func close() {
    guard !isClosed else {
      return
    }
    isClosed = true
    removeAllPendingRequests()
    eventHandler = nil
    listenerToken?.cancel()
    listenerToken = nil
  }

  private func requestException() -> NSError {
    NSError(
      domain: NEAISearchSwiftUIConstants.moduleName,
      code: -1,
      userInfo: [
        NSLocalizedDescriptionKey: NEAISearchSwiftUIBundle.localized(
          NEAISearchLocalizableKey.requestException,
          value: "Request Exception"
        ),
      ]
    )
  }
}

private extension AIWordSearchService {
  func handle(_ data: NEAIModelCallResult) {
    guard !isClosed,
          removePendingRequestIfExists(data.requestId) else {
      return
    }

    let result = AIWordSearchResult(
      requestId: data.requestId,
      text: AIWordSearchErrorMapper.text(for: data),
      isError: !AIWordSearchErrorMapper.isSuccess(data)
    )

    Task { @MainActor [eventHandler] in
      eventHandler?(.completed(result))
    }
  }

  func insertPendingRequest(_ requestId: String) {
    pendingLock.lock()
    pendingRequestIds.insert(requestId)
    pendingLock.unlock()
  }

  func removePendingRequest(_ requestId: String) {
    pendingLock.lock()
    pendingRequestIds.remove(requestId)
    pendingLock.unlock()
  }

  func removePendingRequestIfExists(_ requestId: String) -> Bool {
    pendingLock.lock()
    let contains = pendingRequestIds.contains(requestId)
    if contains {
      pendingRequestIds.remove(requestId)
    }
    pendingLock.unlock()
    return contains
  }

  func removeAllPendingRequests() {
    pendingLock.lock()
    pendingRequestIds.removeAll()
    pendingLock.unlock()
  }
}
