// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation

public enum ChatInputMode: Equatable {
  case text
  case voice
  case emoji
  case more
}

public enum ChatMoreAction: String, CaseIterable, Identifiable, Equatable {
  case photo
  case takePicture
  case file
  case location
  case rtc
  case translate

  public var id: String {
    rawValue
  }
}

public struct ChatMoreActionState: Equatable, Identifiable {
  public var id: ChatMoreAction
  public var title: String
  public var systemImageName: String
  public var imageName: String?
  public var isEnabled: Bool

  public init(id: ChatMoreAction,
              title: String,
              systemImageName: String,
              imageName: String? = nil,
              isEnabled: Bool = true) {
    self.id = id
    self.title = title
    self.systemImageName = systemImageName
    self.imageName = imageName
    self.isEnabled = isEnabled
  }
}

public struct ChatEmojiState: Equatable, Identifiable {
  public var id: String
  public var text: String
  public var imageName: String?
  public var accessibilityLabel: String

  public init(id: String,
              text: String,
              imageName: String? = nil,
              accessibilityLabel: String? = nil) {
    self.id = id
    self.text = text
    self.imageName = imageName
    self.accessibilityLabel = accessibilityLabel ?? text
  }
}

public struct ChatReplyState: Equatable, Identifiable {
  public var id: String
  public var serverId: String?
  public var preview: String
  public var senderName: String?

  public init(id: String, serverId: String? = nil, preview: String, senderName: String? = nil) {
    self.id = id
    self.serverId = serverId
    self.preview = preview
    self.senderName = senderName
  }

  public var displayText: String {
    guard let senderName,
          !senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return preview
    }
    let reply = NEChatUIKitSwiftUIBundle.localized("operation_replay", value: "Reply")
    return "\(reply) \(senderName): \(preview)"
  }
}

public struct ChatInputValidationState: Equatable {
  public var characterCount: Int
  public var characterLimit: Int?

  public init(characterCount: Int = 0,
              characterLimit: Int? = nil) {
    self.characterCount = max(0, characterCount)
    self.characterLimit = characterLimit
  }

  public var isOverLimit: Bool {
    guard let characterLimit else {
      return false
    }
    return characterCount > characterLimit
  }

  public var shouldShowCounter: Bool {
    guard let characterLimit, characterLimit > 0 else {
      return false
    }
    return isOverLimit || characterCount >= Int(Double(characterLimit) * 0.9)
  }
}

public struct ChatMentionState: Equatable, Identifiable {
  public var accountId: String
  public var displayText: String
  public var start: Int
  public var end: Int

  public init(accountId: String,
              displayText: String,
              start: Int,
              end: Int) {
    self.accountId = accountId
    self.displayText = displayText
    self.start = start
    self.end = end
  }

  public var id: String {
    "\(accountId):\(start):\(end)"
  }
}

public enum ChatVoiceRecordingPhase: Equatable {
  case idle
  case preparing
  case recording
  case cancelling
  case finishing
  case failed(String)
}

public struct ChatVoiceRecordingProgressState: Equatable {
  public var duration: TimeInterval
  public var level: Double
  public var remainingTime: TimeInterval?

  public init(duration: TimeInterval = 0,
              level: Double = 0,
              remainingTime: TimeInterval? = nil) {
    self.duration = duration
    self.level = max(0, min(1, level))
    self.remainingTime = remainingTime
  }
}

public struct ChatVoiceRecordingState: Equatable {
  public var phase: ChatVoiceRecordingPhase
  public var progress: ChatVoiceRecordingProgressState

  public init(phase: ChatVoiceRecordingPhase = .idle,
              progress: ChatVoiceRecordingProgressState = ChatVoiceRecordingProgressState()) {
    self.phase = phase
    self.progress = progress
  }

  public var isActive: Bool {
    switch phase {
    case .preparing, .recording, .cancelling, .finishing:
      return true
    case .idle, .failed:
      return false
    }
  }
}

