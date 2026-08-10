// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

@MainActor
public final class BotSubSessionListViewModel: ObservableObject {
  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var rows: [BotSubSessionRowState] = []
  @Published public var query = ""
  @Published public var toast: ChatToastState?
  @Published public var renameState: BotSubSessionRenameState?
  @Published public var deleteState: BotSubSessionDeleteState?

  public let context: ChatSessionContext
  public let config: ChatSwiftUIConfig

  private let topicRepo: TopicRepo
  private let chatRepo: ChatRepo
  private let conversationRepo: ConversationRepo
  private let localConversationRepo: LocalConversationRepo
  private let networkOperationGuard: () -> Bool
  private let listenerBag = NEChatKitListenerBag()
  private var isListening = false
  private var allRows: [BotSubSessionRowState] = []
  private var loadGeneration = 0
  private var lastCreateActionTime: TimeInterval = 0
  private let pageLimit = 100
  private let summaryLength = 30

  public init(context: ChatSessionContext,
              config: ChatSwiftUIConfig = ChatSwiftUIConfig(),
              topicRepo: TopicRepo = .shared,
              chatRepo: ChatRepo = .shared,
              conversationRepo: ConversationRepo = .shared,
              localConversationRepo: LocalConversationRepo = .shared,
              networkOperationGuard: @escaping () -> Bool = { true }) {
    self.context = context
    self.config = config
    self.topicRepo = topicRepo
    self.chatRepo = chatRepo
    self.conversationRepo = conversationRepo
    self.localConversationRepo = localConversationRepo
    self.networkOperationGuard = networkOperationGuard
  }

  deinit {
    listenerBag.cancelAll()
  }

  public var title: String {
    context.title ??
      context.sessionName ??
      context.sessionId ??
      context.conversationId
  }

  public var shouldShowSearchEmpty: Bool {
    phase == .empty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public func onAppear() {
    attachListeners()
    load(reset: rows.isEmpty)
  }

  public func onDisappear() {
    topicRepo.swiftUIMarkBotSubSessionsRead(conversationId: context.conversationId) { _ in }
  }

  public func load(reset: Bool = true) {
    if reset {
      phase = rows.isEmpty ? .loading : .refreshing
    } else if rows.isEmpty {
      phase = .loading
    }

    let generation = nextLoadGeneration()
    topicRepo.swiftUIBotSubSessionRows(
      conversationId: context.conversationId,
      keyword: "",
      pageLimit: pageLimit,
      summaryLength: summaryLength,
      localizer: { key, value in NEChatUIKitSwiftUIBundle.localized(key, value: value) }
    ) { [weak self] rows, error in
      Task { @MainActor in
        guard let self, self.loadGeneration == generation else {
          return
        }
        self.applyLoadResult(rows: rows, error: error)
      }
    }
  }

  public func updateQuery(_ value: String) {
    query = value
    applyFilter()
  }

  public func routeForCreate() -> NEChatSwiftUIRoute? {
    let now = Date().timeIntervalSince1970
    guard now - lastCreateActionTime >= 0.5 else {
      return nil
    }
    lastCreateActionTime = now

    guard networkOperationGuard() else {
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_offline_create", value: "You are offline. Cannot create a conversation now"),
        style: .warning
      )
      return nil
    }

    return .botSubSessionChat(chatContext(topic: nil))
  }

  public func routeForTopic(_ row: BotSubSessionRowState) -> NEChatSwiftUIRoute {
    .botSubSessionChat(chatContext(topic: row.topic))
  }

  public func routeForSetting() -> NEChatSwiftUIRoute {
    .userSetting(context)
  }

  public func beginRename(row: BotSubSessionRowState) {
    renameState = BotSubSessionRenameState(row: row, name: row.title)
  }

  public func updateRenameName(_ value: String) {
    renameState?.name = NECommonTextLimit.limitedUTF16(value, limit: 20)
    renameState?.error = nil
  }

  public func cancelRename() {
    renameState = nil
  }

  public func submitRename() {
    guard var state = renameState else {
      return
    }

    let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      state.error = NEChatUIKitSwiftUIBundle.localized("bot_sub_session_input_name", value: "Please enter a name")
      renameState = state
      return
    }

    guard networkOperationGuard() else {
      state.error = NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
      renameState = state
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
      return
    }

    state.name = name
    state.isSaving = true
    renameState = state

