// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum ChatMessageInteraction: Equatable {
  case avatarTap
  case avatarLongPress
  case messageTap
  case messageLongPress
  case readReceipt
}

public struct ChatMessageInteractionContext: Equatable {
  public var interaction: ChatMessageInteraction
  public var row: MessageRowState
  public var session: ChatSessionContext

  public init(interaction: ChatMessageInteraction,
              row: MessageRowState,
              session: ChatSessionContext) {
    self.interaction = interaction
    self.row = row
    self.session = session
  }
}

public struct ChatCustomMessageContext: Equatable {
  public var row: MessageRowState
  public var session: ChatSessionContext
  public var payload: ChatCustomMessagePayloadState?

  public init(row: MessageRowState,
              session: ChatSessionContext,
              payload: ChatCustomMessagePayloadState? = nil) {
    self.row = row
    self.session = session
    self.payload = payload ?? row.customPayload
  }
}

public struct ChatCustomMessageLayout: Equatable {
  public var contentSize: CGSize?
  public var minContentHeight: CGFloat?
  public var rowHeight: CGFloat?

  public init(contentSize: CGSize? = nil,
              minContentHeight: CGFloat? = nil,
              rowHeight: CGFloat? = nil) {
    self.contentSize = contentSize
    self.minContentHeight = minContentHeight.map { max(0, $0) }
    self.rowHeight = rowHeight.map { max(0, $0) }
  }
}

public struct ChatInputAccessoryContext: Equatable {
  public var input: ChatInputState
  public var session: ChatSessionContext

  public init(input: ChatInputState,
              session: ChatSessionContext) {
    self.input = input
    self.session = session
  }
}

public enum ChatBodyContentPlacement: String, Equatable {
  case top
  case bottom
}

public struct ChatBodyContentContext: Equatable {
  public var session: ChatSessionContext
  public var state: ChatSessionState
  public var placement: ChatBodyContentPlacement

  public init(session: ChatSessionContext,
              state: ChatSessionState,
              placement: ChatBodyContentPlacement) {
    self.session = session
    self.state = state
    self.placement = placement
  }
}

public struct ChatInputBarLayout: Equatable {
  public var containerHorizontalPadding: CGFloat
  public var containerVerticalPadding: CGFloat
  public var textLeadingInset: CGFloat
  public var textTrailingInset: CGFloat

  public init(containerHorizontalPadding: CGFloat = 8,
              containerVerticalPadding: CGFloat = 3,
              textLeadingInset: CGFloat = 0,
              textTrailingInset: CGFloat = 0) {
    self.containerHorizontalPadding = max(0, containerHorizontalPadding)
    self.containerVerticalPadding = max(0, containerVerticalPadding)
    self.textLeadingInset = max(0, textLeadingInset)
    self.textTrailingInset = max(0, textTrailingInset)
  }
}

public struct ChatInputBarActions {
  public var updateText: (String) -> Void
  public var setMode: (ChatInputMode) -> Void
  public var cancelReply: () -> Void
  public var appendEmoji: (ChatEmojiState) -> Void
  public var deleteBackward: () -> Void
  public var handleMoreAction: (ChatMoreActionState) -> Void
  public var beginVoiceRecording: () -> Void
  public var updateVoiceRecording: (Bool) -> Void
  public var endVoiceRecording: (Bool) -> Void
  public var requestMentionSelection: () -> Void
  public var send: () -> Void

  public init(updateText: @escaping (String) -> Void,
              setMode: @escaping (ChatInputMode) -> Void,
              cancelReply: @escaping () -> Void,
              appendEmoji: @escaping (ChatEmojiState) -> Void,
              deleteBackward: @escaping () -> Void,
              handleMoreAction: @escaping (ChatMoreActionState) -> Void,
              beginVoiceRecording: @escaping () -> Void,
              updateVoiceRecording: @escaping (Bool) -> Void,
              endVoiceRecording: @escaping (Bool) -> Void,
              requestMentionSelection: @escaping () -> Void,
              send: @escaping () -> Void) {
    self.updateText = updateText
    self.setMode = setMode
    self.cancelReply = cancelReply
    self.appendEmoji = appendEmoji
    self.deleteBackward = deleteBackward
    self.handleMoreAction = handleMoreAction
    self.beginVoiceRecording = beginVoiceRecording
    self.updateVoiceRecording = updateVoiceRecording
    self.endVoiceRecording = endVoiceRecording
    self.requestMentionSelection = requestMentionSelection
    self.send = send
  }
}

