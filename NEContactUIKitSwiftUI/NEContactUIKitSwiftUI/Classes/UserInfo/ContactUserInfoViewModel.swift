// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

public struct ContactUserInfoState: Equatable {
  public var phase: ContactListPhase = .idle
  public var accountId: String
  public var displayName: String
  public var profileName: String?
  public var avatarURL: String?
  public var alias: String?
  public var birthday: String?
  public var phone: String?
  public var email: String?
  public var sign: String?
  public var isFriend: Bool
  public var isBlocked: Bool
  public var isCurrentUser: Bool
  public var isRobot: Bool
  public var isAIUser: Bool
  public var toast: NECommonToast?
  public var pendingRoute: ContactRouteRequest?
  public var aliasSaveSucceeded: Bool = false
  public var shouldDismiss: Bool = false

  public init(accountId: String,
              displayName: String = "",
              isFriend: Bool = false,
              isBlocked: Bool = false,
              isCurrentUser: Bool = false,
              isRobot: Bool = false,
              isAIUser: Bool = false) {
    self.accountId = accountId
    self.displayName = displayName
    self.isFriend = isFriend
    self.isBlocked = isBlocked
    self.isCurrentUser = isCurrentUser
    self.isRobot = isRobot
    self.isAIUser = isAIUser
  }
}

@MainActor
public final class ContactUserInfoViewModel: ObservableObject {
  @Published public private(set) var state: ContactUserInfoState
  private let contactRepo: ContactRepo
  private var user: NEUserWithFriend?
  private var aiUser: V2NIMAIUser?
  private var listenerToken: NEChatKitListenerToken?

  public init(accountId: String,
              isCurrentUser: Bool = false,
              isRobot: Bool = false,
              aiUser: V2NIMAIUser? = nil,
              user: NEUserWithFriend? = nil,
              contactRepo: ContactRepo = .shared) {
    self.contactRepo = contactRepo
    self.aiUser = aiUser
    let cachedUser = contactRepo.getUserInfo([accountId])?.first ??
      NEFriendUserCache.shared.getFriendInfo(accountId)
    let initialUser = user ?? aiUser.map { NEUserWithFriend(user: $0) } ??
      NEAIUserManager.shared.getNEUserById(accountId) ?? cachedUser
    self.user = initialUser
    state = ContactUserInfoState(
      accountId: accountId,
      displayName: initialUser.map(ContactSectionBuilder.displayName(for:)) ?? accountId,
      isFriend: NEFriendUserCache.shared.isFriend(accountId),
      isBlocked: NEFriendUserCache.shared.isBlockAccount(accountId),
      isCurrentUser: isCurrentUser,
      isRobot: isRobot || NEAIRobotManager.shared.isRobot(accountId),
      isAIUser: initialUser?.user is V2NIMAIUser
    )
    state.profileName = initialUser?.showName(false)
  }

  deinit {
    listenerToken?.cancel()
  }

  public func onAppear() {
    installListenerIfNeeded()
    load()
  }

  public func consumeToast(_ toast: NECommonToast) {
    if state.toast?.id == toast.id {
      state.toast = nil
    }
  }

  public func consumePendingRoute() {
    state.pendingRoute = nil
  }

  public func consumeAliasSaveSucceeded() {
    state.aliasSaveSucceeded = false
  }

