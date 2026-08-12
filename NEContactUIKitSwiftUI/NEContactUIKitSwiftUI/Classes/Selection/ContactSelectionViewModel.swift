// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

public enum ContactSelectionTab: String, CaseIterable, Identifiable {
  case friends
  case aiUsers

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .friends:
      return NEContactUIKitSwiftUIBundle.localized("contact_friend", value: "Friend")
    case .aiUsers:
      return NEContactUIKitSwiftUIBundle.localized("contact_ai_user", value: "AI User")
    }
  }
}

@MainActor
public final class ContactSelectionViewModel: ObservableObject {
  @Published public private(set) var phase: ContactListPhase = .idle
  @Published public private(set) var sections: [ContactSectionState] = []
  @Published public private(set) var selectedRows: [ContactEntryState] = []
  @Published public var selectedTab: ContactSelectionTab = .friends {
    didSet {
      sections = sections(for: selectedTab)
    }
  }
  @Published public var toast: NECommonToast?

  public let context: ContactSelectionContext
  private let contactRepo: ContactRepo
  private var friends = [NEUserWithFriend]()
  private var aiUsers = [V2NIMAIUser]()
  private var friendSections = [ContactSectionState]()
  private var aiUserSections = [ContactSectionState]()
  private var selectedAccountIds = Set<String>()
  private var selectedOrder = [String]()
  private var isRefreshingCachedFriends = false

  public init(context: ContactSelectionContext,
              contactRepo: ContactRepo = .shared) {
    self.context = context
    self.contactRepo = contactRepo
  }

  public func onAppear() {
    load()
  }

