// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import Combine
import NEChatKit
import NIMSDK

public enum HistorySearchScope: String, CaseIterable, Identifiable, Equatable, Hashable {
  case keyword
  case image
  case video
  case file
  case date
  case member

  public var id: String {
    rawValue
  }

  public var title: String {
    switch self {
    case .keyword:
      return NEChatUIKitSwiftUIBundle.localized("search_message", value: "Messages")
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("msg_image", value: "Image")
    case .video:
      return NEChatUIKitSwiftUIBundle.localized("msg_video", value: "Video")
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("msg_file", value: "File")
    case .date:
      return NEChatUIKitSwiftUIBundle.localized("search_message_by_date", value: "Date")
    case .member:
      return NEChatUIKitSwiftUIBundle.localized("search_message_by_member", value: "Member")
    }
  }
}

@MainActor
public final class HistorySearchViewModel: ObservableObject {
  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var rows: [MessageRowState] = []
  @Published public var query = ""
  @Published public var scope: HistorySearchScope = .keyword
  @Published public var selectedDate = Date()
  @Published public var memberAccountId = ""
  @Published public var toast: ChatToastState?
  @Published public var filePreview: ChatFilePreviewState?
  @Published public var mediaPreview: ChatMediaPreviewState?
  @Published public var fileActionMenu: HistoryFileActionMenuState?
  @Published public private(set) var mediaDownloadProgressByRowId: [String: Double] = [:]

  public private(set) var hasMore = false
  public var activeTitle: String {
    scope == .member
      ? NEChatUIKitSwiftUIBundle.localized("search_message_by_member", value: "Search by Member")
      : NEChatUIKitSwiftUIBundle.localized("historical_record", value: "Search chat history")
  }

  public var conversationID: String {
    conversationId
  }

