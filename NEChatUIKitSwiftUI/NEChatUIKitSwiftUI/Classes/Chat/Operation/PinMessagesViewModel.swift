// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

public struct PinMessageSelection {
  public var row: MessageRowState
  public var anchorMessage: V2NIMMessage?
  public var pendingMessages: [V2NIMMessage]
  public var opensConversationOnly: Bool

  public init(row: MessageRowState,
              anchorMessage: V2NIMMessage? = nil,
              pendingMessages: [V2NIMMessage] = [],
              opensConversationOnly: Bool = false) {
    self.row = row
    self.anchorMessage = anchorMessage
    self.pendingMessages = pendingMessages
    self.opensConversationOnly = opensConversationOnly
  }
}

private struct PinnedMessageDisplayInfo {
  var operatorId: String?
  var operatorName: String?
  var messageRefer: V2NIMMessageRefer?
  var serverExtension: String
}

@MainActor
public final class PinMessagesViewModel: ObservableObject {
  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var rows: [MessageRowState] = []
  @Published public private(set) var mediaDownloadProgressByRowId: [String: Double] = [:]
  @Published public var toast: ChatToastState?

  private let conversationId: String
  private let chatRepo: ChatRepo
  private let resourceDownloader: ChatResourceDownloading
  private let currentAccountProvider: () -> String?
  private let networkOperationGuard: () -> Bool
  private var listenerToken: NEChatKitListenerToken?
  private var clientListenerToken: NEChatKitListenerToken?
  private var messageContextById: [String: V2NIMMessage] = [:]
  private var pendingNewMessages = [V2NIMMessage]()
  private var pendingNewMessageIds = Set<String>()
  private var pinnedInfoById: [String: PinnedMessageDisplayInfo] = [:]
  private var mediaDownloadGenerationByRowId: [String: Int] = [:]
  private var hasLoadedOnce = false
  private var wasNetworkBroken = false
  private var reconnectReloadGeneration = 0

