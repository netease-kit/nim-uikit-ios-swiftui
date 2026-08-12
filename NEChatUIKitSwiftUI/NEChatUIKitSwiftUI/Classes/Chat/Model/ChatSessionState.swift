// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum TopMessageSource: Equatable {
  case teamTop(canClose: Bool)
  case pinned

  public var canClose: Bool {
    if case let .teamTop(canClose) = self {
      return canClose
    }
    return false
  }
}

public struct TopMessageState: Equatable, Identifiable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var source: TopMessageSource
  public var row: MessageRowState?

  public init(id: String,
              title: String,
              subtitle: String? = nil,
              source: TopMessageSource = .pinned,
              row: MessageRowState? = nil) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.source = source
    self.row = row
  }
}

public struct NewMessageIndicatorState: Equatable {
  public var count: Int
  public var firstMessageId: String?
  public var requiresLatestReload: Bool

  public init(count: Int = 0,
              firstMessageId: String? = nil,
              requiresLatestReload: Bool = false) {
    self.count = count
    self.firstMessageId = firstMessageId
    self.requiresLatestReload = requiresLatestReload
  }
}

public enum ChatHeaderAction: String, CaseIterable, Identifiable, Equatable {
  case pinnedMessages
  case historySearch
  case collectionMessages
  case aiRobots
  case userSetting

  public var id: String {
    rawValue
  }
}

public enum ChatTimelineScrollAnchor: String, Equatable {
  case top
  case center
  case bottom
}

public struct ChatTimelineScrollTarget: Equatable, Identifiable {
  public enum Reason: String, Equatable {
    case normal
    case initialLatest
    case jumpToLatest
    case prependRestore
    case explicitAnchor
  }

  public var id: String
  public var messageId: String
  public var anchor: ChatTimelineScrollAnchor
  public var animated: Bool
  public var reason: Reason
  public var createdAtUptime: TimeInterval
  public var scopeId: String

  public init(messageId: String,
              anchor: ChatTimelineScrollAnchor,
              sequence: Int,
              animated: Bool = true,
              reason: Reason = .normal,
              scopeId: String = UUID().uuidString,
              createdAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    self.messageId = messageId
    self.anchor = anchor
    self.animated = animated
    self.reason = reason
    self.scopeId = scopeId
    self.createdAtUptime = createdAtUptime
    id = "\(sequence):\(scopeId):\(anchor.rawValue):\(messageId)"
  }

  public var ageMilliseconds: Int {
    Int((ProcessInfo.processInfo.systemUptime - createdAtUptime) * 1000)
  }
}

public struct ChatTranslationLanguageState: Equatable, Identifiable {
  public var id: String { code }
  public var code: String
  public var title: String

  public init(code: String, title: String) {
    self.code = code
    self.title = title
  }
}

public enum ChatInputTranslationPhase: Equatable {
  case idle
  case translating
  case translated
}

public struct ChatInputTranslationState: Equatable, Identifiable {
  public var id: String
  public var selectedLanguage: String
  public var languages: [ChatTranslationLanguageState]
  public var phase: ChatInputTranslationPhase
  public var translatedText: String
  public var requestId: String?

  public init(selectedLanguage: String,
              languages: [ChatTranslationLanguageState],
              phase: ChatInputTranslationPhase = .idle,
              translatedText: String = "",
              requestId: String? = nil) {
    id = "inputTranslation"
    self.selectedLanguage = selectedLanguage
    self.languages = languages
    self.phase = phase
    self.translatedText = translatedText
    self.requestId = requestId
  }
}

public struct ChatForwardSheetState: Equatable, Identifiable {
  public var id: String
  public var request: ChatForwardRequest
  public var recentTargets: [ChatForwardTargetState]
  public var fixedTargets: [ChatForwardTargetState]
  public var selectedTargetIds: Set<String>
  public var comment: String

