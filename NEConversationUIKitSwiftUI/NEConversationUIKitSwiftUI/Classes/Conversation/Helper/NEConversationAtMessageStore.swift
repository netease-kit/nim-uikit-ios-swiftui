// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NIMSDK

final class NEConversationAtMessageStore {
  static let shared = NEConversationAtMessageStore()

  private struct Record: Codable {
    var messageTimes = [String: TimeInterval]()
    var lastTime: TimeInterval = 0

    var isUnread: Bool {
      !messageTimes.isEmpty
    }
  }

  private final class AtMessageBatchState {
    var changed = false
  }

  private struct RoamingConversation: Hashable {
    let conversationId: String
    let messageLimit: Int
  }

  private final class RoamingScanState {
    let conversations: [RoamingConversation]
    var nextIndex = 0
    var inFlightCount = 0
    var changed = false
    var isRefillScheduled = false

    init(conversations: [RoamingConversation]) {
      self.conversations = conversations
    }
  }

  private let queue = DispatchQueue(
    label: "NEConversationUIKitSwiftUI.AtMessageStore",
    qos: .utility
  )
  // This is a best-effort reconciliation pass. Keep it below foreground
  // navigation and timeline loading, especially for accounts with many groups.
  private let maxConcurrentRoamingRequests = 1
  private let roamingScanDebounceInterval: TimeInterval = 3
  private let roamingRequestBatchInterval: TimeInterval = 0.25
  private var records = [String: Record]()
  private var conversationGenerations = [String: Int]()
  private var listenerBag = NEChatKitListenerBag()
  private var didSetup = false
  private var currentAccountId = ""
  private var roamingScanGeneration = 0
  private var pendingRoamingScanWorkItem: DispatchWorkItem?
  private var isRoamingScanRunning = false
  private var completedRoamingScanAccountId: String?

  private init() {}

  func setup() {
    guard !didSetup else {
      return
    }
    didSetup = true

    ChatRepo.shared.addChatEventListener(
      NEChatEvent(
        receiveMessages: { [weak self] messages in
          self?.filterAtMessages(messages)
        },
        messageRevokeNotifications: { [weak self] notifications in
          self?.removeMessageRefers(notifications.compactMap(\.messageRefer))
        },
        messageDeletedNotifications: { [weak self] notifications in
          self?.removeMessageRefers(notifications.map(\.messageRefer))
        },
        clearHistoryNotifications: { [weak self] notifications in
          self?.removeConversations(notifications.map(\.conversationId))
        }
      )
    )
    .store(in: listenerBag)

    IMKitClient.instance.addClientEventListener(
      NEIMKitClientEvent(
        dataSync: { [weak self] _, state, _ in
          if state == .DATA_SYNC_STATE_COMPLETED {
            self?.scheduleRoamingMessageScan()
          }
        },
        loginStatus: { [weak self] status in
          self?.handleLoginStatus(status)
        }
      )
    )
    .store(in: listenerBag)

    ConversationRepo.shared.addConversationEventListener(
      NEConversationEvent(
        syncFinished: { [weak self] in self?.scheduleRoamingMessageScan() },
        conversationReadTimeUpdated: { [weak self] conversationId, readTime in
          self?.removeReadMessages(conversationId: conversationId, readTime: readTime)
        }
      )
    )
    .store(in: listenerBag)

    LocalConversationRepo.shared.addLocalConversationEventListener(
      NELocalConversationEvent(
        syncFinished: { [weak self] in self?.scheduleRoamingMessageScan() },
        conversationReadTimeUpdated: { [weak self] conversationId, readTime in
          self?.removeReadMessages(conversationId: conversationId, readTime: readTime)
        }
      )
    )
    .store(in: listenerBag)

    let accountId = IMKitClient.instance.account()
    if !accountId.isEmpty {
      loadRecords(accountId: accountId)
      scheduleRoamingMessageScan()
    }
  }

