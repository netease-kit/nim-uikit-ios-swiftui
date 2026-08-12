// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NEChatUIKitSwiftUI
import NECommonUIKitSwiftUI
import NIMSDK

@MainActor
public final class ConversationListViewModel: ObservableObject {
  @Published public private(set) var state: ConversationListState

  public let mode: ConversationMode
  public let config: ConversationSwiftUIConfig

  private let dataSource: ConversationDataSource
  private let listenerBag = NEChatKitListenerBag()
  private var notificationTokens = [NSObjectProtocol]()
  private var snapshotById = [String: ConversationItemSnapshot]()
  private var clearedUnreadBoundaryByConversationId = [String: ConversationItemSnapshot]()
  private var onlineStatusByConversationId = [String: Bool]()
  private var pendingOnlineAccountIds = Set<String>()
  private var subscribedOnlineAccountIds = Set<String>()
  private var retriedOnlineAccountIds = Set<String>()
  private var onlineSubscriptionGeneration = 0
  private var p2pAccountIds = Set<String>()
  private var isVisible = false
  private var isStarted = false
  private var isSyncFinished = false
  private var shouldReloadAfterInitialSync = false
  private var pendingInitialCompletion: (() -> Void)?
  private var networkWasBroken = false
  private var activeAccountId: String
  private let pageSize = 50

  public convenience init(mode: ConversationMode,
                          config: ConversationSwiftUIConfig = ConversationSwiftUIConfigCenter.shared.current()) {
    let source: ConversationDataSource = mode == .cloud
      ? CloudConversationDataSource()
      : LocalConversationDataSource()
    self.init(mode: mode, dataSource: source, config: config)
  }

  init(mode: ConversationMode,
       dataSource: ConversationDataSource,
       config: ConversationSwiftUIConfig) {
    self.mode = mode
    self.dataSource = dataSource
    self.config = config
    activeAccountId = IMKitClient.instance.account()
    state = ConversationListState()
  }

  deinit {
    listenerBag.cancelAll()
    notificationTokens.forEach(NotificationCenter.default.removeObserver)
  }

  public func onAppear() {
    isVisible = true
    let networkBroken = NEChatDetectNetworkTool.shareInstance.manager?.isReachable == false
    if state.networkBroken != networkBroken {
      state.networkBroken = networkBroken
    }
    networkWasBroken = networkBroken
    refreshFeatureToggleState()
    guard !isStarted else {
      return
    }
    isStarted = true
    installListeners()
    loadInitial()
  }

  public func onDisappear() {
    isVisible = false
  }