  public func load() {
    selectedAccountIds.removeAll()
    selectedOrder.removeAll()
    let cachedFriends = NEFriendUserCache.shared.getFriendListNotInBlocklist().map(\.value)
    if !cachedFriends.isEmpty {
      friends = normalizedCachedFriends(cachedFriends)
      if context.allowsAIUsers {
        aiUsers = NEAIUserManager.shared.getAllAIUsers()
      }
      rebuild()
      phase = .loaded
      refreshCachedFriendsIfNeeded()
      return
    }

    phase = .loading
    contactRepo.getContactList { [weak self] friends, error in
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
        self.friends = self.normalizedCachedFriends(friends ?? [])
        if self.context.allowsAIUsers {
          self.aiUsers = NEAIUserManager.shared.getAllAIUsers()
        }
        self.rebuild()
        self.phase = .loaded
      }
    }
  }

  public func toggle(_ row: ContactEntryState) {
    guard let accountId = row.accountId, !row.isDisabled else {
      return
    }
    if selectedAccountIds.contains(accountId) {
      selectedAccountIds.remove(accountId)
      selectedOrder.removeAll { $0 == accountId }
    } else {
      guard context.limit > 0 else {
        toast = NECommonToast(message: String(format: NEContactUIKitSwiftUIBundle.localized("exceeded_limit", value: "Exceed the %d person limit"), 0))
        return
      }
      guard selectedAccountIds.count < context.limit else {
        toast = NECommonToast(message: String(format: NEContactUIKitSwiftUIBundle.localized("exceeded_limit", value: "Exceed the %d person limit"), context.limit))
        return
      }
      selectedAccountIds.insert(accountId)
      selectedOrder.append(accountId)
    }
    rebuild()
  }

  public func removeSelected(_ row: ContactEntryState) {
    guard let accountId = row.accountId else {
      return
    }
    selectedAccountIds.remove(accountId)
    selectedOrder.removeAll { $0 == accountId }
    rebuild()
  }

  public func makeResult() -> ContactSelectionResult? {
    guard !selectedRows.isEmpty else {
      toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("select_contact", value: "Please select Contact"))
      return nil
    }
    guard NEContactNetworkGuard.allowsNetworkOperation else {
      toast = NECommonToast(message: NEContactErrorMessageMapper.networkMessage())
      return nil
    }
    let names = selectedRows.map(\.title).joined(separator: "、")
    return ContactSelectionResult(accountIds: selectedRows.compactMap(\.accountId), names: names)
  }

  public var isDoneEnabled: Bool {
    context.disablesDoneWhenEmpty ? !selectedRows.isEmpty : true
  }

  public func consumeToast(_ toast: NECommonToast) {
    if self.toast?.id == toast.id {
      self.toast = nil
    }
  }

  public var selectionTabs: [ContactSelectionTab] {
    context.allowsAIUsers ? [.friends, .aiUsers] : []
  }

  public var showsTabs: Bool {
    context.allowsAIUsers
  }

  private func rebuild() {
    friendSections = ContactSectionBuilder.groupedFriendSections(
      friends: friends.filter { user in
        guard let accountId = user.user?.accountId ?? user.friend?.accountId else {
          return false
        }
        return !context.filterAccountIds.contains(accountId)
      },
      onlineStatus: [:],
      selectedAccountIds: selectedAccountIds,
      disabledAccountIds: context.filterAccountIds
    )

    if context.allowsAIUsers {
      let rows = aiUsers.compactMap { aiUser -> ContactEntryState? in
        guard let accountId = aiUser.accountId, !context.filterAccountIds.contains(accountId) else {
          return nil
        }
        return ContactEntryState(
          id: "ai.\(accountId)",
          kind: .aiUser,
          accountId: accountId,
          title: ContactSectionBuilder.displayName(for: aiUser),
          subtitle: accountId,
          avatarURL: aiUser.avatar,
          avatarName: aiUser.name,
          isSelected: selectedAccountIds.contains(accountId),
          aiUser: aiUser
        )
      }
      aiUserSections = rows.isEmpty ? [] : [ContactSectionState(title: "", entries: rows)]
    } else {
      aiUserSections = []
    }

    sections = sections(for: selectedTab)
    let rowsByAccountId = (friendSections + aiUserSections)
      .flatMap(\.entries)
      .reduce(into: [String: ContactEntryState]()) { result, row in
        if let accountId = row.accountId {
          result[accountId] = row
        }
      }
    selectedRows = selectedOrder.compactMap { rowsByAccountId[$0] }
    let validSelectedAccountIds = Set(selectedRows.compactMap(\.accountId))
    selectedAccountIds.formIntersection(validSelectedAccountIds)
    selectedOrder.removeAll { !validSelectedAccountIds.contains($0) }
  }

  private func refreshCachedFriendsIfNeeded() {
    guard !isRefreshingCachedFriends else {
      return
    }
    let accountIds = friends.compactMap { user -> String? in
      guard let accountId = user.user?.accountId ?? user.friend?.accountId,
            !context.filterAccountIds.contains(accountId),
            effectiveAvatarURL(for: user, accountId: accountId) == nil else {
        return nil
      }
      return accountId
    }
    guard !accountIds.isEmpty else {
      return
    }

    isRefreshingCachedFriends = true
    NEFriendUserCache.shared.loadShowName(accountIds) { [weak self] users in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.isRefreshingCachedFriends = false
        guard let users, !users.isEmpty else {
          return
        }

        var usersByAccountId = users.reduce(into: [String: NEUserWithFriend]()) { result, user in
          if let accountId = user.user?.accountId ?? user.friend?.accountId {
            result[accountId] = user
          }
        }
        guard !usersByAccountId.isEmpty else {
          return
        }

        self.friends = self.friends.map { user in
          guard let accountId = user.user?.accountId ?? user.friend?.accountId,
                let refreshed = usersByAccountId.removeValue(forKey: accountId) else {
            return user
          }
          return self.mergedUserWithFriend(primary: refreshed, fallback: user)
        }
        self.rebuild()
      }
    }
  }

  private func normalizedCachedFriends(_ friends: [NEUserWithFriend]) -> [NEUserWithFriend] {
    friends.map { user in
      guard let accountId = user.user?.accountId ?? user.friend?.accountId,
            let cached = NEFriendUserCache.shared.getFriendInfo(accountId) else {
        return user
      }
      return mergedUserWithFriend(primary: cached, fallback: user)
    }
  }

  private func mergedUserWithFriend(primary: NEUserWithFriend,
                                    fallback: NEUserWithFriend) -> NEUserWithFriend {
    NEUserWithFriend(
      user: primary.user ?? fallback.user,
      friend: primary.friend ?? fallback.friend
    )
  }

  private func effectiveAvatarURL(for user: NEUserWithFriend,
                                  accountId: String) -> String? {
    nonEmpty(NEFriendUserCache.shared.getFriendInfo(accountId)?.user?.avatar) ??
      nonEmpty(user.user?.avatar)
  }

  private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private func sections(for tab: ContactSelectionTab) -> [ContactSectionState] {
    switch tab {
    case .friends:
      return friendSections
    case .aiUsers:
      return aiUserSections
    }
  }
}