  func isAtCurrentUser(conversationId: String) -> Bool {
    queue.sync {
      records[conversationId]?.isUnread == true
    }
  }

  func clearAtRecord(_ conversationId: String) {
    queue.async { [weak self] in
      guard let self else { return }
      self.invalidatePendingUpdates(conversationId)
      guard self.records.removeValue(forKey: conversationId) != nil else { return }
      self.persistRecords()
      self.notifyChanged()
    }
  }

  private func handleLoginStatus(_ status: V2NIMLoginStatus) {
    switch status {
    case .LOGIN_STATUS_LOGINED:
      loadRecords(accountId: IMKitClient.instance.account())
      scheduleRoamingMessageScan()
    case .LOGIN_STATUS_LOGOUT:
      queue.async { [weak self] in
        guard let self else { return }
        self.invalidateRoamingMessageScan(resetCompletion: true)
        self.currentAccountId = ""
        self.records.removeAll()
        self.conversationGenerations.removeAll()
        self.notifyChanged()
      }
    default:
      break
    }
  }

  private func loadRecords(accountId: String) {
    let normalizedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAccountId.isEmpty else {
      return
    }
    queue.async { [weak self] in
      guard let self else { return }
      let accountChanged = self.currentAccountId != normalizedAccountId
      self.invalidateRoamingMessageScan(resetCompletion: accountChanged)
      self.currentAccountId = normalizedAccountId
      self.conversationGenerations.removeAll()
      let url = self.storageURL(accountId: normalizedAccountId)
      if let data = try? Data(contentsOf: url),
         let cached = try? JSONDecoder().decode([String: Record].self, from: data) {
        self.records = cached.filter { $0.value.isUnread }
      } else {
        self.records.removeAll()
      }
      self.notifyChanged()
    }
  }

  private func invalidateRoamingMessageScan(resetCompletion: Bool) {
    pendingRoamingScanWorkItem?.cancel()
    pendingRoamingScanWorkItem = nil
    roamingScanGeneration += 1
    isRoamingScanRunning = false
    if resetCompletion {
      completedRoamingScanAccountId = nil
    }
  }

  private func filterAtMessages(_ messages: [V2NIMMessage]) {
    filterAtMessages(messages, commitChanges: true, completion: nil)
  }

  private func filterAtMessages(_ messages: [V2NIMMessage],
                                commitChanges: Bool,
                                completion: ((Bool) -> Void)?) {
    let accountId = IMKitClient.instance.account()
    guard !accountId.isEmpty else {
      queue.async { completion?(false) }
      return
    }

    queue.async { [weak self] in
      guard let self, self.currentAccountId == accountId else {
        completion?(false)
        return
      }
      self.filterAtMessagesOnQueue(
        messages,
        accountId: accountId,
        commitChanges: commitChanges,
        completion: completion
      )
    }
  }

  private func filterAtMessagesOnQueue(_ messages: [V2NIMMessage],
                                       accountId: String,
                                       commitChanges: Bool,
                                       completion: ((Bool) -> Void)?) {
    var messagesByConversation = [String: [V2NIMMessage]]()
    for message in messages where isMention(message, accountId: accountId) {
      guard let conversationId = message.conversationId else {
        continue
      }
      messagesByConversation[conversationId, default: []].append(message)
    }
    guard !messagesByConversation.isEmpty else {
      completion?(false)
      return
    }

    let generationByConversation = Dictionary(uniqueKeysWithValues: messagesByConversation.keys.map {
      ($0, conversationGenerations[$0, default: 0])
    })
    let group = DispatchGroup()
    let batchState = AtMessageBatchState()

    for (conversationId, conversationMessages) in messagesByConversation {
      group.enter()
      DispatchQueue.main.async { [weak self] in
        guard let self else {
          group.leave()
          return
        }
        self.getConversationReadTime(conversationId) { [weak self] readTime, _ in
          guard let self else {
            group.leave()
            return
          }
          self.queue.async {
            defer { group.leave() }
            guard self.currentAccountId == accountId,
                  self.conversationGenerations[conversationId, default: 0] == generationByConversation[conversationId] else {
              return
            }
            var record = self.records[conversationId] ?? Record()
            var conversationChanged = false
            for message in conversationMessages {
              guard message.createTime > (readTime ?? 0) else {
                continue
              }
              let messageId = self.messageIdentifier(message)
              guard record.messageTimes[messageId] == nil else {
                continue
              }
              record.messageTimes[messageId] = message.createTime
              record.lastTime = max(record.lastTime, message.createTime)
              conversationChanged = true
              batchState.changed = true
            }
            if conversationChanged {
              self.records[conversationId] = record
            }
          }
        }
      }
    }

    group.notify(queue: queue) { [weak self] in
      guard let self else { return }
      if batchState.changed, commitChanges {
        self.persistRecords()
        self.notifyChanged()
      }
      completion?(batchState.changed)
    }
  }

