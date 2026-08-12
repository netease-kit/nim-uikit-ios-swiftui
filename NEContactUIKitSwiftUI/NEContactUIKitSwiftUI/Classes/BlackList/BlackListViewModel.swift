// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit

@MainActor
public final class BlackListViewModel: ObservableObject {
  @Published public private(set) var phase: ContactListPhase = .idle
  @Published public private(set) var rows: [ContactEntryState] = []
  @Published public var toast: NECommonToast?
  @Published public var didFinishAddingSelection = false

  private let contactRepo: ContactRepo
  private var friendsByAccountId = [String: NEUserWithFriend]()
  private var listenerToken: NEChatKitListenerToken?

  public init(contactRepo: ContactRepo = .shared) {
    self.contactRepo = contactRepo
  }

  deinit {
    listenerToken?.cancel()
  }

  public func onAppear() {
    installListenerIfNeeded()
    load()
  }

  public func load() {
    friendsByAccountId = NEFriendUserCache.shared.getFriendList()
    if !loadCachedRowsIfAvailable() {
      phase = .loaded
    }
  }

  public func remove(_ row: ContactEntryState) {
    guard let accountId = row.accountId else {
      return
    }
    guard ensureNetworkForMutation() else {
      return
    }
    contactRepo.removeBlockList(accountId: accountId) { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
        } else {
          self.rows.removeAll { $0.accountId == accountId }
          NEFriendUserCache.shared.removeBlockAccount(accountId)
        }
      }
    }
  }

  public func addSelectedContacts(_ result: ContactSelectionResult) {
    let accountIds = result.accountIds.filter { accountId in
      !rows.contains { $0.accountId == accountId }
    }
    guard !accountIds.isEmpty else {
      return
    }
    addNext(accountIds: accountIds, index: 0)
  }

  public func consumeToast(_ toast: NECommonToast) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  public func consumeDidFinishAddingSelection() {
    didFinishAddingSelection = false
  }

  private func installListenerIfNeeded() {
    guard listenerToken == nil else {
      return
    }
    listenerToken = contactRepo.addContactChangeListener { [weak self] changeType, contacts in
      Task { @MainActor in
        self?.applyContactChange(changeType, contacts: contacts)
      }
    }
  }

  private func applyContactChange(_ changeType: NEContactChangeType,
                                  contacts: [NEUserWithFriend]) {
    for contact in contacts {
      guard let accountId = contact.user?.accountId ?? contact.friend?.accountId else {
        continue
      }
      friendsByAccountId[accountId] = contact
      switch changeType {
      case .addBlock:
        if !rows.contains(where: { $0.accountId == accountId }) {
          rows.append(makeRow(for: contact, accountId: accountId))
        }
      case .update:
        if let index = rows.firstIndex(where: { $0.accountId == accountId }) {
          rows[index] = makeRow(for: contact, accountId: accountId)
        }
      case .removeBlock, .deleteFriend:
        rows.removeAll { $0.accountId == accountId }
      case .addFriend:
        break
      @unknown default:
        break
      }
    }
  }

  private func addNext(accountIds: [String], index: Int) {
    guard index < accountIds.count else {
      didFinishAddingSelection = true
      return
    }

    let accountId = accountIds[index]
    guard ensureNetworkForMutation() else {
      return
    }
    contactRepo.addBlockList(accountId: accountId) { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
          return
        }
        if let user = self.friendsByAccountId[accountId],
           !self.rows.contains(where: { $0.accountId == accountId }) {
          self.rows.append(self.makeRow(for: user, accountId: accountId))
        }
        self.addNext(accountIds: accountIds, index: index + 1)
      }
    }
  }

  private func makeRow(for user: NEUserWithFriend, accountId: String) -> ContactEntryState {
    ContactEntryState(
      id: "black.\(accountId)",
      kind: .friend,
      accountId: accountId,
      title: ContactSectionBuilder.displayName(for: user),
      subtitle: accountId,
      avatarURL: user.user?.avatar,
      avatarName: user.showName(false),
      user: user
    )
  }

  private func loadCachedRowsIfAvailable() -> Bool {
    guard let cachedBlockAccountIds = NEFriendUserCache.shared.getBlocklist(),
          !cachedBlockAccountIds.isEmpty else {
      rows = []
      return false
    }

    let cachedRows = cachedBlockAccountIds.compactMap { accountId -> ContactEntryState? in
      guard let user = friendsByAccountId[accountId] ?? NEFriendUserCache.shared.getFriendInfo(accountId) else {
        return nil
      }
      return makeRow(for: displayUser(for: user, accountId: accountId), accountId: accountId)
    }
    guard !cachedRows.isEmpty else {
      rows = []
      return false
    }

    rows = cachedRows
    phase = .loaded

    NEFriendUserCache.shared.loadShowName(cachedBlockAccountIds) { [weak self] users in
      Task { @MainActor in
        guard let self,
              let users else {
          return
        }
        for user in users {
          if let accountId = user.user?.accountId ?? user.friend?.accountId {
            self.friendsByAccountId[accountId] = user
          }
        }
        var refreshedUsers = [String: NEUserWithFriend]()
        for user in users {
          if let accountId = user.user?.accountId ?? user.friend?.accountId {
            refreshedUsers[accountId] = user
          }
        }
        let refreshedRows = cachedBlockAccountIds.compactMap { accountId -> ContactEntryState? in
          guard let user = refreshedUsers[accountId] ?? self.friendsByAccountId[accountId] else {
            return nil
          }
          return self.makeRow(
            for: self.displayUser(for: user, accountId: accountId),
            accountId: accountId
          )
        }
        guard !refreshedRows.isEmpty,
              refreshedRows != self.rows else {
          return
        }
        self.rows = refreshedRows
      }
    }
    return true
  }

  private func displayUser(for user: NEUserWithFriend, accountId: String) -> NEUserWithFriend {
    guard let cached = friendsByAccountId[accountId] ?? NEFriendUserCache.shared.getFriendInfo(accountId) else {
      return user
    }
    let cachedAvatar = cached.user?.avatar?.trimmingCharacters(in: .whitespacesAndNewlines)
    let userAvatar = user.user?.avatar?.trimmingCharacters(in: .whitespacesAndNewlines)
    if cachedAvatar?.isEmpty == false, userAvatar?.isEmpty != false {
      return cached
    }
    return user
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NEContactNetworkGuard.allowsNetworkOperation else {
      toast = NECommonToast(message: NEContactErrorMessageMapper.networkMessage())
      return false
    }
    return true
  }
}