public struct ChatInputBarContentContext {
  public var input: ChatInputState
  public var session: ChatSessionContext
  public var layout: ChatInputBarLayout
  public var actions: ChatInputBarActions

  public init(input: ChatInputState,
              session: ChatSessionContext,
              layout: ChatInputBarLayout,
              actions: ChatInputBarActions) {
    self.input = input
    self.session = session
    self.layout = layout
    self.actions = actions
  }
}

public struct ChatSecurityWarningContext: Equatable {
  public var session: ChatSessionContext
  public var isDismissed: Bool
  public var dismiss: () -> Void

  public init(session: ChatSessionContext,
              isDismissed: Bool,
              dismiss: @escaping () -> Void) {
    self.session = session
    self.isDismissed = isDismissed
    self.dismiss = dismiss
  }

  public static func == (lhs: ChatSecurityWarningContext,
                         rhs: ChatSecurityWarningContext) -> Bool {
    lhs.session == rhs.session && lhs.isDismissed == rhs.isDismissed
  }
}

public struct ChatThemeTokenContext {
  public var styleMode: ChatStyleMode
  public var baseToken: ChatThemeToken

  public init(styleMode: ChatStyleMode,
              baseToken: ChatThemeToken) {
    self.styleMode = styleMode
    self.baseToken = baseToken
  }
}

public struct ChatTeamSettingActions {
  public var onBack: () -> Void
  public var onSelectMessage: (PinMessageSelection) -> Void

  public init(onBack: @escaping () -> Void,
              onSelectMessage: @escaping (PinMessageSelection) -> Void) {
    self.onBack = onBack
    self.onSelectMessage = onSelectMessage
  }
}

public struct ChatSwiftUIConfig {
  public static let minRevokeTimeGapMinutes = 2
  public static let maxRevokeTimeGapMinutes = 10080

