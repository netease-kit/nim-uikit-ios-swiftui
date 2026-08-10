// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import AVFoundation
import Foundation
import ImageIO
import NEChatKit

public enum MessageDirection: Equatable {
  case incoming
  case outgoing
  case system
}

public enum MessageDeliveryState: Equatable {
  case none
  case pending(progress: Double?)
  case sent
  case read
  case failed(String?)
}

public struct MessageReadReceiptState: Equatable {
  public var readCount: Int
  public var unreadCount: Int
  public var isP2PRead: Bool
  public var timestamp: TimeInterval?
  public var displayLimit: Int?

  public init(readCount: Int = 0,
              unreadCount: Int = 0,
              isP2PRead: Bool = false,
              timestamp: TimeInterval? = nil,
              displayLimit: Int? = nil) {
    self.readCount = max(0, readCount)
    self.unreadCount = max(0, unreadCount)
    self.isP2PRead = isP2PRead
    self.timestamp = timestamp
    self.displayLimit = displayLimit
  }

  public var totalCount: Int {
    readCount + unreadCount
  }

  public var progress: Double? {
    if isP2PRead {
      return readCount > 0 && unreadCount == 0 ? 1 : 0
    }
    guard totalCount > 0 else {
      return nil
    }
    return Double(readCount) / Double(totalCount)
  }

  public var shouldDisplayTeamProgress: Bool {
    guard !isP2PRead else {
      return true
    }
    guard let displayLimit, displayLimit > 0 else {
      return true
    }
    return totalCount + 1 <= displayLimit
  }
}

public enum MessageContentState: Equatable {
  case text(String)
  case richText(title: String?, body: String)
  case image(MessageMediaState)
  case audio(MessageAudioState)
  case video(MessageMediaState)
  case file(MessageFileState)
  case location(MessageLocationState)
  case call(MessageCallState)
  case custom(title: String, body: String?)
  case multiForward(MessageMultiForwardState)
  case reply(preview: String?, content: BoxedMessageContentState)
  case revoke(String)
  case tip(String)
  case aiStream(text: String, isFinished: Bool, error: String?)
  case unsupported(String)
}

public struct MessageCallState: Equatable {
  public var summary: String
  public var type: Int

  public init(summary: String,
              type: Int = 0) {
    self.summary = summary
    self.type = type
  }
}

public indirect enum ChatCustomPayloadValue: Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([ChatCustomPayloadValue])
  case object([String: ChatCustomPayloadValue])
  case null

  public init?(jsonCompatibleValue value: Any?) {
    guard let value else {
      self = .null
      return
    }

    if value is NSNull {
      self = .null
    } else if let string = value as? String {
      self = .string(string)
    } else if let bool = value as? Bool {
      self = .bool(bool)
    } else if let int = value as? Int {
      self = .int(int)
    } else if let double = value as? Double {
      self = .double(double)
    } else if let float = value as? Float {
      self = .double(Double(float))
    } else if let number = value as? NSNumber {
      let double = number.doubleValue
      if double.rounded(.towardZero) == double {
        self = .int(number.intValue)
      } else {
        self = .double(double)
      }
    } else if let array = value as? [Any] {
      self = .array(array.compactMap(ChatCustomPayloadValue.init(jsonCompatibleValue:)))
    } else if let array = value as? NSArray {
      self = .array(array.compactMap(ChatCustomPayloadValue.init(jsonCompatibleValue:)))
    } else if let dictionary = value as? [String: Any] {
      self = .object(Self.object(from: dictionary))
    } else if let dictionary = value as? NSDictionary {
      self = .object(Self.object(from: dictionary))
    } else {
      return nil
    }
  }

  public static func object(from value: Any?) -> [String: ChatCustomPayloadValue] {
    let dictionary: [String: Any]
    if let value = value as? [String: Any] {
      dictionary = value
    } else if let value = value as? NSDictionary {
      var bridged = [String: Any]()
      for key in value.allKeys {
        guard let stringKey = key as? String else {
          continue
        }
        bridged[stringKey] = value[key]
      }
      dictionary = bridged
    } else {
      return [:]
    }

    return dictionary.reduce(into: [String: ChatCustomPayloadValue]()) { result, element in
      guard let value = ChatCustomPayloadValue(jsonCompatibleValue: element.value) else {
        return
      }
      result[element.key] = value
    }
  }
}