  private func isMention(_ message: V2NIMMessage, accountId: String) -> Bool {
    guard message.senderId != accountId,
          message.conversationId != nil,
          let extensionText = message.serverExtension,
          let remoteExt = NECommonUtil.getDictionaryFromJSONString(extensionText),
          let payload = remoteExt["yxAitMsg"] as? [String: Any] else {
      return false
    }
    return payload["ait_all"] != nil || payload[accountId] != nil
  }

  private func removeMessageRefers(_ messageRefers: [V2NIMMessageRefer]) {
    guard !messageRefers.isEmpty else {
      return
    }
    queue.async { [weak self] in
      guard let self else { return }
      var changed = false
      for refer in messageRefers {
        guard let conversationId = refer.conversationId else {
          continue
        }
        self.invalidatePendingUpdates(conversationId)
        guard var record = self.records[conversationId] else {
          continue
        }
        let identifiers = [refer.messageClientId, refer.messageServerId].compactMap { value in
          value?.isEmpty == false ? value : nil
        }
        for identifier in identifiers where record.messageTimes.removeValue(forKey: identifier) != nil {
          changed = true
        }
        if record.messageTimes.isEmpty {
          self.records.removeValue(forKey: conversationId)
        } else {
          record.lastTime = record.messageTimes.values.max() ?? 0
          self.records[conversationId] = record
        }
      }
      if changed {
        self.persistRecords()
        self.notifyChanged()
      }
    }
  }

  private func removeConversations(_ conversationIds: [String]) {
    queue.async { [weak self] in
      guard let self else { return }
      var changed = false
      for conversationId in conversationIds {
        self.invalidatePendingUpdates(conversationId)
        changed = self.records.removeValue(forKey: conversationId) != nil || changed
      }
      if changed {
        self.persistRecords()
        self.notifyChanged()
      }
    }
  }

  private func removeReadMessages(conversationId: String, readTime: TimeInterval) {
    queue.async { [weak self] in
      guard let self else {
        return
      }
      self.invalidatePendingUpdates(conversationId)
      guard var record = self.records[conversationId] else {
        return
      }
      record.messageTimes = record.messageTimes.filter { $0.value > readTime }
      if record.messageTimes.isEmpty {
        self.records.removeValue(forKey: conversationId)
      } else {
        record.lastTime = record.messageTimes.values.max() ?? 0
        self.records[conversationId] = record
      }
      self.persistRecords()
      self.notifyChanged()
    }
  }

