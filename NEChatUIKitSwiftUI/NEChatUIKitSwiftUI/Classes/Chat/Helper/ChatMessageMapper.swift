// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import AVFoundation
import Foundation
import NEChatKit
import NIMSDK

enum ChatUnitFormatter {
  private struct FormatterKey: Hashable {
    let dateFormat: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let calendarIdentifier: String
  }

  private static let formatterLock = NSLock()
  private static var formatterCache = [FormatterKey: DateFormatter]()

  static func playTime(_ seconds: TimeInterval) -> String {
    if seconds.isNaN || seconds <= 0 {
      return "00:01"
    }

    let displaySeconds = max(1, Int(seconds.rounded(.down)))
    var minutes = displaySeconds / 60
    let remainingSeconds = displaySeconds % 60
    var hours = 0
    if minutes >= 60 {
      hours = Int(minutes / 60)
      minutes -= hours * 60
      return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%02d:%02d", minutes, remainingSeconds)
  }

  static func audioDurationSeconds(_ duration: TimeInterval) -> Int {
    max(0, Int(duration.rounded()))
  }

  static func audioDurationText(_ duration: TimeInterval) -> String {
    "\(audioDurationSeconds(duration))s"
  }

  static func fileSizeText<T: BinaryInteger>(bytes: T) -> String {
    let sizeB = Double(UInt64(clamping: bytes))
    var sizeText = String(format: "%.2f B", sizeB)
    if sizeB > 1e3 {
      let sizeKB = sizeB / 1e3
      sizeText = String(format: "%.2f KB", sizeKB)
      if sizeKB > 1e3 {
        let sizeMB = sizeKB / 1e3
        sizeText = String(format: "%.2f MB", sizeMB)
        if sizeMB > 1e3 {
          let sizeGB = sizeKB / 1e6
          sizeText = String(format: "%.2f GB", sizeGB)
        }
      }
    }
    return sizeText
  }

  static func messageTimeText(_ timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }
    return dateText(Date(timeIntervalSince1970: timestamp), showHM: true)
  }

  static func historyFileDateText(_ timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }
    return formattedString(
      from: Date(timeIntervalSince1970: timestamp),
      dateFormat: localizedDateFormat("md", fallback: "MM.dd")
    )
  }

  static func historyMediaDateText(_ timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }
    return dateText(Date(timeIntervalSince1970: timestamp), showHM: false)
  }

  static func conversationTimeText(_ timestamp: TimeInterval?) -> String {
    guard let timestamp, timestamp > 0 else {
      return ""
    }

    let date = Date(timeIntervalSince1970: timestamp)
    let dateFormat: String
    if Calendar.current.isDateInToday(date) {
      dateFormat = localizedDateFormat("hm", fallback: "HH:mm")
    } else if isThisYear(date) {
      dateFormat = localizedDateFormat("mdhm", fallback: "MM.dd HH:mm")
    } else {
      dateFormat = localizedDateFormat("ymdhm", fallback: "yyyy.MM.dd HH:mm")
    }
    return formattedString(from: date, dateFormat: dateFormat)
  }

  static func recordingStopText(remainingTime: TimeInterval) -> String {
    let format = NEChatUIKitSwiftUIBundle.localized(
      "stop_record",
      value: "Recording will stop after %d"
    )
    return String(format: format, max(0, Int(remainingTime)))
  }

  private static func dateText(_ date: Date, showHM: Bool) -> String {
    let dateFormat: String
    if showHM, Calendar.current.isDateInToday(date) {
      dateFormat = localizedDateFormat("hm", fallback: "HH:mm")
    } else if let firstDayYear = firstDayInYear(), date.timeIntervalSince(firstDayYear) > 0 {
      dateFormat = showHM
        ? localizedDateFormat("mdhm", fallback: "MM.dd HH:mm")
        : localizedDateFormat("md", fallback: "MM.dd")
    } else {
      dateFormat = showHM
        ? localizedDateFormat("ymdhm", fallback: "yyyy.MM.dd HH:mm")
        : localizedDateFormat("ymd", fallback: "yyyy.MM.dd")
    }
    return formattedString(from: date, dateFormat: dateFormat)
  }

  private static func firstDayInYear() -> Date? {
    let calendar = Calendar.current
    let year = calendar.component(.year, from: Date())
    return calendar.date(from: DateComponents(year: year, month: 1, day: 1))
  }

  private static func isThisYear(_ date: Date) -> Bool {
    Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
  }

  private static func localizedDateFormat(_ key: String, fallback: String) -> String {
    NEChatUIKitSwiftUIBundle.localized(key, value: fallback)
  }

  private static func formattedString(from date: Date, dateFormat: String) -> String {
    let locale = Locale.current
    let timeZone = TimeZone.current
    let calendar = Calendar.current
    let key = FormatterKey(
      dateFormat: dateFormat,
      localeIdentifier: locale.identifier,
      timeZoneIdentifier: timeZone.identifier,
      calendarIdentifier: String(describing: calendar.identifier)
    )

    formatterLock.lock()
    defer { formatterLock.unlock() }
    if let formatter = formatterCache[key] {
      return formatter.string(from: date)
    }

    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.calendar = calendar
    formatter.dateFormat = dateFormat
    formatterCache[key] = formatter
    return formatter.string(from: date)
  }
}

public enum ChatMessageMapper {
  private static let defaultImageThumbSize = 350

  public static func stableMessageId(for message: V2NIMMessage) -> String {
    if let clientId = message.messageClientId, !clientId.isEmpty {
      return clientId
    }
    if let serverId = message.messageServerId, !serverId.isEmpty {
      return serverId
    }
    let sender = message.senderId ?? ""
    let time = message.createTime
    return "\(sender)-\(time)"
  }