  public func loadInitial() {
    if mode == .cloud, !isSyncFinished {
      shouldReloadAfterInitialSync = true
    }
    dataSource.reset()
    snapshotById.removeAll()
    state.phase = .loading
    state.hasMore = true
    dataSource.loadPage(limit: pageSize) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        switch result {
        case let .success(page):
          self.merge(page.conversations)
          self.state.hasMore = !page.finished
          self.state.phase = .loaded
          self.refreshRows()
          self.refreshP2PUserInfos()
          self.pendingInitialCompletion?()
          self.pendingInitialCompletion = nil
        case let .failure(error):
          let message = NEConversationErrorMessageMapper.message(for: error)
          self.state.phase = .failed(message)
          self.showToast(message)
        }
      }
    }
  }

  public func loadMoreIfNeeded(currentRow row: ConversationRowState? = nil) {
    guard state.hasMore, !state.isLoadingMore else {
      return
    }
    if let row, row.id != state.rows.last?.id {
      return
    }
    state.isLoadingMore = true
    dataSource.loadPage(limit: pageSize) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.state.isLoadingMore = false
        switch result {
        case let .success(page):
          self.merge(page.conversations)
          self.state.hasMore = !page.finished
          self.state.phase = .loaded
          self.refreshRows()
          self.refreshP2PUserInfos()
        case let .failure(error):
          self.showToast(NEConversationErrorMessageMapper.message(for: error))
        }
      }
    }
  }

  public func refreshAfterReconnect() {
    let limit = max(snapshotById.count, pageSize)
    dataSource.reloadCurrent(limit: limit) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        switch result {
        case let .success(page):
          let snapshots = page.conversations.map { self.preservingClearedUnread(in: $0) }
          self.snapshotById = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.conversationId, $0) })
          snapshots.forEach { snapshot in
            if snapshot.unreadCount <= 0 {
              NEConversationAtMessageStore.shared.clearAtRecord(snapshot.conversationId)
            }
          }
          self.state.hasMore = !page.finished
          self.state.phase = .loaded
          self.refreshRows()
          self.refreshP2PUserInfos()
        case let .failure(error):
          self.showToast(NEConversationErrorMessageMapper.message(for: error))
        }
      }
    }
  }

  public func setSearchText(_ text: String) {
    state.searchText = text
  }

  public func clearSearch() {
    state.searchText = ""
  }

  public func toggleActionMenu() {
    guard IMKitConfigCenter.shared.enableTeam else {
      performAction(.addFriend)
      return
    }
    state.isActionMenuPresented.toggle()
  }

  public func dismissActionMenu() {
    state.isActionMenuPresented = false
  }

  public func performAction(_ action: ConversationAction) {
    dismissActionMenu()
    let currentConfig = ConversationSwiftUIConfigCenter.shared.current()
    if let actionHandler = currentConfig.actionHandler {
      actionHandler(action)
      return
    }
    if action == .scanQR, let qrScanHandler = currentConfig.qrScanHandler {
      qrScanHandler()
      return
    }
    showToast(defaultActionToast(action))
  }

  public func openSearch() {
    if let searchHandler = ConversationSwiftUIConfigCenter.shared.current().searchHandler {
      searchHandler()
    } else {
      state.searchText = ""
    }
  }

  public func select(_ row: ConversationRowState) {
    clearAtRecord(row.conversationId)
    guard let route = row.routeContext else {
      showToast(NEConversationUIKitSwiftUIBundle.localized("unknown", value: "[Unknown Message]"))
      return
    }

    if row.targetKind == .p2p,
       let targetId = row.targetId {
      NEAIRobotManager.shared.checkIfRobot(targetId) { [weak self] isRobot in
        Task { @MainActor in
          var resolved = route
          resolved.isRobot = isRobot
          self?.openRoute(resolved)
        }
      }
    } else {
      openRoute(route)
    }
  }

  public func selectAIUser(_ aiUser: ConversationAIUserState) {
    openRoute(ConversationRouteContext(
      conversationId: aiUser.conversationId,
      targetId: aiUser.id,
      kind: .p2p,
      title: aiUser.title,
      isRobot: false
    ))
  }

  public func toggleStickTop(_ row: ConversationRowState) {
    guard ensureNetworkForMutation(allowOfflineDelete: false) else {
      return
    }
    let targetStickTop = !row.isStickTop
    let originalSnapshot = snapshotById[row.conversationId]
    applyStickTopOverride(conversationId: row.conversationId,
                          stickTop: targetStickTop,
                          fallbackSortOrder: row.sortOrder)
    dataSource.setStickTop(conversationId: row.conversationId, stickTop: targetStickTop) { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        if let error {
          self.restoreStickTopSnapshot(conversationId: row.conversationId,
                                       snapshot: originalSnapshot)
          self.showToast(NEConversationErrorMessageMapper.message(for: error))
        }
      }
    }
  }

  public func delete(_ row: ConversationRowState) {
    guard ensureNetworkForMutation(allowOfflineDelete: dataSource.allowsOfflineDelete) else {
      return
    }
    dataSource.deleteConversation(conversationId: row.conversationId) { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        if let error {
          self.showToast(NEConversationErrorMessageMapper.message(for: error))
        } else {
          self.snapshotById.removeValue(forKey: row.conversationId)
          self.clearedUnreadBoundaryByConversationId.removeValue(forKey: row.conversationId)
          self.refreshRows()
        }
      }
    }
  }

  public func consumeToast(_ toast: ConversationToastState) {
    if state.toast?.id == toast.id {
      state.toast = nil
    }
  }

  public func consumePendingRoute() {
    state.pendingRoute = nil
  }

  private func installListeners() {
    dataSource.addListener(
      onCreated: { [weak self] snapshot in
        Task { @MainActor in
          guard let self, !self.shouldSuppressDismissedTeam(snapshot) else { return }
          self.merge([snapshot])
          self.refreshRows()
          let accountIds = snapshot.type == .CONVERSATION_TYPE_P2P
            ? [snapshot.targetId].compactMap { $0 }
            : []
          self.refreshP2PUserInfos(accountIds: accountIds)
        }
      },
      onChanged: { [weak self] snapshots in
        Task { @MainActor in
          guard let self else { return }
          let active = snapshots.filter { !self.shouldSuppressDismissedTeam($0) }
          self.merge(active)
          self.refreshRows()
          let accountIds = active.compactMap { snapshot in
            snapshot.type == .CONVERSATION_TYPE_P2P ? snapshot.targetId : nil
          }
          self.refreshP2PUserInfos(accountIds: accountIds)
        }
      },
      onDeleted: { [weak self] ids in
        Task { @MainActor in
          ids.forEach {
            self?.snapshotById.removeValue(forKey: $0)
            self?.clearedUnreadBoundaryByConversationId.removeValue(forKey: $0)
          }
          self?.refreshRows()
        }
      },
      onSyncFinished: { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          self.isSyncFinished = true
          self.pendingInitialCompletion?()
          self.pendingInitialCompletion = nil
          if self.shouldReloadAfterInitialSync {
            self.shouldReloadAfterInitialSync = false
            self.loadInitial()
          }
        }
      },
      onSyncFailed: { [weak self] error in
        Task { @MainActor in
          self?.showToast(NEConversationErrorMessageMapper.message(for: error))
        }
      }
    )
    .store(in: listenerBag)

    IMKitClient.instance.addClientEventListener(
      NEIMKitClientEvent(
        connectStatus: { [weak self] status in
          Task { @MainActor in
            self?.handleConnectStatus(status)
          }
        },
        loginStatus: { [weak self] status in
          Task { @MainActor in
            guard let self else { return }
            if status == .LOGIN_STATUS_LOGOUT {
              self.activeAccountId = ""
              self.p2pAccountIds.removeAll()
              self.invalidateOnlineSubscriptions()
              self.onlineStatusByConversationId.removeAll()
              self.snapshotById.removeAll()
              self.clearedUnreadBoundaryByConversationId.removeAll()
              self.refreshRows()
            } else if status == .LOGIN_STATUS_LOGINED {
              let accountId = IMKitClient.instance.account()
              let accountChanged = self.activeAccountId != accountId
              self.activeAccountId = accountId
              self.p2pAccountIds.removeAll()
              self.invalidateOnlineSubscriptions()
              self.onlineStatusByConversationId.removeAll()
              if accountChanged {
                self.clearedUnreadBoundaryByConversationId.removeAll()
              }
              NESubscribeManager.shared.cleanCache()
              if self.isStarted {
                // UIKit recreates and reloads the conversation controller after
                // an account switch. The SwiftUI tab is retained, so explicitly
                // rebuild the list and its P2P subscription set for the new account.
                self.loadInitial()
              }
            }
          }
        }
      )
    )
    .store(in: listenerBag)

    ContactRepo.shared.addContactEventListener(
      NEContactEvent(
        userProfileChanged: { [weak self] users in
          Task { @MainActor in
            ChatRepo.cacheSwiftUIP2PDisplayUsers(users.map { NEUserWithFriend(user: $0) })
            self?.refreshRows()
            users.compactMap(\.accountId).forEach { self?.reloadP2PConversation($0) }
          }
        },
        friendDeleted: { [weak self] accountId, _ in
          Task { @MainActor in
            ChatRepo.removeSwiftUIP2PDisplayUser(accountId: accountId)
            self?.refreshRows()
            self?.reloadP2PConversation(accountId)
          }
        },
        friendInfoChanged: { [weak self] friend in
          Task { @MainActor in
            if let accountId = friend.accountId {
              ChatRepo.removeSwiftUIP2PDisplayUser(accountId: accountId)
              self?.refreshRows()
              self?.reloadP2PConversation(accountId)
            }
          }
        },
        contactChanged: { [weak self] changeType, contacts in
          guard changeType == .deleteFriend else {
            return
          }
          let accountIds = contacts.compactMap { $0.user?.accountId ?? $0.friend?.accountId }
          let users = Self.nonFriendDisplayUsers(from: contacts)
          Task { @MainActor in
            ChatRepo.cacheSwiftUIP2PDisplayUsers(users)
            self?.refreshRows()
            ChatRepo.shared.loadSwiftUIP2PDisplayUsers(accountIds: accountIds) { [weak self] _, _ in
              Task { @MainActor in
                accountIds.forEach { self?.reloadP2PConversation($0) }
              }
            }
          }
        }
      )
    )
    .store(in: listenerBag)

    TeamRepo.shared.addTeamEventListener(
      NETeamEvent(
        syncFinished: { [weak self] in
          Task { @MainActor in self?.refreshRows() }
        },
        teamDismissed: { [weak self] team in
          Task { @MainActor in self?.deleteDismissedTeam(team.teamId) }
        },
        teamLeft: { [weak self] team, _ in
          Task { @MainActor in self?.deleteDismissedTeam(team.teamId) }
        },
        teamInfoUpdated: { [weak self] _ in
          Task { @MainActor in self?.refreshRows() }
        }
      )
    )
    .store(in: listenerBag)

    ChatRepo.shared.addChatEventListener(
      NEChatEvent(receiveMessages: { [weak self] _ in
        Task { @MainActor in
          self?.refreshRows()
        }
      })
    )
    .store(in: listenerBag)

    if IMKitConfigCenter.shared.enableOnlineStatus {
      SubscribeRepo.shared.addSubscribeEventListener(
        NESubscribeEvent(userStatusChanged: { [weak self] statuses in
          Task { @MainActor in
            self?.handleOnlineStatuses(statuses)
          }
        })
      )
      .store(in: listenerBag)
    }

    NEAIUserPinManager.shared.addPinUserInfoChangeHandler { [weak self] in
      Task { @MainActor in self?.loadAIUsers() }
    }
    .store(in: listenerBag)

    NEAIUserManager.shared.addAIUserChangeHandler { [weak self] users in
      Task { @MainActor in
        guard let self else { return }
        guard IMKitConfigCenter.shared.enableAIUser else {
          self.state.aiUsers = []
          return
        }
        self.state.aiUsers = ConversationRowMapper.aiUserRows(from: users)
      }
    }
    .store(in: listenerBag)

    notificationTokens.append(
      NotificationCenter.default.addObserver(
        forName: NEConversationUIKitSwiftUIConstants.atMessageChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.refreshRows() }
      }
    )
    notificationTokens.append(
      NotificationCenter.default.addObserver(
        forName: NENotificationName.deleteConversationNotificationName,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let conversationId = notification.object as? String else {
          return
        }
        self?.dataSource.deleteConversation(conversationId: conversationId) { _ in }
      }
    )
    notificationTokens.append(
      NotificationCenter.default.addObserver(
        forName: NENotificationName.conversationUnreadDidClearLocally,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let conversationId = notification.object as? String else {
          return
        }
        Task { @MainActor in
          self?.clearUnreadSnapshot(conversationId: conversationId)
        }
      }
    )
  }

  private func merge(_ snapshots: [ConversationItemSnapshot]) {
    snapshots.forEach { incomingSnapshot in
      var snapshot = preservingClearedUnread(in: incomingSnapshot)
      if let existing = snapshotById[snapshot.conversationId],
         existing.stickTop,
         snapshot.stickTop,
         snapshot.lastMessage?.lastMessageState.rawValue == 1 {
        // A revoke changes the last-message preview, not the position the
        // conversation earned when that message arrived.
        snapshot.sortOrder = existing.sortOrder
      }
      if snapshot.unreadCount <= 0 {
        NEConversationAtMessageStore.shared.clearAtRecord(snapshot.conversationId)
      }
      snapshotById[snapshot.conversationId] = snapshot
      if snapshot.type == .CONVERSATION_TYPE_P2P,
         let accountId = snapshot.targetId {
        p2pAccountIds.insert(accountId)
      }
    }
    subscribeOnlineIfNeeded()
  }

  private func preservingClearedUnread(
    in incoming: ConversationItemSnapshot
  ) -> ConversationItemSnapshot {
    guard let boundary = clearedUnreadBoundaryByConversationId[incoming.conversationId] else {
      return incoming
    }

    if incoming.unreadCount <= 0 {
      if isLastMessageNewer(incoming, than: boundary) {
        recordClearedUnreadBoundary(incoming)
      }
      return incoming
    }

    if isLastMessageNewer(incoming, than: boundary) {
      clearedUnreadBoundaryByConversationId.removeValue(forKey: incoming.conversationId)
      return incoming
    }

    var snapshot = incoming
    snapshot.unreadCount = 0
    return snapshot
  }

  private func recordClearedUnreadBoundary(_ snapshot: ConversationItemSnapshot) {
    var boundary = snapshot
    boundary.unreadCount = 0
    clearedUnreadBoundaryByConversationId[snapshot.conversationId] = boundary
  }

  private func isLastMessageNewer(_ incoming: ConversationItemSnapshot,
                                  than boundary: ConversationItemSnapshot) -> Bool {
    guard let incomingLastMessage = incoming.lastMessage else {
      return false
    }
    guard let boundaryLastMessage = boundary.lastMessage else {
      return incoming.sortOrder > boundary.sortOrder
    }

    let incomingRefer = incomingLastMessage.messageRefer
    let boundaryRefer = boundaryLastMessage.messageRefer
    let incomingIdentifiers = Set([
      incomingRefer.messageClientId,
      incomingRefer.messageServerId,
    ].compactMap { identifier -> String? in
      guard let identifier, !identifier.isEmpty else { return nil }
      return identifier
    })
    let boundaryIdentifiers = Set([
      boundaryRefer.messageClientId,
      boundaryRefer.messageServerId,
    ].compactMap { identifier -> String? in
      guard let identifier, !identifier.isEmpty else { return nil }
      return identifier
    })
    if !incomingIdentifiers.isDisjoint(with: boundaryIdentifiers) {
      return false
    }

    if incomingRefer.createTime > 0,
       boundaryRefer.createTime > 0,
       incomingRefer.createTime != boundaryRefer.createTime {
      return incomingRefer.createTime > boundaryRefer.createTime
    }

    return incoming.sortOrder > boundary.sortOrder
  }

  private func refreshRows() {
    let rows = ConversationSortPolicy.sorted(Array(snapshotById.values)).map {
      ConversationRowMapper.row(from: $0, onlineStatus: onlineStatusByConversationId)
    }
    guard state.rows != rows else {
      return
    }
    state.rows = rows
  }

  private func clearUnreadSnapshot(conversationId: String) {
    NEConversationAtMessageStore.shared.clearAtRecord(conversationId)
    guard var snapshot = snapshotById[conversationId] else {
      return
    }
    let needsRefresh = snapshot.unreadCount > 0
    snapshot.unreadCount = 0
    recordClearedUnreadBoundary(snapshot)
    guard needsRefresh else {
      return
    }
    snapshotById[conversationId] = snapshot
    refreshRows()
  }

  private func applyStickTopOverride(conversationId: String,
                                     stickTop: Bool,
                                     fallbackSortOrder: Int64) {
    guard var snapshot = snapshotById[conversationId] else {
      return
    }
    snapshot.stickTop = stickTop
    snapshot.sortOrder = fallbackSortOrder
    snapshotById[conversationId] = snapshot
    refreshRows()
  }

  private func restoreStickTopSnapshot(conversationId: String,
                                       snapshot: ConversationItemSnapshot?) {
    if let snapshot {
      snapshotById[conversationId] = snapshot
    } else {
      snapshotById.removeValue(forKey: conversationId)
    }
    refreshRows()
  }

  private func refreshP2PUserInfos(accountIds: [String]? = nil) {
    let accounts: [String]
    if let accountIds {
      accounts = Array(Set(accountIds).intersection(p2pAccountIds)).sorted()
    } else {
      accounts = p2pAccountIds.sorted()
    }
    guard !accounts.isEmpty else {
      return
    }
    ContactRepo.shared.getUserListFromCloud(accountIds: accounts) { [weak self] _, _ in
      self?.dataSource.conversationIds(for: accounts) { snapshots in
        Task { @MainActor in
          self?.merge(snapshots)
          self?.refreshRows()
        }
      }
    }
  }

  private func reloadP2PConversation(_ accountId: String) {
    dataSource.conversationIds(for: [accountId]) { [weak self] snapshots in
      Task { @MainActor in
        self?.merge(snapshots)
        self?.refreshRows()
      }
    }
  }

  private static func nonFriendDisplayUsers(from contacts: [NEUserWithFriend]) -> [NEUserWithFriend] {
    contacts.compactMap { contact in
      guard let user = contact.user ?? contact.friend?.userProfile else {
        return nil
      }
      return NEUserWithFriend(user: user, friend: nil)
    }
  }

  private func subscribeOnlineIfNeeded() {
    guard isVisible, IMKitConfigCenter.shared.enableOnlineStatus else {
      return
    }
    var pending = [String]()
    for accountId in p2pAccountIds.sorted() where !NEAIUserManager.shared.isAIUser(accountId) {
      let cached = SubscribeRepo.shared.cachedSwiftUIOnlineState(accountId: accountId)
      if cached != .unknown {
        _ = applyOnlineState(cached, accountId: accountId)
      }
      if subscribedOnlineAccountIds.contains(accountId) {
        continue
      }
      if pendingOnlineAccountIds.insert(accountId).inserted {
        pending.append(accountId)
      }
    }
    guard !pending.isEmpty else {
      return
    }

    let generation = onlineSubscriptionGeneration
    NESubscribeManager.shared.subscribeUsersOnlineState(pending) { [weak self] _ in
      Task { @MainActor in
        guard let self, generation == self.onlineSubscriptionGeneration else {
          return
        }
        self.pendingOnlineAccountIds.subtract(pending)
        guard self.isVisible, IMKitConfigCenter.shared.enableOnlineStatus else {
          return
        }
        var changed = false
        var failedAccountIds = [String]()
        for accountId in pending {
          let state = SubscribeRepo.shared.cachedSwiftUIOnlineState(accountId: accountId)
          if NESubscribeManager.shared.hasSubscribe(accountId) {
            self.subscribedOnlineAccountIds.insert(accountId)
          } else {
            self.subscribedOnlineAccountIds.remove(accountId)
            if self.retriedOnlineAccountIds.insert(accountId).inserted {
              failedAccountIds.append(accountId)
            }
          }
          changed = self.applyOnlineState(state, accountId: accountId) || changed
        }
        if changed {
          self.refreshRows()
        }
        self.scheduleOnlineCacheRefresh(accountIds: pending, generation: generation)
        if !failedAccountIds.isEmpty {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self,
                  generation == self.onlineSubscriptionGeneration,
                  self.isVisible else {
              return
            }
            self.subscribeOnlineIfNeeded()
          }
        }
      }
    }
  }

  private func scheduleOnlineCacheRefresh(accountIds: [String], generation: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self,
            generation == self.onlineSubscriptionGeneration,
            self.isVisible,
            IMKitConfigCenter.shared.enableOnlineStatus else {
        return
      }
      var changed = false
      for accountId in accountIds {
        let state = SubscribeRepo.shared.cachedSwiftUIOnlineState(accountId: accountId)
        changed = self.applyOnlineState(state, accountId: accountId) || changed
      }
      if changed {
        self.refreshRows()
      }
    }
  }

  private func handleOnlineStatuses(_ statuses: [V2NIMUserStatus]) {
    guard isVisible else {
      return
    }
    guard IMKitConfigCenter.shared.enableOnlineStatus else {
      if !onlineStatusByConversationId.isEmpty {
        onlineStatusByConversationId.removeAll()
        refreshRows()
      }
      return
    }
    var changed = false
    for status in statuses where p2pAccountIds.contains(status.accountId) {
      pendingOnlineAccountIds.remove(status.accountId)
      subscribedOnlineAccountIds.insert(status.accountId)
      let state = NESwiftUIUserOnlineState(status: status)
      changed = applyOnlineState(state, accountId: status.accountId) || changed
    }
    if changed {
      refreshRows()
    }
  }

  private func refreshFeatureToggleState() {
    if IMKitConfigCenter.shared.enableOnlineStatus {
      subscribeOnlineIfNeeded()
    } else {
      invalidateOnlineSubscriptions()
      onlineStatusByConversationId.removeAll()
    }
    loadAIUsers()
    refreshRows()
  }

  private func loadAIUsers() {
    guard IMKitConfigCenter.shared.enableAIUser else {
      state.aiUsers = []
      return
    }
    NEAIUserManager.shared.getAIUserList()
    state.aiUsers = ConversationRowMapper.aiUserRows(from: NEAIUserManager.shared.getAllAIUsers())
  }

  private func applyOnlineState(_ state: NESwiftUIUserOnlineState,
                                accountId: String) -> Bool {
    guard state != .unknown,
          let conversationId = V2NIMConversationIdUtil.p2pConversationId(accountId) else {
      return false
    }
    let isOnline = state.isOnline
    guard onlineStatusByConversationId[conversationId] != isOnline else {
      return false
    }
    onlineStatusByConversationId[conversationId] = isOnline
    return true
  }

  private func invalidateOnlineSubscriptions() {
    onlineSubscriptionGeneration += 1
    pendingOnlineAccountIds.removeAll()
    subscribedOnlineAccountIds.removeAll()
    retriedOnlineAccountIds.removeAll()
  }

  private func shouldSuppressDismissedTeam(_ snapshot: ConversationItemSnapshot) -> Bool {
    guard IMKitConfigCenter.shared.enableDismissTeamDeleteConversation,
          snapshot.type == .CONVERSATION_TYPE_TEAM,
          snapshot.lastMessage?.messageType == .MESSAGE_TYPE_NOTIFICATION,
          let attachment = snapshot.lastMessage?.attachment as? V2NIMMessageNotificationAttachment else {
      return false
    }

    let isDismissed = attachment.type == .MESSAGE_NOTIFICATION_TYPE_TEAM_DISMISS
    let isKicked = attachment.type == .MESSAGE_NOTIFICATION_TYPE_TEAM_KICK &&
      (attachment.targetIds?.contains(IMKitClient.instance.account()) == true)
    let isLeave = attachment.type == .MESSAGE_NOTIFICATION_TYPE_TEAM_LEAVE &&
      IMKitClient.instance.isMe(snapshot.lastMessage?.messageRefer.senderId)

    guard isDismissed || isKicked || isLeave else {
      return false
    }

    dataSource.deleteConversation(conversationId: snapshot.conversationId) { _ in }
    snapshotById.removeValue(forKey: snapshot.conversationId)
    clearedUnreadBoundaryByConversationId.removeValue(forKey: snapshot.conversationId)
    refreshRows()
    return true
  }

  private func deleteDismissedTeam(_ teamId: String) {
    guard IMKitConfigCenter.shared.enableDismissTeamDeleteConversation,
          let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) else {
      return
    }
    dataSource.deleteConversation(conversationId: conversationId) { _ in }
    snapshotById.removeValue(forKey: conversationId)
    clearedUnreadBoundaryByConversationId.removeValue(forKey: conversationId)
    refreshRows()
  }

  private func handleConnectStatus(_ status: V2NIMConnectStatus) {
    if status == .CONNECT_STATUS_WAITING {
      networkWasBroken = true
      state.networkBroken = true
      invalidateOnlineSubscriptions()
    } else if status == .CONNECT_STATUS_CONNECTED {
      let shouldRefresh = networkWasBroken
      networkWasBroken = false
      state.networkBroken = false
      if shouldRefresh {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
          Task { @MainActor in
            self?.refreshAfterReconnect()
          }
        }
      }
    }
  }

  private func clearAtRecord(_ conversationId: String) {
    NEConversationAtMessageStore.shared.clearAtRecord(conversationId)
    Router.shared.use(
      NEConversationUIKitSwiftUIConstants.clearAtMessageRoute,
      parameters: ["sessionId": conversationId],
      closure: nil
    )
  }

  private func openRoute(_ route: ConversationRouteContext) {
    state.pendingRoute = route
    config.routeHandler?(route)
  }

  private func ensureNetworkForMutation(allowOfflineDelete: Bool) -> Bool {
    if allowOfflineDelete {
      return true
    }
    if !NEConversationNetworkGuard.allowsNetworkOperation {
      showToast(NEConversationErrorMessageMapper.networkMessage())
      return false
    }
    return true
  }

  private func showToast(_ message: String) {
    state.toast = ConversationToastState(message: message)
    ConversationSwiftUIConfigCenter.shared.current().onToast?(message)
  }

  private func defaultActionToast(_ action: ConversationAction) -> String {
    switch action {
    case .addFriend:
      return NEConversationUIKitSwiftUIBundle.localized("add_friend", value: "Add Contacts")
    case .joinTeam:
      return NECommonUIKitSwiftUIBundle.localized("join_team", fallback: "Join Team")
    case .createDiscussion:
      return NEConversationUIKitSwiftUIBundle.localized("create_discussion_group", value: "Create Discussion")
    case .createSeniorTeam:
      return NEConversationUIKitSwiftUIBundle.localized("create_senior_group", value: "Create Group")
    case .scanQR:
      return NEConversationUIKitSwiftUIBundle.localized("scan_qr_no_result", value: "No valid content recognized")
    }
  }
}