public struct ChatCustomMessagePayloadState: Equatable {
  public var type: Int?
  public var rawAttachment: String?
  public var customHeight: Double?
  public var payload: [String: ChatCustomPayloadValue]
  public var data: [String: ChatCustomPayloadValue]

  public init(type: Int? = nil,
              rawAttachment: String? = nil,
              customHeight: Double? = nil,
              payload: [String: ChatCustomPayloadValue] = [:],
              data: [String: ChatCustomPayloadValue] = [:]) {
    self.type = type
    self.rawAttachment = rawAttachment
    self.customHeight = customHeight
    self.payload = payload
    self.data = data
  }
}

public enum MessageTextHighlightKind: Equatable {
  case mention
  case keyword
}

public struct MessageTextHighlightState: Equatable {
  public var start: Int
  public var end: Int
  public var kind: MessageTextHighlightKind

  public init(start: Int,
              end: Int,
              kind: MessageTextHighlightKind) {
    self.start = start
    self.end = end
    self.kind = kind
  }

  public var range: Range<Int> {
    start ..< end
  }
}

public struct ChatTextPreviewState: Equatable, Identifiable {
  public var id: String
  public var messageId: String
  public var title: String?
  public var body: String
  public var source: Source

  public enum Source: String, Equatable {
    case message
    case reply
    case utility
  }

  public init(messageId: String,
              title: String? = nil,
              body: String,
              source: Source = .message) {
    self.messageId = messageId
    self.title = title
    self.body = body
    self.source = source
    id = "textPreview:\(source.rawValue):\(messageId)"
  }
}

public struct MessageReplyState: Equatable {
  public var messageClientId: String?
  public var messageServerId: String?
  public var senderId: String?
  public var receiverId: String?
  public var senderName: String?
  public var conversationId: String?
  public var conversationType: Int
  public var createTime: TimeInterval
  public var preview: String?
  public var resolvedContent: BoxedMessageContentState?
  public var isResolved: Bool

  public init(messageClientId: String? = nil,
              messageServerId: String? = nil,
              senderId: String? = nil,
              receiverId: String? = nil,
              senderName: String? = nil,
              conversationId: String? = nil,
              conversationType: Int = 0,
              createTime: TimeInterval = 0,
              preview: String? = nil,
              resolvedContent: BoxedMessageContentState? = nil,
              isResolved: Bool = false) {
    self.messageClientId = messageClientId
    self.messageServerId = messageServerId
    self.senderId = senderId
    self.receiverId = receiverId
    self.senderName = senderName
    self.conversationId = conversationId
    self.conversationType = conversationType
    self.createTime = createTime
    self.preview = preview
    self.resolvedContent = resolvedContent
    self.isResolved = isResolved
  }

  public var displayPreview: String? {
    if let senderName, !senderName.isEmpty,
       let preview, !preview.isEmpty {
      return "\(senderName): \(preview)"
    }
    return preview ?? senderName ?? senderId
  }
}

public struct MessageMultiForwardSummaryState: Equatable {
  public var senderNick: String?
  public var content: String
  public var userAccId: String?

  public init(senderNick: String? = nil,
              content: String,
              userAccId: String? = nil) {
    self.senderNick = senderNick
    self.content = content
    self.userAccId = userAccId
  }

  public var displayText: String {
    chatDisplayText
  }

  public var chatDisplayText: String {
    if let senderNick, !senderNick.isEmpty {
      return "\(NEFriendUserCache.getCutName(senderNick))：\(localizedContent)"
    }
    return localizedContent
  }

  public var compactDisplayText: String {
    if let senderNick, !senderNick.isEmpty {
      return "\(Self.compactSenderNick(senderNick))：\(localizedContent)"
    }
    return localizedContent
  }

