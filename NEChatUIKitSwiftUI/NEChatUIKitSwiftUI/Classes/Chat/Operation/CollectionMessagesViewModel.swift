// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NIMSDK

public struct CollectionMessageRowState: Identifiable, Equatable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var senderName: String?
  public var senderId: String?
  public var avatarURL: URL?
  public var avatarName: String?
  public var conversationName: String?
  public var conversationTip: String?
  public var previewText: String
  public var iconSystemName: String
  public var iconImageName: String
  public var messageRow: MessageRowState?
  public var createTime: TimeInterval
  public var createTimeText: String

  public init(id: String,
              title: String,
              subtitle: String? = nil,
              senderName: String? = nil,
              senderId: String? = nil,
              avatarURL: URL? = nil,
              avatarName: String? = nil,
              conversationName: String? = nil,
              conversationTip: String? = nil,
              previewText: String? = nil,
              iconSystemName: String = "text.bubble",
              iconImageName: String = "op_replay",
              messageRow: MessageRowState? = nil,
              createTime: TimeInterval = 0,
              createTimeText: String? = nil) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.senderName = senderName
    self.senderId = senderId
    self.avatarURL = avatarURL
    self.avatarName = avatarName
    self.conversationName = conversationName
    self.conversationTip = conversationTip
    self.previewText = previewText ?? title
    self.iconSystemName = iconSystemName
    self.iconImageName = iconImageName
    self.messageRow = messageRow
    self.createTime = createTime
    self.createTimeText = createTimeText ?? ChatUnitFormatter.messageTimeText(createTime)
  }
}

@MainActor
public final class CollectionMessagesViewModel: ObservableObject {
  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var rows: [CollectionMessageRowState] = []
  @Published public private(set) var mediaDownloadProgressByRowId: [String: Double] = [:]
  @Published public var toast: ChatToastState?

  public private(set) var hasMore = true
  private var hasLoadedOnce = false

  private let chatRepo: ChatRepo
  private let contactRepo: ContactRepo
  private let resourceDownloader: ChatResourceDownloading
  private let networkOperationGuard: () -> Bool
  private let listenerBinder = ChatListenerBinder()
  private var anchorCollection: V2NIMCollection?
  private var messageContextById: [String: V2NIMMessage] = [:]
  private var mediaDownloadGenerationByRowId: [String: Int] = [:]
  private var contactDisplayInfoByAccountId = [String: NEUserWithFriend]()
  private var pendingContactDisplayAccountIds = Set<String>()
  private var nextRowIdentifierSequence = 0

  public init(chatRepo: ChatRepo = .shared,
              contactRepo: ContactRepo = .shared,
              resourceDownloader: ChatResourceDownloading = NEChatKitResourceDownloader(),
              networkOperationGuard: @escaping () -> Bool = { true }) {
    self.chatRepo = chatRepo
    self.contactRepo = contactRepo
    self.resourceDownloader = resourceDownloader
    self.networkOperationGuard = networkOperationGuard
    bindDisplayInfoEvents()
  }

  deinit {
    listenerBinder.cancel()
  }

  public func load(reset: Bool = true, force: Bool = false) {
    guard phase != .loading, phase != .loadingMore else {
      return
    }

    if reset {
      guard force || !hasLoadedOnce else {
        return
      }
      rows.removeAll()
      anchorCollection = nil
      hasMore = true
      hasLoadedOnce = false
    }

    guard hasMore else {
      return
    }
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }

    phase = rows.isEmpty ? .loading : .loadingMore
    let option = V2NIMCollectionOption()
    option.anchorCollection = anchorCollection
    if reset {
      option.endTime = Date().timeIntervalSince1970
      if let tenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: Date()) {
        option.beginTime = tenYearsAgo.timeIntervalSince1970
      }
    }
    option.limit = NEChatUIKitSwiftUIConstants.defaultHistoryPageSize
    option.direction = .QUERY_DIRECTION_DESC

    chatRepo.getCollections(option) { [weak self] collections, error in
      Task { @MainActor in
        self?.applyLoadResult(collections: collections, error: error, reset: reset)
      }
    }
  }

  public func loadMoreIfNeeded(currentRow: CollectionMessageRowState?) {
    guard currentRow?.id == rows.last?.id else {
      return
    }
    load(reset: false)
  }

  public func refresh() {
    hasLoadedOnce = false
    collectionMap.removeAll()
    messageContextById.removeAll()
    load(reset: true)
  }

  public func selection(for row: CollectionMessageRowState) -> PinMessageSelection {
    let messageRow = row.messageRow ?? fallbackSelectionRow(from: row)
    return PinMessageSelection(row: messageRow, anchorMessage: message(for: row))
  }

  public func shouldDownloadVideoBeforePreview(row: CollectionMessageRowState) -> Bool {
    guard let messageRow = row.messageRow,
          case let .video(media) = messageRow.content else {
      return false
    }
    return media.existingLocalPath == nil &&
      media.url != nil &&
      mediaDownloadProgressByRowId[row.id] == nil
  }

  public func shouldDownloadAudioBeforePlayback(row: CollectionMessageRowState) -> Bool {
    guard let messageRow = row.messageRow,
          case let .audio(audio) = messageRow.content else {
      return false
    }
    return audio.existingLocalPath == nil &&
      audio.url != nil &&
      mediaDownloadProgressByRowId[row.id] == nil
  }

  public func shouldDownloadFileBeforePreview(row: CollectionMessageRowState) -> Bool {
    guard let messageRow = row.messageRow,
          case let .file(file) = messageRow.content else {
      return false
    }
    return file.existingLocalPath == nil &&
      file.url != nil &&
      mediaDownloadProgressByRowId[row.id] == nil
  }

  public func downloadVideo(row: CollectionMessageRowState,
                            completion: ((CollectionMessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    guard let messageRow = row.messageRow,
          case let .video(media) = messageRow.content,
          media.existingLocalPath == nil,
          let url = media.url else {
      return
    }
    guard let filePath = videoDownloadPath(for: row, messageRow: messageRow, media: media, url: url) else {
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
        if let updatedRow = self.updateVideoContent(for: row.id, media: downloaded) {
          completion?(updatedRow)
        }
      }
    }
  }

  public func downloadAudio(row: CollectionMessageRowState,
                            completion: ((CollectionMessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    guard let messageRow = row.messageRow,
          case let .audio(audio) = messageRow.content,
          audio.existingLocalPath == nil,
          let url = audio.url else {
      return
    }
    guard let filePath = audioDownloadPath(for: row, messageRow: messageRow, audio: audio, url: url) else {
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
        if let error {
          self.toast = NEChatErrorMessageMapper.toast(
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

  public func downloadFile(row: CollectionMessageRowState,
                           completion: ((CollectionMessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }
    guard let messageRow = row.messageRow,
          case let .file(file) = messageRow.content,
          file.existingLocalPath == nil,
          let url = file.url else {
      return
    }
    guard let filePath = fileDownloadPath(for: row, messageRow: messageRow, file: file, url: url) else {
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
          self.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_file_unavailable",
            fallbackValue: "File unavailable"
          )
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

  public func removeCollection(id: String) {
    guard let collection = collectionMap[id] else {
      return
    }
    guard networkOperationGuard() else {
      toast = Self.networkToast()
      return
    }

    chatRepo.removeCollections([collection]) { [weak self] _, error in
      Task { @MainActor in
        if let error {
          self?.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_collection_delete_failed",
            fallbackValue: "Failed to delete collection"
          )
        } else {
          self?.applyRemoveResult(id: id)
        }
      }
    }
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard self.toast?.id == toast.id else {
      return
    }
    self.toast = nil
  }

  private var collectionMap = [String: V2NIMCollection]()

  private func applyLoadResult(collections: [V2NIMCollection]?,
                               error: NSError?,
                               reset: Bool) {
    if let error {
      phase = .failed(
        NEChatErrorMessageMapper.errorState(
          for: error,
          fallbackKey: "chat_collection_load_failed",
          fallbackValue: "Failed to load collections"
        )
      )
      toast = NEChatErrorMessageMapper.toast(
        for: error,
        fallbackKey: "chat_collection_load_failed",
        fallbackValue: "Failed to load collections"
      )
      return
    }

    let collections = collections ?? []
    if reset {
      collectionMap.removeAll()
      nextRowIdentifierSequence = 0
    }
    hasMore = collections.count >= NEChatUIKitSwiftUIConstants.defaultHistoryPageSize
    anchorCollection = collections.last ?? anchorCollection
    let newRows = collections.map { collection in
      rowState(from: collection, rowId: makeRowId(for: collection))
    }
    for (collection, row) in zip(collections, newRows) {
      collectionMap[row.id] = collection
    }

    if reset {
      rows = newRows
    } else {
      rows.append(contentsOf: newRows)
    }
    hasLoadedOnce = true
    phase = rows.isEmpty ? .empty : .loaded
    refreshContactDisplayInfosIfNeeded()
  }

  private func applyRemoveResult(id: String) {
    let removedCollection = collectionMap[id]
    collectionMap[id] = nil
    rows.removeAll { $0.id == id }
    refreshAnchorAfterRemovingCollection(removedCollection)
    phase = rows.isEmpty ? .empty : .loaded
    toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("delete_collection_success", value: "Deleted"),
      style: .success
    )
    refillPageIfNeededAfterRemoval()
  }

  private func refreshAnchorAfterRemovingCollection(_ removedCollection: V2NIMCollection?) {
    guard let anchorCollection,
          let removedCollection,
          collectionId(for: anchorCollection) == collectionId(for: removedCollection) else {
      return
    }
    self.anchorCollection = rows.last.flatMap { collectionMap[$0.id] }
  }

  private func refillPageIfNeededAfterRemoval() {
    guard hasMore,
          phase != .loading,
          phase != .loadingMore else {
      return
    }
    if rows.isEmpty {
      hasLoadedOnce = false
      load(reset: true, force: true)
    } else if rows.count < NEChatUIKitSwiftUIConstants.defaultHistoryPageSize {
      load(reset: false)
    }
  }

  private func rowState(from collection: V2NIMCollection,
                        rowId: String) -> CollectionMessageRowState {
    let data = collection.collectionData.flatMap { NECommonUtil.getDictionaryFromJSONString($0) as? [String: Any] }
    let message = data?["message"]
      .flatMap(serializedCollectionMessageString(from:))
      .flatMap { V2NIMMessageConverter.messageDeserialization($0) }
    let mappedMessageRow = message.map { ChatMessageMapper.row(message: $0) }
    let fallbackMessageRow = messageRowState(from: data, collection: collection, message: message)
    let messageRow = restoringCollectionTextHighlights(
      from: data,
      message: message,
      to: collectionAlignedMessageRow(
        mappedRow: mappedMessageRow,
        fallbackRow: fallbackMessageRow,
        collectionType: Int(collection.collectionType)
      )
    )
    if let message {
      cacheMessageContext(message, collectionRowId: rowId)
    }
    let preview = messageRow.map { collectionPreviewText(for: $0.content, fallback: ChatMessageMapper.previewText(for: $0.content)) } ??
      (data?["text"] as? String) ??
      NEChatUIKitSwiftUIBundle.localized("chat_collection_message", value: "Collection")
    let conversationName = data?["conversationName"] as? String
    let senderName = nonEmpty(data?["senderName"] as? String) ?? messageRow?.senderName
    let senderId = message?.senderId ?? nonEmpty(data?["senderId"] as? String) ?? messageRow?.senderId
    let avatarURL = ChatAvatarURLResolver.url(from: data?["avatar"] as? String) ?? messageRow?.avatarURL
    let avatarDisplay = ChatAvatarDisplayResolver.info(
      accountId: senderId,
      fallbackName: senderName,
      fallbackAvatarURL: avatarURL,
      loadedUser: senderId.flatMap { contactDisplayInfoByAccountId[$0] }
    )
    let conversationTip = Self.conversationTip(
      conversationName: conversationName,
      conversationType: message?.conversationType ?? conversationType(from: data?["conversationType"]),
      conversationId: message?.conversationId ?? messageRow?.conversationId
    )
    let title = preview.isEmpty
      ? NEChatUIKitSwiftUIBundle.localized("chat_collection_message", value: "Collection")
      : preview
    let resolvedSenderName = senderName ?? avatarDisplay.displayName
    let resolvedAvatarURL = avatarURL ?? avatarDisplay.avatarURL
    let resolvedAvatarName = messageRow?.avatarName ?? senderId.flatMap { accountId -> String? in
      let name = ChatRepo.swiftUIDisplayName(accountId: accountId, showAlias: false)
      return name.isEmpty ? nil : name
    }
    let subtitle = [resolvedSenderName, conversationName].compactMap { value -> String? in
      guard let value, !value.isEmpty else {
        return nil
      }
      return value
    }.joined(separator: " - ")

    return CollectionMessageRowState(
      id: rowId,
      title: title,
      subtitle: subtitle.isEmpty ? nil : subtitle,
      senderName: resolvedSenderName,
      senderId: senderId,
      avatarURL: resolvedAvatarURL,
      avatarName: resolvedAvatarName,
      conversationName: conversationName,
      conversationTip: conversationTip,
      previewText: preview,
      iconSystemName: iconSystemName(for: messageRow?.content, collectionType: Int(collection.collectionType)),
      iconImageName: iconImageName(for: messageRow?.content, collectionType: Int(collection.collectionType)),
      messageRow: messageRow,
      createTime: collection.updateTime > 0 ? collection.updateTime : collection.createTime
    )
  }

  private func cacheMessageContext(_ message: V2NIMMessage,
                                   collectionRowId: String) {
    messageContextById[collectionRowId] = message
    let stableId = ChatMessageMapper.stableMessageId(for: message)
    messageContextById[stableId] = message
    if let serverId = message.messageServerId, !serverId.isEmpty {
      messageContextById[serverId] = message
    }
    if let clientId = message.messageClientId, !clientId.isEmpty {
      messageContextById[clientId] = message
    }
  }

  private func message(for row: CollectionMessageRowState) -> V2NIMMessage? {
    if let message = messageContextById[row.id] {
      return message
    }
    if let messageRow = row.messageRow {
      if let message = messageContextById[messageRow.id] {
        return message
      }
      if let serverId = messageRow.serverId,
         let message = messageContextById[serverId] {
        return message
      }
    }
    return nil
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
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.messageRow?.id == rowId || $0.messageRow?.serverId == rowId }),
          rows[index].messageRow != nil else {
      return
    }
    rows[index].messageRow?.deliveryState = deliveryState
  }

  private func updateVideoContent(for rowId: String, media: MessageMediaState) -> CollectionMessageRowState? {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.messageRow?.id == rowId || $0.messageRow?.serverId == rowId }),
          rows[index].messageRow != nil else {
      return nil
    }
    rows[index].messageRow?.content = .video(media)
    return rows[index]
  }

  private func updateAudioContent(for rowId: String, audio: MessageAudioState) -> CollectionMessageRowState? {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.messageRow?.id == rowId || $0.messageRow?.serverId == rowId }),
          rows[index].messageRow != nil else {
      return nil
    }
    rows[index].messageRow?.content = .audio(audio)
    return rows[index]
  }

  private func updateFileContent(for rowId: String, file: MessageFileState) -> CollectionMessageRowState? {
    guard let index = rows.firstIndex(where: { $0.id == rowId || $0.messageRow?.id == rowId || $0.messageRow?.serverId == rowId }),
          rows[index].messageRow != nil else {
      return nil
    }
    rows[index].messageRow?.content = .file(file)
    return rows[index]
  }

  private func videoDownloadPath(for row: CollectionMessageRowState,
                                 messageRow: MessageRowState,
                                 media: MessageMediaState,
                                 url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)video/") else {
      return nil
    }
    let message = message(for: row)
    let attachment = message?.attachment as? V2NIMMessageFileAttachment
    path += message?.messageClientId ?? downloadFileBaseName(for: messageRow)
    if let ext = attachmentFileExtension(attachment) ??
      normalizedFileExtension(attachment.map { ($0.name as NSString).pathExtension }) ??
      downloadFileExtension(preferredPath: media.localPath, url: url, fallbackName: nil) {
      path += ext.hasPrefix(".") ? ext : ".\(ext)"
    }
    return path
  }

  private func audioDownloadPath(for row: CollectionMessageRowState,
                                 messageRow: MessageRowState,
                                 audio: MessageAudioState,
                                 url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)audio/") else {
      return nil
    }
    let message = message(for: row)
    path += message?.messageClientId ?? downloadFileBaseName(for: messageRow)
    if let ext = attachmentFileExtension(message?.attachment as? V2NIMMessageFileAttachment) ??
      downloadFileExtension(preferredPath: audio.localPath, url: url, fallbackName: nil) {
      path += ext.hasPrefix(".") ? ext : ".\(ext)"
    }
    return path
  }

  private func fileDownloadPath(for row: CollectionMessageRowState,
                                messageRow: MessageRowState,
                                file: MessageFileState,
                                url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") else {
      return nil
    }
    let message = message(for: row)
    path += message?.messageClientId ?? downloadFileBaseName(for: messageRow)
    if let ext = attachmentFileExtension(message?.attachment as? V2NIMMessageFileAttachment) ??
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

  private func fallbackSelectionRow(from row: CollectionMessageRowState) -> MessageRowState {
    MessageRowState(
      id: row.id,
      conversationId: nil,
      senderId: row.senderId,
      senderName: row.senderName,
      avatarURL: row.avatarURL,
      direction: .incoming,
      content: .text(row.previewText),
      deliveryState: .sent,
      timestamp: row.createTime
    )
  }

  private func collectionId(for collection: V2NIMCollection) -> String {
    if let id = collection.collectionId, !id.isEmpty {
      return id
    }
    if let uid = collection.uniqueId, !uid.isEmpty {
      return uid
    }
    return "\(collection.collectionType)-\(collection.createTime)-\(collection.collectionData?.hashValue ?? 0)"
  }

  private func makeRowId(for collection: V2NIMCollection) -> String {
    defer { nextRowIdentifierSequence += 1 }
    return "\(collectionId(for: collection))#\(nextRowIdentifierSequence)"
  }

  private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private func stringValue(_ value: Any?) -> String? {
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      return number.stringValue
    default:
      return nil
    }
  }

  private func timeValue(_ value: Any?) -> TimeInterval? {
    switch value {
    case let time as TimeInterval:
      return time
    case let number as NSNumber:
      return number.doubleValue
    case let string as String:
      return TimeInterval(string)
    default:
      return nil
    }
  }

  private func richTextTitle(from message: V2NIMMessage?) -> String? {
    guard let attachment = message?.attachment,
          NECustomUtils.typeOfCustomMessage(attachment) == customRichTextType else {
      return nil
    }
    return nonEmpty(NECustomUtils.titleOfRichText(attachment))
  }

  private func richTextBody(from message: V2NIMMessage?) -> String? {
    guard let attachment = message?.attachment,
          NECustomUtils.typeOfCustomMessage(attachment) == customRichTextType else {
      return nil
    }
    return nonEmpty(NECustomUtils.bodyOfRichText(attachment))
  }

  private func messageRowState(from data: [String: Any]?,
                               collection: V2NIMCollection,
                               message: V2NIMMessage? = nil) -> MessageRowState? {
    guard let data else {
      return nil
    }

    let text = nonEmpty(stringValue(data["text"])) ?? nonEmpty(message?.text)
    let richTextTitle = nonEmpty(stringValue(data["richTextTitle"])) ?? richTextTitle(from: message)
    let richTextBody = nonEmpty(stringValue(data["richTextBody"])) ?? richTextBody(from: message)

    let content: MessageContentState
    if richTextTitle != nil || richTextBody != nil {
      content = .richText(title: richTextTitle, body: richTextBody ?? text ?? "")
    } else if let multiForward = collectionMultiForwardState(from: data, message: message) {
      content = .multiForward(multiForward)
    } else if let typedContent = collectionTypedFallbackContent(from: data, message: message, collectionType: Int(collection.collectionType)) {
      content = typedContent
    } else if let text {
      content = .text(text)
    } else {
      return nil
    }

    return MessageRowState(
      id: nonEmpty(data["messageClientId"] as? String) ?? collectionId(for: collection),
      serverId: nonEmpty(data["messageServerId"] as? String),
      conversationId: nonEmpty(data["conversationId"] as? String),
      senderId: nonEmpty(data["senderId"] as? String),
      senderName: nonEmpty(data["senderName"] as? String),
      avatarURL: ChatAvatarURLResolver.url(from: data["avatar"] as? String),
      direction: .incoming,
      content: content,
      deliveryState: .sent,
      timestamp: collection.updateTime > 0 ? collection.updateTime : collection.createTime
    )
  }

  private func collectionMultiForwardState(from data: [String: Any],
                                           message: V2NIMMessage?) -> MessageMultiForwardState? {
    var payloads = [[String: Any]]()
    if let attachmentData = message?.attachment.flatMap(NECustomUtils.dataOfCustomMessage) {
      payloads.append(attachmentData)
    }
    if let rawAttachment = message?.attachment?.raw {
      payloads.append(contentsOf: multiForwardPayloads(in: rawAttachment))
    }
    if let serializedMessage = data["message"] {
      payloads.append(contentsOf: multiForwardPayloads(in: serializedMessage))
    }
    payloads.append(contentsOf: multiForwardPayloads(in: data))

    let rawTitle = data["multiForwardTitle"] ??
      data["sessionName"] ??
      firstValue(for: ["multiForwardTitle", "sessionName"], in: payloads)
    let rawSummaries = data["multiForwardSummaries"] ??
      data["abstracts"] ??
      firstValue(for: ["multiForwardSummaries", "abstracts"], in: payloads)
    let isMultiForwardMessage = message?.attachment.flatMap(NECustomUtils.typeOfCustomMessage) == customMultiForwardType
    guard isMultiForwardMessage || rawTitle != nil || rawSummaries != nil else {
      return nil
    }
    let summaries = collectionMultiForwardSummaries(from: rawSummaries)
    let title = nonEmpty(stringValue(rawTitle))
    return MessageMultiForwardState(
      title: title ?? NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History"),
      hasSessionName: title != nil,
      url: nonEmpty(stringValue(
        data["multiForwardURL"] ?? data["url"] ?? firstValue(for: ["multiForwardURL", "url"], in: payloads)
      )),
      md5: nonEmpty(stringValue(
        data["multiForwardMD5"] ?? data["md5"] ?? firstValue(for: ["multiForwardMD5", "md5"], in: payloads)
      )),
      depth: Int(timeValue(
        data["multiForwardDepth"] ?? data["depth"] ?? firstValue(for: ["multiForwardDepth", "depth"], in: payloads)
      ) ?? 0),
      sessionId: nonEmpty(stringValue(
        data["multiForwardSessionId"] ?? data["sessionId"] ?? firstValue(for: ["multiForwardSessionId", "sessionId"], in: payloads)
      )),
      summaries: summaries
    )
  }

  private func collectionMultiForwardSummaries(from value: Any?) -> [MessageMultiForwardSummaryState] {
    let rawValues: [Any]
    if let values = value as? [Any] {
      rawValues = values
    } else if let string = value as? String,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) {
      if let values = object as? [Any] {
        rawValues = values
      } else {
        rawValues = [object]
      }
    } else if dictionaryValue(value as Any) != nil {
      rawValues = [value as Any]
    } else {
      rawValues = []
    }
    return rawValues.compactMap { value in
      if let summary = dictionaryValue(value),
         let content = nonEmpty(stringValue(summary["content"])) {
        return MessageMultiForwardSummaryState(
          senderNick: nonEmpty(stringValue(summary["senderNick"])),
          content: content,
          userAccId: nonEmpty(stringValue(summary["userAccId"]))
        )
      }
      if let content = nonEmpty(stringValue(value)) {
        return MessageMultiForwardSummaryState(content: content)
      }
      return nil
    }
  }

  private func firstValue(for keys: [String],
                          in dictionaries: [[String: Any]]) -> Any? {
    for dictionary in dictionaries {
      for key in keys where dictionary[key] != nil {
        return dictionary[key]
      }
    }
    return nil
  }

  private func multiForwardPayloads(in value: Any,
                                    depth: Int = 0) -> [[String: Any]] {
    guard depth <= 8 else {
      return []
    }
    if let string = value as? String,
       let data = string.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) {
      return multiForwardPayloads(in: object, depth: depth + 1)
    }
    if let values = value as? [Any] {
      return values.flatMap { multiForwardPayloads(in: $0, depth: depth + 1) }
    }
    guard let dictionary = dictionaryValue(value) else {
      return []
    }

    var result = [[String: Any]]()
    let type = messageType(from: dictionary["type"])
    let hasMultiForwardFields = dictionary["abstracts"] != nil ||
      dictionary["multiForwardSummaries"] != nil ||
      dictionary["multiForwardTitle"] != nil
    if hasMultiForwardFields {
      result.append(dictionary)
    }
    if type == customMultiForwardType,
       let nestedData = dictionary["data"].flatMap(dictionaryValue) {
      result.append(nestedData)
    }
    for nestedValue in dictionary.values {
      result.append(contentsOf: multiForwardPayloads(in: nestedValue, depth: depth + 1))
    }
    return result
  }

  private func restoringCollectionTextHighlights(from data: [String: Any]?,
                                                 message: V2NIMMessage?,
                                                 to row: MessageRowState?) -> MessageRowState? {
    guard var row,
          let text = textForCollectionHighlights(in: row.content) else {
      return row
    }
    let serverHighlights = ChatMessageMapper.mentionHighlights(fromServerExtension: message?.serverExtension, in: text)
    let storedHighlights = collectionTextHighlights(from: data?["textHighlights"], in: text)
    let highlights = serverHighlights.isEmpty ? storedHighlights : serverHighlights
    let existingHighlights = shouldReplaceCollectionHighlights(in: row.content) ? [] : row.textHighlights
    row.textHighlights = normalizedTextHighlights(existingHighlights + highlights, in: text)
    return row
  }

  private func shouldReplaceCollectionHighlights(in content: MessageContentState) -> Bool {
    switch content {
    case .richText:
      return true
    case let .reply(_, boxed):
      return shouldReplaceCollectionHighlights(in: boxed.value)
    default:
      return false
    }
  }

  private func textForCollectionHighlights(in content: MessageContentState) -> String? {
    switch content {
    case let .text(text):
      return text
    case let .richText(_, body):
      return body
    case let .reply(_, boxed):
      return textForCollectionHighlights(in: boxed.value)
    case let .aiStream(text, _, _):
      return text
    default:
      return nil
    }
  }

  private func collectionTextHighlights(from value: Any?,
                                        in text: String) -> [MessageTextHighlightState] {
    let items: [Any]
    if let array = value as? [Any] {
      items = array
    } else if let array = value as? NSArray {
      items = array.map { $0 }
    } else {
      return []
    }

    let highlights = items.compactMap { item -> MessageTextHighlightState? in
      guard let dictionary = dictionaryValue(item),
            let start = messageType(from: dictionary["start"]),
            let end = messageType(from: dictionary["end"]),
            let kind = textHighlightKind(from: dictionary["kind"]) else {
        return nil
      }
      return MessageTextHighlightState(start: start, end: end, kind: kind)
    }
    return normalizedTextHighlights(highlights, in: text)
  }

  private func textHighlightKind(from value: Any?) -> MessageTextHighlightKind? {
    guard let rawValue = stringValue(value) else {
      return nil
    }
    switch rawValue {
    case "mention":
      return .mention
    case "keyword":
      return .keyword
    default:
      return nil
    }
  }

  private func normalizedTextHighlights(_ highlights: [MessageTextHighlightState],
                                        in text: String) -> [MessageTextHighlightState] {
    var result = [MessageTextHighlightState]()
    for highlight in highlights.sorted(by: { left, right in
      if left.start == right.start {
        return left.end < right.end
      }
      return left.start < right.start
    }) {
      guard highlight.start >= 0,
            highlight.start < highlight.end,
            highlight.end <= text.count,
            result.last?.range.overlaps(highlight.range) != true else {
        continue
      }
      result.append(highlight)
    }
    return result
  }

  private func dictionaryValue(_ value: Any) -> [String: Any]? {
    if let dictionary = value as? [String: Any] {
      return dictionary
    }
    if let dictionary = value as? NSDictionary {
      return dictionary as? [String: Any]
    }
    return nil
  }

  private func serializedCollectionMessageString(from value: Any) -> String? {
    if let string = value as? String {
      return nonEmpty(string)
    }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let string = String(data: data, encoding: .utf8) else {
      return nil
    }
    return nonEmpty(string)
  }

  private func collectionAlignedMessageRow(mappedRow: MessageRowState?,
                                           fallbackRow: MessageRowState?,
                                           collectionType: Int) -> MessageRowState? {
    guard let mappedRow else {
      return fallbackRow
    }
    if let fallbackRow,
       case let .multiForward(mappedMultiForward) = mappedRow.content,
       case let .multiForward(fallbackMultiForward) = fallbackRow.content {
      var mergedRow = mappedRow
      mergedRow.content = .multiForward(
        mergedCollectionMultiForward(
          mapped: mappedMultiForward,
          fallback: fallbackMultiForward
        )
      )
      return mergedRow
    }
    if let fallbackRow,
       messageContentContainsMultiForward(fallbackRow.content),
       !messageContentContainsMultiForward(mappedRow.content) {
      return fallbackRow
    }
    if let fallbackRow,
       messageContentContainsRichText(fallbackRow.content),
       !messageContentContainsRichText(mappedRow.content) {
      return fallbackRow
    }
    guard let fallbackRow,
          let expectedType = messageType(fromCollectionType: collectionType),
          !messageContent(mappedRow.content, matchesMessageType: expectedType),
          messageContent(fallbackRow.content, matchesMessageType: expectedType) else {
      return mappedRow
    }
    return fallbackRow
  }

  private func mergedCollectionMultiForward(mapped: MessageMultiForwardState,
                                            fallback: MessageMultiForwardState) -> MessageMultiForwardState {
    MessageMultiForwardState(
      title: nonEmpty(mapped.title) ?? fallback.title,
      hasSessionName: mapped.hasSessionName || fallback.hasSessionName,
      url: nonEmpty(mapped.url) ?? fallback.url,
      md5: nonEmpty(mapped.md5) ?? fallback.md5,
      depth: mapped.depth > 0 ? mapped.depth : fallback.depth,
      sessionId: nonEmpty(mapped.sessionId) ?? fallback.sessionId,
      summaries: mapped.summaries.isEmpty ? fallback.summaries : mapped.summaries
    )
  }

  private func messageContentContainsRichText(_ content: MessageContentState) -> Bool {
    switch content {
    case .richText:
      return true
    case let .reply(_, boxed):
      return messageContentContainsRichText(boxed.value)
    default:
      return false
    }
  }

  private func messageContentContainsMultiForward(_ content: MessageContentState) -> Bool {
    switch content {
    case .multiForward:
      return true
    case let .reply(_, boxed):
      return messageContentContainsMultiForward(boxed.value)
    default:
      return false
    }
  }

  private func messageContent(_ content: MessageContentState,
                              matchesMessageType messageType: Int) -> Bool {
    switch messageType {
    case Int(V2NIMMessageType.MESSAGE_TYPE_TEXT.rawValue):
      if case .text = content { return true }
      if case .aiStream = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_IMAGE.rawValue):
      if case .image = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_AUDIO.rawValue):
      if case .audio = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_VIDEO.rawValue):
      if case .video = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_FILE.rawValue):
      if case .file = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_LOCATION.rawValue):
      if case .location = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_CALL.rawValue):
      if case .call = content { return true }
      return false
    case Int(V2NIMMessageType.MESSAGE_TYPE_CUSTOM.rawValue):
      switch content {
      case .richText, .multiForward, .custom, .reply:
        return true
      default:
        return false
      }
    default:
      return true
    }
  }

  private func collectionTypedFallbackContent(from data: [String: Any],
                                              message: V2NIMMessage?,
                                              collectionType: Int) -> MessageContentState? {
    let fallbackType = messageType(fromCollectionType: collectionType) ??
      messageType(from: data["messageType"]) ??
      message.map { Int($0.messageType.rawValue) }
    switch fallbackType {
    case Int(V2NIMMessageType.MESSAGE_TYPE_IMAGE.rawValue)?:
      return .image(mediaFallbackState(from: data, imageAttachment: message?.attachment as? V2NIMMessageImageAttachment))
    case Int(V2NIMMessageType.MESSAGE_TYPE_VIDEO.rawValue)?:
      return .video(mediaFallbackState(from: data, videoAttachment: message?.attachment as? V2NIMMessageVideoAttachment))
    case Int(V2NIMMessageType.MESSAGE_TYPE_AUDIO.rawValue)?:
      let attachment = message?.attachment as? V2NIMMessageAudioAttachment
      return .audio(MessageAudioState(
        duration: timeValue(data["audioDuration"]) ??
          timeValue(data["duration"]) ??
          attachment.map { TimeInterval($0.duration) / 1000.0 } ??
          0,
        localPath: existingPath(data["audioLocalPath"]) ?? existingPath(data["path"]) ?? existingPath(attachment?.path),
        url: urlValue(data["audioURL"]) ?? urlValue(data["url"]) ?? urlValue(attachment?.url)
      ))
    case Int(V2NIMMessageType.MESSAGE_TYPE_FILE.rawValue)?:
      let attachment = message?.attachment as? V2NIMMessageFileAttachment
      return .file(MessageFileState(
        name: nonEmpty(stringValue(data["fileName"])) ??
          nonEmpty(stringValue(data["name"])) ??
          nonEmpty(stringValue(data["text"])) ??
          nonEmpty(attachment?.name) ??
          nonEmpty(message?.text) ??
          NEChatUIKitSwiftUIBundle.localized("chat_message_file", value: "File"),
        sizeText: nonEmpty(stringValue(data["fileSizeText"])) ??
          data["fileSize"].flatMap(fileSizeText(from:)) ??
          data["size"].flatMap(fileSizeText(from:)) ??
          attachment.map { ChatUnitFormatter.fileSizeText(bytes: $0.size) },
        url: urlValue(data["fileURL"]) ?? urlValue(data["url"]) ?? urlValue(attachment?.url),
        localPath: existingPath(data["fileLocalPath"]) ?? existingPath(data["path"]) ?? existingPath(attachment?.path),
        fileExtension: nonEmpty(stringValue(data["fileExtension"])) ??
          nonEmpty(stringValue(data["ext"])) ??
          nonEmpty(attachment?.ext)
      ))
    case Int(V2NIMMessageType.MESSAGE_TYPE_LOCATION.rawValue)?:
      let attachment = message?.attachment as? V2NIMMessageLocationAttachment
      return .location(MessageLocationState(
        latitude: timeValue(data["locationLatitude"]) ?? attachment?.latitude,
        longitude: timeValue(data["locationLongitude"]) ?? attachment?.longitude,
        title: nonEmpty(stringValue(data["locationTitle"])) ??
          nonEmpty(message?.text) ??
          nonEmpty(attachment?.address) ??
          NEChatUIKitSwiftUIBundle.localized("chat_location", value: "Location"),
        subtitle: nonEmpty(stringValue(data["locationSubtitle"])) ?? nonEmpty(attachment?.address),
        thumbnailURL: urlValue(data["locationThumbnailURL"]) ??
          attachment.flatMap { urlValue(NEChatKitClient.instance.getMapImageUrl(lat: $0.latitude, lng: $0.longitude)) }
      ))
    default:
      return nil
    }
  }

  private func mediaFallbackState(from data: [String: Any],
                                  imageAttachment: V2NIMMessageImageAttachment? = nil,
                                  videoAttachment: V2NIMMessageVideoAttachment? = nil) -> MessageMediaState {
    let mediaURL = urlValue(data["mediaURL"]) ??
      urlValue(data["url"]) ??
      urlValue(imageAttachment?.url) ??
      urlValue(videoAttachment?.url)
    let localPath = existingPath(data["mediaLocalPath"]) ??
      existingPath(data["path"]) ??
      existingPath(imageAttachment?.path) ??
      existingPath(videoAttachment?.path)
    return MessageMediaState(
      url: mediaURL,
      localPath: localPath,
      thumbnailURL: urlValue(data["mediaThumbnailURL"]) ??
        urlValue(data["thumbnailURL"]) ??
        urlValue(data["thumbURL"]) ??
        urlValue(data["thumbUrl"]) ??
        imageThumbnailURL(from: imageAttachment) ??
        videoThumbnailURL(from: videoAttachment),
      width: timeValue(data["mediaWidth"]) ?? timeValue(data["width"]) ?? imageAttachment.map { Double($0.width) } ?? videoAttachment.map { Double($0.width) },
      height: timeValue(data["mediaHeight"]) ?? timeValue(data["height"]) ?? imageAttachment.map { Double($0.height) } ?? videoAttachment.map { Double($0.height) },
      duration: normalizedMediaDuration(
        timeValue(data["mediaDuration"]) ??
          timeValue(data["videoDuration"]) ??
          timeValue(data["duration"]) ??
          videoAttachment.map { TimeInterval($0.duration) }
      )
    )
  }

  private func imageThumbnailURL(from attachment: V2NIMMessageImageAttachment?) -> URL? {
    guard let rawURL = attachment?.url, !rawURL.isEmpty else {
      return nil
    }
    let normalizedExt = attachment?.ext?
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .lowercased()
    guard normalizedExt != "gif" else {
      return urlValue(rawURL)
    }
    return urlValue(V2NIMStorageUtil.imageThumbUrl(rawURL, thumbSize: 350))
  }

  private func videoThumbnailURL(from attachment: V2NIMMessageVideoAttachment?) -> URL? {
    guard let rawURL = attachment?.url, !rawURL.isEmpty else {
      return urlValue(attachment?.path)
    }
    return urlValue(V2NIMStorageUtil.videoCoverUrl(rawURL, offset: 0))
  }

  private func messageType(fromCollectionType collectionType: Int) -> Int? {
    let rawValue = collectionType - collectionTypeOffset
    guard rawValue >= 0 else {
      return nil
    }
    return rawValue
  }

  private func normalizedMediaDuration(_ duration: TimeInterval?) -> TimeInterval? {
    guard let duration, duration > 0 else {
      return duration
    }
    return duration >= 1000 ? duration / 1000.0 : duration
  }

  private func messageType(from value: Any?) -> Int? {
    switch value {
    case let int as Int:
      return int
    case let int32 as Int32:
      return Int(int32)
    case let number as NSNumber:
      return number.intValue
    case let string as String:
      return Int(string)
    default:
      return nil
    }
  }

  private func urlValue(_ value: Any?) -> URL? {
    switch value {
    case let url as URL:
      return url
    case let string as String:
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return nil
      }
      if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return URL(string: trimmed)
      }
      return URL(fileURLWithPath: trimmed)
    default:
      return nil
    }
  }

  private func existingPath(_ value: Any?) -> String? {
    guard let path = nonEmpty(stringValue(value)) else {
      return nil
    }
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }

  private func fileSizeText(from value: Any) -> String? {
    switch value {
    case let number as NSNumber:
      return ChatUnitFormatter.fileSizeText(bytes: number.int64Value)
    case let string as String:
      guard let bytes = Int64(string) else {
        return nil
      }
      return ChatUnitFormatter.fileSizeText(bytes: bytes)
    default:
      return nil
    }
  }

  private func collectionPreviewText(for content: MessageContentState,
                                     fallback: String? = nil) -> String {
    switch content {
    case let .richText(title, body):
      return [title, body]
        .compactMap { value in
          let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
    case let .reply(preview, boxed):
      let contentPreview = collectionPreviewText(for: boxed.value)
      return contentPreview.isEmpty ? preview ?? "" : contentPreview
    case let .custom(title, body):
      return [title, body]
        .compactMap { value in
          let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
    default:
      return fallback ?? ChatMessageMapper.previewText(for: content)
    }
  }

  private func bindDisplayInfoEvents() {
    guard !listenerBinder.isActive else {
      return
    }

    let contactToken = contactRepo.addContactEventListener(
      NEContactEvent(
        userProfileChanged: { [weak self] users in
          Task { @MainActor in
            let contacts = users.map { NEUserWithFriend(user: $0) }
            self?.mergeContactDisplayInfos(contacts)
          }
        },
        friendAdded: { [weak self] friend in
          Task { @MainActor in
            guard let accountId = friend.accountId else {
              return
            }
            ChatRepo.removeSwiftUIP2PDisplayUser(accountId: accountId)
            self?.mergeContactDisplayInfos([NEUserWithFriend(friend: friend)])
          }
        },
        friendDeleted: { [weak self] accountId, _ in
          Task { @MainActor in
            self?.contactDisplayInfoByAccountId.removeValue(forKey: accountId)
            self?.refreshVisibleAvatarDisplayInfos(matching: [accountId])
          }
        },
        friendInfoChanged: { [weak self] friend in
          Task { @MainActor in
            self?.mergeContactDisplayInfos([NEUserWithFriend(friend: friend)])
          }
        },
        contactChanged: { [weak self] changeType, contacts in
          Task { @MainActor in
            self?.mergeContactDisplayInfos(Self.contactDisplayInfos(from: contacts, changeType: changeType))
          }
        }
      )
    )
    listenerBinder.bind(contactToken)

    let friendCacheToken = NEFriendUserCache.shared.addFriendCacheInitListener { [weak self] in
      Task { @MainActor in
        self?.refreshVisibleAvatarDisplayInfos()
        self?.refreshContactDisplayInfosIfNeeded()
      }
    }
    listenerBinder.bind(friendCacheToken)
  }

  private func refreshContactDisplayInfosIfNeeded() {
    var seenAccountIds = Set<String>()
    let accountIds = rows.compactMap { row -> String? in
      guard let accountId = ChatAvatarDisplayResolver.nonEmpty(row.senderId),
            seenAccountIds.insert(accountId).inserted,
            !pendingContactDisplayAccountIds.contains(accountId),
            shouldLoadContactDisplayInfo(accountId: accountId) else {
        return nil
      }
      return accountId
    }
    guard !accountIds.isEmpty else {
      return
    }

    pendingContactDisplayAccountIds.formUnion(accountIds)
    ChatRepo.shared.loadSwiftUIP2PDisplayUsers(accountIds: accountIds) { [weak self] users, _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.pendingContactDisplayAccountIds.subtract(accountIds)
        self.mergeContactDisplayInfos(users ?? [])
      }
    }
  }

  private func shouldLoadContactDisplayInfo(accountId: String) -> Bool {
    if contactDisplayInfoByAccountId[accountId]?.user != nil {
      return false
    }
    return ChatAvatarDisplayResolver.info(accountId: accountId).avatarURL == nil
  }

  private func mergeContactDisplayInfos(_ users: [NEUserWithFriend]) {
    guard !users.isEmpty else {
      return
    }

    var changedAccountIds = Set<String>()
    ChatRepo.cacheSwiftUIP2PDisplayUsers(users)
    for user in users {
      guard let accountId = ChatAvatarDisplayResolver.accountId(from: user) else {
        continue
      }
      if let existing = contactDisplayInfoByAccountId[accountId] {
        contactDisplayInfoByAccountId[accountId] = mergedUserWithFriend(
          primary: user,
          fallback: existing,
          preserveFallbackFriend: user.friend != nil || NEFriendUserCache.shared.isFriend(accountId)
        )
      } else {
        contactDisplayInfoByAccountId[accountId] = user
      }
      changedAccountIds.insert(accountId)
    }
    refreshVisibleAvatarDisplayInfos(matching: changedAccountIds)
  }

  private func mergedUserWithFriend(primary: NEUserWithFriend,
                                    fallback: NEUserWithFriend,
                                    preserveFallbackFriend: Bool = true) -> NEUserWithFriend {
    NEUserWithFriend(
      user: primary.user ?? fallback.user,
      friend: primary.friend ?? (preserveFallbackFriend ? fallback.friend : nil)
    )
  }

  private static func contactDisplayInfos(from contacts: [NEUserWithFriend],
                                          changeType: NEContactChangeType) -> [NEUserWithFriend] {
    guard changeType == .deleteFriend else {
      return contacts
    }
    return contacts.compactMap { contact in
      let user = contact.user ?? contact.friend?.userProfile
      guard user != nil else {
        return nil
      }
      return NEUserWithFriend(user: user, friend: nil)
    }
  }

  private func refreshVisibleAvatarDisplayInfos(matching accountIds: Set<String>? = nil) {
    let nextRows = applyingDisplayInfos(to: rows, matching: accountIds)
    guard nextRows != rows else {
      return
    }
    rows = nextRows
  }

  private func applyingDisplayInfos(to rows: [CollectionMessageRowState],
                                    matching accountIds: Set<String>? = nil) -> [CollectionMessageRowState] {
    rows.map { row in
      guard let senderId = ChatAvatarDisplayResolver.nonEmpty(row.senderId),
            accountIds?.contains(senderId) ?? true else {
        return row
      }

      let display = ChatAvatarDisplayResolver.info(
        accountId: senderId,
        fallbackName: row.senderName,
        fallbackAvatarURL: row.avatarURL,
        loadedUser: contactDisplayInfoByAccountId[senderId]
      )
      var next = row
      if next.senderName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        next.senderName = display.displayName
      }
      if next.avatarURL == nil {
        next.avatarURL = display.avatarURL
      }
      let avatarName = ChatRepo.swiftUIDisplayName(accountId: senderId, showAlias: false)
      next.avatarName = avatarName.isEmpty ? nil : avatarName
      if var messageRow = next.messageRow,
         messageRow.senderId == senderId {
        messageRow.senderName = next.senderName ?? messageRow.senderName
        messageRow.avatarURL = next.avatarURL ?? messageRow.avatarURL
        messageRow.avatarName = next.avatarName ?? messageRow.avatarName
        next.messageRow = messageRow
      }
      return next
    }
  }

  private func iconSystemName(for content: MessageContentState?,
                              collectionType: Int) -> String {
    if let content {
      switch content {
      case .text, .richText:
        return "text.bubble"
      case .image:
        return "photo"
      case .audio:
        return "waveform"
      case .video:
        return "play.rectangle"
      case .file:
        return "doc"
      case .location:
        return "mappin.and.ellipse"
      case .call:
        return "phone"
      case .multiForward:
        return "rectangle.stack"
      case .reply:
        return "arrowshape.turn.up.left"
      case .custom:
        return "square.grid.2x2"
      case .aiStream:
        return "sparkles"
      case .revoke, .tip, .unsupported:
        return "exclamationmark.bubble"
      }
    }

    switch collectionType - collectionTypeOffset {
    case Int(V2NIMMessageType.MESSAGE_TYPE_IMAGE.rawValue):
      return "photo"
    case Int(V2NIMMessageType.MESSAGE_TYPE_AUDIO.rawValue):
      return "waveform"
    case Int(V2NIMMessageType.MESSAGE_TYPE_VIDEO.rawValue):
      return "play.rectangle"
    case Int(V2NIMMessageType.MESSAGE_TYPE_FILE.rawValue):
      return "doc"
    case Int(V2NIMMessageType.MESSAGE_TYPE_LOCATION.rawValue):
      return "mappin.and.ellipse"
    default:
      return "text.bubble"
    }
  }

  private func iconImageName(for content: MessageContentState?,
                             collectionType: Int) -> String {
    if let content {
      switch content {
      case .text, .richText:
        return "op_replay"
      case .image:
        return "photo"
      case .audio:
        return "audio_play"
      case .video:
        return "chat_video"
      case .file:
        return "chat_file"
      case .location:
        return "chat_location"
      case .call:
        return "chat_rtc"
      case .multiForward:
        return "select_multiForward"
      case .reply:
        return "op_replay"
      case .custom:
        return "op_collection"
      case .aiStream:
        return "op_collection"
      case .revoke, .tip, .unsupported:
        return "sendMessage_failed"
      }
    }

    switch collectionType - collectionTypeOffset {
    case Int(V2NIMMessageType.MESSAGE_TYPE_IMAGE.rawValue):
      return "photo"
    case Int(V2NIMMessageType.MESSAGE_TYPE_AUDIO.rawValue):
      return "audio_play"
    case Int(V2NIMMessageType.MESSAGE_TYPE_VIDEO.rawValue):
      return "chat_video"
    case Int(V2NIMMessageType.MESSAGE_TYPE_FILE.rawValue):
      return "chat_file"
    case Int(V2NIMMessageType.MESSAGE_TYPE_LOCATION.rawValue):
      return "chat_location"
    default:
      return "op_replay"
    }
  }

  private static func conversationTip(conversationName: String?,
                                      conversationType: V2NIMConversationType?,
                                      conversationId: String?) -> String? {
    guard let conversationName, !conversationName.isEmpty else {
      return nil
    }

    let resolvedType = conversationType ?? conversationId.map { V2NIMConversationIdUtil.conversationType($0) }
    switch resolvedType {
    case .CONVERSATION_TYPE_P2P:
      let format = NEChatUIKitSwiftUIBundle.localized("chat_collection_p2p_tip", value: "From Chat with %@")
      return String(format: format, conversationName)
    case .CONVERSATION_TYPE_TEAM, .CONVERSATION_TYPE_SUPER_TEAM:
      let format = NEChatUIKitSwiftUIBundle.localized("chat_collection_team_tip", value: "From %@")
      return String(format: format, conversationName)
    default:
      return conversationName
    }
  }

  private func conversationType(from value: Any?) -> V2NIMConversationType? {
    switch messageType(from: value) {
    case Int(V2NIMConversationType.CONVERSATION_TYPE_P2P.rawValue)?:
      return .CONVERSATION_TYPE_P2P
    case Int(V2NIMConversationType.CONVERSATION_TYPE_TEAM.rawValue)?:
      return .CONVERSATION_TYPE_TEAM
    case Int(V2NIMConversationType.CONVERSATION_TYPE_SUPER_TEAM.rawValue)?:
      return .CONVERSATION_TYPE_SUPER_TEAM
    default:
      return nil
    }
  }

  private static func networkToast() -> ChatToastState {
    ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
      style: .warning
    )
  }
}