  public static func row(message: V2NIMMessage,
                         currentAccountId: String? = IMKitClient.instance.account(),
                         imageThumbSize: Int = 350) -> MessageRowState {
    let senderId = displaySenderId(for: message)
    let isRevoke = isRevokeMessage(message)
    let direction = message.messageType == .MESSAGE_TYPE_TIP || message.messageType == .MESSAGE_TYPE_NOTIFICATION
      ? MessageDirection.system
      : (senderId == currentAccountId ? .outgoing : .incoming)
    let deliveryState = deliveryState(for: message)
    let replyReference = ChatRepo.shared.replyReference(from: message)
    let suppressesDisplayedReply = shouldSuppressDisplayedReply(for: message)

    return MessageRowState(
      id: stableMessageId(for: message),
      serverId: message.messageServerId,
      conversationId: message.conversationId,
      senderId: senderId,
      senderName: displayName(for: senderId, isTeamMessage: message.conversationType == .CONVERSATION_TYPE_TEAM),
      avatarURL: displayAvatarURL(for: senderId),
      avatarName: displayName(for: senderId, isTeamMessage: false, showAlias: false),
      direction: direction,
      content: content(for: message, imageThumbSize: imageThumbSize),
      deliveryState: deliveryState,
      isSendFailureRetryable: message.sendingState == .MESSAGE_SENDING_STATE_FAILED,
      isReadReceiptEnabled: isReadReceiptEnabled(for: message),
      timestamp: message.createTime,
      suppressesTimeDivider: suppressesTimeDivider(for: message),
      textHighlights: textHighlights(for: message),
      isAIResponse: isAIResponseMessage(message),
      aiTriggerSenderId: message.threadReply?.senderId ?? replyReference?.senderId,
      reply: isRevoke || isSystemMessage(message) || suppressesDisplayedReply
        ? nil
        : replyState(for: message, reference: replyReference),
      reedit: reeditState(for: message),
      topicRefer: topicReferState(for: message.topicRefer),
      customPayload: customPayloadState(for: message)
    )
  }

  private static func isSystemMessage(_ message: V2NIMMessage) -> Bool {
    message.messageType == .MESSAGE_TYPE_TIP ||
      message.messageType == .MESSAGE_TYPE_NOTIFICATION
  }

  public static func fallbackTextRow(message: V2NIMMessage,
                                     currentAccountId: String?,
                                     imageThumbSize: Int = 350) -> MessageRowState {
    row(message: message, currentAccountId: currentAccountId, imageThumbSize: imageThumbSize)
  }

  public static func pendingTextRow(id: String,
                                    conversationId: String,
                                    senderId: String?,
                                    text: String,
                                    richTextTitle: String? = nil,
                                    progress: Double? = nil,
                                    mentions: [ChatMentionState] = []) -> MessageRowState {
    let trimmedRichTextTitle = richTextTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return MessageRowState(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: displayName(for: senderId, isTeamMessage: false),
      avatarURL: displayAvatarURL(for: senderId),
      avatarName: displayName(for: senderId, isTeamMessage: false, showAlias: false),
      direction: .outgoing,
      content: trimmedRichTextTitle.isEmpty ? .text(text) : .richText(title: trimmedRichTextTitle, body: text),
      deliveryState: .pending(progress: progress),
      timestamp: Date().timeIntervalSince1970,
      textHighlights: mentionHighlights(from: mentions, in: text)
    )
  }

  public static func pendingRow(id: String,
                                conversationId: String,
                                senderId: String?,
                                payload: ChatOutgoingMessagePayload,
                                progress: Double? = nil) -> MessageRowState {
    MessageRowState(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: displayName(for: senderId, isTeamMessage: false),
      avatarURL: displayAvatarURL(for: senderId),
      avatarName: displayName(for: senderId, isTeamMessage: false, showAlias: false),
      direction: .outgoing,
      content: content(from: payload),
      deliveryState: .pending(progress: progress),
      timestamp: Date().timeIntervalSince1970,
      customPayload: customPayloadState(from: payload)
    )
  }

  private static func suppressesTimeDivider(for message: V2NIMMessage) -> Bool {
    message.messageType == .MESSAGE_TYPE_NOTIFICATION &&
      message.attachment is V2NIMMessageNotificationAttachment
  }

  public static func previewText(for content: MessageContentState) -> String {
    switch content {
    case let .text(text):
      return text
    case let .richText(title, body):
      return title?.isEmpty == false ? title ?? body : body
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("chat_message_image", value: "[Image]")
    case .audio:
      // Voice-to-text is a transient chat-row presentation detail. UIKit keeps
      // reply, forward, pin, collection and search summaries as an audio message.
      return NEChatUIKitSwiftUIBundle.localized("chat_message_audio", value: "[Audio]")
    case let .video(media):
      return videoPreviewText(media: media)
    case let .file(file):
      return file.name
    case let .location(location):
      return location.title
    case let .call(call):
      return call.summary
    case let .custom(title, body):
      return [title, body].compactMap { $0 }.joined(separator: " ")
    case let .multiForward(multiForward):
      return multiForward.title
    case let .reply(preview, boxed):
      let contentPreview = previewText(for: boxed.value)
      return contentPreview.isEmpty ? preview ?? "" : contentPreview
    case let .revoke(text), let .tip(text), let .unsupported(text):
      return text
    case let .aiStream(text, _, _):
      return text
    }
  }

  public static func referencePreviewText(for content: MessageContentState) -> String {
    switch content {
    case .image:
      return NEChatUIKitSwiftUIBundle.localized("msg_image", value: "[Photo]")
    case .audio:
      return NEChatUIKitSwiftUIBundle.localized("msg_audio", value: "[Voice]")
    case .video:
      return NEChatUIKitSwiftUIBundle.localized("msg_video", value: "[Video]")
    case .file:
      return NEChatUIKitSwiftUIBundle.localized("msg_file", value: "[File]")
    case let .location(location):
      let type = NEChatUIKitSwiftUIBundle.localized("msg_location", value: "[Location]")
      return location.title.isEmpty ? type : "\(type) \(location.title)"
    case .multiForward:
      let title = NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History")
      return "[\(title)]"
    case let .reply(_, boxed):
      return referencePreviewText(for: boxed.value)
    default:
      return previewText(for: content)
    }
  }

  public static func replacingDeliveryState(_ row: MessageRowState,
                                            with deliveryState: MessageDeliveryState) -> MessageRowState {
    var next = row
    next.deliveryState = deliveryState
    return next
  }