  private var localizedContent: String {
    switch content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "[image]", "[photo]", "[图片]", "[图片消息]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_image", value: "[Image]")
    case "[audio]", "[voice]", "[语音]", "[语音消息]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_audio", value: "[Audio]")
    case "[video]", "[视频]", "[视频消息]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_video", value: "[Video]")
    case "[file]", "[文件]", "[文件消息]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_file", value: "[File]")
    case "[chat history]", "[history]", "[聊天记录]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_history", value: "[Chat History]")
    case "[location]", "[位置]", "[地理位置]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_location", value: "[Location]")
    case "[audio call]", "[voice call]", "[语音通话]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_audio_call", value: "[Audio Call]")
    case "[video call]", "[视频通话]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_video_call", value: "[Video Call]")
    case "[call]", "[音视频通话]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_call", value: "[Call]")
    case "[custom]", "[custom message]", "[自定义消息]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_custom", value: "[Custom Message]")
    case "[unknown]", "[unknown message]", "[未知消息]", "[未知消息体]":
      return NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_summary_unknown", value: "[Unknown Message]")
    default:
      return content
    }
  }

  private static func compactSenderNick(_ senderNick: String) -> String {
    guard senderNick.count > 5 else {
      return senderNick
    }
    let leftEndIndex = senderNick.index(senderNick.startIndex, offsetBy: 2)
    let rightStartIndex = senderNick.index(senderNick.endIndex, offsetBy: -2)
    return senderNick[senderNick.startIndex ..< leftEndIndex] + "..." + senderNick[rightStartIndex ..< senderNick.endIndex]
  }
}

public struct MessageMultiForwardState: Equatable {
  public var title: String
  public var hasSessionName: Bool
  public var url: String?
  public var md5: String?
  public var depth: Int
  public var sessionId: String?
  public var summaries: [MessageMultiForwardSummaryState]

  public init(title: String,
              hasSessionName: Bool = true,
              url: String? = nil,
              md5: String? = nil,
              depth: Int = 0,
              sessionId: String? = nil,
              summaries: [MessageMultiForwardSummaryState] = []) {
    self.title = title
    self.hasSessionName = hasSessionName
    self.url = url
    self.md5 = md5
    self.depth = depth
    self.sessionId = sessionId
    self.summaries = summaries
  }
}

public struct ChatMultiForwardPreviewState: Equatable, Identifiable {
  public var id: String
  public var messageId: String
  public var multiForward: MessageMultiForwardState

  public init(messageId: String,
              multiForward: MessageMultiForwardState) {
    self.messageId = messageId
    self.multiForward = multiForward
    id = "multiForward:\(messageId):\(multiForward.url ?? ""):\(multiForward.md5 ?? "")"
  }
}

public enum AIStreamActionPhase: Equatable {
  case idle
  case stopping
  case regenerating
  case failed(String)
}

public extension MessageRowState {
  var isUnfinishedAIStream: Bool {
    content.isUnfinishedAIStream
  }
}

public extension MessageContentState {
  var isUnfinishedAIStream: Bool {
    switch self {
    case let .aiStream(_, isFinished, _):
      return !isFinished
    case let .reply(_, boxed):
      return boxed.value.isUnfinishedAIStream
    default:
      return false
    }
  }
}

public enum MessageVoiceToTextPhase: Equatable {
  case idle
  case converting
  case converted
  case failed(String)
}

public struct MessageVoiceToTextState: Equatable {
  public var text: String?
  public var phase: MessageVoiceToTextPhase

  public init(text: String? = nil,
              phase: MessageVoiceToTextPhase = .idle) {
    self.text = text
    self.phase = phase
  }
}

public struct ChatReeditState: Equatable {
  public var text: String
  public var title: String?
  public var mentions: [ChatMentionState]
  public var reply: MessageReplyState?
  public var revokeTime: TimeInterval
  public var editTimeGapMinutes: Int

