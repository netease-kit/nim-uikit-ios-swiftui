// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import Combine
import NEChatKit

@MainActor
public final class AIWordSearchViewModel: ObservableObject {
  @Published public private(set) var state: AIWordSearchState

  public let route: AIWordSearchRoute
  private let service: AIWordSearchService
  private var submittedTexts = [String]()
  private var didSubmitInitialQuery = false

  public init(route: AIWordSearchRoute,
              service: AIWordSearchService = AIWordSearchService()) {
    self.route = route
    self.service = service
    state = AIWordSearchState()
    service.setEventHandler { [weak self] event in
      self?.handle(event)
    }
  }

  deinit {
    service.close()
  }

  public func onAppear() {
    guard !didSubmitInitialQuery else {
      return
    }
    didSubmitInitialQuery = true
    submit(route.query)
  }

  public func dismiss() {
    state.isDismissed = true
    service.close()
  }

  public func expandSupplement() {
    state.isSupplementExpanded = true
  }

  public func updateSupplementText(_ text: String) {
    state.supplementText = text
  }

  public func submitSupplement() {
    let trimmed = state.supplementText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    guard NEChatDetectNetworkTool.shareInstance.manager?.isReachable != false else {
      state.toastMessage = NEAISearchSwiftUIBundle.localized(
        NEAISearchLocalizableKey.networkError,
        value: "Network error"
      )
      return
    }

    submit(trimmed)
    state.supplementText = ""
  }

  public func consumeToast() {
    state.toastMessage = nil
  }

  private func submit(_ text: String) {
    guard !state.isDismissed else {
      return
    }

    state.isLoading = true
    let contextTexts = submittedTexts
    service.submit(text: text, contextTexts: contextTexts) { [weak self] result in
      Task { @MainActor in
        guard let self, !self.state.isDismissed else {
          return
        }
        switch result {
        case .success(let token):
          self.submittedTexts.append(token.text)
          self.state.isLoading = self.service.hasPendingRequests
        case .failure(let error):
          self.state.toastMessage = AIWordSearchErrorMapper.text(for: error)
          self.state.isLoading = self.service.hasPendingRequests
        }
      }
    }
  }

  private func handle(_ event: AIWordSearchRequestEvent) {
    guard !state.isDismissed else {
      return
    }

    switch event {
    case .completed(let result):
      state.results.insert(result, at: 0)
      state.isLoading = service.hasPendingRequests
    }
  }
}