  public init(request: ChatForwardRequest,
              recentTargets: [ChatForwardTargetState] = [],
              fixedTargets: [ChatForwardTargetState] = [],
              selectedTargetIds: Set<String> = [],
              comment: String = "") {
    id = "forwardSheet:\(request.merged):\(request.messageIds.sorted().joined(separator: ","))"
    self.request = request
    self.recentTargets = recentTargets
    self.fixedTargets = fixedTargets
    self.selectedTargetIds = selectedTargetIds
    self.comment = comment
  }

  public var selectedTargets: [ChatForwardTargetState] {
    if !fixedTargets.isEmpty {
      return fixedTargets
    }
    return recentTargets.filter { selectedTargetIds.contains($0.id) }
  }
}

public enum MessageOperation: String, CaseIterable, Identifiable, Equatable, Hashable {
  case copy
  case delete
  case revoke
  case reply
  case forward
  case collect
  case pin
  case top
  case untop
  case readReceipt
  case selectText
  case multiSelect
  case voiceToText
  case earpiece
  case speaker
  case resend
  case plugin

  public var id: String {
    rawValue
  }
}

public enum ChatOperationRole: String, Equatable {
  case normal
  case destructive
}

public struct ChatOperationDescriptor: Identifiable, Equatable {
  public var id: String { operation.rawValue }
  public var operation: MessageOperation
  public var title: String
  public var imageName: String?
  public var imageResource: NEChatKitImageResource?
  public var role: ChatOperationRole
  public var isEnabled: Bool

  public init(operation: MessageOperation,
              title: String? = nil,
              imageName: String? = nil,
              imageResource: NEChatKitImageResource? = nil,
              role: ChatOperationRole? = nil,
              isEnabled: Bool = true) {
    self.operation = operation
    self.title = title ?? Self.defaultTitle(for: operation)
    self.imageName = imageName ?? Self.defaultImageName(for: operation)
    self.imageResource = imageResource
    self.role = role ?? Self.defaultRole(for: operation)
    self.isEnabled = isEnabled
  }

  public var isDestructive: Bool {
    role == .destructive
  }

  public static func defaultTitle(for operation: MessageOperation) -> String {
    switch operation {
    case .copy:
      return NEChatUIKitSwiftUIBundle.localized("operation_copy", value: "Copy")
    case .delete:
      return NEChatUIKitSwiftUIBundle.localized("operation_delete", value: "Delete")
    case .revoke:
      return NEChatUIKitSwiftUIBundle.localized("operation_recall", value: "Recall")
    case .reply:
      return NEChatUIKitSwiftUIBundle.localized("operation_replay", value: "Reply")
    case .forward:
      return NEChatUIKitSwiftUIBundle.localized("operation_forward", value: "Forward")
    case .collect:
      return NEChatUIKitSwiftUIBundle.localized("operation_collection", value: "Collect")
    case .pin:
      return NEChatUIKitSwiftUIBundle.localized("operation_pin", value: "Pin")
    case .top:
      return NEChatUIKitSwiftUIBundle.localized("operation_top", value: "Top")
    case .untop:
      return NEChatUIKitSwiftUIBundle.localized("operation_untop", value: "Untop")
    case .readReceipt:
      return NEChatUIKitSwiftUIBundle.localized("chat_read_receipt", value: "Read Receipt")
    case .selectText:
      return NEChatUIKitSwiftUIBundle.localized("operation_select_text", value: "Select Text")
    case .multiSelect:
      return NEChatUIKitSwiftUIBundle.localized("operation_select", value: "Select")
    case .voiceToText:
      return NEChatUIKitSwiftUIBundle.localized("operation_to_text", value: "Convert to Text")
    case .earpiece:
      return NEChatUIKitSwiftUIBundle.localized("operation_earpiece", value: "Earpiece")
    case .speaker:
      return NEChatUIKitSwiftUIBundle.localized("operation_speaker", value: "Speaker")
    case .resend:
      return NEChatUIKitSwiftUIBundle.localized("chat_resend", value: "Resend")
    case .plugin:
      return NEChatUIKitSwiftUIBundle.localized("chat_plugin", value: "Plugin")
    }
  }