  public init(text: String,
              title: String? = nil,
              mentions: [ChatMentionState] = [],
              reply: MessageReplyState? = nil,
              revokeTime: TimeInterval,
              editTimeGapMinutes: Int = 2) {
    self.text = text
    self.title = title
    self.mentions = mentions
    self.reply = reply
    self.revokeTime = revokeTime
    self.editTimeGapMinutes = max(1, editTimeGapMinutes)
  }

  public var isExpired: Bool {
    Int(Date().timeIntervalSince1970 - revokeTime) >= editTimeGapMinutes * 60
  }
}

public final class BoxedMessageContentState: Equatable {
  public let value: MessageContentState

  public init(_ value: MessageContentState) {
    self.value = value
  }

  public static func == (lhs: BoxedMessageContentState, rhs: BoxedMessageContentState) -> Bool {
    lhs.value == rhs.value
  }
}

public struct MessageMediaState: Equatable {
  public var url: URL?
  public var localPath: String?
  public var thumbnailURL: URL?
  public var width: Double?
  public var height: Double?
  public var duration: TimeInterval?

  public init(url: URL? = nil,
              localPath: String? = nil,
              thumbnailURL: URL? = nil,
              width: Double? = nil,
              height: Double? = nil,
              duration: TimeInterval? = nil) {
    self.url = url
    self.localPath = localPath
    self.thumbnailURL = thumbnailURL
    self.width = width
    self.height = height
    self.duration = duration
  }
}

public enum ChatMediaPreviewKind: String, Equatable {
  case image
  case video
}

public struct ChatMediaPreviewState: Equatable, Identifiable {
  public var id: String
  public var kind: ChatMediaPreviewKind
  public var media: MessageMediaState
  public var title: String?
  public var mediaItems: [ChatMediaItem]

  public init(id: String,
              kind: ChatMediaPreviewKind,
              media: MessageMediaState,
              title: String? = nil,
              mediaItems: [ChatMediaItem] = []) {
    self.id = id
    self.kind = kind
    self.media = media
    self.title = title
    self.mediaItems = mediaItems
  }

  public static func == (lhs: ChatMediaPreviewState, rhs: ChatMediaPreviewState) -> Bool {
    lhs.id == rhs.id
  }
}

public struct ChatMediaItem: Equatable, Identifiable {
  public var id: String
  public var media: MessageMediaState
  public var kind: ChatMediaPreviewKind
  public var title: String?

  public init(id: String,
              media: MessageMediaState,
              kind: ChatMediaPreviewKind,
              title: String? = nil) {
    self.id = id
    self.media = media
    self.kind = kind
    self.title = title
  }
}

public struct MessageAudioState: Equatable {
  public var duration: TimeInterval
  public var localPath: String?
  public var url: URL?
  public var isPlaying: Bool
  public var convertedText: String?

  public init(duration: TimeInterval = 0,
              localPath: String? = nil,
              url: URL? = nil,
              isPlaying: Bool = false,
              convertedText: String? = nil) {
    self.duration = duration
    self.localPath = localPath
    self.url = url
    self.isPlaying = isPlaying
    self.convertedText = convertedText
  }
}

public extension MessageAudioState {
  var existingLocalPath: String? {
    guard let localPath,
          !localPath.isEmpty,
          FileManager.default.fileExists(atPath: localPath) else {
      return nil
    }
    return localPath
  }
}

public struct MessageFileState: Equatable, Hashable {
  public var name: String
  public var sizeText: String?
  public var url: URL?
  public var localPath: String?
  public var fileExtension: String?

  public init(name: String = "file",
              sizeText: String? = nil,
              url: URL? = nil,
              localPath: String? = nil,
              fileExtension: String? = nil) {
    self.name = name.isEmpty ? "file" : name
    self.sizeText = sizeText
    self.url = url
    self.localPath = localPath
    self.fileExtension = fileExtension
  }
}

public struct ChatFilePreviewState: Equatable, Hashable, Identifiable {
  public var id: String
  public var file: MessageFileState

  public init(id: String, file: MessageFileState) {
    self.id = id
    self.file = file
  }
}