  public func load() {
    if applyAIUserIfAvailable() {
      state.phase = .loaded
      return
    }

    if let cachedUser = cachedUser() {
      user = cachedUser
      updateStateFromUser()
      // Keep cached profile data visible while a best-effort remote refresh runs.
      state.phase = .loaded
    } else {
      state.phase = .loading
    }

    contactRepo.getUserWithFriend(accountIds: [state.accountId]) { [weak self] users, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          if self.applyAIUserIfAvailable() {
            self.state.phase = .loaded
            return
          }
          if let cachedUser = self.cachedUser() {
            self.user = cachedUser
            self.updateStateFromUser()
            self.state.phase = .loaded
            return
          }
          let message = NEContactErrorMessageMapper.message(for: error)
          self.state.phase = .failed(message)
          self.state.toast = NECommonToast(message: message)
          return
        }
        if let user = users?.first {
          self.user = user
          ChatRepo.cacheSwiftUIP2PDisplayUsers([user])
          NotificationCenter.default.post(
            name: NENotificationName.didTapHeader,
            object: user
          )
        } else if let aiUser = NEAIUserManager.shared.getNEUserById(self.state.accountId) {
          self.user = aiUser
        }
        self.updateStateFromUser()
        self.state.phase = .loaded
      }
    }
  }

  public func addFriend() {
    guard ensureNetworkForMutation() else {
      return
    }
    let params = V2NIMFriendAddParams()
    params.addMode = .FRIEND_MODE_TYPE_APPLAY
    contactRepo.addFriend(accountId: state.accountId, params: params) { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.state.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
        } else {
          self.state.toast = NECommonToast(message: NEContactUIKitSwiftUIBundle.localized("send_friend_apply", value: "Contact Request Sent"))
          if NEFriendUserCache.shared.isBlockAccount(self.state.accountId) {
            self.contactRepo.removeBlockList(accountId: self.state.accountId) { _ in }
          }
        }
      }
    }
  }

  public func deleteFriend() {
    guard ensureNetworkForMutation() else {
      return
    }
    let params = V2NIMFriendDeleteParams()
    params.deleteAlias = true
    contactRepo.deleteFriend(account: state.accountId, params: params) { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.state.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
        } else {
          self.state.isFriend = false
          self.state.shouldDismiss = true
        }
      }
    }
  }

  public func toggleBlock(_ isBlocked: Bool) {
    guard ensureNetworkForMutation() else {
      return
    }
    let completion: (NSError?) -> Void = { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.state.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
        } else {
          self.state.isBlocked = isBlocked
        }
      }
    }
    if isBlocked {
      contactRepo.addBlockList(accountId: state.accountId, completion)
    } else {
      contactRepo.removeBlockList(accountId: state.accountId, completion)
    }
  }

  public func updateAlias(_ alias: String,
                          completion: ((Bool) -> Void)? = nil) {
    guard ensureNetworkForMutation() else {
      completion?(false)
      return
    }
    let params = V2NIMFriendSetParams()
    params.alias = alias
    contactRepo.setFriendInfo(accountId: state.accountId, params: params) { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.state.toast = NECommonToast(message: NEContactErrorMessageMapper.message(for: error))
          completion?(false)
        } else {
          self.state.alias = alias
          self.state.displayName = alias.isEmpty ? (self.user?.showName(false) ?? self.state.accountId) : alias
          self.state.aliasSaveSucceeded = true
          // The profile request can complete without a friend object. Reuse the
          // authoritative friend cache so returning pages update immediately.
          let cachedUser = NEFriendUserCache.shared.getFriendInfo(self.state.accountId)
          if self.user == nil {
            self.user = cachedUser
          }
          if self.user?.user == nil {
            self.user?.user = cachedUser?.user
          }
          let friend = self.user?.friend ?? cachedUser?.friend
          friend?.alias = alias
          self.user?.friend = friend
          if let friend {
            self.contactRepo.onFriendInfoChanged(friend)
          }
          if let user = self.user {
            ChatRepo.cacheSwiftUIP2PDisplayUsers([user])
          }
          completion?(true)
        }
      }
    }
  }

  public func openChat() {
    state.pendingRoute = ContactRouteRequest(kind: .chat(accountId: state.accountId, title: state.displayName))
  }

  private func installListenerIfNeeded() {
    guard listenerToken == nil else {
      return
    }
    listenerToken = contactRepo.addContactEventListener(
      NEContactEvent(
        userProfileChanged: { [weak self] users in
          Task { @MainActor in
            guard let self,
                  users.contains(where: { $0.accountId == self.state.accountId }) else {
              return
            }
            self.load()
          }
        },
        blockListAdded: { [weak self] user in
          Task { @MainActor in
            guard let self, user.accountId == self.state.accountId else {
              return
            }
            self.state.isBlocked = true
          }
        },
        blockListRemoved: { [weak self] accountId in
          Task { @MainActor in
            guard let self, accountId == self.state.accountId else {
              return
            }
            self.state.isBlocked = false
          }
        },
        friendAdded: { [weak self] friend in
          Task { @MainActor in
            guard let self, friend.accountId == self.state.accountId else {
              return
            }
            self.state.isFriend = true
            self.load()
          }
        },
        friendDeleted: { [weak self] accountId, _ in
          Task { @MainActor in
            guard let self, accountId == self.state.accountId else {
              return
            }
            self.state.isFriend = false
            self.state.alias = nil
            self.load()
          }
        },
        friendInfoChanged: { [weak self] friend in
          Task { @MainActor in
            guard let self, friend.accountId == self.state.accountId else {
              return
            }
            self.load()
          }
        },
        contactChanged: { [weak self] _, contacts in
          Task { @MainActor in
            guard let self else {
              return
            }
            for contact in contacts where contact.user?.accountId == self.state.accountId || contact.friend?.accountId == self.state.accountId {
              self.user = contact
              self.updateStateFromUser()
            }
          }
        }
      )
    )
  }

  private func updateStateFromUser() {
    guard let user else {
      state.displayName = state.accountId
      state.isFriend = NEFriendUserCache.shared.isFriend(state.accountId)
      state.isBlocked = NEFriendUserCache.shared.isBlockAccount(state.accountId)
      state.isAIUser = false
      state.isRobot = NEAIRobotManager.shared.isRobot(state.accountId)
      return
    }

    state.displayName = ContactSectionBuilder.displayName(for: user)
    state.profileName = user.user?.name
    state.avatarURL = user.user?.avatar
    state.alias = user.friend?.alias
    state.birthday = user.user?.birthday
    state.phone = user.user?.mobile
    state.email = user.user?.email
    state.sign = user.user?.sign
    state.isFriend = NEFriendUserCache.shared.isFriend(state.accountId)
    state.isBlocked = NEFriendUserCache.shared.isBlockAccount(state.accountId)
    state.isAIUser = user.user is V2NIMAIUser
    state.isRobot = state.isRobot || NEAIRobotManager.shared.isRobot(state.accountId)
  }

  private func cachedUser() -> NEUserWithFriend? {
    contactRepo.getUserInfo([state.accountId])?.first ??
      NEFriendUserCache.shared.getFriendInfo(state.accountId)
  }

  private func applyAIUserIfAvailable() -> Bool {
    if let aiUser {
      user = NEUserWithFriend(user: aiUser)
      updateStateFromUser()
      return true
    }
    if let cachedAIUser = NEAIUserManager.shared.getNEUserById(state.accountId) {
      user = cachedAIUser
      updateStateFromUser()
      return true
    }
    return false
  }

  private func ensureNetworkForMutation() -> Bool {
    guard NEContactNetworkGuard.allowsNetworkOperation else {
      state.toast = NECommonToast(message: NEContactErrorMessageMapper.networkMessage())
      return false
    }
    return true
  }
}
