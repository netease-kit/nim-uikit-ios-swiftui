// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit

public enum ChatPreviewFixtures {
  public static let context = ChatSessionContext(
    kind: .p2p,
    conversationId: "p2p-preview",
    title: "Preview Chat"
  )

  public static let rows = [
    MessageRowState(
      id: "incoming-text",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .text("Hello from UIKit behavior, rendered by SwiftUI."),
      deliveryState: .sent,
      timeDividerText: "10:00"
    ),
    MessageRowState(
      id: "incoming-rich-text",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .richText(title: "Rich text title", body: "Line one\nLine two with **markdown** fallback."),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "incoming-mention-highlight",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .text("Hi @Me please review this."),
      deliveryState: .sent,
      textHighlights: [
        MessageTextHighlightState(start: 3, end: 6, kind: .mention),
      ]
    ),
    MessageRowState(
      id: "incoming-keyword-highlight",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .text("Keyword search result fixture."),
      deliveryState: .sent,
      textHighlights: [
        MessageTextHighlightState(start: 0, end: 7, kind: .keyword),
      ]
    ),
    MessageRowState(
      id: "incoming-emoticon",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .text("UIKit emoticon tag [Laugh] renders as an image."),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "outgoing-text",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .text("This is the first generated chat foundation."),
      deliveryState: .read,
      readReceipt: MessageReadReceiptState(
        readCount: 1,
        unreadCount: 0,
        isP2PRead: true,
        timestamp: Date().timeIntervalSince1970
      ),
      isPinned: true
    ),
    MessageRowState(
      id: "outgoing-pending",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .text("Sending progress fixture."),
      deliveryState: .pending(progress: 0.42)
    ),
    MessageRowState(
      id: "outgoing-failed",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .text("Failed state fixture."),
      deliveryState: .failed("Network unavailable")
    ),
    MessageRowState(
      id: "image",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .image(MessageMediaState(width: 1280, height: 720)),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "audio",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .audio(MessageAudioState(duration: 12, isPlaying: true)),
      deliveryState: .sent,
      voiceToText: MessageVoiceToTextState(text: "Converted voice text", phase: .converted)
    ),
    MessageRowState(
      id: "video",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .video(MessageMediaState(width: 640, height: 960, duration: 18)),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "file",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .file(MessageFileState(name: "UIKitSwiftUI-plan.pdf", sizeText: "248 KB")),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "location",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .location(
        MessageLocationState(latitude: 30.27,
                             longitude: 120.15,
                             title: "Hangzhou",
                             subtitle: "Location message display placeholder")
      ),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "call",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .call(MessageCallState(summary: "Video call ended, 03:12", type: 2)),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "custom",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .custom(title: "Custom order card", body: "Order #20260602 is ready for review."),
      deliveryState: .sent
    ),
    MessageRowState(
      id: "multi-forward",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .multiForward(
        MessageMultiForwardState(
          title: "Chat History",
          url: "https://example.com/forward.json",
          md5: "fixture-md5",
          sessionId: "p2p-preview",
          summaries: [
            MessageMultiForwardSummaryState(senderNick: "Friend", content: "First forwarded message"),
            MessageMultiForwardSummaryState(senderNick: "Me", content: "Second forwarded message"),
          ]
        )
      ),
      deliveryState: .sent,
      isSelected: true
    ),
    MessageRowState(
      id: "reply",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .reply(preview: "Friend: original image", content: BoxedMessageContentState(.image(MessageMediaState(width: 320, height: 240)))),
      deliveryState: .sent,
      reply: MessageReplyState(
        messageClientId: "origin-image",
        senderId: "friend",
        senderName: "Friend",
        preview: "original image",
        isResolved: true
      )
    ),
    MessageRowState(
      id: "revoke",
      senderId: "friend",
      senderName: "Friend",
      direction: .system,
      content: .revoke("Friend recalled a message"),
      deliveryState: .none
    ),
    MessageRowState(
      id: "revoke-reedit",
      senderId: "me",
      senderName: "Me",
      direction: .outgoing,
      content: .revoke("Message recalled"),
      deliveryState: .sent,
      reedit: ChatReeditState(
        text: "Original text ready for re-edit.",
        revokeTime: Date().timeIntervalSince1970
      )
    ),
    MessageRowState(
      id: "tip",
      senderId: nil,
      senderName: nil,
      direction: .system,
      content: .tip("You pinned this message"),
      deliveryState: .none,
      suppressesTimeDivider: true
    ),
    MessageRowState(
      id: "ai-stream",
      senderId: "ai-assistant",
      senderName: "AI",
      direction: .incoming,
      content: .aiStream(text: "Here is a streaming answer", isFinished: false, error: nil),
      deliveryState: .sent,
      aiStreamActionPhase: .stopping
    ),
    MessageRowState(
      id: "ai-stream-finished",
      senderId: "ai-assistant",
      senderName: "AI",
      direction: .incoming,
      content: .aiStream(text: "Finished AI answer", isFinished: true, error: nil),
      deliveryState: .sent,
      aiStreamActionPhase: .idle
    ),
    MessageRowState(
      id: "ai-stream-failed",
      senderId: "ai-assistant",
      senderName: "AI",
      direction: .incoming,
      content: .aiStream(text: "Partial AI answer", isFinished: false, error: "Stream interrupted"),
      deliveryState: .failed("Stream interrupted"),
      aiStreamActionPhase: .failed("retry available")
    ),
    MessageRowState(
      id: "translated",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .text("Good morning"),
      deliveryState: .sent,
      isTopMessage: true,
      topicRefer: MessageTopicReferState(
        conversationId: "team-preview",
        topicId: 1001,
        createTime: Date().timeIntervalSince1970
      )
    ),
    MessageRowState(
      id: "unsupported",
      senderId: "friend",
      senderName: "Friend",
      direction: .incoming,
      content: .unsupported("Unsupported custom attachment"),
      deliveryState: .sent
    ),
  ]