public struct MessageLocationState: Equatable {
  public var latitude: Double?
  public var longitude: Double?
  public var title: String
  public var subtitle: String?
  public var thumbnailURL: URL?

  public init(latitude: Double? = nil,
              longitude: Double? = nil,
              title: String,
              subtitle: String? = nil,
              thumbnailURL: URL? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.title = title.isEmpty ? NEChatUIKitSwiftUIBundle.localized("chat_location_unavailable", value: "Location") : title
    self.subtitle = subtitle
    self.thumbnailURL = thumbnailURL
  }
}

public struct MessageTopicReferState: Equatable {
  public var conversationId: String?
  public var topicId: UInt64?
  public var createTime: TimeInterval

  public init(conversationId: String? = nil,
              topicId: UInt64? = nil,
              createTime: TimeInterval = 0) {
    self.conversationId = conversationId
    self.topicId = topicId
    self.createTime = createTime
  }

  public var isValid: Bool {
    conversationId?.isEmpty == false && topicId != nil
  }
}

public struct MessageRowState: Identifiable, Equatable {
  public var id: String
  public var serverId: String?
  public var conversationId: String?
  public var senderId: String?
  public var senderName: String?
  public var avatarURL: URL?
  public var avatarName: String?
  public var direction: MessageDirection
  public var content: MessageContentState
  public var deliveryState: MessageDeliveryState
  public var isSendFailureRetryable: Bool
  public var readReceipt: MessageReadReceiptState?
  public var isReadReceiptEnabled: Bool
  public var timestamp: TimeInterval?
  public var timeDividerText: String?
  public var suppressesTimeDivider: Bool
  public var textHighlights: [MessageTextHighlightState]
  public var isSelected: Bool
  public var isPinned: Bool
  public var pinOperatorId: String?
  public var pinOperatorName: String?
  public var isTopMessage: Bool
  public var voiceToText: MessageVoiceToTextState?
  public var aiStreamActionPhase: AIStreamActionPhase
  public var isAIResponse: Bool
  public var aiTriggerSenderId: String?
  public var reply: MessageReplyState?
  public var reedit: ChatReeditState?
  public var topicRefer: MessageTopicReferState?
  public var customPayload: ChatCustomMessagePayloadState?

  public init(id: String,
              serverId: String? = nil,
              conversationId: String? = nil,
              senderId: String? = nil,
              senderName: String? = nil,
              avatarURL: URL? = nil,
              avatarName: String? = nil,
              direction: MessageDirection,
              content: MessageContentState,
              deliveryState: MessageDeliveryState = .none,
              isSendFailureRetryable: Bool = true,
              readReceipt: MessageReadReceiptState? = nil,
              isReadReceiptEnabled: Bool = true,
              timestamp: TimeInterval? = nil,
              timeDividerText: String? = nil,
              suppressesTimeDivider: Bool = false,
              textHighlights: [MessageTextHighlightState] = [],
              isSelected: Bool = false,
              isPinned: Bool = false,
              pinOperatorId: String? = nil,
              pinOperatorName: String? = nil,
              isTopMessage: Bool = false,
              voiceToText: MessageVoiceToTextState? = nil,
              aiStreamActionPhase: AIStreamActionPhase = .idle,
              isAIResponse: Bool = false,
              aiTriggerSenderId: String? = nil,
              reply: MessageReplyState? = nil,
              reedit: ChatReeditState? = nil,
              topicRefer: MessageTopicReferState? = nil,
              customPayload: ChatCustomMessagePayloadState? = nil) {
    self.id = id
    self.serverId = serverId
    self.conversationId = conversationId
    self.senderId = senderId
    self.senderName = senderName
    self.avatarURL = avatarURL
    self.avatarName = avatarName
    self.direction = direction
    self.content = content
    self.deliveryState = deliveryState
    self.isSendFailureRetryable = isSendFailureRetryable
    self.readReceipt = readReceipt
    self.isReadReceiptEnabled = isReadReceiptEnabled
    self.timestamp = timestamp
    self.timeDividerText = timeDividerText
    self.suppressesTimeDivider = suppressesTimeDivider
    self.textHighlights = textHighlights
    self.isSelected = isSelected
    self.isPinned = isPinned
    self.pinOperatorId = pinOperatorId
    self.pinOperatorName = pinOperatorName
    self.isTopMessage = isTopMessage
    self.voiceToText = voiceToText
    self.aiStreamActionPhase = aiStreamActionPhase
    self.isAIResponse = isAIResponse
    self.aiTriggerSenderId = aiTriggerSenderId
    self.reply = reply
    self.reedit = reedit
    self.topicRefer = topicRefer
    self.customPayload = customPayload
  }
}