  public var styleMode: ChatStyleMode
  public var titleProvider: ((ChatSessionContext) -> String?)?
  public var securityWarningProvider: ((ChatSessionContext) -> AnyView?)?
  public var securityWarningContentProvider: ((ChatSecurityWarningContext) -> AnyView?)?
  public var bodyTopContentProvider: ((ChatBodyContentContext) -> AnyView?)?
  public var bodyBottomContentProvider: ((ChatBodyContentContext) -> AnyView?)?
  public var messageContentProvider: ((ChatCustomMessageContext) -> AnyView?)?
  public var customMessageLayoutProvider: ((ChatCustomMessageContext) -> ChatCustomMessageLayout?)?
  public var inputAccessoryProvider: ((ChatInputAccessoryContext) -> AnyView?)?
  public var inputBarContentProvider: ((ChatInputBarContentContext) -> AnyView?)?
  public var inputBarLayout: ChatInputBarLayout
  public var messageInteractionHandler: ((ChatMessageInteractionContext) -> Bool)?
  public var messageOperationsProvider: ((MessageRowState, ChatSessionContext) -> [MessageOperation])?
  public var disabledMessageOperations: Set<MessageOperation>
  public var moreActionsProvider: ((ChatSessionContext) -> [ChatMoreActionState])?
  public var emojisProvider: (() -> [ChatEmojiState])?
  public var p2pSettingPinMessagesViewProvider: ((String, ChatThemeToken, @escaping () -> Bool, @escaping (PinMessageSelection) -> Void, @escaping () -> Void) -> AnyView?)?
  public var teamSettingViewProvider: ((String, ChatSessionContext) -> AnyView?)?
  public var teamSettingViewProviderWithBackAction: ((String, ChatSessionContext, @escaping () -> Void) -> AnyView?)?
  public var teamSettingViewProviderWithActions: ((String, ChatSessionContext, ChatTeamSettingActions) -> AnyView?)?
  public var userProfilePushViewProvider: ((ChatUserProfileRequest, ChatThemeToken) -> AnyView?)?
  /// Profile host that can replace the current chat route after the profile opens a P2P conversation.
  public var userProfilePushViewProviderWithChatRoute: ((ChatUserProfileRequest, ChatThemeToken, @escaping (String, String) -> Void) -> AnyView?)?
  public var nativeBoundaryPolicy: ChatNativeBoundaryPolicy
  public var nativeBoundaryHandler: ChatNativeBoundaryHandling?
  public var mediaPreviewHandler: ChatMediaPreviewHandling?
  public var mediaImageSaveHandler: ((ChatMediaItem) async throws -> Void)?
  public var fileInteractionHandler: ChatFileInteractionHandling?
  public var audioPlaybackHandler: ChatAudioPlaybackHandling?
  public var audioRecordingHandler: ChatAudioRecordingHandling?
  public var locationInteractionHandler: ChatLocationInteractionHandling?
  public var callInteractionHandler: ChatCallInteractionHandling?
  public var avatarSelectionHandler: ChatAvatarSelectionHandling?
  public var aiRobotConfigClipboardHandler: AIRobotConfigClipboardHandling?
  public var clipboardHandler: ChatClipboardHandling?
  public var urlInteractionHandler: ChatURLInteractionHandling?
  public var forwardSelectionHandler: ChatForwardSelectionHandling?
  public var recentForwardProvider: ChatRecentForwardProviding?
  public var mentionSelectionHandler: ChatMentionSelectionHandling?
  public var userProfileRouter: ChatUserProfileRouting?
  public var p2pDiscussSelectionHandler: ChatP2PDiscussSelectionHandling?
  public var aiStreamActionPerformer: AIStreamActionPerforming?
  public var themeTokenProvider: ((ChatThemeTokenContext) -> ChatThemeToken)?
  public var titleBarRightActionHandler: ((ChatSessionContext) -> Void)?
  public var titleBarRightSystemImageName: String
  public var titleBarRightImageName: String?
  public var shouldShowAvatar: (MessageRowState, ChatSessionContext) -> Bool
  public var shouldShowSenderName: (MessageRowState, ChatSessionContext) -> Bool
  public var shouldShowTitleBar: Bool
  public var shouldShowTitleBarRightAction: Bool
  public var fileSizeLimitMB: Double
  public var imageThumbSize: Int
  public var maxTeamReadReceiptCount: Int
  public var revokeEditTimeGapMinutes: Int
  public var maxTextMessageLength: Int?
  public var revokeTimeGapMinutes: Int {
    get {
      clampedRevokeTimeGapMinutes
    }
    set {
      clampedRevokeTimeGapMinutes = Self.clampedRevokeTimeGap(newValue)
    }
  }

  private var clampedRevokeTimeGapMinutes: Int
  public var defaultTranslationLanguage: String
  public var translationLanguages: [ChatTranslationLanguageState]
  public var isP2PReadReceiptEnabled: Bool
  public var isTeamReadReceiptEnabled: Bool
  public var isP2PPresenceEnabled: Bool
  public var isApplicationActiveProvider: () -> Bool
  public var conversationAtReminderClearHandler: ((String) -> Void)?