  public static func applyingKeywordHighlight(to row: MessageRowState,
                                              keyword: String) -> MessageRowState {
    let source = keywordHighlightSource(for: row.content)
    let keywordHighlights = keywordHighlights(in: source.text, keyword: keyword)
    guard !keywordHighlights.isEmpty else {
      return row
    }
    var next = row
    let existingHighlights: [MessageTextHighlightState]
    if let richTextBodyOffset = source.richTextBodyOffset,
       !row.textHighlights.contains(where: { $0.kind == .keyword }) {
      existingHighlights = row.textHighlights.map { highlight in
        MessageTextHighlightState(
          start: highlight.start + richTextBodyOffset,
          end: highlight.end + richTextBodyOffset,
          kind: highlight.kind
        )
      }
    } else {
      existingHighlights = row.textHighlights
    }
    let preservedHighlights = existingHighlights
      .filter { $0.kind != .keyword }
      .flatMap { existing in
        subtractingKeywordHighlights(keywordHighlights, from: existing)
      }
    next.textHighlights = normalizedHighlights(preservedHighlights + keywordHighlights)
    return next
  }

  private static func subtractingKeywordHighlights(_ keywordHighlights: [MessageTextHighlightState],
                                                   from existing: MessageTextHighlightState) -> [MessageTextHighlightState] {
    let remainingRanges = keywordHighlights.reduce([existing.range]) { ranges, keyword in
      ranges.flatMap { range -> [Range<Int>] in
        guard range.overlaps(keyword.range) else {
          return [range]
        }

        var remaining = [Range<Int>]()
        if range.lowerBound < keyword.start {
          remaining.append(range.lowerBound ..< min(range.upperBound, keyword.start))
        }
        if keyword.end < range.upperBound {
          remaining.append(max(range.lowerBound, keyword.end) ..< range.upperBound)
        }
        return remaining
      }
    }

    return remainingRanges.map { range in
      MessageTextHighlightState(start: range.lowerBound, end: range.upperBound, kind: existing.kind)
    }
  }

  private static func keywordHighlightSource(for content: MessageContentState) -> (text: String, richTextBodyOffset: Int?) {
    switch content {
    case let .richText(title, body):
      let displayTitle = title?.isEmpty == false ? title ?? "" : ""
      let separator = !displayTitle.isEmpty && !body.isEmpty ? "\n" : ""
      return (displayTitle + separator + body, displayTitle.count + separator.count)
    case let .reply(_, boxed):
      return keywordHighlightSource(for: boxed.value)
    default:
      return (previewText(for: content), nil)
    }
  }

  public static func keywordHighlights(in text: String,
                                       keyword: String) -> [MessageTextHighlightState] {
    let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !normalizedKeyword.isEmpty else {
      return []
    }

    let escapedKeyword = NSRegularExpression.escapedPattern(for: normalizedKeyword)
    guard let regex = try? NSRegularExpression(pattern: escapedKeyword, options: []) else {
      return []
    }

    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return regex.matches(in: text, options: [], range: range).compactMap { match in
      guard let matchRange = Range(match.range, in: text) else {
        return nil
      }
      let start = text.distance(from: text.startIndex, to: matchRange.lowerBound)
      let end = text.distance(from: text.startIndex, to: matchRange.upperBound)
      guard start < end else {
        return nil
      }
      return MessageTextHighlightState(start: start, end: end, kind: .keyword)
    }
  }

  public static func isRevokeMessage(_ message: V2NIMMessage) -> Bool {
    revokeTextIfNeeded(message) != nil
  }

  private static func content(for message: V2NIMMessage,
                              imageThumbSize: Int = defaultImageThumbSize) -> MessageContentState {
    if let revokeText = revokeTextIfNeeded(message) {
      return .revoke(revokeText)
    }

    if message.messageType == .MESSAGE_TYPE_TEXT,
       isAIResponseMessage(message),
       let aiConfig = message.aiConfig,
       aiConfig.aiStream || aiConfig.aiStreamStatus != .MESSAGE_AI_STREAM_STATUS_NONE {
      let messageText = aiConfig.aiStreamStatus == .MESSAGE_AI_STREAM_STATUS_PLACEHOLDER
        ? ""
        : aiResponseText(for: message)
      return .aiStream(
        text: messageText,
        isFinished: aiConfig.aiStreamStatus != .MESSAGE_AI_STREAM_STATUS_PLACEHOLDER &&
          aiConfig.aiStreamStatus != .MESSAGE_AI_STREAM_STATUS_STREAMING,
        error: nil
      )
    }

    switch message.messageType {
    case .MESSAGE_TYPE_TEXT:
      let content: MessageContentState = aiTextContentIfNeeded(for: message) ??
        .text(normalizedAIUnsupportedText(message.text ?? ""))
      return wrappingReplyIfNeeded(content, for: message)
    case .MESSAGE_TYPE_IMAGE:
      return wrappingReplyIfNeeded(.image(mediaState(
        from: message.attachment as? V2NIMMessageImageAttachment,
        imageThumbSize: imageThumbSize
      )), for: message)
    case .MESSAGE_TYPE_AUDIO:
      return wrappingReplyIfNeeded(.audio(audioState(from: message.attachment as? V2NIMMessageAudioAttachment)), for: message)
    case .MESSAGE_TYPE_VIDEO:
      return wrappingReplyIfNeeded(.video(mediaState(from: message.attachment as? V2NIMMessageVideoAttachment)), for: message)
    case .MESSAGE_TYPE_FILE:
      return wrappingReplyIfNeeded(.file(fileState(from: message.attachment as? V2NIMMessageFileAttachment)), for: message)
    case .MESSAGE_TYPE_LOCATION:
      return wrappingReplyIfNeeded(.location(locationState(from: message)), for: message)
    case .MESSAGE_TYPE_CALL:
      return wrappingReplyIfNeeded(.call(callState(from: message)), for: message)
    case .MESSAGE_TYPE_CUSTOM:
      return wrappingReplyIfNeeded(customContent(from: message), for: message)
    case .MESSAGE_TYPE_TIP:
      if isAIResponseMessage(message) || isRobotMessage(message) {
        return .tip(aiResponseText(for: message))
      }
      return .tip(normalizedAIUnsupportedText(
        message.text ?? NEChatUIKitSwiftUIBundle.localized("chat_message_tip", value: "Tip")
      ))
    case .MESSAGE_TYPE_NOTIFICATION:
      return .tip(notificationText(for: message))
    default:
      return wrappingReplyIfNeeded(.unsupported(unknownMessageText()), for: message)
    }
  }

