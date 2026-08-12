// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

@MainActor
public final class ContactListViewModel: ObservableObject {
  @Published public private(set) var state = ContactListState()

  public let config: ContactSwiftUIConfig
  public var showsOnlineStatus: Bool {
    config.showsOnlineStatus && IMKitConfigCenter.shared.enableOnlineStatus
  }

  private let contactRepo: ContactRepo
  private let teamRepo: TeamRepo
  private let subscribeRepo: SubscribeRepo
  private var listenerTokens = [NEChatKitListenerToken]()
  private var notificationTokens = [NSObjectProtocol]()
  private var aiListener: ContactAIUserChangeListener?
  private var friends = [NEUserWithFriend]()
  private var onlineStatus = [String: Bool]()
  private var didLoad = false
  private var networkWasBroken = false

  public init(config: ContactSwiftUIConfig = ContactSwiftUIConfigCenter.shared.config,
              contactRepo: ContactRepo = .shared,
              teamRepo: TeamRepo = .shared,
              subscribeRepo: SubscribeRepo = .shared) {
    self.config = config
    self.contactRepo = contactRepo
    self.teamRepo = teamRepo
    self.subscribeRepo = subscribeRepo
  }

  deinit {
    listenerTokens.forEach { $0.cancel() }
    listenerTokens.removeAll()
    notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    notificationTokens.removeAll()
    if let aiListener {
      NEAIUserManager.shared.removeAIUserChangeListener(listener: aiListener)
    }
  }

  public func onAppear() {
    installListenersIfNeeded()
    guard !didLoad else {
      loadFriends(silent: true)
      return
    }
    didLoad = true
    loadInitial()
  }

  public func onDisappear() {}

  public func loadInitial() {
    state.phase = .loading
    loadFriends()
    loadValidationUnread()
  }

  public func setSearchText(_ text: String) {
    state.searchText = text
  }

  public func clearSearch() {
    state.searchText = ""
  }

  public func consumePendingRoute() {
    state.pendingRoute = nil
  }

  public func consumeToast(_ toast: NECommonToast) {
    if state.toast?.id == toast.id {
      state.toast = nil
    }
  }

  public func select(_ entry: ContactEntryState) {
    switch entry.kind {
    case .validation:
      open(.validation)
    case .blackList:
      open(.blackList)
    case .team:
      if let team = entry.team {
        open(.team(teamId: team.teamId))
      } else {
        open(.teamList)
      }
    case .aiUser:
      open(.aiUserList)
    case .aiRobot:
      open(.aiRobotList)
    case .friend:
      guard let accountId = entry.accountId else {
        return
      }
      open(.userInfo(accountId: accountId, isCurrentUser: accountId == IMKitClient.instance.account()))
    case .header:
      break
    }
  }

  public func openAddFriend() {
    open(.addFriend)
  }

  public func openSearchContact() {
    open(.searchContact)
  }

  private func open(_ kind: ContactRouteRequest.Kind) {
    let request = ContactRouteRequest(kind: kind)
    if let routeHandler = config.routeHandler {
      routeHandler(request)
    } else {
      state.pendingRoute = request
    }
  }

  private func installListenersIfNeeded() {
    guard listenerTokens.isEmpty else {
      return
    }

    notificationTokens.append(
      NotificationCenter.default.addObserver(
        forName: NENotificationName.clearValidationMessageUnreadCount,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.clearValidationUnreadCount()
        }
      }
    )

    listenerTokens.append(
      contactRepo.addContactEventListener(
        NEContactEvent(
          userProfileChanged: { [weak self] _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          },
          blockListAdded: { [weak self] _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          },
          blockListRemoved: { [weak self] _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          },
          friendAdded: { [weak self] _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          },
          friendDeleted: { [weak self] _, _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          },
          friendAddApplication: { [weak self] _ in
            Task { @MainActor in self?.loadValidationUnread() }
          },
          friendAddRejected: { [weak self] _ in
            Task { @MainActor in self?.loadValidationUnread() }
          },
          friendInfoChanged: { [weak self] _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          },
          contactChanged: { [weak self] _, _ in
            Task { @MainActor in self?.loadFriends(silent: true) }
          }
        )
      )
    )

    listenerTokens.append(
      teamRepo.addTeamEventListener(
        NETeamEvent(
          receiveJoinAction: { [weak self] _ in
            Task { @MainActor in self?.loadValidationUnread() }
          }
        )
      )
    )

    if config.showsOnlineStatus, IMKitConfigCenter.shared.enableOnlineStatus {
      listenerTokens.append(
        subscribeRepo.addSubscribeEventListener(
          NESubscribeEvent(userStatusChanged: { [weak self] statuses in
            Task { @MainActor in
              self?.handleUserStatusChanged(statuses)
            }
          })
        )
      )
    }

    listenerTokens.append(
      NEFriendUserCache.shared.addFriendCacheInitListener { [weak self] in
        Task { @MainActor in
          self?.loadFriends(silent: true)
        }
      }
    )

    listenerTokens.append(
      IMKitClient.instance.addClientEventListener(
        NEIMKitClientEvent(
          connectStatus: { [weak self] status in
            Task { @MainActor in
              self?.handleConnectStatus(status)
            }
          },
          loginStatus: { [weak self] status in
            guard status == .LOGIN_STATUS_LOGOUT else {
              return
            }
            Task { @MainActor in
              self?.resetForLogout()
            }
          },
          kickedOffline: { [weak self] _ in
            Task { @MainActor in
              self?.resetForLogout()
            }
          }
        )
      )
    )