  public init(styleMode: ChatStyleMode = .normal,
              titleProvider: ((ChatSessionContext) -> String?)? = nil,
              securityWarningProvider: ((ChatSessionContext) -> AnyView?)? = nil,
              securityWarningContentProvider: ((ChatSecurityWarningContext) -> AnyView?)? = nil,
              bodyTopContentProvider: ((ChatBodyContentContext) -> AnyView?)? = nil,
              bodyBottomContentProvider: ((ChatBodyContentContext) -> AnyView?)? = nil,
              messageContentProvider: ((ChatCustomMessageContext) -> AnyView?)? = nil,
              customMessageLayoutProvider: ((ChatCustomMessageContext) -> ChatCustomMessageLayout?)? = nil,
              inputAccessoryProvider: ((ChatInputAccessoryContext) -> AnyView?)? = nil,
              inputBarContentProvider: ((ChatInputBarContentContext) -> AnyView?)? = nil,
              inputBarLayout: ChatInputBarLayout = ChatInputBarLayout(),
              messageInteractionHandler: ((ChatMessageInteractionContext) -> Bool)? = nil,
              messageOperationsProvider: ((MessageRowState, ChatSessionContext) -> [MessageOperation])? = nil,
              disabledMessageOperations: Set<MessageOperation> = [],
              moreActionsProvider: ((ChatSessionContext) -> [ChatMoreActionState])? = nil,
              emojisProvider: (() -> [ChatEmojiState])? = nil,
              p2pSettingPinMessagesViewProvider: ((String, ChatThemeToken, @escaping () -> Bool, @escaping (PinMessageSelection) -> Void, @escaping () -> Void) -> AnyView?)? = nil,
              teamSettingViewProvider: ((String, ChatSessionContext) -> AnyView?)? = nil,
              teamSettingViewProviderWithBackAction: ((String, ChatSessionContext, @escaping () -> Void) -> AnyView?)? = nil,
              teamSettingViewProviderWithActions: ((String, ChatSessionContext, ChatTeamSettingActions) -> AnyView?)? = nil,
              userProfilePushViewProvider: ((ChatUserProfileRequest, ChatThemeToken) -> AnyView?)? = nil,
              userProfilePushViewProviderWithChatRoute: ((ChatUserProfileRequest, ChatThemeToken, @escaping (String, String) -> Void) -> AnyView?)? = nil,
              nativeBoundaryPolicy: ChatNativeBoundaryPolicy = .firstPhase,
              nativeBoundaryHandler: ChatNativeBoundaryHandling? = nil,
              mediaPreviewHandler: ChatMediaPreviewHandling? = nil,
              mediaImageSaveHandler: ((ChatMediaItem) async throws -> Void)? = nil,
              fileInteractionHandler: ChatFileInteractionHandling? = nil,
              audioPlaybackHandler: ChatAudioPlaybackHandling? = nil,
              audioRecordingHandler: ChatAudioRecordingHandling? = nil,
              locationInteractionHandler: ChatLocationInteractionHandling? = nil,
              callInteractionHandler: ChatCallInteractionHandling? = nil,
              avatarSelectionHandler: ChatAvatarSelectionHandling? = nil,
              aiRobotConfigClipboardHandler: AIRobotConfigClipboardHandling? = nil,
              clipboardHandler: ChatClipboardHandling? = nil,
              urlInteractionHandler: ChatURLInteractionHandling? = nil,
              forwardSelectionHandler: ChatForwardSelectionHandling? = nil,
              recentForwardProvider: ChatRecentForwardProviding? = ChatRecentForwardProvider.chatKitDefault,
              mentionSelectionHandler: ChatMentionSelectionHandling? = nil,
              userProfileRouter: ChatUserProfileRouting? = nil,
              p2pDiscussSelectionHandler: ChatP2PDiscussSelectionHandling? = nil,
              aiStreamActionPerformer: AIStreamActionPerforming? = nil,
              themeTokenProvider: ((ChatThemeTokenContext) -> ChatThemeToken)? = nil,
              titleBarRightActionHandler: ((ChatSessionContext) -> Void)? = nil,
              titleBarRightSystemImageName: String = "ellipsis",
              titleBarRightImageName: String? = "three_point",
              shouldShowAvatar: @escaping (MessageRowState, ChatSessionContext) -> Bool = { _, _ in true },
              shouldShowSenderName: @escaping (MessageRowState, ChatSessionContext) -> Bool = { row, context in
                context.kind == .team && row.direction == .incoming
              },
              shouldShowTitleBar: Bool = true,
              shouldShowTitleBarRightAction: Bool = true,
              fileSizeLimitMB: Double = 200,
              imageThumbSize: Int = 350,
              maxTeamReadReceiptCount: Int = 200,
              revokeEditTimeGapMinutes: Int = 2,
              maxTextMessageLength: Int? = nil,
              revokeTimeGapMinutes: Int = ChatSwiftUIConfig.maxRevokeTimeGapMinutes,
              defaultTranslationLanguage: String = "zh-CHS",
              translationLanguages: [ChatTranslationLanguageState] = ChatSwiftUIConfig.defaultTranslationLanguages(),
              isP2PReadReceiptEnabled: Bool = true,
              isTeamReadReceiptEnabled: Bool = true,
              isP2PPresenceEnabled: Bool = true,
              isApplicationActiveProvider: @escaping () -> Bool = { true },
              conversationAtReminderClearHandler: ((String) -> Void)? = nil) {
    self.styleMode = styleMode
    self.titleProvider = titleProvider
    self.securityWarningProvider = securityWarningProvider
    self.securityWarningContentProvider = securityWarningContentProvider
    self.bodyTopContentProvider = bodyTopContentProvider
    self.bodyBottomContentProvider = bodyBottomContentProvider
    self.messageContentProvider = messageContentProvider
    self.customMessageLayoutProvider = customMessageLayoutProvider
    self.inputAccessoryProvider = inputAccessoryProvider
    self.inputBarContentProvider = inputBarContentProvider
    self.inputBarLayout = inputBarLayout
    self.messageInteractionHandler = messageInteractionHandler
    self.messageOperationsProvider = messageOperationsProvider
    self.disabledMessageOperations = disabledMessageOperations
    self.moreActionsProvider = moreActionsProvider
    self.emojisProvider = emojisProvider
    self.p2pSettingPinMessagesViewProvider = p2pSettingPinMessagesViewProvider
    self.teamSettingViewProvider = teamSettingViewProvider
    self.teamSettingViewProviderWithBackAction = teamSettingViewProviderWithBackAction
    self.teamSettingViewProviderWithActions = teamSettingViewProviderWithActions
    self.userProfilePushViewProvider = userProfilePushViewProvider
    self.userProfilePushViewProviderWithChatRoute = userProfilePushViewProviderWithChatRoute
    self.nativeBoundaryPolicy = nativeBoundaryPolicy
    self.nativeBoundaryHandler = nativeBoundaryHandler
    self.mediaPreviewHandler = mediaPreviewHandler
    self.mediaImageSaveHandler = mediaImageSaveHandler
    self.fileInteractionHandler = fileInteractionHandler
    self.audioPlaybackHandler = audioPlaybackHandler
    self.audioRecordingHandler = audioRecordingHandler
    self.locationInteractionHandler = locationInteractionHandler
    self.callInteractionHandler = callInteractionHandler
    self.avatarSelectionHandler = avatarSelectionHandler
    self.aiRobotConfigClipboardHandler = aiRobotConfigClipboardHandler
    self.clipboardHandler = clipboardHandler
    self.urlInteractionHandler = urlInteractionHandler
    self.forwardSelectionHandler = forwardSelectionHandler
    self.recentForwardProvider = recentForwardProvider
    self.mentionSelectionHandler = mentionSelectionHandler
    self.userProfileRouter = userProfileRouter
    self.p2pDiscussSelectionHandler = p2pDiscussSelectionHandler
    self.aiStreamActionPerformer = aiStreamActionPerformer
    self.themeTokenProvider = themeTokenProvider
    self.titleBarRightActionHandler = titleBarRightActionHandler
    self.titleBarRightSystemImageName = titleBarRightSystemImageName
    self.titleBarRightImageName = titleBarRightImageName
    self.shouldShowAvatar = shouldShowAvatar
    self.shouldShowSenderName = shouldShowSenderName
    self.shouldShowTitleBar = shouldShowTitleBar
    self.shouldShowTitleBarRightAction = shouldShowTitleBarRightAction
    self.fileSizeLimitMB = max(0, fileSizeLimitMB)
    self.imageThumbSize = max(0, imageThumbSize)
    self.maxTeamReadReceiptCount = max(0, maxTeamReadReceiptCount)
    self.revokeEditTimeGapMinutes = max(1, revokeEditTimeGapMinutes)
    self.maxTextMessageLength = maxTextMessageLength
    clampedRevokeTimeGapMinutes = Self.clampedRevokeTimeGap(revokeTimeGapMinutes)
    self.defaultTranslationLanguage = defaultTranslationLanguage
    self.translationLanguages = translationLanguages
    self.isP2PReadReceiptEnabled = isP2PReadReceiptEnabled
    self.isTeamReadReceiptEnabled = isTeamReadReceiptEnabled
    self.isP2PPresenceEnabled = isP2PPresenceEnabled
    self.isApplicationActiveProvider = isApplicationActiveProvider
    self.conversationAtReminderClearHandler = conversationAtReminderClearHandler
  }