  public var teamId: String? {
    let conversationType = V2NIMConversationIdUtil.conversationType(conversationId)
    guard conversationType == .CONVERSATION_TYPE_TEAM ||
      conversationType == .CONVERSATION_TYPE_SUPER_TEAM else {
      return nil
    }
    let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId) ?? ""
    return targetId.isEmpty ? conversationId : targetId
  }

  public var teamType: V2NIMTeamType {
    let conversationType = V2NIMConversationIdUtil.conversationType(conversationId)
    return conversationType == .CONVERSATION_TYPE_SUPER_TEAM ? .TEAM_TYPE_SUPER : .TEAM_TYPE_NORMAL
  }

  public var quickScopes: [HistorySearchScope] {
    var scopes = [HistorySearchScope]()
    let conversationType = V2NIMConversationIdUtil.conversationType(conversationId)
    if conversationType == .CONVERSATION_TYPE_TEAM ||
      conversationType == .CONVERSATION_TYPE_SUPER_TEAM {
      scopes.append(.member)
    }
    scopes.append(contentsOf: [.image, .video, .date, .file])
    return scopes
  }

  private let conversationId: String
  private let chatRepo: ChatRepo
  private let resourceDownloader: ChatResourceDownloading
  private let operationPerformer: ChatMessageOperationPerforming
  private let fileInteractionHandler: ChatFileInteractionHandling?
  private let mediaPreviewHandler: ChatMediaPreviewHandling?
  private let currentAccountProvider: () -> String?
  private let networkOperationGuard: () -> Bool
  private let sessionContextProvider: () -> ChatSessionContext
  private let conversationNameProvider: () -> String?
  private var pageToken = ""
  private var listenerToken: NEChatKitListenerToken?
  private var messageContextById: [String: V2NIMMessage] = [:]
  private var pendingNewMessages = [V2NIMMessage]()
  private var pendingNewMessageIds = Set<String>()
  private var fileDownloadGenerationByRowId: [String: Int] = [:]
  private var replyResolutionRequestIds = [String: UUID]()
  private var searchRequestGeneration = 0
  private var isSearchInFlight = false

  public init(conversationId: String,
              chatRepo: ChatRepo = .shared,
              resourceDownloader: ChatResourceDownloading = NEChatKitResourceDownloader(),
              operationPerformer: ChatMessageOperationPerforming = NEChatKitMessageOperationPerformer(),
              fileInteractionHandler: ChatFileInteractionHandling? = nil,
              mediaPreviewHandler: ChatMediaPreviewHandling? = nil,
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() },
              networkOperationGuard: @escaping () -> Bool = { true },
              sessionContextProvider: (() -> ChatSessionContext)? = nil,
              conversationNameProvider: (() -> String?)? = nil) {
    self.conversationId = conversationId
    self.chatRepo = chatRepo
    self.resourceDownloader = resourceDownloader
    self.operationPerformer = operationPerformer
    self.fileInteractionHandler = fileInteractionHandler
    self.mediaPreviewHandler = mediaPreviewHandler
    self.currentAccountProvider = currentAccountProvider
    self.networkOperationGuard = networkOperationGuard
    let resolvedSessionContextProvider = sessionContextProvider ?? {
      ChatSessionContext(
        kind: HistorySearchViewModel.sessionKind(for: conversationId),
        conversationId: conversationId,
        sessionId: V2NIMConversationIdUtil.conversationTargetId(conversationId)
      )
    }
    self.sessionContextProvider = resolvedSessionContextProvider
    self.conversationNameProvider = conversationNameProvider ?? {
      let context = resolvedSessionContextProvider()
      return context.sessionName ?? context.title
    }
    bindChatEvents()
  }

  deinit {
    listenerToken?.cancel()
  }

  public func search(reset: Bool = true) {
    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard scope != .keyword || !keyword.isEmpty else {
      rows = []
      phase = .idle
      return
    }

    guard scope != .member || !memberAccountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      rows = []
      phase = .idle
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_history_member_required", value: "Enter a member account to search"),
        style: .info
      )
      return
    }

    guard !isSearchInFlight else {
      return
    }

    let isSearchingCloud = IMKitConfigCenter.shared.enableCloudMessageSearch
    guard !isSearchingCloud || networkOperationGuard() else {
      phase = rows.isEmpty ? .empty : .loaded
      toast = Self.networkToast()
      return
    }
    if reset {
      pageToken = ""
    }
    phase = rows.isEmpty ? .loading : .loadingMore
    isSearchInFlight = true
    searchRequestGeneration += 1
    let requestGeneration = searchRequestGeneration

    let params = V2NIMMessageSearchExParams()
    params.conversationId = conversationId
    applyScope(to: params, keyword: keyword)
    params.pageToken = pageToken
    params.limit = NEChatUIKitSwiftUIConstants.defaultHistoryPageSize

    let completion: (V2NIMMessageSearchResult?, NSError?) -> Void = { [weak self] result, error in
      Task { @MainActor in
        guard let self,
              self.searchRequestGeneration == requestGeneration else {
          return
        }
        self.isSearchInFlight = false
        self.applySearchResult(result, error: error, reset: reset)
      }
    }

    if isSearchingCloud {
      chatRepo.searchCloudMessagesEx(params: params, completion)
    } else {
      chatRepo.searchLocalMessages(params: params, completion)
    }
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  public func presentToast(_ toast: ChatToastState) {
    self.toast = toast
  }

  public func updateScope(_ scope: HistorySearchScope) {
    guard self.scope != scope else {
      return
    }
    self.scope = scope
    searchRequestGeneration += 1
    isSearchInFlight = false
    rows = []
    hasMore = false
    pageToken = ""
    messageContextById.removeAll()
    fileDownloadGenerationByRowId.removeAll()
    mediaDownloadProgressByRowId.removeAll()
    replyResolutionRequestIds.removeAll()
    phase = .idle
    if scope == .image || scope == .video || scope == .file {
      search(reset: true)
    }
  }

  public func searchDate(_ date: Date) {
    selectedDate = date
    scope = .date
    search(reset: true)
  }

  public func searchMember(accountId: String) {
    memberAccountId = accountId
    scope = .member
    search(reset: true)
  }

  public func searchKeyword() {
    scope = .keyword
    search(reset: true)
  }

  public func resetToKeyword() {
    scope = .keyword
    rows = []
    hasMore = false
    pageToken = ""
    messageContextById.removeAll()
    fileDownloadGenerationByRowId.removeAll()
    mediaDownloadProgressByRowId.removeAll()
    replyResolutionRequestIds.removeAll()
    phase = .idle
  }

  public func sibling() -> HistorySearchViewModel {
    HistorySearchViewModel(
      conversationId: conversationId,
      chatRepo: chatRepo,
      resourceDownloader: resourceDownloader,
      operationPerformer: operationPerformer,
      fileInteractionHandler: fileInteractionHandler,
      mediaPreviewHandler: mediaPreviewHandler,
      currentAccountProvider: currentAccountProvider,
      networkOperationGuard: networkOperationGuard,
      sessionContextProvider: sessionContextProvider,
      conversationNameProvider: conversationNameProvider
    )
  }

  public func selection(for row: MessageRowState) -> PinMessageSelection {
    PinMessageSelection(
      row: row,
      anchorMessage: message(for: row),
      pendingMessages: pendingNewMessages
    )
  }

  public func sourceMessage(for row: MessageRowState) -> V2NIMMessage? {
    message(for: row)
  }

  public func openFile(row: MessageRowState) {
    guard case let .file(file) = row.content else {
      return
    }
    if file.existingLocalPath != nil {
      openFilePreview(row: row, file: file)
      return
    }
    guard let url = file.url,
          let filePath = fileDownloadPath(for: row, file: file, url: url) else {
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_file_unavailable", value: "File unavailable"),
        style: .warning
      )
      return
    }
    let generation = (fileDownloadGenerationByRowId[row.id] ?? 0) + 1
    fileDownloadGenerationByRowId[row.id] = generation
    updateMediaDownloadProgress(rowId: row.id, progress: 0)
    let downloadStartedAt = Date()
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        guard self?.fileDownloadGenerationByRowId[row.id] == generation else {
          return
        }
        self?.updateMediaDownloadProgress(rowId: row.id, progress: Double(progress) / 100.0)
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        let remainingIndicatorTime = 0.2 - Date().timeIntervalSince(downloadStartedAt)
        if remainingIndicatorTime > 0 {
          try? await Task.sleep(
            nanoseconds: UInt64(remainingIndicatorTime * 1_000_000_000)
          )
        }
        guard let self,
              self.fileDownloadGenerationByRowId[row.id] == generation else {
          return
        }
        self.fileDownloadGenerationByRowId[row.id] = nil
        self.clearMediaDownloadProgress(rowId: row.id)
        if let error {
          self.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_file_unavailable",
            fallbackValue: "File unavailable"
          )
          return
        }
        var downloaded = file
        downloaded.localPath = localPath ?? filePath
        downloaded.fileExtension = self.downloadedFileExtension(
          file: downloaded,
          localPath: downloaded.localPath ?? filePath,
          url: url
        )
        self.replaceFileContent(rowId: row.id, file: downloaded)
      }
    }
  }

  public func openMedia(row: MessageRowState) {
    switch row.content {
    case let .image(media):
      openMediaPreview(row: row, media: media, kind: .image)
    case let .video(media):
      if media.playableLocalPath == nil,
         let url = media.url,
         let filePath = mediaDownloadPath(for: row, media: media, kind: .video, url: url) {
        downloadMedia(row: row, media: media, url: url, filePath: filePath)
        return
      }
      openMediaPreview(row: row, media: media, kind: .video)
    default:
      break
    }
  }

  public func consumeFilePreview() {
    filePreview = nil
  }

  public func consumeMediaPreview() {
    mediaPreview = nil
  }

  public func showFileActionMenu(row: MessageRowState) {
    fileActionMenu = HistoryFileActionMenuState(row: row)
  }

  public func dismissFileActionMenu() {
    fileActionMenu = nil
  }

  public func collect(row: MessageRowState) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    performCollection(row: row)
  }

  private func performCollection(row: MessageRowState) {
    let completion: (Result<ChatOperationResult, Error>) -> Void = { [weak self] result in
      Task { @MainActor in
        guard let self else {
          return
        }
        switch result {
        case .success(let operationResult):
          self.toast = ChatToastState(
            message: operationResult.message ?? NEChatUIKitSwiftUIBundle.localized("chat_collected", value: "Collected"),
            style: .success
          )
        case .failure(let error):
          self.toast = Self.collectFailureToast(for: error)
        }
      }
    }
    if let message = message(for: row) {
      operationPerformer.collectMessage(
        message: message,
        conversationName: conversationName,
        displayRow: row,
        completion: completion
      )
      return
    }
    operationPerformer.collectMessage(
      id: row.id,
      conversationName: conversationName,
      displayRow: row,
      completion: completion
    )
  }

  public func locateFirstMessage(after date: Date,
                                 completion: @escaping (MessageRowState?) -> Void) {
    locateFirstMessageSelection(after: date) { selection in
      completion(selection?.row)
    }
  }

  public func locateFirstMessageSelection(after date: Date,
                                          completion: @escaping (PinMessageSelection?) -> Void) {
    selectedDate = date
    let queryBeginTime = max(0, date.timeIntervalSince1970)
    let queryKey = "date-\(Int64((queryBeginTime * 1000).rounded()))"
    guard !IMKitConfigCenter.shared.enableCloudMessageSearch || networkOperationGuard() else {
      NEChatSwiftUILogger.log(
        "messageJump dateQuery blocked query=\(queryKey) conversationId=\(conversationId) reason=network"
      )
      toast = Self.networkToast()
      completion(nil)
      return
    }

    let option = V2NIMMessageListOption()
    option.conversationId = conversationId
    option.limit = 1
    option.direction = .QUERY_DIRECTION_ASC
    option.beginTime = queryBeginTime
    NEChatSwiftUILogger.log(
      "messageJump dateQuery start query=\(queryKey) conversationId=\(conversationId) beginTime=\(queryBeginTime) direction=asc limit=1 cloudSearch=\(IMKitConfigCenter.shared.enableCloudMessageSearch)"
    )

    chatRepo.getMessageList(option: option) { [weak self] messages, error in
      Task { @MainActor in
        guard let self else {
          NEChatSwiftUILogger.log(
            "messageJump dateQuery abandoned query=\(queryKey) reason=viewModelReleased"
          )
          completion(nil)
          return
        }
        if let error {
          NEChatSwiftUILogger.log(
            "messageJump dateQuery failure query=\(queryKey) conversationId=\(self.conversationId) returned=\(messages?.count ?? 0) error=\(error.localizedDescription)"
          )
          self.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_history_search_failed",
            fallbackValue: "History search failed"
          )
          completion(nil)
          return
        }
        guard let message = messages?.first else {
          NEChatSwiftUILogger.log(
            "messageJump dateQuery empty query=\(queryKey) conversationId=\(self.conversationId) returned=\(messages?.count ?? 0)"
          )
          completion(nil)
          return
        }
        let row = ChatMessageMapper.row(message: message, currentAccountId: self.currentAccountProvider())
        NEChatSwiftUILogger.log(
          "messageJump dateQuery anchor query=\(queryKey) rowId=\(row.id) serverId=\(row.serverId ?? "nil") clientId=\(message.messageClientId ?? "nil") messageTime=\(message.createTime) requestedBeginTime=\(queryBeginTime) deltaSeconds=\(message.createTime - queryBeginTime) returned=\(messages?.count ?? 0)"
        )
        self.cacheMessageContext([message])
        TeamMemberDisplayEnricher.enrich(rows: [row], conversationId: self.conversationId) { enrichedRows in
          Task { @MainActor in
            let enrichedRow = enrichedRows.first ?? row
            NEChatSwiftUILogger.log(
              "messageJump dateQuery ready query=\(queryKey) rowId=\(enrichedRow.id) serverId=\(enrichedRow.serverId ?? "nil") senderEnriched=\(enrichedRow.senderName?.isEmpty == false)"
            )
            completion(PinMessageSelection(
              row: enrichedRow,
              anchorMessage: message,
              pendingMessages: self.pendingNewMessages
            ))
          }
        }
      }
    }
  }

  public func fallbackSelectionForDateRoute() -> PinMessageSelection {
    let row = MessageRowState(
      id: "history-date-fallback-\(conversationId)",
      conversationId: conversationId,
      direction: .system,
      content: .tip(""),
      deliveryState: .none,
      timestamp: selectedDate.timeIntervalSince1970
    )
    return PinMessageSelection(
      row: row,
      anchorMessage: nil,
      pendingMessages: pendingNewMessages,
      opensConversationOnly: true
    )
  }

  private func applyScope(to params: V2NIMMessageSearchExParams,
                          keyword: String) {
    switch scope {
    case .keyword:
      params.keywordList = [keyword]
    case .image:
      params.messageTypes = [NSNumber(value: V2NIMMessageType.MESSAGE_TYPE_IMAGE.rawValue)]
    case .video:
      params.messageTypes = [NSNumber(value: V2NIMMessageType.MESSAGE_TYPE_VIDEO.rawValue)]
    case .file:
      params.messageTypes = [NSNumber(value: V2NIMMessageType.MESSAGE_TYPE_FILE.rawValue)]
    case .date:
      let calendar = Calendar.current
      let start = calendar.startOfDay(for: selectedDate)
      let end = calendar.date(byAdding: .day, value: 1, to: start) ?? selectedDate
      let startMs = Int64(start.timeIntervalSince1970 * 1000)
      let endMs = Int64(end.timeIntervalSince1970 * 1000)
      params.searchStartTime = endMs
      params.searchTimePeriod = endMs - startMs
    case .member:
      params.senderAccountIds = [memberAccountId.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
  }

  private func applySearchResult(_ result: V2NIMMessageSearchResult?,
                                 error: NSError?,
                                 reset: Bool) {
    if let error {
      // UIKit keeps the current result list visible and only reports the
      // request failure. A transient network error must not replace results
      // with a full-screen error view.
      phase = rows.isEmpty ? .empty : .loaded
      toast = NEChatErrorMessageMapper.toast(
        for: error,
        fallbackKey: "chat_history_search_failed",
        fallbackValue: "History search failed"
      )
      return
    }

    pageToken = result?.nextPageToken ?? ""
    hasMore = result?.hasMore ?? false
    let sortedMessages = sortedSearchMessages(searchDisplayMessages(result?.items.flatMap(\.messages) ?? []))
    if reset {
      fileDownloadGenerationByRowId.removeAll()
      mediaDownloadProgressByRowId.removeAll()
      messageContextById.removeAll()
      replyResolutionRequestIds.removeAll()
    }
    cacheMessageContext(sortedMessages)
    let newRows = sortedMessages
      .map { message in
        let row = ChatMessageMapper.row(message: message, currentAccountId: currentAccountProvider())
        guard scope == .keyword else {
          return row
        }
        return ChatMessageMapper.applyingKeywordHighlight(to: row, keyword: query)
      }
    TeamMemberDisplayEnricher.enrich(rows: newRows, conversationId: conversationId) { [weak self] enrichedRows in
      Task { @MainActor in
        guard let self else {
          return
        }
        if reset {
          self.rows = enrichedRows
        } else if self.shouldReorderRowsAfterAppending {
          self.rows = (self.rows + enrichedRows).sorted { left, right in
            (left.timestamp ?? 0) < (right.timestamp ?? 0)
          }
        } else {
          self.rows.append(contentsOf: enrichedRows)
        }
        self.phase = self.rows.isEmpty ? .empty : .loaded
        self.resolveRepliesIfNeeded(for: enrichedRows)
      }
    }
  }

  public func loadMoreIfNeeded(currentRow: MessageRowState?) {
    guard hasMore, !isSearchInFlight, phase != .loadingMore else {
      return
    }
    guard currentRow?.id == loadMoreTriggerRowId else {
      return
    }
    search(reset: false)
  }

  public func loadMore() {
    guard hasMore, !isSearchInFlight, phase != .loadingMore else {
      return
    }
    search(reset: false)
  }

  private func bindChatEvents() {
    listenerToken = chatRepo.addChatEventListener(
      NEChatEvent(
        receiveMessages: { [weak self] messages in
          Task { @MainActor in
            self?.appendPendingNewMessages(messages)
          }
        },
        messageRevokeNotifications: { [weak self] notifications in
          Task { @MainActor in
            self?.handleRevokeNotifications(notifications)
          }
        },
        messageDeletedNotifications: { [weak self] notifications in
          Task { @MainActor in
            self?.handleDeletedNotifications(notifications)
          }
        }
      )
    )
  }

  private func appendPendingNewMessages(_ messages: [V2NIMMessage]) {
    for message in messages where message.conversationId == conversationId {
      let id = ChatMessageMapper.stableMessageId(for: message)
      guard !id.isEmpty,
            pendingNewMessageIds.insert(id).inserted else {
        continue
      }
      pendingNewMessages.append(message)
    }
  }

  private func handleRevokeNotifications(_ notifications: [V2NIMMessageRevokeNotification]) {
    removeRows(messageRefers: notifications.compactMap(\.messageRefer))
  }

  private func handleDeletedNotifications(_ notifications: [V2NIMMessageDeletedNotification]) {
    removeRows(messageRefers: notifications.map(\.messageRefer))
  }

  private func removeRows(messageRefers: [V2NIMMessageRefer?]) {
    let ids = Set(messageRefers.flatMap(messageIds(from:)))
    guard !ids.isEmpty else {
      return
    }

    removePendingNewMessages(matching: ids)
    let previousCount = rows.count
    rows.removeAll { row in
      ids.contains(row.id) || row.serverId.map(ids.contains) == true
    }
    for id in ids {
      messageContextById.removeValue(forKey: id)
      fileDownloadGenerationByRowId.removeValue(forKey: id)
      mediaDownloadProgressByRowId.removeValue(forKey: id)
    }
    guard rows.count != previousCount else {
      return
    }
    phase = rows.isEmpty ? .empty : .loaded
  }

  private func removePendingNewMessages(matching ids: Set<String>) {
    pendingNewMessages.removeAll { message in
      let aliases = Set([
        ChatMessageMapper.stableMessageId(for: message),
        message.messageClientId,
        message.messageServerId,
      ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
      return !aliases.isDisjoint(with: ids)
    }
    pendingNewMessageIds = Set(pendingNewMessages.compactMap { message in
      let id = ChatMessageMapper.stableMessageId(for: message)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return id.isEmpty ? nil : id
    })
  }

  private func messageIds(from messageRefer: V2NIMMessageRefer?) -> [String] {
    guard messageRefer?.conversationId == conversationId else {
      return []
    }

    return [messageRefer?.messageClientId, messageRefer?.messageServerId]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func cacheMessageContext(_ messages: [V2NIMMessage]) {
    for message in messages {
      let rowId = ChatMessageMapper.stableMessageId(for: message)
      messageContextById[rowId] = message
      if let serverId = message.messageServerId, !serverId.isEmpty {
        messageContextById[serverId] = message
      }
      if let clientId = message.messageClientId, !clientId.isEmpty {
        messageContextById[clientId] = message
      }
    }
  }

  private func message(for row: MessageRowState) -> V2NIMMessage? {
    if let message = messageContextById[row.id] {
      return message
    }
    if let serverId = row.serverId,
       let message = messageContextById[serverId] {
      return message
    }
    return nil
  }

  private func resolveRepliesIfNeeded(for rows: [MessageRowState]) {
    for row in rows {
      guard let reply = row.reply, !reply.isResolved else {
        continue
      }

      if let localRow = findResolvedReplyRow(for: reply) {
        updateReplyFromRow(for: row.id, replyRow: localRow)
        continue
      }

      let reference = NEChatReplyReference(
        messageClientId: reply.messageClientId,
        messageServerId: reply.messageServerId,
        senderId: reply.senderId,
        receiverId: reply.receiverId,
        conversationId: reply.conversationId,
        conversationType: V2NIMConversationType(rawValue: reply.conversationType) ??
          V2NIMConversationIdUtil.conversationType(conversationId),
        createTime: reply.createTime
      )
      let requestId = UUID()
      replyResolutionRequestIds[row.id] = requestId
      chatRepo.findReplyMessage(reference: reference) { [weak self] replyMessage, _ in
        Task { @MainActor in
          guard let self,
                self.replyResolutionRequestIds[row.id] == requestId,
                self.rows.contains(where: { $0.id == row.id || $0.serverId == row.id }) else {
            return
          }
          self.replyResolutionRequestIds[row.id] = nil
          self.updateReply(for: row.id, replyMessage: replyMessage)
        }
      }
    }
  }

  private func findResolvedReplyRow(for reply: MessageReplyState) -> MessageRowState? {
    rows.first { row in
      if let messageClientId = reply.messageClientId, row.id == messageClientId {
        return true
      }
      if let messageServerId = reply.messageServerId, row.serverId == messageServerId {
        return true
      }
      return false
    }
  }

  private func updateReplyFromRow(for id: String, replyRow: MessageRowState) {
    guard let index = rows.firstIndex(where: { $0.id == id || $0.serverId == id }),
          var reply = rows[index].reply else {
      return
    }

    reply.senderId = replyRow.senderId ?? reply.senderId
    reply.senderName = replyRow.senderName ?? reply.senderName
    reply.conversationId = replyRow.conversationId ?? reply.conversationId
    reply.conversationType = V2NIMConversationIdUtil.conversationType(replyRow.conversationId ?? conversationId).rawValue
    reply.preview = ChatMessageMapper.previewText(for: replyRow.content)
    reply.resolvedContent = BoxedMessageContentState(replyRow.content)
    reply.isResolved = true
    rows[index].reply = reply
    if case let .reply(_, content) = rows[index].content {
      rows[index].content = .reply(preview: reply.displayPreview, content: content)
    }
  }

  private func updateReply(for id: String, replyMessage: V2NIMMessage?) {
    guard let index = rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }
    rows[index] = ChatMessageMapper.resolvingReply(
      rows[index],
      with: replyMessage,
      currentAccountId: currentAccountProvider()
    )
    if let replyMessage {
      cacheMessageContext([replyMessage])
    }
  }

  private func sortedSearchMessages(_ messages: [V2NIMMessage]) -> [V2NIMMessage] {
    switch scope {
    case .image, .video:
      return messages.sorted { $0.createTime < $1.createTime }
    default:
      return messages.sorted { $0.createTime > $1.createTime }
    }
  }

  private func searchDisplayMessages(_ messages: [V2NIMMessage]) -> [V2NIMMessage] {
    return messages.filter { message in
      guard !ChatMessageMapper.isRevokeMessage(message) else {
        return false
      }
      guard scope == .member else {
        return true
      }
      return message.messageType != .MESSAGE_TYPE_NOTIFICATION &&
        message.messageType != .MESSAGE_TYPE_TIP
    }
  }

  private var shouldReorderRowsAfterAppending: Bool {
    scope == .image || scope == .video
  }

  private var loadMoreTriggerRowId: String? {
    shouldReorderRowsAfterAppending ? rows.first?.id : rows.last?.id
  }

  private func replaceFileContent(rowId: String, file: MessageFileState) {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.serverId == rowId }) else {
      return
    }
    rows[index].content = .file(file)
  }

  private func replaceMediaContent(rowId: String,
                                   media: MessageMediaState,
                                   kind: ChatMediaPreviewKind) {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.serverId == rowId }) else {
      return
    }
    rows[index].content = kind == .video ? .video(media) : .image(media)
  }

  private func openMediaPreview(row: MessageRowState,
                                media: MessageMediaState,
                                kind: ChatMediaPreviewKind) {
    let items = rows.compactMap { item -> ChatMediaItem? in
      switch (kind, item.content) {
      case let (.image, .image(itemMedia)):
        return ChatMediaItem(
          id: item.id,
          media: itemMedia,
          kind: .image,
          title: ChatMessageMapper.previewText(for: item.content)
        )
      case let (.video, .video(itemMedia)):
        return ChatMediaItem(
          id: item.id,
          media: itemMedia,
          kind: .video,
          title: ChatMessageMapper.previewText(for: item.content)
        )
      default:
        return nil
      }
    }
    let preview = ChatMediaPreviewState(
      id: row.id,
      kind: kind,
      media: media,
      title: ChatMessageMapper.previewText(for: row.content),
      mediaItems: items
    )
    guard let mediaPreviewHandler else {
      mediaPreview = preview
      return
    }

    let request = ChatMediaPreviewRequest(
      preview: preview,
      message: row,
      context: sessionContextProvider()
    )
    mediaPreviewHandler.handleMediaPreview(request) { [weak self] result in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.handleMediaPreviewResult(result, fallbackPreview: preview)
      }
    }
  }

  private func handleMediaPreviewResult(_ result: Result<ChatNativeBoundaryResult, Error>,
                                        fallbackPreview: ChatMediaPreviewState) {
    switch result {
    case .success(let boundaryResult):
      switch boundaryResult {
      case let .route(.mediaPreview(preview)):
        mediaPreview = preview
      case .route:
        mediaPreview = fallbackPreview
      case let .toast(toast):
        self.toast = toast
      case .send, .sendMultiple, .none:
        break
      }
    case .failure(let error):
      mediaPreview = fallbackPreview
      toast = NEChatErrorMessageMapper.toast(
        for: error,
        fallbackKey: "chat_boundary_failed",
        fallbackValue: "Operation could not be completed"
      )
    }
  }

  private func downloadMedia(row: MessageRowState,
                             media: MessageMediaState,
                             url: URL,
                             filePath: String) {
    guard mediaDownloadProgressByRowId[row.id] == nil else {
      return
    }
    let generation = (fileDownloadGenerationByRowId[row.id] ?? 0) + 1
    fileDownloadGenerationByRowId[row.id] = generation
    updateMediaDownloadProgress(rowId: row.id, progress: 0)
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        guard self?.fileDownloadGenerationByRowId[row.id] == generation else {
          return
        }
        self?.updateMediaDownloadProgress(rowId: row.id, progress: Double(progress) / 100.0)
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.fileDownloadGenerationByRowId[row.id] == generation else {
          return
        }
        self.fileDownloadGenerationByRowId[row.id] = nil
        self.clearMediaDownloadProgress(rowId: row.id)
        if let error {
          self.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_video_unavailable",
            fallbackValue: "Video unavailable"
          )
          return
        }
        guard let resolvedPath = self.resolvedDownloadedPath(localPath, fallback: filePath) else {
          self.toast = ChatToastState(
            message: NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable"),
            style: .warning
          )
          return
        }
        var downloaded = media
        downloaded.localPath = resolvedPath
        self.replaceMediaContent(rowId: row.id, media: downloaded, kind: .video)
      }
    }
  }

  private func updateMediaDownloadProgress(rowId: String, progress: Double) {
    mediaDownloadProgressByRowId[rowId] = max(0, min(1, progress))
  }

  private func clearMediaDownloadProgress(rowId: String) {
    mediaDownloadProgressByRowId.removeValue(forKey: rowId)
  }

  private func openFilePreview(row: MessageRowState, file: MessageFileState) {
    let preview = ChatFilePreviewState(id: row.id, file: file)
    guard let fileInteractionHandler else {
      filePreview = preview
      return
    }
    let request = ChatFileInteractionRequest(
      preview: preview,
      message: row,
      context: sessionContextProvider()
    )
    fileInteractionHandler.handleFileInteraction(request) { [weak self] result in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.handleFileInteractionResult(result, fallbackPreview: preview)
      }
    }
  }

  private func handleFileInteractionResult(_ result: Result<ChatNativeBoundaryResult, Error>,
                                           fallbackPreview: ChatFilePreviewState) {
    switch result {
    case .success(let boundaryResult):
      switch boundaryResult {
      case let .route(.filePreview(preview)):
        filePreview = preview
      case .route:
        filePreview = fallbackPreview
      case let .toast(toast):
        self.toast = toast
      case .send, .sendMultiple, .none:
        break
      }
    case .failure(let error):
      filePreview = fallbackPreview
      toast = NEChatErrorMessageMapper.toast(
        for: error,
        fallbackKey: "chat_boundary_failed",
        fallbackValue: "Operation could not be completed"
      )
    }
  }

  private func fileDownloadPath(for row: MessageRowState,
                                file: MessageFileState,
                                url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") else {
      return nil
    }
    let baseName = [
      row.serverId,
      row.id,
      file.name
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? UUID().uuidString
    path += baseName
    let ext = [
      file.fileExtension,
      downloadFileExtension(preferredPath: file.localPath, url: url, fallbackName: file.name),
      file.normalizedFileExtension,
    ].compactMap { normalizedFileExtension($0) }.first
    let currentExt = (path as NSString).pathExtension
    if let ext, !ext.isEmpty, currentExt.caseInsensitiveCompare(ext) != .orderedSame {
      path += ".\(ext)"
    }
    return path
  }

  private func mediaDownloadPath(for row: MessageRowState,
                                 media: MessageMediaState,
                                 kind: ChatMediaPreviewKind,
                                 url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") else {
      return nil
    }
    let baseName = [
      row.serverId,
      row.id,
      UUID().uuidString,
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? UUID().uuidString
    path += baseName
    if let ext = downloadFileExtension(preferredPath: media.localPath, url: url, fallbackName: nil) {
      path += ".\(ext)"
    } else if kind == .video {
      path += ".mp4"
    }
    return path
  }

  private func downloadFileExtension(preferredPath: String?,
                                     url: URL,
                                     fallbackName: String?) -> String? {
    [
      preferredPath.map { URL(fileURLWithPath: $0).pathExtension },
      fallbackName.map { ($0 as NSString).pathExtension },
      url.pathExtension,
    ]
      .compactMap { normalizedFileExtension($0) }
      .first
  }

  private func downloadedFileExtension(file: MessageFileState,
                                       localPath: String,
                                       url: URL) -> String? {
    [
      file.fileExtension,
      downloadFileExtension(preferredPath: localPath, url: url, fallbackName: file.name),
      file.normalizedFileExtension,
    ].compactMap { normalizedFileExtension($0) }.first
  }

  private func normalizedFileExtension(_ value: String?) -> String? {
    let ext = value?
      .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
      .lowercased() ?? ""
    guard !ext.isEmpty,
          ext.count < 8 else {
      return nil
    }
    return ext
  }

  private func resolvedDownloadedPath(_ localPath: String?,
                                      fallback: String) -> String? {
    for path in [localPath, fallback] {
      guard let path,
            !path.isEmpty,
            FileManager.default.fileExists(atPath: path) else {
        continue
      }
      return path
    }
    return nil
  }

  private static func networkToast() -> ChatToastState {
    ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
      style: .warning
    )
  }

  private static func collectFailureToast(for error: Error) -> ChatToastState {
    let code = (error as NSError).code
    if code == collectionLimitCode {
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("collection_limit", value: "The number of favorites has reached the limit"),
        style: .warning
      )
    }
    return ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed"),
      style: .error
    )
  }

  private var conversationName: String {
    if let name = conversationNameProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
       !name.isEmpty {
      return name
    }
    guard let targetId = V2NIMConversationIdUtil.conversationTargetId(conversationId) else {
      return conversationId
    }
    if V2NIMConversationIdUtil.conversationType(conversationId) == .CONVERSATION_TYPE_P2P {
      let name = ChatRepo.swiftUIDisplayName(accountId: targetId, showAlias: true)
      return name.isEmpty ? targetId : name
    }
    return targetId
  }

  private static func sessionKind(for conversationId: String) -> ChatSessionKind {
    switch V2NIMConversationIdUtil.conversationType(conversationId) {
    case .CONVERSATION_TYPE_P2P:
      return .p2p
    case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
      return .team
    default:
      return .history
    }
  }
}

public struct HistoryFileActionMenuState: Equatable, Identifiable {
  public var row: MessageRowState

  public init(row: MessageRowState) {
    self.row = row
  }

  public var id: String {
    "history-file-actions:\(row.id)"
  }
}