  public init(conversationId: String,
              chatRepo: ChatRepo = .shared,
              resourceDownloader: ChatResourceDownloading = NEChatKitResourceDownloader(),
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() },
              networkOperationGuard: @escaping () -> Bool = { true }) {
    self.conversationId = conversationId
    self.chatRepo = chatRepo
    self.resourceDownloader = resourceDownloader
    self.currentAccountProvider = currentAccountProvider
    self.networkOperationGuard = networkOperationGuard
    bindChatEvents()
    bindClientEvents()
  }

  deinit {
    listenerToken?.cancel()
    clientListenerToken?.cancel()
  }

  public func load() {
    guard phase != .loading else {
      return
    }
    guard !hasLoadedOnce else {
      return
    }
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    phase = .loading

    chatRepo.getPinnedMessageList(conversationId: conversationId) { [weak self] pins, error in
      if let error {
        Task { @MainActor in
          self?.phase = .failed(Self.errorState(for: error, fallbackKey: "chat_pinned_load_failed", fallbackValue: "Failed to load pinned messages"))
          self?.toast = Self.toast(for: error, fallbackKey: "chat_pinned_load_failed", fallbackValue: "Failed to load pinned messages")
        }
        return
      }

      let refers = (pins ?? []).compactMap(\.messageRefer)
      guard !refers.isEmpty else {
        Task { @MainActor in
          self?.messageContextById.removeAll()
          self?.pinnedInfoById.removeAll()
          self?.rows = []
          self?.phase = .empty
        }
        return
      }

      self?.chatRepo.getMessageListByRefers(refers) { [weak self] messages, error in
        Task { @MainActor in
          guard let self else {
            return
          }
          if let error {
            self.phase = .failed(Self.errorState(for: error, fallbackKey: "chat_pinned_load_failed", fallbackValue: "Failed to load pinned messages"))
            self.toast = Self.toast(for: error, fallbackKey: "chat_pinned_load_failed", fallbackValue: "Failed to load pinned messages")
            return
          }

          self.applyLoadResult(messages: messages, pinnedInfoById: Self.pinnedInfoById(from: pins ?? []))
        }
      }
    }
  }

  public func reload() {
    hasLoadedOnce = false
    load()
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  public func selection(for row: MessageRowState) -> PinMessageSelection {
    PinMessageSelection(
      row: row,
      anchorMessage: message(for: row),
      pendingMessages: pendingNewMessages
    )
  }

  public func shouldDownloadVideoBeforePreview(row: MessageRowState) -> Bool {
    guard case let .video(media) = row.content else {
      return false
    }
    return media.existingLocalPath == nil &&
      media.url != nil &&
      mediaDownloadProgressByRowId[row.id] == nil
  }

  public func shouldDownloadAudioBeforePlayback(row: MessageRowState) -> Bool {
    guard case let .audio(audio) = row.content else {
      return false
    }
    return audio.existingLocalPath == nil &&
      audio.url != nil &&
      mediaDownloadProgressByRowId[row.id] == nil
  }

  public func shouldDownloadFileBeforePreview(row: MessageRowState) -> Bool {
    guard case let .file(file) = row.content else {
      return false
    }
    return file.existingLocalPath == nil &&
      file.url != nil &&
      mediaDownloadProgressByRowId[row.id] == nil
  }

  public func downloadVideo(row: MessageRowState,
                            completion: ((MessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    guard case let .video(media) = row.content,
          media.existingLocalPath == nil,
          let url = media.url else {
      return
    }
    guard let filePath = videoDownloadPath(for: row, media: media, url: url) else {
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable"),
        style: .warning
      )
      return
    }

    let generation = beginMediaDownload(rowId: row.id)
    updateDeliveryState(for: row.id, deliveryState: .pending(progress: 0))
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        self?.updateMediaDownload(rowId: row.id, progress: Double(progress) / 100.0)
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.finishMediaDownloadIfCurrent(rowId: row.id, generation: generation) else {
          return
        }
        self.updateDeliveryState(for: row.id, deliveryState: .sent)
        if let error {
          self.toast = Self.toast(for: error, fallbackKey: "chat_video_unavailable", fallbackValue: "Video unavailable")
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
        if let updatedRow = self.updateVideoContent(for: row.id, media: downloaded) {
          completion?(updatedRow)
        }
      }
    }
  }

  public func downloadAudio(row: MessageRowState,
                            completion: ((MessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    guard case let .audio(audio) = row.content,
          audio.existingLocalPath == nil,
          let url = audio.url else {
      return
    }
    guard let filePath = audioDownloadPath(for: row, audio: audio, url: url) else {
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_audio_playback_failed", value: "Audio playback failed"),
        style: .warning
      )
      return
    }

    let generation = beginMediaDownload(rowId: row.id)
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        self?.updateMediaDownload(rowId: row.id, progress: Double(progress) / 100.0)
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.finishMediaDownloadIfCurrent(rowId: row.id, generation: generation) else {
          return
        }
        self.updateDeliveryState(for: row.id, deliveryState: .sent)
        if let error {
          self.toast = Self.toast(
            for: error,
            fallbackKey: "chat_audio_playback_failed",
            fallbackValue: "Audio playback failed"
          )
          return
        }
        guard let resolvedPath = self.resolvedDownloadedPath(localPath, fallback: filePath) else {
          self.toast = ChatToastState(
            message: NEChatUIKitSwiftUIBundle.localized("chat_audio_playback_failed", value: "Audio playback failed"),
            style: .warning
          )
          return
        }
        var downloaded = audio
        downloaded.localPath = resolvedPath
        if let updatedRow = self.updateAudioContent(for: row.id, audio: downloaded) {
          completion?(updatedRow)
        }
      }
    }
  }

  public func downloadFile(row: MessageRowState,
                           completion: ((MessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    guard case let .file(file) = row.content,
          file.existingLocalPath == nil,
          let url = file.url else {
      return
    }
    guard let filePath = fileDownloadPath(for: row, file: file, url: url) else {
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_file_unavailable", value: "File unavailable"),
        style: .warning
      )
      return
    }

    let generation = beginMediaDownload(rowId: row.id)
    updateDeliveryState(for: row.id, deliveryState: .pending(progress: 0))
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        self?.updateMediaDownload(rowId: row.id, progress: Double(progress) / 100.0)
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.finishMediaDownloadIfCurrent(rowId: row.id, generation: generation) else {
          return
        }
        self.updateDeliveryState(for: row.id, deliveryState: .sent)
        if let error {
          self.toast = Self.toast(for: error, fallbackKey: "chat_file_unavailable", fallbackValue: "File unavailable")
          return
        }
        guard let resolvedPath = self.resolvedDownloadedPath(localPath, fallback: filePath) else {
          self.toast = ChatToastState(
            message: NEChatUIKitSwiftUIBundle.localized("chat_file_unavailable", value: "File unavailable"),
            style: .warning
          )
          return
        }
        var downloaded = file
        downloaded.localPath = resolvedPath
        downloaded.fileExtension = self.downloadedFileExtension(file: downloaded, localPath: resolvedPath, url: url)
        if let updatedRow = self.updateFileContent(for: row.id, file: downloaded) {
          completion?(updatedRow)
        }
      }
    }
  }

  private func applyLoadResult(messages: [V2NIMMessage]?,
                               pinnedInfoById: [String: PinnedMessageDisplayInfo]) {
    let sortedMessages = (messages ?? []).sorted { $0.createTime > $1.createTime }
    messageContextById.removeAll()
    self.pinnedInfoById = pinnedInfoById
    cacheMessageContext(sortedMessages)
    let mappedRows = sortedMessages
      .sorted { $0.createTime > $1.createTime }
      .map {
        var row = ChatMessageMapper.row(message: $0, currentAccountId: currentAccountProvider())
        if let info = Self.pinnedInfo(for: row, in: pinnedInfoById) {
          row.isPinned = true
          row.pinOperatorId = info.operatorId
          row.pinOperatorName = info.operatorName
        }
        return row
      }
    TeamMemberDisplayEnricher.enrich(rows: mappedRows, conversationId: conversationId) { [weak self] enrichedRows in
      Task { @MainActor in
        self?.rows = enrichedRows.map { self?.applyingFallbackPinOperatorName($0) ?? $0 }
        self?.phase = enrichedRows.isEmpty ? .empty : .loaded
        self?.hasLoadedOnce = true
      }
    }
  }

  private func applyingFallbackPinOperatorName(_ row: MessageRowState) -> MessageRowState {
    var next = row
    if let operatorId = next.pinOperatorId {
      next.pinOperatorName = next.pinOperatorName ??
        Self.pinOperatorName(operatorId: operatorId, currentAccount: currentAccountProvider())
    }
    return next
  }

  public func removePin(row: MessageRowState) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    if let info = Self.pinnedInfo(for: row, in: pinnedInfoById),
       let messageRefer = info.messageRefer {
      chatRepo.unpinMessage(
        messageRefer: messageRefer,
        serverExtension: info.serverExtension
      ) { [weak self] error in
        Task { @MainActor in
          self?.applyRemovePinResult(row: row, error: error)
        }
      }
      return
    }
    chatRepo.getMessageListByIds([row.id]) { [weak self] messages, error in
      if let error {
        Task { @MainActor in
          self?.toast = Self.toast(for: error, fallbackKey: "chat_pin_removed_failed", fallbackValue: "Failed to unpin message")
        }
        return
      }
      guard let message = messages?.first else {
        return
      }
      self?.chatRepo.unpinMessage(message, serverExt: "") { [weak self] error in
        Task { @MainActor in
          self?.applyRemovePinResult(row: row, error: error)
        }
      }
    }
  }

  private func applyRemovePinResult(row: MessageRowState, error: NSError?) {
    if let error {
      toast = Self.toast(for: error, fallbackKey: "chat_pin_removed_failed", fallbackValue: "Failed to unpin message")
    } else {
      rows.removeAll { $0.id == row.id }
      removeCachedMessage(row: row)
      phase = rows.isEmpty ? .empty : .loaded
      toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("cancel_pin_success", value: "Unpin"),
        style: .success
      )
    }
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
        messagePinNotification: { [weak self] notification in
          Task { @MainActor in
            self?.handlePinNotification(notification)
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

  private func bindClientEvents() {
    clientListenerToken = IMKitClient.instance.addClientEventListener(
      NEIMKitClientEvent(connectStatus: { [weak self] status in
        Task { @MainActor in
          self?.handleConnectStatus(status)
        }
      })
    )
  }

  private func handleConnectStatus(_ status: V2NIMConnectStatus) {
    switch status {
    case .CONNECT_STATUS_WAITING, .CONNECT_STATUS_DISCONNECTED:
      wasNetworkBroken = true
      reconnectReloadGeneration += 1
    case .CONNECT_STATUS_CONNECTED where wasNetworkBroken:
      wasNetworkBroken = false
      reconnectReloadGeneration += 1
      let generation = reconnectReloadGeneration
      Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let self,
              self.reconnectReloadGeneration == generation else {
          return
        }
        self.reload()
      }
    default:
      break
    }
  }

  private func handleRevokeNotifications(_ notifications: [V2NIMMessageRevokeNotification]) {
    let ids = Set(notifications.compactMap(\.messageRefer).flatMap(messageIds(from:)))
    guard !ids.isEmpty else {
      return
    }
    removePendingNewMessages(matching: ids)
    reload()
  }

  private func handlePinNotification(_ notification: V2NIMMessagePinNotification) {
    let messageRefer = notification.pin?.messageRefer
    guard messageRefer?.conversationId == conversationId else {
      return
    }

    switch notification.pinState {
    case .MESSAGE_PIN_STEATE_NOT_PINNED:
      removeRows(messageRefers: [messageRefer])
    case .MESSAGE_PIN_STEATE_PINNED, .MESSAGE_PIN_STEATE_UPDATED:
      reload()
    default:
      break
    }
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
    rows.removeAll { row in
      ids.contains(row.id) || row.serverId.map(ids.contains) == true
    }
    for id in ids {
      messageContextById.removeValue(forKey: id)
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

  private func cacheMessageContext(_ messages: [V2NIMMessage]) {
    for message in messages {
      let stableId = ChatMessageMapper.stableMessageId(for: message)
      messageContextById[stableId] = message
      if let clientId = message.messageClientId, !clientId.isEmpty {
        messageContextById[clientId] = message
      }
      if let serverId = message.messageServerId, !serverId.isEmpty {
        messageContextById[serverId] = message
      }
    }
  }

  private func message(for row: MessageRowState) -> V2NIMMessage? {
    if let message = messageContextById[row.id] {
      return message
    }
    if let serverId = row.serverId, !serverId.isEmpty {
      return messageContextById[serverId]
    }
    return nil
  }

  private func removeCachedMessage(row: MessageRowState) {
    messageContextById.removeValue(forKey: row.id)
    pinnedInfoById.removeValue(forKey: row.id)
    if let serverId = row.serverId, !serverId.isEmpty {
      messageContextById.removeValue(forKey: serverId)
      pinnedInfoById.removeValue(forKey: serverId)
    }
  }

  private func beginMediaDownload(rowId: String) -> Int {
    let generation = (mediaDownloadGenerationByRowId[rowId] ?? 0) + 1
    mediaDownloadGenerationByRowId[rowId] = generation
    mediaDownloadProgressByRowId[rowId] = 0
    return generation
  }

  private func finishMediaDownloadIfCurrent(rowId: String, generation: Int) -> Bool {
    guard mediaDownloadGenerationByRowId[rowId] == generation else {
      return false
    }
    mediaDownloadGenerationByRowId[rowId] = nil
    mediaDownloadProgressByRowId[rowId] = nil
    return true
  }

  private func updateMediaDownload(rowId: String, progress: Double) {
    guard mediaDownloadGenerationByRowId[rowId] != nil else {
      return
    }
    let normalized = max(0, min(1, progress))
    mediaDownloadProgressByRowId[rowId] = normalized
    updateDeliveryState(for: rowId, deliveryState: .pending(progress: normalized))
  }

  private func updateDeliveryState(for rowId: String, deliveryState: MessageDeliveryState) {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.serverId == rowId }) else {
      return
    }
    rows[index].deliveryState = deliveryState
  }

  private func updateVideoContent(for rowId: String, media: MessageMediaState) -> MessageRowState? {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.serverId == rowId }) else {
      return nil
    }
    rows[index].content = .video(media)
    return rows[index]
  }

  private func updateAudioContent(for rowId: String, audio: MessageAudioState) -> MessageRowState? {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.serverId == rowId }) else {
      return nil
    }
    rows[index].content = .audio(audio)
    return rows[index]
  }

  private func updateFileContent(for rowId: String, file: MessageFileState) -> MessageRowState? {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.serverId == rowId }) else {
      return nil
    }
    rows[index].content = .file(file)
    return rows[index]
  }

  private func videoDownloadPath(for row: MessageRowState,
                                 media: MessageMediaState,
                                 url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)video/") else {
      return nil
    }
    let message = message(for: row)
    path += message?.messageClientId ?? downloadFileBaseName(for: row)
    if let ext = attachmentFileExtension(message?.attachment as? V2NIMMessageFileAttachment) ??
      downloadFileExtension(preferredPath: media.localPath, url: url, fallbackName: nil) {
      path += ext.hasPrefix(".") ? ext : ".\(ext)"
    }
    return path
  }

  private func audioDownloadPath(for row: MessageRowState,
                                 audio: MessageAudioState,
                                 url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)audio/") else {
      return nil
    }
    let message = message(for: row)
    let attachment = message?.attachment as? V2NIMMessageAudioAttachment
    path += message?.messageClientId ?? downloadFileBaseName(for: row)
    if let ext = normalizedFileExtension(attachment?.ext) ??
      downloadFileExtension(preferredPath: audio.localPath, url: url, fallbackName: nil) {
      path += ext.hasPrefix(".") ? ext : ".\(ext)"
    }
    return path
  }

  private func fileDownloadPath(for row: MessageRowState,
                                file: MessageFileState,
                                url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") else {
      return nil
    }
    let message = message(for: row)
    let attachment = message?.attachment as? V2NIMMessageFileAttachment
    path += message?.messageClientId ?? downloadFileBaseName(for: row)
    if let ext = attachmentFileExtension(attachment) ??
      normalizedFileExtension(file.fileExtension) ??
      downloadFileExtension(preferredPath: file.localPath, url: url, fallbackName: file.name) {
      path += ext.hasPrefix(".") ? ext : ".\(ext)"
    }
    return path
  }

  private func downloadFileBaseName(for row: MessageRowState) -> String {
    let raw = row.id.isEmpty ? UUID().uuidString : row.id
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let sanitized = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    return String(sanitized)
  }

  private func downloadFileExtension(preferredPath: String?,
                                     url: URL,
                                     fallbackName: String?) -> String? {
    let candidates = [
      preferredPath.map { URL(fileURLWithPath: $0).pathExtension },
      fallbackName.map { ($0 as NSString).pathExtension },
      url.pathExtension,
    ]
    return candidates.compactMap { normalizedFileExtension($0) }.first
  }

  private func downloadedFileExtension(file: MessageFileState,
                                       localPath: String,
                                       url: URL) -> String? {
    let candidates = [
      file.fileExtension,
      downloadFileExtension(preferredPath: localPath, url: url, fallbackName: file.name),
      file.normalizedFileExtension,
    ]
    return candidates.compactMap { normalizedFileExtension($0) }.first
  }

  private func attachmentFileExtension(_ attachment: V2NIMMessageFileAttachment?) -> String? {
    normalizedFileExtension(attachment?.ext)
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
      guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty,
            FileManager.default.fileExists(atPath: trimmed),
            let attributes = try? FileManager.default.attributesOfItem(atPath: trimmed),
            (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
        continue
      }
      return trimmed
    }
    return nil
  }

  private func messageIds(from messageRefer: V2NIMMessageRefer?) -> [String] {
    guard messageRefer?.conversationId == conversationId else {
      return []
    }

    return [messageRefer?.messageClientId, messageRefer?.messageServerId]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func pinnedInfoById(from pins: [V2NIMMessagePin]) -> [String: PinnedMessageDisplayInfo] {
    var result = [String: PinnedMessageDisplayInfo]()
    for pin in pins {
      let operatorId = pin.operatorId.trimmingCharacters(in: .whitespacesAndNewlines)
      let info = PinnedMessageDisplayInfo(
        operatorId: operatorId.isEmpty ? nil : operatorId,
        operatorName: operatorId.isEmpty ? nil : pinOperatorName(operatorId: operatorId),
        messageRefer: pin.messageRefer,
        serverExtension: pin.serverExtension
      )
      [pin.messageRefer?.messageClientId, pin.messageRefer?.messageServerId]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .forEach { result[$0] = info }
    }
    return result
  }

  private static func pinnedInfo(for row: MessageRowState,
                                 in infoById: [String: PinnedMessageDisplayInfo]) -> PinnedMessageDisplayInfo? {
    if let info = infoById[row.id] {
      return info
    }
    if let serverId = row.serverId, let info = infoById[serverId] {
      return info
    }
    return nil
  }

  private static func pinOperatorName(operatorId: String,
                                      currentAccount: String? = IMKitClient.instance.account()) -> String {
    if currentAccount == operatorId {
      return NEChatUIKitSwiftUIBundle.localized("You", value: "you")
    }
    return ChatRepo.swiftUIDisplayName(accountId: operatorId, showAlias: true)
  }

  private static func errorState(for error: Error,
                                 fallbackKey: String,
                                 fallbackValue: String) -> NEChatKitErrorState {
    NEChatErrorMessageMapper.errorState(for: error, fallbackKey: fallbackKey, fallbackValue: fallbackValue)
  }

  private static func toast(for error: Error,
                            fallbackKey: String,
                            fallbackValue: String) -> ChatToastState {
    NEChatErrorMessageMapper.toast(for: error, fallbackKey: fallbackKey, fallbackValue: fallbackValue)
  }

  private static func networkToast() -> ChatToastState {
    ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
      style: .warning
    )
  }
}