public extension MessageRowState {
  var isAIStreamTriggeredByCurrentUser: Bool {
    aiTriggerSenderId == IMKitClient.instance.account()
  }
}

public extension MessageMediaState {
  var playableLocalPath: String? {
    existingLocalPath
  }

  var existingLocalPath: String? {
    guard let localPath,
          !localPath.isEmpty,
          FileManager.default.fileExists(atPath: localPath) else {
      return nil
    }
    return localPath
  }

  /// The attachment URL is the exact file that was sent. For non-original
  /// picks that is the processed image; for original picks it is the source
  /// asset. The thumbnail is only a last-resort fallback.
  var imageDownloadURL: URL? {
    if let existingLocalPath {
      return URL(fileURLWithPath: existingLocalPath)
    }
    return url ?? thumbnailURL
  }
}

public extension MessageFileState {
  var existingLocalPath: String? {
    guard let localPath,
          !localPath.isEmpty,
          FileManager.default.fileExists(atPath: localPath) else {
      return nil
    }
    return localPath
  }

  var normalizedFileExtension: String {
    let candidates = [
      (name as NSString).pathExtension,
      fileExtension,
      localPath.map { URL(fileURLWithPath: $0).pathExtension },
      url?.pathExtension,
    ]
    for candidate in candidates {
      let ext = candidate?
        .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
        .lowercased() ?? ""
      if !ext.isEmpty {
        return ext
      }
    }
    return ""
  }

  var isVideoFile: Bool {
    let fileExtension = normalizedFileExtension
    if Self.videoFileExtensions.contains(fileExtension) {
      return true
    }
    if Self.imageFileExtensions.contains(fileExtension) {
      return false
    }
    if let detectedLocalMediaKind {
      return detectedLocalMediaKind == .video
    }
    return false
  }

  var isImageFile: Bool {
    let fileExtension = normalizedFileExtension
    if Self.imageFileExtensions.contains(fileExtension) {
      return true
    }
    if Self.videoFileExtensions.contains(fileExtension) {
      return false
    }
    if let detectedLocalMediaKind {
      return detectedLocalMediaKind == .image
    }
    return false
  }

  var imageMediaState: MessageMediaState? {
    guard isImageFile else {
      return nil
    }
    return MessageMediaState(
      url: url,
      localPath: existingLocalPath ?? localPath,
      thumbnailURL: nil
    )
  }

  var videoMediaState: MessageMediaState? {
    guard isVideoFile else {
      return nil
    }
    return MessageMediaState(
      url: url,
      localPath: existingLocalPath ?? localPath,
      thumbnailURL: nil
    )
  }

  private static var videoFileExtensions: Set<String> {
    ["mp4", "avi", "wmv", "mpeg", "m4v", "mov", "asf", "flv", "f4v", "rmvb", "rm", "3gp"]
  }

  private static var imageFileExtensions: Set<String> {
    ["jpg", "jpeg", "png", "tiff", "heic", "gif", "bmp", "webp"]
  }

  private enum LocalMediaKind: Equatable {
    case image
    case video
  }

  private var detectedLocalMediaKind: LocalMediaKind? {
    guard let path = existingLocalPath else {
      return nil
    }
    let fileURL = URL(fileURLWithPath: path)
    if !AVURLAsset(url: fileURL).tracks(withMediaType: .video).isEmpty {
      return .video
    }
    if CGImageSourceCreateWithURL(fileURL as CFURL, nil) != nil {
      return .image
    }
    return nil
  }
}