  public static func defaultImageName(for operation: MessageOperation) -> String {
    switch operation {
    case .copy:
      return "op_copy"
    case .delete:
      return "op_delete"
    case .revoke:
      return "op_recall"
    case .reply:
      return "op_replay"
    case .forward:
      return "op_forward"
    case .collect:
      return "op_collect"
    case .pin:
      return "op_pin"
    case .top:
      return "op_top"
    case .untop:
      return "op_untop"
    case .readReceipt:
      return "chat_read_all"
    case .selectText:
      return "op_select"
    case .multiSelect:
      return "op_select"
    case .voiceToText:
      return "op_toText"
    case .earpiece:
      return "op_earpiece"
    case .speaker:
      return "op_speaker"
    case .resend:
      return "sendMessage_failed"
    case .plugin:
      return "op_collection"
    }
  }

  public static func defaultRole(for operation: MessageOperation) -> ChatOperationRole {
    switch operation {
    case .delete, .revoke:
      return .destructive
    case .plugin:
      return .normal
    default:
      return .normal
    }
  }
}

public struct OperationMenuState: Equatable {
  public var messageId: String
  public var descriptors: [ChatOperationDescriptor]

  public init(messageId: String, descriptors: [ChatOperationDescriptor]) {
    self.messageId = messageId
    self.descriptors = descriptors
  }

  public init(messageId: String, operations: [MessageOperation]) {
    self.init(
      messageId: messageId,
      descriptors: operations.map { ChatOperationDescriptor(operation: $0) }
    )
  }

  public var operations: [MessageOperation] {
    descriptors.map(\.operation)
  }
}

public enum ChatPendingConfirmation: Equatable, Identifiable {
  case deleteMessage(messageId: String)
  case revokeMessage(messageId: String)
  case deleteSelected(messageIds: [String])
  case forwardSelected(messageIds: [String], invalidMessageIds: [String], merged: Bool, depth: Int)

  public var id: String {
    switch self {
    case let .deleteMessage(messageId):
      return "delete:\(messageId)"
    case let .revokeMessage(messageId):
      return "revoke:\(messageId)"
    case let .deleteSelected(messageIds):
      return "deleteSelected:\(messageIds.sorted().joined(separator: ","))"
    case let .forwardSelected(messageIds, invalidMessageIds, merged, depth):
      return "forwardSelected:\(merged):\(depth):\(messageIds.sorted().joined(separator: ",")):\(invalidMessageIds.sorted().joined(separator: ","))"
    }
  }
}

public enum ChatTeamLifecycleReason: String, Equatable {
  case invalid
  case dismissed
  case left
}

public struct ChatTeamLifecycleAlertState: Equatable, Identifiable {
  public var id: String
  public var reason: ChatTeamLifecycleReason
  public var teamId: String
  public var conversationId: String
  public var message: String
  public var shouldDeleteConversation: Bool
  public var requiresUserConfirmation: Bool

  public init(reason: ChatTeamLifecycleReason,
              teamId: String,
              conversationId: String,
              message: String,
              shouldDeleteConversation: Bool = true,
              requiresUserConfirmation: Bool = true) {
    id = "teamLifecycle:\(reason.rawValue):\(teamId)"
    self.reason = reason
    self.teamId = teamId
    self.conversationId = conversationId
    self.message = message
    self.shouldDeleteConversation = shouldDeleteConversation
    self.requiresUserConfirmation = requiresUserConfirmation
  }
}

public struct MultiSelectState: Equatable {
  public var selection: NEChatKitSelectionState<String>

  public init(selection: NEChatKitSelectionState<String> = NEChatKitSelectionState<String>()) {
    self.selection = selection
  }
}

public enum ChatAudioPlaybackPhase: Equatable {
  case idle
  case loading
  case playing
  case failed(String)
}

public struct ChatAudioPlaybackState: Equatable {
  public var messageId: String?
  public var phase: ChatAudioPlaybackPhase

  public init(messageId: String? = nil,
              phase: ChatAudioPlaybackPhase = .idle) {
    self.messageId = messageId
    self.phase = phase
  }
}