public struct ChatInputState: Equatable {
  public var text: String
  public var selectedRange: NSRange
  public var richTextTitle: String
  public var isRichTextExpanded: Bool
  public var mode: ChatInputMode
  public var reply: ChatReplyState?
  public var isEnabled: Bool
  public var disabledReason: String?
  public var placeholder: String?
  public var isSendEnabled: Bool
  public var isRecording: Bool
  public var recording: ChatVoiceRecordingState
  public var validation: ChatInputValidationState
  public var mentionedAccountIds: Set<String>
  public var mentions: [ChatMentionState]
  public var moreActions: [ChatMoreActionState]
  public var emojis: [ChatEmojiState]
  public var collapseRevision: Int
  public var focusRevision: Int

  public init(text: String = "",
              selectedRange: NSRange? = nil,
              richTextTitle: String = "",
              isRichTextExpanded: Bool = false,
              mode: ChatInputMode = .text,
              reply: ChatReplyState? = nil,
              isEnabled: Bool = true,
              disabledReason: String? = nil,
              placeholder: String? = nil,
              isSendEnabled: Bool = false,
              isRecording: Bool = false,
              recording: ChatVoiceRecordingState = ChatVoiceRecordingState(),
              validation: ChatInputValidationState? = nil,
              mentionedAccountIds: Set<String> = [],
              mentions: [ChatMentionState] = [],
              moreActions: [ChatMoreActionState] = ChatInputState.defaultMoreActions(),
              emojis: [ChatEmojiState] = ChatInputState.defaultEmojis(),
              collapseRevision: Int = 0,
              focusRevision: Int = 0) {
    self.text = text
    self.selectedRange = selectedRange ?? NSRange(location: text.utf16.count, length: 0)
    self.richTextTitle = richTextTitle
    self.isRichTextExpanded = isRichTextExpanded
    self.mode = mode
    self.reply = reply
    self.isEnabled = isEnabled
    self.disabledReason = disabledReason
    self.placeholder = placeholder
    self.isSendEnabled = isSendEnabled
    self.isRecording = isRecording
    self.recording = recording
    self.validation = validation ?? ChatInputValidationState(characterCount: text.utf16.count)
    self.mentionedAccountIds = mentionedAccountIds
    self.mentions = mentions
    self.moreActions = moreActions
    self.emojis = emojis
    self.collapseRevision = collapseRevision
    self.focusRevision = focusRevision
  }

  public static func defaultMoreActions() -> [ChatMoreActionState] {
    [
      ChatMoreActionState(
        id: .photo,
        title: NEChatUIKitSwiftUIBundle.localized("chat_more_photo", value: "Photo"),
        systemImageName: "photo.on.rectangle",
        imageName: "photo"
      ),
      ChatMoreActionState(
        id: .takePicture,
        title: NEChatUIKitSwiftUIBundle.localized("chat_more_camera", value: "Camera"),
        systemImageName: "camera",
        imageName: "chat_takePicture"
      ),
      ChatMoreActionState(
        id: .file,
        title: NEChatUIKitSwiftUIBundle.localized("chat_more_file", value: "File"),
        systemImageName: "doc",
        imageName: "chat_file"
      ),
      ChatMoreActionState(
        id: .location,
        title: NEChatUIKitSwiftUIBundle.localized("chat_more_location", value: "Location"),
        systemImageName: "mappin.and.ellipse",
        imageName: "chat_location"
      ),
      ChatMoreActionState(
        id: .rtc,
        title: NEChatUIKitSwiftUIBundle.localized("chat_rtc", value: "Audio and Video Call"),
        systemImageName: "phone",
        imageName: "chat_rtc"
      ),
      ChatMoreActionState(
        id: .translate,
        title: NEChatUIKitSwiftUIBundle.localized("chat_more_translate", value: "Translate"),
        systemImageName: "character.book.closed",
        imageName: "chat_translation"
      ),
    ]
  }

  public static func defaultEmojis() -> [ChatEmojiState] {
    MessageEmoticonCatalog.shared.defaultEmojiStates()
  }
}