  public var themeToken: ChatThemeToken {
    let baseToken: ChatThemeToken
    switch styleMode {
    case .normal:
      baseToken = .normal
    case .fun:
      baseToken = .fun
    }
    return themeTokenProvider?(
      ChatThemeTokenContext(styleMode: styleMode, baseToken: baseToken)
    ) ?? baseToken
  }

  public static func defaultTranslationLanguages() -> [ChatTranslationLanguageState] {
    [
      ChatTranslationLanguageState(code: "zh-CHS", title: NEChatUIKitSwiftUIBundle.localized("chat_language_chinese", value: "Chinese")),
      ChatTranslationLanguageState(code: "en", title: NEChatUIKitSwiftUIBundle.localized("chat_language_english", value: "English")),
      ChatTranslationLanguageState(code: "ja", title: NEChatUIKitSwiftUIBundle.localized("chat_language_japanese", value: "Japanese")),
      ChatTranslationLanguageState(code: "ko", title: NEChatUIKitSwiftUIBundle.localized("chat_language_korean", value: "Korean")),
      ChatTranslationLanguageState(code: "fr", title: NEChatUIKitSwiftUIBundle.localized("chat_language_french", value: "French")),
      ChatTranslationLanguageState(code: "de", title: NEChatUIKitSwiftUIBundle.localized("chat_language_german", value: "German")),
      ChatTranslationLanguageState(code: "es", title: NEChatUIKitSwiftUIBundle.localized("chat_language_spanish", value: "Spanish")),
    ]
  }