  private static func textHighlights(for message: V2NIMMessage) -> [MessageTextHighlightState] {
    guard IMKitConfigCenter.shared.enableAtMessage,
          message.aiConfig?.aiStatus != .MESSAGE_AI_STATUS_RESPONSE,
          let text = textForHighlights(in: message),
          !text.isEmpty else {
      return []
    }

    return mentionHighlights(fromServerExtension: message.serverExtension, in: text)
  }

  private static func textForHighlights(in message: V2NIMMessage) -> String? {
    if message.messageType == .MESSAGE_TYPE_TEXT {
      return message.text
    }
    if message.messageType == .MESSAGE_TYPE_CUSTOM,
       NECustomUtils.typeOfCustomMessage(message.attachment) == customRichTextType {
      return NECustomUtils.bodyOfRichText(message.attachment) ?? ""
    }
    return nil
  }

  static func mentionHighlights(fromServerExtension serverExtension: String?,
                                in text: String) -> [MessageTextHighlightState] {
    guard let serverExtension,
          let data = serverExtension.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let mentionDictionary = json["yxAitMsg"] as? [String: Any] else {
      return []
    }

    var highlights = [MessageTextHighlightState]()
    for value in mentionDictionary.values {
      guard let dictionary = dictionaryValue(value),
            let segments = dictionary["segments"] as? [Any] else {
        continue
      }
      let displayText = mentionDisplayText(from: dictionary)
      highlights.append(contentsOf: segments.compactMap { value in
        guard let segment = dictionaryValue(value) else {
          return nil
        }
        guard let start = integerValue(segment["start"]),
              let end = integerValue(segment["end"]) else {
          return nil
        }
        return mentionHighlightFromServerExtension(
          start: start,
          end: end,
          displayText: mentionDisplayText(from: segment) ?? displayText,
          in: text
        )
      })
    }

    return normalizedHighlights(highlights)
  }

  static func mentionStates(fromServerExtension serverExtension: String?,
                            in text: String) -> [ChatMentionState] {
    guard let serverExtension,
          let data = serverExtension.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let mentionDictionary = json["yxAitMsg"] as? [String: Any] else {
      return []
    }

    var mentions = [ChatMentionState]()
    for (accountId, value) in mentionDictionary {
      guard !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let dictionary = dictionaryValue(value),
            let segments = dictionary["segments"] as? [Any] else {
        continue
      }
      let displayText = mentionDisplayText(from: dictionary)
      for segmentValue in segments {
        guard let segment = dictionaryValue(segmentValue),
              let start = integerValue(segment["start"]),
              let end = integerValue(segment["end"]),
              let highlight = mentionHighlightFromServerExtension(
                start: start,
                end: end,
                displayText: mentionDisplayText(from: segment) ?? displayText,
                in: text
              ),
              highlight.start < highlight.end,
              let restoredText = substring(in: text, range: highlight.range) else {
          continue
        }
        let lower = text.index(text.startIndex, offsetBy: highlight.start)
        let upper = text.index(text.startIndex, offsetBy: highlight.end)
        let utf16Range = NSRange(lower ..< upper, in: text)
        mentions.append(ChatMentionState(
          accountId: accountId,
          displayText: restoredText.trimmingCharacters(in: .whitespaces),
          start: utf16Range.location,
          end: NSMaxRange(utf16Range) - 1
        ))
      }
    }

    var normalized = [ChatMentionState]()
    for mention in mentions.sorted(by: { left, right in
      left.start == right.start ? left.end < right.end : left.start < right.start
    }) where !normalized.contains(where: { existing in
      existing.start ... existing.end ~= mention.start || mention.start ... mention.end ~= existing.start
    }) {
      normalized.append(mention)
    }
    return normalized
  }

  private static func dictionaryValue(_ value: Any) -> [String: Any]? {
    if let dictionary = value as? [String: Any] {
      return dictionary
    }
    if let dictionary = value as? NSDictionary {
      return dictionary as? [String: Any]
    }
    return nil
  }

  private static func mentionHighlights(from mentions: [ChatMentionState],
                                        in text: String) -> [MessageTextHighlightState] {
    normalizedHighlights(mentions.compactMap { mention in
      mentionHighlightFromServerExtension(
        start: mention.start,
        end: mention.end,
        displayText: mention.displayText,
        in: text
      )
    })
  }

  private static func mentionHighlightFromServerExtension(start: Int,
                                                          end: Int,
                                                          displayText: String?,
                                                          in text: String) -> MessageTextHighlightState? {
    guard start >= 0, start <= end else {
      return nil
    }

    let candidates = [
      start ..< end,
      start ..< (end + 1),
    ]

    for candidate in candidates {
      guard let range = characterRange(fromUTF16Start: candidate.lowerBound, utf16End: candidate.upperBound, in: text),
            mentionRange(range, matches: displayText, in: text) else {
        continue
      }
      return MessageTextHighlightState(start: range.lowerBound, end: range.upperBound, kind: .mention)
    }

    for candidate in candidates {
      guard candidate.upperBound <= text.count,
            candidate.lowerBound < candidate.upperBound,
            mentionRange(candidate, matches: displayText, in: text) else {
        continue
      }
      return MessageTextHighlightState(start: candidate.lowerBound, end: candidate.upperBound, kind: .mention)
    }

    if let fallbackRange = mentionFallbackRange(displayText: displayText, near: start, in: text) {
      return MessageTextHighlightState(start: fallbackRange.lowerBound, end: fallbackRange.upperBound, kind: .mention)
    }

    return nil
  }

  private static func mentionHighlightFromCharacterRange(start: Int,
                                                         end: Int,
                                                         displayText: String?,
                                                         in text: String) -> MessageTextHighlightState? {
    guard start >= 0, start <= end else {
      return nil
    }

    let candidates = [
      start ..< end,
      start ..< (end + 1),
    ]

    for candidate in candidates {
      guard candidate.upperBound <= text.count,
            candidate.lowerBound < candidate.upperBound,
            mentionRange(candidate, matches: displayText, in: text) else {
        continue
      }
      return MessageTextHighlightState(start: candidate.lowerBound, end: candidate.upperBound, kind: .mention)
    }

    if let fallbackRange = mentionFallbackRange(displayText: displayText, near: start, in: text) {
      return MessageTextHighlightState(start: fallbackRange.lowerBound, end: fallbackRange.upperBound, kind: .mention)
    }

    return nil
  }

  public static func mentionHighlightRange(start: Int,
                                           end: Int,
                                           displayText: String?,
                                           in text: String) -> MessageTextHighlightState? {
    mentionHighlightFromServerExtension(start: start, end: end, displayText: displayText, in: text)
  }