  public static var sessionState: ChatSessionState {
    ChatSessionState(
      phase: .loaded,
      isLoadingOlder: true,
      hasMoreOlder: true,
      oldestAnchorMessageId: rows.first?.id,
      newestAnchorMessageId: rows.last?.id,
      visibleMessageAnchorId: "incoming-rich-text",
      timelineScrollTarget: ChatTimelineScrollTarget(
        messageId: "translated",
        anchor: .center,
        sequence: 1
      ),
      rows: rows,
      input: ChatInputState(
        text: "@Friend fixture message",
        mode: .more,
        reply: ChatReplyState(id: "incoming-text", preview: "Friend: Hello from UIKit behavior"),
        isSendEnabled: true,
        recording: ChatVoiceRecordingState(
          phase: .recording,
          progress: ChatVoiceRecordingProgressState(duration: 9, level: 0.72, remainingTime: 51)
        ),
        validation: ChatInputValidationState(characterCount: 23, characterLimit: 500),
        mentionedAccountIds: Set(["friend"]),
        mentions: [
          ChatMentionState(accountId: "friend", displayText: "@Friend", start: 0, end: 7),
        ]
      ),
      topMessage: TopMessageState(
        id: "translated",
        title: "Pinned fixture",
        subtitle: "Tap to focus the top message",
        source: .teamTop(canClose: true),
        row: rows.first { $0.id == "translated" }
      ),
      newMessageIndicator: NewMessageIndicatorState(count: 3, firstMessageId: "ai-stream"),
      operationMenu: OperationMenuState(
        messageId: "translated",
        operations: [.copy, .reply, .forward, .pin, .readReceipt, .multiSelect]
      ),
      multiSelect: MultiSelectState(
        selection: NEChatKitSelectionState<String>(
          ids: Set(["multi-forward", "translated"]),
          limit: 50
        )
      ),
      audioPlayback: ChatAudioPlaybackState(messageId: "audio", phase: .playing),
      readSync: ChatReadSyncState(
        phase: .failed("Read sync failed"),
        lastReadTime: Date().timeIntervalSince1970,
        lastSyncedMessageIds: ["outgoing-text", "translated"],
        didClearUnread: true
      ),
      clientRuntime: ChatClientRuntimeState(
        connectionPhase: .waiting,
        loginPhase: .loggedIn,
        dataSync: ChatDataSyncState(type: 1, phase: .syncing),
        isNetworkBroken: true,
        lastErrorMessage: "Network waiting"
      ),
      topic: ChatTopicState(title: "Topic Preview", isRemoved: false),
      inputTranslation: ChatInputTranslationState(
        selectedLanguage: "English",
        languages: [
          ChatTranslationLanguageState(code: "English", title: "English"),
          ChatTranslationLanguageState(code: "Japanese", title: "Japanese"),
        ],
        phase: .translated,
        translatedText: "Translated fixture message"
      ),
      forwardSheet: ChatForwardSheetState(
        request: ChatForwardRequest(
          context: context,
          messageIds: ["outgoing-text", "translated"],
          merged: false
        ),
        recentTargets: [
          ChatForwardTargetState(conversationId: "p2p-friend", title: "Friend"),
          ChatForwardTargetState(conversationId: "team-preview", title: "Team"),
        ],
        selectedTargetIds: Set(["p2p-friend"]),
        comment: "Forward comment fixture"
      ),
      pendingConfirmation: .deleteSelected(messageIds: ["multi-forward", "translated"]),
      toast: ChatToastState(message: "Fixture warning toast", style: .warning),
      route: ChatRouteState(
        currentRoute: .mediaPreview(
          ChatMediaPreviewState(
            id: "image",
            kind: .image,
            media: MessageMediaState(width: 1280, height: 720),
            title: "Image preview"
          )
        ),
        handlingState: .queued
      )
    )
  }

  @MainActor
  public static func viewModel(styleMode: ChatStyleMode = .normal) -> ChatSessionViewModel {
    ChatSessionViewModel(
      context: context,
      config: ChatSwiftUIConfig(styleMode: styleMode),
      initialRows: rows
    )
  }
}