public enum ChatReadSyncPhase: Equatable {
  case idle
  case syncing
  case synced
  case failed(String)
}

public struct ChatReadSyncState: Equatable {
  public var phase: ChatReadSyncPhase
  public var lastReadTime: TimeInterval?
  public var lastSyncedMessageIds: [String]
  public var didClearUnread: Bool

  public init(phase: ChatReadSyncPhase = .idle,
              lastReadTime: TimeInterval? = nil,
              lastSyncedMessageIds: [String] = [],
              didClearUnread: Bool = false) {
    self.phase = phase
    self.lastReadTime = lastReadTime
    self.lastSyncedMessageIds = lastSyncedMessageIds
    self.didClearUnread = didClearUnread
  }
}

public enum ChatConnectionPhase: String, Equatable {
  case unknown
  case waiting
  case connected
  case disconnected
  case failed
}

public enum ChatLoginPhase: String, Equatable {
  case unknown
  case loggedIn
  case loggingOut
  case loggedOut
  case failed
  case kickedOffline
}

public enum ChatDataSyncPhase: String, Equatable {
  case idle
  case waiting
  case syncing
  case completed
  case failed
}

public struct ChatDataSyncState: Equatable {
  public var type: Int?
  public var phase: ChatDataSyncPhase
  public var errorMessage: String?

  public init(type: Int? = nil,
              phase: ChatDataSyncPhase = .idle,
              errorMessage: String? = nil) {
    self.type = type
    self.phase = phase
    self.errorMessage = errorMessage
  }
}

public struct ChatClientRuntimeState: Equatable {
  public var connectionPhase: ChatConnectionPhase
  public var loginPhase: ChatLoginPhase
  public var dataSync: ChatDataSyncState
  public var isNetworkBroken: Bool
  public var lastErrorMessage: String?
  public var kickedOfflineReason: String?

  public init(connectionPhase: ChatConnectionPhase = .unknown,
              loginPhase: ChatLoginPhase = .unknown,
              dataSync: ChatDataSyncState = ChatDataSyncState(),
              isNetworkBroken: Bool = false,
              lastErrorMessage: String? = nil,
              kickedOfflineReason: String? = nil) {
    self.connectionPhase = connectionPhase
    self.loginPhase = loginPhase
    self.dataSync = dataSync
    self.isNetworkBroken = isNetworkBroken
    self.lastErrorMessage = lastErrorMessage
    self.kickedOfflineReason = kickedOfflineReason
  }

  public var shouldShowNetworkWarning: Bool {
    isNetworkBroken || connectionPhase == .waiting || connectionPhase == .disconnected || connectionPhase == .failed
  }
}

public struct ChatTopicState: Equatable {
  public var title: String?
  public var isRemoved: Bool

  public init(title: String? = nil,
              isRemoved: Bool = false) {
    self.title = title
    self.isRemoved = isRemoved
  }
}

public struct P2PChatPresenceState: Equatable {
  public var accountId: String?
  public var isTyping: Bool
  public var onlineState: NESwiftUIUserOnlineState
  public var lastTypingTime: Date?

  public init(accountId: String? = nil,
              isTyping: Bool = false,
              onlineState: NESwiftUIUserOnlineState = .unknown,
              lastTypingTime: Date? = nil) {
    self.accountId = accountId
    self.isTyping = isTyping
    self.onlineState = onlineState
    self.lastTypingTime = lastTypingTime
  }

  public var isOnline: Bool {
    onlineState.isOnline
  }

  public var shouldShowStatus: Bool {
    isTyping || onlineState != .unknown
  }
}