  private func scheduleRoamingMessageScan() {
    let accountId = IMKitClient.instance.account()
    guard !accountId.isEmpty else {
      return
    }
    queue.async { [weak self] in
      guard let self else { return }
      guard self.currentAccountId == accountId,
            self.completedRoamingScanAccountId != accountId,
            !self.isRoamingScanRunning else {
        return
      }
      self.pendingRoamingScanWorkItem?.cancel()
      self.roamingScanGeneration += 1
      let generation = self.roamingScanGeneration
      let workItem = DispatchWorkItem { [weak self] in
        guard let self,
              self.roamingScanGeneration == generation,
              self.currentAccountId == accountId else {
          return
        }
        self.pendingRoamingScanWorkItem = nil
        self.isRoamingScanRunning = true
        DispatchQueue.main.async { [weak self] in
          self?.startRoamingMessageScan(generation: generation)
        }
      }
      self.pendingRoamingScanWorkItem = workItem
      self.queue.asyncAfter(
        deadline: .now() + self.roamingScanDebounceInterval,
        execute: workItem
      )
    }
  }

  private func startRoamingMessageScan(generation: Int) {
    loadConversationPage(offset: 0, generation: generation, conversations: [])
  }

  private func loadConversationPage(offset: Int64,
                                    generation: Int,
                                    conversations collectedConversations: [RoamingConversation]) {
    guard generation == queue.sync(execute: { roamingScanGeneration }) else {
      return
    }
    if IMKitClient.instance.isV2CloudConversationEnabled {
      ConversationRepo.shared.getConversationList(offset, 20) { [weak self] pageConversations, nextOffset, finished, error in
        let unreadTeamConversations = pageConversations?.compactMap { conversation in
          conversation.type == .CONVERSATION_TYPE_TEAM && conversation.unreadCount > 0
            ? RoamingConversation(
              conversationId: conversation.conversationId,
              messageLimit: min(max(conversation.unreadCount, 1), 100)
            )
            : nil
        } ?? []
        self?.handleConversationPage(
          collectedConversations + unreadTeamConversations,
          nextOffset: nextOffset ?? 0,
          finished: finished ?? true,
          error: error,
          generation: generation
        )
      }
    } else {
      LocalConversationRepo.shared.getConversationList(Int(offset), 20) { [weak self] pageConversations, nextOffset, finished, error in
        let unreadTeamConversations = pageConversations?.compactMap { conversation in
          conversation.type == .CONVERSATION_TYPE_TEAM && conversation.unreadCount > 0
            ? RoamingConversation(
              conversationId: conversation.conversationId,
              messageLimit: min(max(conversation.unreadCount, 1), 100)
            )
            : nil
        } ?? []
        self?.handleConversationPage(
          collectedConversations + unreadTeamConversations,
          nextOffset: Int64(nextOffset ?? 0),
          finished: finished ?? true,
          error: error,
          generation: generation
        )
      }
    }
  }

  private func handleConversationPage(_ conversations: [RoamingConversation],
                                      nextOffset: Int64,
                                      finished: Bool,
                                      error: NSError?,
                                      generation: Int) {
    guard generation == queue.sync(execute: { roamingScanGeneration }) else {
      return
    }
    guard error == nil else {
      finishRoamingMessageScan(generation: generation, completed: false, changed: false)
      return
    }
    guard finished else {
      loadConversationPage(
        offset: nextOffset,
        generation: generation,
        conversations: conversations
      )
      return
    }
    var conversationById = [String: RoamingConversation]()
    for conversation in conversations {
      if conversation.messageLimit > (conversationById[conversation.conversationId]?.messageLimit ?? 0) {
        conversationById[conversation.conversationId] = conversation
      }
    }
    scanConversations(Array(conversationById.values), generation: generation)
  }

  private func scanConversations(_ conversations: [RoamingConversation], generation: Int) {
    queue.async { [weak self] in
      guard let self,
            self.roamingScanGeneration == generation,
            self.isRoamingScanRunning else {
        return
      }
      let state = RoamingScanState(conversations: conversations)
      self.startNextRoamingRequests(state, generation: generation)
    }
  }

