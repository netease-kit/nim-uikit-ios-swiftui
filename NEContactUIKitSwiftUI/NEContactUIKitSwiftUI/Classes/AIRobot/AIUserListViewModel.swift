// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

@MainActor
public final class AIUserListViewModel: ObservableObject {
  @Published public private(set) var phase: ContactListPhase = .idle
  @Published public private(set) var rows: [ContactEntryState] = []
  @Published public var pendingRoute: ContactRouteRequest?
  @Published public var toast: NECommonToast?

  private var listener: ContactAIListListener?

  public init() {}

  deinit {
    if let listener {
      NEAIUserManager.shared.removeAIUserChangeListener(listener: listener)
    }
  }

  public func onAppear() {
    installListenerIfNeeded()
    load()
  }

  public func load() {
    phase = .loading
    AIRepo.shared.getAIUserList { [weak self] users, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          let message = NEContactErrorMessageMapper.message(for: error)
          self.phase = .failed(message)
          self.toast = NECommonToast(message: message)
          return
        }
        self.rows = (users ?? []).compactMap(Self.row)
        self.phase = .loaded
      }
    }
  }

  public func select(_ row: ContactEntryState) {
    guard let accountId = row.accountId else {
      return
    }
    pendingRoute = ContactRouteRequest(kind: .userInfo(accountId: accountId, isCurrentUser: false))
  }

  public func consumePendingRoute() {
    pendingRoute = nil
  }

  public func consumeToast(_ toast: NECommonToast) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  private func installListenerIfNeeded() {
    guard listener == nil else {
      return
    }
    let listener = ContactAIListListener { [weak self] users in
      Task { @MainActor in
        self?.rows = users.compactMap(Self.row)
      }
    }
    NEAIUserManager.shared.addAIUserChangeListener(listener: listener)
    self.listener = listener
  }

  private static func row(_ aiUser: V2NIMAIUser) -> ContactEntryState? {
    guard let accountId = aiUser.accountId else {
      return nil
    }
    return ContactEntryState(
      id: "ai.\(accountId)",
      kind: .aiUser,
      accountId: accountId,
      title: ContactSectionBuilder.displayName(for: aiUser),
      subtitle: nil,
      avatarURL: aiUser.avatar,
      avatarName: aiUser.name,
      aiUser: aiUser
    )
  }
}

private final class ContactAIListListener: NSObject, AIUserChangeListener {
  private let handler: ([V2NIMAIUser]) -> Void

  init(handler: @escaping ([V2NIMAIUser]) -> Void) {
    self.handler = handler
  }

  func onAIUserChanged(aiUsers: [V2NIMAIUser]) {
    handler(aiUsers)
  }
}