    let aiListener = ContactAIUserChangeListener { [weak self] _ in
      Task { @MainActor in
        self?.rebuildSections()
      }
    }
    NEAIUserManager.shared.addAIUserChangeListener(listener: aiListener)
    self.aiListener = aiListener
  }

  private func loadFriends(silent: Bool = false) {
    if !NEFriendUserCache.shared.isEmpty() {
      friends = NEFriendUserCache.shared.getFriendListNotInBlocklist().map(\.value)
      updateOnlineStatusAndRebuild()
      state.phase = .loaded
      return
    }

    if !silent {
      state.phase = .loading
    }

    contactRepo.getContactList { [weak self] friends, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          let message = NEContactErrorMessageMapper.message(for: error)
          self.state.phase = .failed(message)
          self.state.toast = NECommonToast(message: message)
          return
        }
        self.friends = friends ?? []
        self.updateOnlineStatusAndRebuild()
        self.state.phase = .loaded
      }
    }
  }

  private func loadValidationUnread() {
    contactRepo.getUnreadApplicationCount { [weak self] friendUnread, friendError in
      guard let self else {
        return
      }

      guard IMKitConfigCenter.shared.enableTeamJoinAgreeModelAuth else {
        Task { @MainActor in
          self.state.unreadValidationCount = friendUnread
          self.rebuildSections()
        }
        return
      }

      let option = V2NIMTeamJoinActionInfoQueryOption()
      option.offset = 0
      option.limit = 100
      self.teamRepo.getTeamJoinActionInfoList(option) { result, teamError in
        Task { @MainActor in
          let message = (friendError ?? teamError).map { NEContactErrorMessageMapper.message(for: $0) }
          if let message {
            self.state.toast = NECommonToast(message: message)
          }
          let readTime = UserDefaults.standard.double(forKey: keyTeamJoinActionReadTime)
          let teamUnread = result?.infos?.filter {
            $0.timestamp > readTime
          }.count ?? 0
          self.state.unreadValidationCount = friendUnread + teamUnread
          self.rebuildSections()
        }
      }
    }
  }

  private func updateOnlineStatusAndRebuild() {
    guard config.showsOnlineStatus, IMKitConfigCenter.shared.enableOnlineStatus else {
      onlineStatus = [:]
      rebuildSections()
      return
    }

    var pending = [String]()
    var updated = onlineStatus
    for friend in friends {
      guard let accountId = friend.user?.accountId ?? friend.friend?.accountId else {
        continue
      }
      let cached = subscribeRepo.cachedSwiftUIOnlineState(accountId: accountId)
      switch cached {
      case .online:
        updated[accountId] = true
      case .offline:
        updated[accountId] = false
      case .unknown:
        pending.append(accountId)
      }
    }
    onlineStatus = updated
    rebuildSections()

    if !pending.isEmpty {
      NESubscribeManager.shared.subscribeUsersOnlineState(pending) { [weak self] _ in
        Task { @MainActor in
          guard let self else {
            return
          }
          var refreshed = self.onlineStatus
          for accountId in pending {
            refreshed[accountId] = self.subscribeRepo.cachedSwiftUIOnlineState(accountId: accountId).isOnline
          }
          self.onlineStatus = refreshed
          self.rebuildSections()
        }
      }
    }
  }

  private func handleUserStatusChanged(_ statuses: [V2NIMUserStatus]) {
    var changed = false
    for status in statuses {
      guard NEFriendUserCache.shared.isFriend(status.accountId) else {
        continue
      }
      let isOnline = status.statusType == .USER_STATUS_TYPE_LOGIN
      guard onlineStatus[status.accountId] != isOnline else {
        continue
      }
      onlineStatus[status.accountId] = isOnline
      changed = true
    }
    if changed {
      rebuildSections()
    }
  }

  private func handleConnectStatus(_ status: V2NIMConnectStatus) {
    if status == .CONNECT_STATUS_WAITING {
      networkWasBroken = true
      return
    }

    guard status == .CONNECT_STATUS_CONNECTED, networkWasBroken else {
      return
    }

    networkWasBroken = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      Task { @MainActor in
        self?.updateOnlineStatusAndRebuild()
      }
    }
  }

  private func resetForLogout() {
    networkWasBroken = false
    didLoad = false
    friends.removeAll()
    onlineStatus.removeAll()
    state.phase = .idle
    state.unreadValidationCount = 0
    state.sections.removeAll()
    state.indexTitles.removeAll()
    state.pendingRoute = nil
    state.toast = nil
  }

  private func clearValidationUnreadCount() {
    state.unreadValidationCount = 0
    rebuildSections()
  }

  private func rebuildSections() {
    let sections = ContactSectionBuilder.sections(
      friends: friends,
      unreadCount: state.unreadValidationCount,
      onlineStatus: onlineStatus,
      config: config
    )
    let indexTitles = ContactSectionBuilder.indexTitles(for: sections)
    guard state.sections != sections || state.indexTitles != indexTitles else {
      return
    }
    var nextState = state
    nextState.sections = sections
    nextState.indexTitles = indexTitles
    state = nextState
  }
}

private final class ContactAIUserChangeListener: NSObject, AIUserChangeListener {
  private let handler: ([V2NIMAIUser]) -> Void

  init(handler: @escaping ([V2NIMAIUser]) -> Void) {
    self.handler = handler
  }

  func onAIUserChanged(aiUsers: [V2NIMAIUser]) {
    handler(aiUsers)
  }
}