    topicRepo.swiftUIUpdateBotSubSessionName(topic: state.row.topic, name: name) { [weak self] _, error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.renameState?.isSaving = false
          self.renameState?.error = NEChatErrorMessageMapper.message(
            for: error,
            fallbackKey: "bot_sub_session_rename_failed",
            fallbackValue: "Failed to rename. Please try again"
          )
          return
        }

        self.renameState = nil
        self.toast = ChatToastState(
          message: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_rename_success", value: "Renamed"),
          style: .success
        )
        self.load(reset: false)
      }
    }
  }

  public func beginDelete(row: BotSubSessionRowState) {
    deleteState = BotSubSessionDeleteState(row: row)
  }

  public func cancelDelete() {
    deleteState = nil
  }

  public func confirmDelete() {
    guard var state = deleteState else {
      return
    }

    state.isDeleting = true
    deleteState = state
    topicRepo.swiftUIRemoveBotSubSession(topic: state.row.topic) { [weak self] error in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let error {
          self.deleteState?.isDeleting = false
          self.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "bot_sub_session_delete_failed",
            fallbackValue: "Failed to delete. Please try again"
          )
          return
        }

        self.allRows.removeAll { $0.id == state.row.id }
        self.applyFilter()
        self.deleteState = nil
        self.toast = ChatToastState(
          message: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_delete_success", value: "Deleted"),
          style: .success
        )
        self.load(reset: false)
      }
    }
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  private func attachListeners() {
    guard !isListening else {
      return
    }
    isListening = true

    topicRepo.addTopicEventListener(
      NETopicEvent(
        topicAdded: { [weak self] topic in
          Task { @MainActor in
            self?.handleTopicAdded(topic)
          }
        },
        topicsRemoved: { [weak self] topics in
          Task { @MainActor in
            self?.handleTopicsRemoved(topics)
          }
        },
        topicUpdated: { [weak self] topic in
          Task { @MainActor in
            self?.handleTopicUpdated(topic)
          }
        }
      )
    ).store(in: listenerBag)

    chatRepo.addChatEventListener(
      NEChatEvent(
        receiveMessages: { [weak self] messages in
          Task { @MainActor in
            self?.handleReceivedMessages(messages)
          }
        },
        messageRevokeNotifications: { [weak self] notifications in
          Task { @MainActor in
            self?.handleRevokeNotifications(notifications)
          }
        }
      )
    ).store(in: listenerBag)

    conversationRepo.addConversationEventListener(
      NEConversationEvent(
        conversationReadTimeUpdated: { [weak self] conversationId, _ in
          Task { @MainActor in
            self?.handleConversationReadTimeUpdated(conversationId)
          }
        }
      )
    ).store(in: listenerBag)

    localConversationRepo.addLocalConversationEventListener(
      NELocalConversationEvent(
        conversationReadTimeUpdated: { [weak self] conversationId, _ in
          Task { @MainActor in
            self?.handleConversationReadTimeUpdated(conversationId)
          }
        }
      )
    ).store(in: listenerBag)
  }

  private func handleTopicAdded(_ topic: V2NIMTopic) {
    guard topic.conversationId == context.conversationId else {
      return
    }
    load(reset: false)
  }

  private func handleTopicsRemoved(_ topics: [V2NIMTopicRefer]) {
    let removedTopicIds = Set(
      topics
        .filter { $0.conversationId == context.conversationId }
        .map(\.topicId)
    )
    guard !removedTopicIds.isEmpty else {
      return
    }

    rows.removeAll { row in
      removedTopicIds.contains(row.topic.topicId)
    }
    allRows.removeAll { row in
      removedTopicIds.contains(row.topic.topicId)
    }
    phase = rows.isEmpty ? .empty : .loaded
  }

  private func handleTopicUpdated(_ topic: V2NIMTopic) {
    guard topic.conversationId == context.conversationId else {
      return
    }
    load(reset: false)
  }

  private func handleReceivedMessages(_ messages: [V2NIMMessage]) {
    let topicIds = topicIdsForCurrentRows(from: messages)
    guard !topicIds.isEmpty else {
      return
    }
    refreshRows(topicIds: topicIds, refreshUnread: true)
  }

  private func handleRevokeNotifications(_ notifications: [V2NIMMessageRevokeNotification]) {
    let refers = notifications.compactMap { notification -> V2NIMMessageRefer? in
      guard let refer = notification.messageRefer,
            refer.conversationId == context.conversationId else {
        return nil
      }
      return refer
    }
    guard !refers.isEmpty else {
      return
    }

    chatRepo.getMessageListByRefers(refers) { [weak self] messages, _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        let topicIds = self.topicIdsForCurrentRows(from: messages ?? [])
        self.refreshRows(topicIds: topicIds, refreshUnread: false)
      }
    }
  }

  private func handleConversationReadTimeUpdated(_ conversationId: String) {
    guard conversationId == context.conversationId else {
      return
    }
    refreshUnreadState()
  }

  private func topicIdsForCurrentRows(from messages: [V2NIMMessage]) -> Set<UInt64> {
    let currentIds = Set(allRows.map { $0.topic.topicId })
    return Set(messages.compactMap { message -> UInt64? in
      guard message.conversationId == context.conversationId,
            let topicId = message.topicRefer?.topicId,
            currentIds.contains(topicId) else {
        return nil
      }
      return topicId
    })
  }

  private func refreshRows(topicIds: Set<UInt64>, refreshUnread: Bool) {
    guard !topicIds.isEmpty else {
      return
    }
    let shouldShowRefreshing = rows.isEmpty
    if refreshUnread || shouldShowRefreshing {
      load(reset: shouldShowRefreshing)
      return
    }
    load(reset: false)
  }

  private func refreshUnreadState() {
    topicRepo.swiftUILoadBotSubSessionReadTime(conversationId: context.conversationId) { [weak self] readTime, _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.updateUnreadState(readTime: readTime)
      }
    }
  }

  private func updateUnreadState(readTime: TimeInterval) {
    let updated = allRows.map { row -> BotSubSessionRowState in
      let summary = row.botSubSessionSummary
      var next = row
      next.hasUnread = topicRepo.swiftUIBotSubSessionHasUnread(summary: summary, conversationReadTime: readTime)
      return next
    }
    allRows = updated.sorted { left, right in
      topicRepo.swiftUIBotSubSessionSortTime(
        topic: left.topic,
        summary: left.botSubSessionSummary
      ) > topicRepo.swiftUIBotSubSessionSortTime(
        topic: right.topic,
        summary: right.botSubSessionSummary
      )
    }
    applyFilter()
  }

  private func applyLoadResult(rows: [NEBotSubSessionRow], error: NSError?) {
    if let error {
      phase = .failed(
        NEChatErrorMessageMapper.errorState(
          for: error,
          fallbackKey: "bot_sub_session_load_failed",
          fallbackValue: "Load failed"
        )
      )
      toast = NEChatErrorMessageMapper.toast(
        for: error,
        fallbackKey: "bot_sub_session_load_failed",
        fallbackValue: "Load failed"
      )
      return
    }

    allRows = rows.map(Self.rowState)
    applyFilter()
  }

  private func chatContext(topic: V2NIMTopic?) -> ChatSessionContext {
    ChatSessionContext(
      kind: .botSubSession,
      conversationId: context.conversationId,
      title: topicTitle(topic),
      sessionId: context.sessionId,
      sessionName: context.sessionName,
      topic: topic
    )
  }

  private func topicTitle(_ topic: V2NIMTopic?) -> String {
    guard let topic else {
      return NEChatUIKitSwiftUIBundle.localized("bot_sub_session_new_conversation", value: "New conversation")
    }
    return topicRepo.swiftUITopicDisplayName(
      topic,
      fallback: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_new_conversation", value: "New conversation")
    )
  }

  private func nextLoadGeneration() -> Int {
    loadGeneration += 1
    return loadGeneration
  }

  private func applyFilter() {
    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if keyword.isEmpty {
      rows = allRows
    } else {
      rows = allRows.filter { row in
        row.title.lowercased().contains(keyword)
      }
    }
    phase = rows.isEmpty ? .empty : .loaded
  }

  private static func rowState(from row: NEBotSubSessionRow) -> BotSubSessionRowState {
    BotSubSessionRowState(
      id: row.id,
      topic: row.topic,
      title: row.title,
      summary: row.summary?.text ?? "",
      updateTime: row.summary?.updateTime ?? TopicRepo.shared.swiftUINormalizedTimestamp(TimeInterval(row.topic.updateTime)),
      hasSummary: row.summary != nil,
      latestMessageFromSelf: row.summary?.latestMessageFromSelf ?? false,
      hasUnread: row.hasUnread
    )
  }
}