  private func startNextRoamingRequests(_ state: RoamingScanState, generation: Int) {
    guard roamingScanGeneration == generation, isRoamingScanRunning else {
      return
    }
    while state.inFlightCount < maxConcurrentRoamingRequests,
          state.nextIndex < state.conversations.count {
      let conversation = state.conversations[state.nextIndex]
      state.nextIndex += 1
      state.inFlightCount += 1
      DispatchQueue.main.async { [weak self, state] in
        guard let self,
              generation == self.queue.sync(execute: { self.roamingScanGeneration }) else {
          return
        }
        let option = V2NIMMessageListOption()
        option.conversationId = conversation.conversationId
        option.limit = conversation.messageLimit
        option.strictMode = false
        ChatRepo.shared.getMessageList(option: option) { [weak self, state] messages, _ in
          guard let self,
                generation == self.queue.sync(execute: { self.roamingScanGeneration }) else {
            return
          }
          self.filterAtMessages(messages ?? [], commitChanges: false) { [weak self, state] changed in
            guard let self,
                  self.roamingScanGeneration == generation,
                  self.isRoamingScanRunning else {
              return
            }
            state.changed = state.changed || changed
            state.inFlightCount -= 1
            self.scheduleNextRoamingRequests(state, generation: generation)
          }
        }
      }
    }
    if state.nextIndex == state.conversations.count, state.inFlightCount == 0 {
      finishRoamingMessageScanOnQueue(
        generation: generation,
        completed: true,
        changed: state.changed
      )
    }
  }

  private func scheduleNextRoamingRequests(_ state: RoamingScanState, generation: Int) {
    guard roamingScanGeneration == generation,
          isRoamingScanRunning,
          !state.isRefillScheduled else {
      return
    }
    state.isRefillScheduled = true
    queue.asyncAfter(deadline: .now() + roamingRequestBatchInterval) { [weak self, state] in
      guard let self,
            self.roamingScanGeneration == generation,
            self.isRoamingScanRunning else {
        return
      }
      state.isRefillScheduled = false
      self.startNextRoamingRequests(state, generation: generation)
    }
  }

  private func finishRoamingMessageScan(generation: Int, completed: Bool, changed: Bool) {
    queue.async { [weak self] in
      self?.finishRoamingMessageScanOnQueue(
        generation: generation,
        completed: completed,
        changed: changed
      )
    }
  }

  private func finishRoamingMessageScanOnQueue(generation: Int,
                                               completed: Bool,
                                               changed: Bool) {
    guard roamingScanGeneration == generation else {
      return
    }
    if changed {
      persistRecords()
      notifyChanged()
    }
    isRoamingScanRunning = false
    if completed {
      completedRoamingScanAccountId = currentAccountId
    }
  }

  private func getConversationReadTime(_ conversationId: String,
                                       completion: @escaping (TimeInterval?, NSError?) -> Void) {
    if IMKitClient.instance.isV2CloudConversationEnabled {
      ConversationRepo.shared.getConversationReadTime(conversationId, completion)
    } else {
      LocalConversationRepo.shared.getConversationReadTime(conversationId, completion)
    }
  }

  private func messageIdentifier(_ message: V2NIMMessage) -> String {
    if let clientId = message.messageClientId, !clientId.isEmpty {
      return clientId
    }
    if let serverId = message.messageServerId, !serverId.isEmpty {
      return serverId
    }
    return "\(message.conversationId ?? ""):\(message.createTime)"
  }

  private func persistRecords() {
    guard !currentAccountId.isEmpty,
          let data = try? JSONEncoder().encode(records) else {
      return
    }
    let url = storageURL(accountId: currentAccountId)
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try? data.write(to: url, options: .atomic)
  }

  private func invalidatePendingUpdates(_ conversationId: String) {
    conversationGenerations[conversationId, default: 0] += 1
  }

  private func storageURL(accountId: String) -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let fileName = accountId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? accountId
    return root
      .appendingPathComponent("NEConversationUIKitSwiftUI", isDirectory: true)
      .appendingPathComponent("\(fileName)_at_messages.json")
  }

  private func notifyChanged() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: NEConversationUIKitSwiftUIConstants.atMessageChangeNotification,
        object: nil
      )
    }
  }
}
