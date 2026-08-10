// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import CommonCrypto
import Combine
import Foundation
import NEChatKit
import NIMSDK

@MainActor
public final class MultiForwardMessagesViewModel: ObservableObject {
  @Published public private(set) var phase: NEChatKitLoadPhase = .idle
  @Published public private(set) var rows: [MessageRowState] = []
  @Published public private(set) var mediaDownloadProgressByRowId: [String: Double] = [:]
  @Published public var toast: ChatToastState?

  public let preview: ChatMultiForwardPreviewState

  private let chatRepo: ChatRepo
  private let resourceDownloader: ChatResourceDownloading
  private let currentAccountProvider: () -> String?
  let networkOperationGuard: () -> Bool
  private var messageContextById = [String: V2NIMMessage]()
  private var mediaDownloadGenerationByRowId = [String: Int]()

  public init(preview: ChatMultiForwardPreviewState,
              chatRepo: ChatRepo = .shared,
              resourceDownloader: ChatResourceDownloading = NEChatKitResourceDownloader(),
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() },
              networkOperationGuard: @escaping () -> Bool = { true }) {
    self.preview = preview
    self.chatRepo = chatRepo
    self.resourceDownloader = resourceDownloader
    self.currentAccountProvider = currentAccountProvider
    self.networkOperationGuard = networkOperationGuard
  }

  public func load() {
    guard phase != .loading else {
      return
    }

    phase = .loading
    let filePath = localFilePath()

    if FileManager.default.fileExists(atPath: filePath) {
      decode(filePath: filePath)
      return
    }
    guard networkOperationGuard() else {
      let message = NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
      phase = .failed(NEChatKitErrorState(code: protocolSendFailed, message: message))
      toast = ChatToastState(message: message, style: .warning)
      return
    }

    guard let url = preview.multiForward.url, !url.isEmpty else {
      apply(error: Self.error(
        code: -1,
        message: NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_url_missing", value: "Chat history file is missing")
      ))
      return
    }

    chatRepo.downloadMergedForwardFile(urlString: url, filePath: filePath) { [weak self] error in
      Task { @MainActor in
        if let error {
          self?.apply(error: error)
        } else {
          self?.decode(filePath: filePath)
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

  public func showLoadFailureToast(_ error: NEChatKitErrorState) {
    toast = ChatToastState(message: Self.loadFailureMessage(error), style: .warning)
  }

  public func shouldDownloadVideoBeforePreview(row: MessageRowState) -> Bool {
    guard case let .video(media) = row.content else {
      return false
    }
    return media.existingLocalPath == nil &&
      media.url != nil &&
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

  public func currentRow(matching row: MessageRowState) -> MessageRowState {
    rows.first { candidate in
      if candidate.id == row.id {
        return true
      }
      if let serverId = row.serverId, !serverId.isEmpty {
        return candidate.serverId == serverId || candidate.id == serverId
      }
      if let candidateServerId = candidate.serverId, !candidateServerId.isEmpty {
        return candidateServerId == row.id
      }
      return false
    } ?? row
  }

  public func downloadVideo(row: MessageRowState,
                            completion: ((MessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      let message = NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
      toast = ChatToastState(message: message, style: .warning)
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

  public func downloadFile(row: MessageRowState,
                           completion: ((MessageRowState) -> Void)? = nil) {
    guard networkOperationGuard() else {
      let message = NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
      toast = ChatToastState(message: message, style: .warning)
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
        downloaded.fileExtension = self.downloadedFileExtension(
          file: downloaded,
          localPath: resolvedPath,
          url: url
        )
        if let updatedRow = self.updateFileContent(for: row.id, file: downloaded) {
          completion?(updatedRow)
        }
      }
    }
  }

  private func decode(filePath: String) {
    if let expectedMD5 = preview.multiForward.md5,
       !expectedMD5.isEmpty,
       let actualMD5 = Self.fileMD5(atPath: filePath),
       actualMD5 != expectedMD5 {
      try? FileManager.default.removeItem(atPath: filePath)
      apply(error: Self.error(
        code: -2,
        message: NEChatUIKitSwiftUIBundle.localized("file_check_failed", value: "File check failed")
      ))
      return
    }

    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
      guard let text = String(data: data, encoding: .utf8) else {
        apply(error: Self.error(
          code: -3,
          message: NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_decode_failed", value: "Failed to decode chat history")
        ))
        return
      }

      let messages = text
        .components(separatedBy: "\n")
        .dropFirst()
        .compactMap { V2NIMMessageConverter.messageDeserialization($0) }

      rows = messages.map { message in
        var row = ChatMessageMapper.row(message: message, currentAccountId: currentAccountProvider())
        row.direction = .incoming
        row.senderName = senderName(for: message) ?? row.senderName
        row.avatarURL = senderAvatarURL(for: message)
        row.content = multiForwardDisplayContent(for: row.content, message: message)
        // Merged-forward payloads are immutable history. A deserialized
        // `.sending` state must not masquerade as an active media download.
        row.deliveryState = .sent
        row = strippingReplyState(from: row)
        row.isPinned = false
        row.isTopMessage = false
        cacheMessageContext(message, row: row)
        return row
      }
      applyTimeDividers()
      phase = rows.isEmpty ? .empty : .loaded
    } catch {
      apply(error: error)
    }
  }

  private func applyTimeDividers() {
    var previousTimestamp: TimeInterval?
    for index in rows.indices {
      guard let timestamp = rows[index].timestamp, timestamp > 0 else {
        rows[index].timeDividerText = nil
        continue
      }
      let shouldShow = previousTimestamp == nil ||
        (!rows[index].suppressesTimeDivider && timestamp - (previousTimestamp ?? timestamp) > 5 * 60)
      rows[index].timeDividerText = shouldShow ? timeText(for: timestamp) : nil
      previousTimestamp = timestamp
    }
  }

  private func timeText(for timestamp: TimeInterval) -> String {
    let date = Date(timeIntervalSince1970: timestamp)
    if Calendar.current.isDateInToday(date) {
      let formatter = DateFormatter()
      formatter.dateFormat = NEChatUIKitSwiftUIBundle.localized("hm", value: "HH:mm")
      return formatter.string(from: date)
    }
    return ChatUnitFormatter.messageTimeText(timestamp)
  }

  private func senderName(for message: V2NIMMessage) -> String? {
    guard let json = NECommonUtil.getDictionaryFromJSONString(message.serverExtension ?? "") as? [String: Any] else {
      return nil
    }
    return json[mergedMessageNickKey] as? String
  }

  private func senderAvatarURL(for message: V2NIMMessage) -> URL? {
    guard let json = NECommonUtil.getDictionaryFromJSONString(message.serverExtension ?? "") as? [String: Any] else {
      return nil
    }
    return ChatAvatarURLResolver.url(from: json[mergedMessageAvatarKey] as? String)
  }

  private func multiForwardDisplayContent(for content: MessageContentState,
                                          message: V2NIMMessage) -> MessageContentState {
    switch message.messageType {
    case .MESSAGE_TYPE_AUDIO:
      return .text(NEChatUIKitSwiftUIBundle.localized("msg_audio", value: "[Audio]"))
    case .MESSAGE_TYPE_CALL:
      if let attachment = message.attachment as? V2NIMMessageCallAttachment {
        return .text(attachment.type == 1
          ? NEChatUIKitSwiftUIBundle.localized("msg_rtc_audio", value: "[Audio Call]")
          : NEChatUIKitSwiftUIBundle.localized("msg_rtc_video", value: "[Video Call]"))
      }
      return .text(NEChatUIKitSwiftUIBundle.localized("msg_rtc_call", value: "[Call]"))
    case .MESSAGE_TYPE_TIP, .MESSAGE_TYPE_NOTIFICATION:
      return content
    default:
      return content
    }
  }

  private func strippingReplyState(from row: MessageRowState) -> MessageRowState {
    var next = row
    next.reply = nil
    if case let .reply(_, boxed) = next.content {
      next.content = boxed.value
    }
    return next
  }

  private func localFilePath() -> String {
    let directory = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") ?? NSTemporaryDirectory()
    let name = multiForwardFileName + preview.messageId
    return directory + name
  }

  private func cacheMessageContext(_ message: V2NIMMessage, row: MessageRowState) {
    messageContextById[row.id] = message
    let stableId = ChatMessageMapper.stableMessageId(for: message)
    messageContextById[stableId] = message
    if let serverId = message.messageServerId, !serverId.isEmpty {
      messageContextById[serverId] = message
    }
    if let clientId = message.messageClientId, !clientId.isEmpty {
      messageContextById[clientId] = message
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

  private func fileDownloadPath(for row: MessageRowState,
                                file: MessageFileState,
                                url: URL) -> String? {
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") else {
      return nil
    }
    let message = message(for: row)
    path += message?.messageClientId ?? downloadFileBaseName(for: row)
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
    [
      file.fileExtension,
      downloadFileExtension(preferredPath: localPath, url: url, fallbackName: file.name),
      file.normalizedFileExtension,
    ].compactMap { normalizedFileExtension($0) }.first
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

  private func apply(error: Error) {
    phase = .failed(
      NEChatErrorMessageMapper.errorState(
        for: error,
        fallbackKey: "chat_multi_forward_load_failed",
        fallbackValue: "Failed to load chat history"
      )
    )
    toast = NEChatErrorMessageMapper.toast(
      for: error,
      fallbackKey: "chat_multi_forward_load_failed",
      fallbackValue: "Failed to load chat history"
    )
  }

  private static func loadFailureMessage(_ error: NEChatKitErrorState) -> String {
    if error.code == 0 {
      return error.message
    }
    return NEChatUIKitSwiftUIBundle.localized(
      "multiForward_open_failed",
      value: "Information not retrieved."
    )
  }

  private static func error(code: Int, message: String) -> NSError {
    NSError(
      domain: NEChatUIKitSwiftUIConstants.moduleName,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private static func fileMD5(atPath path: String) -> String? {
    guard let file = FileHandle(forReadingAtPath: path) else {
      return nil
    }
    defer {
      try? file.close()
    }

    var context = CC_MD5_CTX()
    CC_MD5_Init(&context)

    while autoreleasepool(invoking: {
      let data = file.readData(ofLength: 1024)
      guard !data.isEmpty else {
        return false
      }
      _ = data.withUnsafeBytes { buffer in
        CC_MD5_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
      }
      return true
    }) {}

    var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    CC_MD5_Final(&digest, &context)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