  private static func characterRange(fromUTF16Start start: Int,
                                     utf16End end: Int,
                                     in text: String) -> Range<Int>? {
    guard start >= 0,
          start < end,
          end <= text.utf16.count,
          let lowerUTF16 = text.utf16.index(text.utf16.startIndex, offsetBy: start, limitedBy: text.utf16.endIndex),
          let upperUTF16 = text.utf16.index(text.utf16.startIndex, offsetBy: end, limitedBy: text.utf16.endIndex),
          let lower = String.Index(lowerUTF16, within: text),
          let upper = String.Index(upperUTF16, within: text) else {
      return nil
    }

    let lowerOffset = text.distance(from: text.startIndex, to: lower)
    let upperOffset = text.distance(from: text.startIndex, to: upper)
    guard lowerOffset < upperOffset else {
      return nil
    }
    return lowerOffset ..< upperOffset
  }

  private static func mentionRange(_ range: Range<Int>,
                                   matches displayText: String?,
                                   in text: String) -> Bool {
    guard range.lowerBound >= 0,
          range.lowerBound < range.upperBound,
          range.upperBound <= text.count else {
      return false
    }

    guard let displayText,
          !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let substring = substring(in: text, range: range) else {
      return true
    }

    guard substring.first?.isWhitespace != true else {
      return false
    }

    let expected = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    let actual = substring.trimmingCharacters(in: .whitespacesAndNewlines)
    return actual == expected
  }

  private static func substring(in text: String,
                                range: Range<Int>) -> String? {
    guard range.lowerBound >= 0,
          range.lowerBound <= range.upperBound,
          range.upperBound <= text.count else {
      return nil
    }
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    return String(text[lower ..< upper])
  }

  private static func mentionFallbackRange(displayText: String?,
                                           near start: Int,
                                           in text: String) -> Range<Int>? {
    guard let displayText else {
      return nil
    }
    let expected = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !expected.isEmpty else {
      return nil
    }

    var ranges = [Range<Int>]()
    var searchStart = text.startIndex
    while searchStart < text.endIndex,
          let range = text.range(of: expected, range: searchStart ..< text.endIndex) {
      ranges.append(
        text.distance(from: text.startIndex, to: range.lowerBound) ..<
          text.distance(from: text.startIndex, to: range.upperBound)
      )
      searchStart = range.upperBound
    }

    return ranges.min { lhs, rhs in
      abs(lhs.lowerBound - start) < abs(rhs.lowerBound - start)
    }
  }

  private static func mentionDisplayText(from segment: [String: Any]) -> String? {
    for key in ["text", "displayText", "name", "nick", "nickName", "account", "accountId"] {
      guard let value = segment[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        continue
      }
      return value
    }
    return nil
  }

  private static func normalizedHighlights(_ highlights: [MessageTextHighlightState]) -> [MessageTextHighlightState] {
    var result = [MessageTextHighlightState]()
    for highlight in highlights.sorted(by: { left, right in
      if left.start == right.start {
        return left.end < right.end
      }
      return left.start < right.start
    }) {
      guard highlight.start < highlight.end,
            result.last?.range.overlaps(highlight.range) != true else {
        continue
      }
      result.append(highlight)
    }
    return result
  }