public struct ChatSessionState: Equatable {
  public var phase: NEChatKitLoadPhase
  public var isLoadingOlder: Bool
  public var isLoadingNewer: Bool
  public var hasMoreOlder: Bool
  public var hasMoreNewer: Bool
  public var oldestAnchorMessageId: String?
  public var newestAnchorMessageId: String?
  public var visibleMessageAnchorId: String?
  public var timelineScrollTarget: ChatTimelineScrollTarget?
  public var timelinePresentationGeneration: Int
  public var keepsTimelineBottomPinned: Bool
  public var rows: [MessageRowState]
  public var sessionTitle: String?
  public var input: ChatInputState
  public var topMessage: TopMessageState?
  public var newMessageIndicator: NewMessageIndicatorState?
  public var operationMenu: OperationMenuState?
  public var multiSelect: MultiSelectState?
  public var audioPlayback: ChatAudioPlaybackState
  public var readSync: ChatReadSyncState
  public var clientRuntime: ChatClientRuntimeState
  public var topic: ChatTopicState?
  public var p2pPresence: P2PChatPresenceState
  public var inputTranslation: ChatInputTranslationState?
  public var forwardSheet: ChatForwardSheetState?
  public var pendingConfirmation: ChatPendingConfirmation?
  public var teamLifecycleAlert: ChatTeamLifecycleAlertState?
  public var toast: ChatToastState?
  public var route: ChatRouteState

  public init(phase: NEChatKitLoadPhase = .idle,
              isLoadingOlder: Bool = false,
              isLoadingNewer: Bool = false,
              hasMoreOlder: Bool = true,
              hasMoreNewer: Bool = false,
              oldestAnchorMessageId: String? = nil,
              newestAnchorMessageId: String? = nil,
              visibleMessageAnchorId: String? = nil,
              timelineScrollTarget: ChatTimelineScrollTarget? = nil,
              timelinePresentationGeneration: Int = 0,
              keepsTimelineBottomPinned: Bool = false,
              rows: [MessageRowState] = [],
              sessionTitle: String? = nil,
              input: ChatInputState = ChatInputState(),
              topMessage: TopMessageState? = nil,
              newMessageIndicator: NewMessageIndicatorState? = nil,
              operationMenu: OperationMenuState? = nil,
              multiSelect: MultiSelectState? = nil,
              audioPlayback: ChatAudioPlaybackState = ChatAudioPlaybackState(),
              readSync: ChatReadSyncState = ChatReadSyncState(),
              clientRuntime: ChatClientRuntimeState = ChatClientRuntimeState(),
              topic: ChatTopicState? = nil,
              p2pPresence: P2PChatPresenceState = P2PChatPresenceState(),
              inputTranslation: ChatInputTranslationState? = nil,
              forwardSheet: ChatForwardSheetState? = nil,
              pendingConfirmation: ChatPendingConfirmation? = nil,
              teamLifecycleAlert: ChatTeamLifecycleAlertState? = nil,
              toast: ChatToastState? = nil,
              route: ChatRouteState = ChatRouteState()) {
    self.phase = phase
    self.isLoadingOlder = isLoadingOlder
    self.isLoadingNewer = isLoadingNewer
    self.hasMoreOlder = hasMoreOlder
    self.hasMoreNewer = hasMoreNewer
    self.oldestAnchorMessageId = oldestAnchorMessageId
    self.newestAnchorMessageId = newestAnchorMessageId
    self.visibleMessageAnchorId = visibleMessageAnchorId
    self.timelineScrollTarget = timelineScrollTarget
    self.timelinePresentationGeneration = timelinePresentationGeneration
    self.keepsTimelineBottomPinned = keepsTimelineBottomPinned
    self.rows = rows
    self.sessionTitle = sessionTitle
    self.input = input
    self.topMessage = topMessage
    self.newMessageIndicator = newMessageIndicator
    self.operationMenu = operationMenu
    self.multiSelect = multiSelect
    self.audioPlayback = audioPlayback
    self.readSync = readSync
    self.clientRuntime = clientRuntime
    self.topic = topic
    self.p2pPresence = p2pPresence
    self.inputTranslation = inputTranslation
    self.forwardSheet = forwardSheet
    self.pendingConfirmation = pendingConfirmation
    self.teamLifecycleAlert = teamLifecycleAlert
    self.toast = toast
    self.route = route
  }
}