  public static func defaultInputTranslationLanguages() -> [ChatTranslationLanguageState] {
    [
      ChatTranslationLanguageState(
        code: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_prompt_english", value: "English"),
        title: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_english", value: "English")
      ),
      ChatTranslationLanguageState(
        code: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_prompt_japanese", value: "Japanese"),
        title: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_japanese", value: "Japanese")
      ),
      ChatTranslationLanguageState(
        code: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_prompt_korean", value: "Korean"),
        title: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_korean", value: "Korean")
      ),
      ChatTranslationLanguageState(
        code: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_prompt_russian", value: "Russian"),
        title: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_russian", value: "Russian")
      ),
      ChatTranslationLanguageState(
        code: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_prompt_french", value: "French"),
        title: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_french", value: "French")
      ),
      ChatTranslationLanguageState(
        code: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_prompt_german", value: "German"),
        title: NEChatUIKitSwiftUIBundle.localized("chat_input_translation_german", value: "German")
      ),
    ]
  }

  private static func clampedRevokeTimeGap(_ minutes: Int) -> Int {
    min(max(minutes, minRevokeTimeGapMinutes), maxRevokeTimeGapMinutes)
  }

}

public extension ChatSwiftUIConfig {
  static func eraseView<V: View>(_ builder: @escaping (ChatSessionContext) -> V?) -> (ChatSessionContext) -> AnyView? {
    { context in
      builder(context).map({ AnyView($0) })
    }
  }

  static func eraseSecurityWarning<V: View>(_ builder: @escaping (ChatSecurityWarningContext) -> V?) -> (ChatSecurityWarningContext) -> AnyView? {
    { context in
      builder(context).map({ AnyView($0) })
    }
  }

  static func eraseBodyContent<V: View>(_ builder: @escaping (ChatBodyContentContext) -> V?) -> (ChatBodyContentContext) -> AnyView? {
    { context in
      builder(context).map({ AnyView($0) })
    }
  }

  static func eraseMessageView<V: View>(_ builder: @escaping (ChatCustomMessageContext) -> V?) -> (ChatCustomMessageContext) -> AnyView? {
    { context in
      builder(context).map({ AnyView($0) })
    }
  }

  static func eraseInputAccessory<V: View>(_ builder: @escaping (ChatInputAccessoryContext) -> V?) -> (ChatInputAccessoryContext) -> AnyView? {
    { context in
      builder(context).map({ AnyView($0) })
    }
  }

  static func eraseInputBarContent<V: View>(_ builder: @escaping (ChatInputBarContentContext) -> V?) -> (ChatInputBarContentContext) -> AnyView? {
    { context in
      builder(context).map({ AnyView($0) })
    }
  }

}

public extension MessageRowState {
  public var isTextTranslatable: Bool {
    switch content {
    case .text, .richText, .aiStream:
      return true
    default:
      return false
    }
  }
}