  private static func integerValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }

  private static func aiStreamText(for message: V2NIMMessage) -> String {
    let text = message.text ?? ""
    guard message.aiConfig?.aiStreamStatus == .MESSAGE_AI_STREAM_STATUS_ABORTED, text.isEmpty else {
      return text
    }
    return NEChatUIKitSwiftUIBundle.localized(
      "server_busy",
      value: "Sorry, the server is busy, please try again later."
    )
  }

  private static func aiResponseText(for message: V2NIMMessage) -> String {
    let serverText = aiStreamText(for: message)
    if let errorMessage = NEChatErrorMessageMapper.aiMessage(
      for: message.messageStatus.errorCode,
      serverText: serverText
    ) {
      return errorMessage
    }
    return normalizedAIUnsupportedText(serverText)
  }

  private static func normalizedAIUnsupportedText(_ text: String) -> String {
    guard isUnsupportedAIResponseText(text) else {
      return text
    }
    return NEChatUIKitSwiftUIBundle.localized(
      "format_not_supported",
      value: "Invalid Type"
    )
  }

  private static func isUnsupportedAIResponseText(_ text: String) -> Bool {
    let punctuation = CharacterSet(charactersIn: ".!?;:。！？；：")
    let normalized = text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: punctuation)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return normalized == "ai messages must be of text"
  }

  private static func aiTextContentIfNeeded(for message: V2NIMMessage) -> MessageContentState? {
    guard message.messageType == .MESSAGE_TYPE_TEXT,
          isAIResponseMessage(message) || isRobotMessage(message) else {
      return nil
    }
    return .aiStream(
      text: aiResponseText(for: message),
      isFinished: true,
      error: nil
    )
  }

  private static func isAIResponseMessage(_ message: V2NIMMessage) -> Bool {
    message.aiConfig?.aiStatus == .MESSAGE_AI_STATUS_RESPONSE
  }

  private static func isRobotMessage(_ message: V2NIMMessage) -> Bool {
    guard let senderId = message.senderId, !senderId.isEmpty else {
      return false
    }
    return NEAIRobotManager.shared.isRobot(senderId)
  }

  static func notificationText(for message: V2NIMMessage,
                               displayNameProvider: ((String) -> String?)? = nil) -> String {
    ChatRepo.shared.swiftUINotificationText(
      for: message,
      displayNameProvider: displayNameProvider
    ) { key, value in
      NEChatUIKitSwiftUIBundle.localized(key, value: value)
    } ?? message.text ?? NEChatUIKitSwiftUIBundle.localized("chat_message_notification", value: "Notification")
  }

  private static func content(from payload: ChatOutgoingMessagePayload) -> MessageContentState {
    switch payload {
    case let .image(path, _, width, height):
      return .image(MessageMediaState(localPath: path, width: Double(width), height: Double(height)))
    case let .audio(filePath, _, duration):
      return .audio(MessageAudioState(duration: TimeInterval(duration) / 1000.0, localPath: filePath))
    case let .video(filePath, _, width, height, duration):
      return .video(MessageMediaState(
        localPath: filePath,
        width: Double(width),
        height: Double(height),
        duration: normalizedVideoDuration(duration, localPath: filePath)
      ))
    case let .file(filePath, displayName):
      return .file(MessageFileState(name: displayName ?? URL(fileURLWithPath: filePath).lastPathComponent, localPath: filePath))
    case let .location(latitude, longitude, title, address):
      return .location(MessageLocationState(latitude: latitude, longitude: longitude, title: title, subtitle: address))
    case let .call(_, type, _, _, _):
      return .call(MessageCallState(summary: callSummary(type: type), type: type))
    case let .custom(text, _):
      return .custom(
        title: NEChatUIKitSwiftUIBundle.localized("chat_message_custom", value: "Custom message"),
        body: text
      )
    }
  }

  private static func mediaState(from attachment: V2NIMMessageImageAttachment?,
                                 imageThumbSize: Int = defaultImageThumbSize) -> MessageMediaState {
    MessageMediaState(
      url: url(from: attachment?.url),
      localPath: existingPath(attachment?.path),
      thumbnailURL: imageThumbnailURL(from: attachment, imageThumbSize: imageThumbSize),
      width: attachment.map { Double($0.width) },
      height: attachment.map { Double($0.height) }
    )
  }

  private static func imageThumbnailURL(from attachment: V2NIMMessageImageAttachment?,
                                        imageThumbSize: Int) -> URL? {
    guard let rawURL = attachment?.url, !rawURL.isEmpty else {
      return nil
    }
    let normalizedExt = attachment?.ext?
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .lowercased()
    guard normalizedExt != "gif", imageThumbSize > 0 else {
      return url(from: rawURL)
    }
    return url(from: V2NIMStorageUtil.imageThumbUrl(rawURL, thumbSize: imageThumbSize))
  }

  private static func mediaState(from attachment: V2NIMMessageVideoAttachment?) -> MessageMediaState {
    let videoUrl = Self.url(from: attachment?.url)
    let localPath = existingPath(attachment?.path)
    let coverUrl: URL?
    if let rawUrl = attachment?.url, !rawUrl.isEmpty {
      coverUrl = Self.url(from: V2NIMStorageUtil.videoCoverUrl(rawUrl, offset: 0))
    } else {
      coverUrl = videoUrl
    }
    return MessageMediaState(
      url: videoUrl,
      localPath: localPath,
      thumbnailURL: coverUrl,
      width: attachment.map { Double($0.width) },
      height: attachment.map { Double($0.height) },
      duration: attachment.map { normalizedVideoDuration($0.duration, localPath: localPath) }
    )
  }

  private static func audioState(from attachment: V2NIMMessageAudioAttachment?) -> MessageAudioState {
    MessageAudioState(
      duration: attachment.map { normalizedAudioDuration($0.duration) } ?? 0,
      localPath: existingPath(attachment?.path),
      url: url(from: attachment?.url)
    )
  }

  private static func normalizedAudioDuration<T: BinaryInteger>(_ rawDuration: T) -> TimeInterval {
    let value = TimeInterval(rawDuration)
    guard value > 0 else {
      return 0
    }
    return value / 1000.0
  }

  private static func normalizedVideoDuration<T: BinaryInteger>(_ rawDuration: T,
                                                                localPath: String?) -> TimeInterval {
    let rawValue = TimeInterval(rawDuration)
    let localDuration = videoDuration(localPath: localPath)
    guard rawValue > 0 else {
      return localDuration ?? 0
    }

    if let localDuration {
      let millisecondDuration = rawValue / 1000.0
      if durationsMatch(millisecondDuration, localDuration) {
        return millisecondDuration
      }
      if durationsMatch(rawValue, localDuration) {
        return rawValue
      }
      return localDuration
    }

    return rawValue >= 1000 ? rawValue / 1000.0 : rawValue
  }

  private static func durationsMatch(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
    abs(lhs - rhs) <= max(1, rhs * 0.1)
  }

  private static func videoDuration(localPath: String?) -> TimeInterval? {
    guard let localPath,
          !localPath.isEmpty,
          FileManager.default.fileExists(atPath: localPath) else {
      return nil
    }
    let duration = AVURLAsset(url: URL(fileURLWithPath: localPath)).duration.seconds
    guard duration.isFinite, duration > 0 else {
      return nil
    }
    return duration
  }

  private static func videoPreviewText(media: MessageMediaState) -> String {
    let title = NEChatUIKitSwiftUIBundle.localized("chat_message_video", value: "[Video]")
    guard let duration = media.duration, duration > 0 else {
      return title
    }
    return "\(title) \(ChatUnitFormatter.playTime(duration))"
  }

  private static func fileState(from attachment: V2NIMMessageFileAttachment?) -> MessageFileState {
    MessageFileState(
      name: attachment?.name ?? NEChatUIKitSwiftUIBundle.localized("chat_message_file", value: "File"),
      sizeText: attachment.map { ChatUnitFormatter.fileSizeText(bytes: $0.size) },
      url: url(from: attachment?.url),
      localPath: existingPath(attachment?.path),
      fileExtension: attachment?.ext
    )
  }

  private static func locationState(from message: V2NIMMessage) -> MessageLocationState {
    let attachment = message.attachment as? V2NIMMessageLocationAttachment
    let mapImageURL = attachment.flatMap {
      NEChatKitClient.instance.getMapImageUrl(lat: $0.latitude, lng: $0.longitude)
    }
    return MessageLocationState(
      latitude: attachment?.latitude,
      longitude: attachment?.longitude,
      title: message.text ?? attachment?.address ?? NEChatUIKitSwiftUIBundle.localized("chat_location_unavailable", value: "Location"),
      subtitle: attachment?.address,
      thumbnailURL: url(from: mapImageURL)
    )
  }

  private static func customContent(from message: V2NIMMessage) -> MessageContentState {
    if let type = NECustomUtils.typeOfCustomMessage(message.attachment) {
      if type == customRichTextType {
        let title = NECustomUtils.titleOfRichText(message.attachment)
        let body = NECustomUtils.bodyOfRichText(message.attachment) ?? ""
        return .richText(title: title, body: body)
      }

      if type == customMultiForwardType {
        let data = NECustomUtils.dataOfCustomMessage(message.attachment)
        let sessionName = data?["sessionName"] as? String
        let summaries = multiForwardSummaries(from: data?["abstracts"])
        return .multiForward(
          MessageMultiForwardState(
            title: sessionName ?? NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History"),
            hasSessionName: sessionName != nil,
            url: data?["url"] as? String,
            md5: data?["md5"] as? String,
            depth: data?["depth"] as? Int ?? 0,
            sessionId: data?["sessionId"] as? String,
            summaries: summaries
          )
        )
      }

      return .unsupported(unknownMessageText())
    }

    return .unsupported(unknownMessageText())
  }

  private static func unknownMessageText() -> String {
    NEChatUIKitSwiftUIBundle.localized("msg_unknown", value: "[Unknown Message]")
  }

  private static func customPayloadState(for message: V2NIMMessage) -> ChatCustomMessagePayloadState? {
    guard message.messageType == .MESSAGE_TYPE_CUSTOM else {
      return nil
    }

    let payload = NECustomUtils.attachmentOfCustomMessage(message.attachment)
    return ChatCustomMessagePayloadState(
      type: NECustomUtils.typeOfCustomMessage(message.attachment),
      rawAttachment: message.attachment?.raw,
      customHeight: NECustomUtils.heightOfCustomMessage(message.attachment).map(Double.init),
      payload: ChatCustomPayloadValue.object(from: payload),
      data: ChatCustomPayloadValue.object(from: payload?["data"])
    )
  }

  private static func customPayloadState(from payload: ChatOutgoingMessagePayload) -> ChatCustomMessagePayloadState? {
    guard case let .custom(_, rawAttachment) = payload,
          let payload = NECustomUtils.getDictionaryFromJSONString(rawAttachment) else {
      return nil
    }

    return ChatCustomMessagePayloadState(
      type: payload["type"] as? Int,
      rawAttachment: rawAttachment,
      customHeight: doubleValue(payload["customHeight"]),
      payload: ChatCustomPayloadValue.object(from: payload),
      data: ChatCustomPayloadValue.object(from: payload["data"])
    )
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let float = value as? Float {
      return Double(float)
    }
    if let int = value as? Int {
      return Double(int)
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  private static func callState(from message: V2NIMMessage) -> MessageCallState {
    let attachment = message.attachment as? V2NIMMessageCallAttachment
    guard let attachment else {
      return MessageCallState(
        summary: NEChatUIKitSwiftUIBundle.localized("msg_rtc_call", value: "[Call]"),
        type: 0
      )
    }
    return MessageCallState(
      summary: callSummary(
        type: attachment.type,
        status: attachment.status,
        duration: callDuration(from: attachment.durations, senderId: message.senderId)
      ),
      type: attachment.type
    )
  }

  private static func callSummary(type: Int) -> String {
    type == 1
      ? NEChatUIKitSwiftUIBundle.localized("msg_rtc_audio", value: "[Audio Call]")
      : NEChatUIKitSwiftUIBundle.localized("msg_rtc_video", value: "[Video Call]")
  }

  private static func callSummary(type: Int,
                                  status: Int?,
                                  duration: TimeInterval?) -> String {
    switch status {
    case 1:
      return "\(NEChatUIKitSwiftUIBundle.localized("call_complete", value: "Call")) \(ChatUnitFormatter.playTime(duration ?? 0))"
    case 2:
      return NEChatUIKitSwiftUIBundle.localized("call_canceled", value: "Canceled")
    case 3:
      return NEChatUIKitSwiftUIBundle.localized("call_rejected", value: "Declined")
    case 4:
      return NEChatUIKitSwiftUIBundle.localized("call_timeout", value: "Time Out")
    case 5:
      return NEChatUIKitSwiftUIBundle.localized("call_busy", value: "Line busy")
    default:
      return callSummary(type: type)
    }
  }

  private static func callDuration(from durations: [V2NIMMessageCallDuration],
                                   senderId: String?) -> TimeInterval {
    guard let senderId else {
      return 0
    }
    return durations.first { $0.accountId == senderId }.map { TimeInterval($0.duration) } ?? 0
  }

  private static func multiForwardSummaries(from value: Any?) -> [MessageMultiForwardSummaryState] {
    if let dictionaries = value as? [[String: Any]] {
      return dictionaries.compactMap { dictionary in
        let content = dictionary["content"] as? String ?? ""
        guard !content.isEmpty else {
          return nil
        }
        return MessageMultiForwardSummaryState(
          senderNick: dictionary["senderNick"] as? String,
          content: content,
          userAccId: dictionary["userAccId"] as? String
        )
      }
    }

    if let strings = value as? [String] {
      return strings.map { MessageMultiForwardSummaryState(content: $0) }
    }

    return []
  }

  private static func deliveryState(for message: V2NIMMessage) -> MessageDeliveryState {
    switch message.sendingState {
    case .MESSAGE_SENDING_STATE_SENDING:
      return .pending(progress: nil)
    case .MESSAGE_SENDING_STATE_FAILED:
      return .failed(errorMessage(for: message))
    case .MESSAGE_SENDING_STATE_SUCCEEDED:
      if message.messageStatus.errorCode != operationSuccess {
        return .failed(errorMessage(for: message))
      }
      return .sent
    default:
      if message.messageStatus.errorCode != operationSuccess {
        return .failed(errorMessage(for: message))
      }
      return .none
    }
  }

  private static func isReadReceiptEnabled(for message: V2NIMMessage) -> Bool {
    guard message.messageType != .MESSAGE_TYPE_CALL,
          !isRevokeMessage(message) else {
      return false
    }
    return message.messageConfig?.readReceiptEnabled ?? true
  }

  public static func replyState(for message: V2NIMMessage) -> MessageReplyState? {
    replyState(for: message, reference: ChatRepo.shared.replyReference(from: message))
  }

  private static func replyState(for message: V2NIMMessage,
                                 reference: NEChatReplyReference?) -> MessageReplyState? {
    guard let reference, reference.isValid else {
      return nil
    }

    return MessageReplyState(
      messageClientId: reference.messageClientId,
      messageServerId: reference.messageServerId,
      senderId: reference.senderId,
      receiverId: reference.receiverId,
      senderName: displayName(for: reference.senderId, isTeamMessage: message.conversationType == .CONVERSATION_TYPE_TEAM),
      conversationId: reference.conversationId,
      conversationType: reference.conversationType.rawValue,
      createTime: reference.createTime,
      preview: NEChatUIKitSwiftUIBundle.localized("chat_reply_loading", value: "Loading replied message"),
      isResolved: false
    )
  }

  public static func topicReferState(for refer: V2NIMTopicRefer?) -> MessageTopicReferState? {
    guard let refer else {
      return nil
    }
    return MessageTopicReferState(
      conversationId: refer.conversationId,
      topicId: refer.topicId,
      createTime: TimeInterval(refer.createTime)
    )
  }

  public static func resolvingReply(_ row: MessageRowState,
                                    with replyMessage: V2NIMMessage?,
                                    currentAccountId: String? = IMKitClient.instance.account(),
                                    imageThumbSize: Int = 350) -> MessageRowState {
    guard let reply = row.reply else {
      return row
    }

    let resolvedReply = resolvingReply(
      reply,
      with: replyMessage,
      currentAccountId: currentAccountId,
      imageThumbSize: imageThumbSize
    )

    var next = row
    next.reply = resolvedReply
    if case let .reply(_, content) = next.content {
      next.content = .reply(preview: resolvedReply.displayPreview, content: content)
    }
    return next
  }

  public static func resolvingReply(_ reply: MessageReplyState,
                                    with replyMessage: V2NIMMessage?,
                                    currentAccountId: String? = IMKitClient.instance.account(),
                                    imageThumbSize: Int = 350) -> MessageReplyState {
    var next = reply

    if let replyMessage {
      let replyRow = self.row(
        message: replyMessage,
        currentAccountId: currentAccountId,
        imageThumbSize: imageThumbSize
      )
      next.senderId = replyRow.senderId ?? next.senderId
      next.senderName = replyRow.senderName ?? next.senderName
      next.conversationId = replyMessage.conversationId ?? next.conversationId
      next.receiverId = replyMessage.receiverId ?? next.receiverId
      next.preview = referencePreviewText(for: replyRow.content)
      next.resolvedContent = BoxedMessageContentState(replyRow.content)
      next.isResolved = true
    } else {
      next.preview = NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found")
      next.resolvedContent = nil
      next.isResolved = false
    }
    return next
  }

  private static func wrappingReplyIfNeeded(_ content: MessageContentState,
                                            for message: V2NIMMessage) -> MessageContentState {
    guard let reply = replyState(for: message),
          !isRevokeMessage(message),
          !isSystemMessage(message),
          !shouldSuppressDisplayedReply(for: message) else {
      return content
    }
    return .reply(preview: reply.displayPreview, content: BoxedMessageContentState(content))
  }

  private static func shouldSuppressDisplayedReply(for message: V2NIMMessage) -> Bool {
    isAIResponseMessage(message) &&
      message.messageStatus.errorCode != operationSuccess
  }

  private static func errorMessage(for message: V2NIMMessage) -> String? {
    guard message.messageStatus.errorCode != operationSuccess else {
      return nil
    }
    return NEChatUIKitSwiftUIBundle.localized("chat_send_failed", value: "Failed")
  }

  private static func displaySenderId(for message: V2NIMMessage) -> String? {
    if IMKitConfigCenter.shared.enableAIUser,
       message.aiConfig?.aiStatus == .MESSAGE_AI_STATUS_RESPONSE {
      return message.aiConfig?.accountId
    }
    return message.senderId
  }

  private static func displayName(for senderId: String?,
                                  isTeamMessage: Bool,
                                  showAlias: Bool = true) -> String? {
    guard let senderId, !senderId.isEmpty else {
      return nil
    }

    _ = isTeamMessage
    let showName = ChatRepo.swiftUIDisplayName(accountId: senderId, showAlias: showAlias)
    return showName.isEmpty ? senderId : showName
  }

  private static func displayAvatarURL(for senderId: String?) -> URL? {
    guard let senderId, !senderId.isEmpty else {
      return nil
    }

    if let avatar = NEAIUserManager.shared.getNEUserById(senderId)?.user?.avatar,
       let avatarURL = url(from: avatar) {
      return avatarURL
    }
    return url(from: ChatRepo.cachedSwiftUIDisplayUser(accountId: senderId)?.user?.avatar)
  }

  private static func url(from value: String?) -> URL? {
    ChatAvatarURLResolver.url(from: value)
  }

  private static func existingPath(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
      return nil
    }
    return FileManager.default.fileExists(atPath: value) ? value : nil
  }

  private static func revokeTextIfNeeded(_ message: V2NIMMessage) -> String? {
    guard let serverExtension = message.serverExtension,
          let json = NECommonUtil.getDictionaryFromJSONString(serverExtension) as? [String: Any],
          json[revokeLocalMessage] as? Bool == true else {
      return nil
    }
    return message.text ?? NEChatUIKitSwiftUIBundle.localized("message_recalled", value: "Message recalled")
  }

  private static func reeditState(for message: V2NIMMessage) -> ChatReeditState? {
    guard let serverExtension = message.serverExtension,
          let json = NECommonUtil.getDictionaryFromJSONString(serverExtension) as? [String: Any],
          json[revokeLocalMessage] as? Bool == true,
          let text = json[revokeLocalMessageContent] as? String,
          !text.isEmpty else {
      return nil
    }

    switch message.messageType {
    case .MESSAGE_TYPE_TEXT:
      return ChatReeditState(
        text: text,
        mentions: mentionStates(fromServerExtension: serverExtension, in: text),
        reply: replyState(for: message),
        revokeTime: revokeTime(from: json)
      )
    case .MESSAGE_TYPE_CUSTOM:
      guard NECustomUtils.typeOfCustomMessage(message.attachment) == customRichTextType else {
        return nil
      }
      return ChatReeditState(
        text: text,
        title: json[revokeLocalMessageTitle] as? String,
        mentions: mentionStates(fromServerExtension: serverExtension, in: text),
        reply: replyState(for: message),
        revokeTime: revokeTime(from: json)
      )
    default:
      return nil
    }
  }

  private static func revokeTime(from json: [String: Any]) -> TimeInterval {
    if let time = json[revokeLocalMessageTime] as? TimeInterval {
      return time
    }
    if let number = json[revokeLocalMessageTime] as? NSNumber {
      return number.doubleValue
    }
    if let text = json[revokeLocalMessageTime] as? String,
       let value = TimeInterval(text) {
      return value
    }
    return 0
  }
}
