// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Combine
import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

private let initialBottomPinDurationNanoseconds: UInt64 = 2_000_000_000
private let initialLatestScrollTargetFallbackNanoseconds: UInt64 = 1_200_000_000
private let prependRestoreScrollTargetFallbackNanoseconds: UInt64 = 3_000_000_000
private let readVisibilityConfirmationNanoseconds: UInt64 = 120_000_000
private let nativeBoundaryReturnFallbackDelay: TimeInterval = 0.5
private let richTextTitleCharacterLimit = 20

public protocol ChatResourceDownloading {
  func downloadFile(urlString: String,
                    filePath: String,
                    progress: ((UInt) -> Void)?,
                    completion: @escaping (String?, NSError?) -> Void)
}

public struct NEChatKitResourceDownloader: ChatResourceDownloading {
  private let chatRepo: ChatRepo

  public init(chatRepo: ChatRepo = .shared) {
    self.chatRepo = chatRepo
  }

  public func downloadFile(urlString: String,
                           filePath: String,
                           progress: ((UInt) -> Void)?,
                           completion: @escaping (String?, NSError?) -> Void) {
    chatRepo.downloadSwiftUIChatFile(
      urlString: urlString,
      filePath: filePath,
      progress: progress,
      completion: completion
    )
  }
}

@MainActor
public final class ChatSessionViewModel: ObservableObject {
  @Published public private(set) var state: ChatSessionState

  public let context: ChatSessionContext
  public let config: ChatSwiftUIConfig

  private let listenerBinder = ChatListenerBinder()
  private let networkReachabilityManager = NENetworkReachabilityManager()
  private let historyLoader: ChatHistoryLoading
  private let sendPipeline: ChatTextSending
  private let operationPerformer: ChatMessageOperationPerforming
  private let outgoingMessageFactory: ChatOutgoingMessageFactory
  private let aiStreamActionPerformer: AIStreamActionPerforming
  private let readReceiptLoader: ChatReadReceiptStateLoading
  private let readSynchronizer: ChatReadSynchronizing
  private let resourceDownloader: ChatResourceDownloading
  private let clientEventSource: IMKitClient
  private let topicRepo: TopicRepo
  private let aiRepo: AIRepo
  private let currentAccountProvider: () -> String?
  private let isApplicationActiveProvider: () -> Bool
  private var currentTopic: V2NIMTopic?
  private var didAppear = false
  private var pageVisibilityGeneration = UUID()
  private var selectedInputTranslationLanguage: String
  private var inputTranslationRequestId: String?
  private var inputTranslationBatch: InputTranslationBatch?
  private var translatedInputMentions = [ChatMentionState]()
  private var voiceToTextRequestIds = [String: UUID]()
  private var aiStreamActionRequestIds = [String: UUID]()
  private var aiStreamRefreshGeneration = 0
  private var sendRequestIds = [String: UUID]()
  private var sendAttemptIds = [String: UUID]()
  private var retrySendMessageAliases = Set<String>()
  private var outgoingTextPresentationByMessageId = [String: OutgoingTextPresentation]()
  private var pendingMediaFingerprints = [String: MessageMediaFingerprint]()
  private var handledSendFailureTipAttempts = Set<String>()
  private var operationRequestIds = [String: String]()
  private var operationPluginItems = [String: OperationItem]()
  private var selectedMessageText = [String: (text: String, isFullSelection: Bool)]()
  private var establishedTextSelectionMessageIds = Set<String>()
  private var replyResolutionRequestIds = [String: UUID]()
  private var historyRequestGeneration = 0
  private var operationRequestGeneration = 0
  private var boundaryRequestGeneration = 0
  private var nativeBoundaryPresentationLifecycle: NativeBoundaryPresentationLifecycle?
  private var voiceRecordingGeneration = 0
  private var audioPlaybackGeneration = 0
  private var mediaDownloadGenerationByMessageId = [String: Int]()
  private var pendingReplyAttachmentDownload: PendingReplyAttachmentDownload?
  private var forwardRequestGeneration = 0
  private var forwardSourceMessagesByRequestKey = [String: [V2NIMMessage]]()
  private var readSyncRequestGeneration = 0
  private var readSyncDebounceTask: Task<Void, Never>?
  private var pendingReadSyncMessagesById = [String: V2NIMMessage]()
  private var pendingConversationReadSync = false
  private var isReadSyncInFlight = false
  private var readReceiptRefreshGeneration = 0
  private var topMessageRequestGeneration = 0
  private var topicRequestGeneration = 0
  private var moreActionRefreshGeneration = 0
  private var mentionSelectionGeneration = 0
  private var userProfileRouteGeneration = 0
  private var teamLifecycleRequestGeneration = 0
  private var teamTitleRequestGeneration = 0
  private var teamMemberCount: Int?
  private var teamInputMuteRequestGeneration = 0
  private var teamMemberDisplayRequestGeneration = 0
  private var teamMemberDisplayInfoByAccountId = [String: NETeamMemberDisplayInfo]()
  private var teamMemberDisplayInfoGenerationByAccountId = [String: Int]()
  private var pendingTeamMemberDisplayAccountIds = Set<String>()
  private var localTeamLifecycleExitInFlightIds = Set<String>()
  private var locallyCompletedTeamLifecycleIds = Set<String>()
  private var contactDisplayRequestGeneration = 0
  private var forcedContactDisplayGenerationByAccountId = [String: Int]()
  private var contactDisplayInfoByAccountId = [String: NEUserWithFriend]()
  private var pendingContactDisplayAccountIds = Set<String>()
  private let scrollTargetScopeId = UUID().uuidString
  private var scrollTargetSequence = 0
  private var timelineBottomPinGeneration = 0
  private var pendingPrependAnchorId: String?
  private var pendingPrependLoadedCount = 0
  private var pendingPrependLoadedTailId: String?
  private var pendingOlderHistoryLoad: PendingOlderHistoryLoad?
  private var visibleTimelineAnchorId: String?
  private var timelineRestoreAnchorId: String?
  private var timelineRestoreBottomMessageId: String?
  private var timelineRestoreWasAtBottom = true
  private var hasRouteTimelineRestoreSnapshot = false
  private var preservesPendingNewMessageIndicatorDuringRouteRestore = false
  private var lastStableVisibleTimelineAnchorId: String?
  private var visibleTimelineRowIds = Set<String>()
  private var isTimelineBottomVisible = true
  private var isPageVisible = false
  // The view must report rows after the current foreground transition before
  // read receipts can be sent. A visible SwiftUI hierarchy alone is stale while
  // an app is backgrounded or a child route covers the timeline.
  private var hasConfirmedForegroundTimelineVisibility = false
  private var isInputAreaFocused = false
  private var preservesTimelinePositionAfterInputDismissal = false
  private var needsVisibleReadSyncAfterPageActivation = false
  private var receivedMessagesWhilePageHidden = false
  private var isProgrammaticallyScrollingToLatest = false
  private var isHistoryContextActive = false
  private var shouldScrollToLatestAfterReload = false
  private var shouldRetryOlderHistoryAfterReconnect = false
  private var isSystemNetworkReachable = true
  private var isSDKTransportConnectedAfterNetworkBreak = false
  /// A history request can cross the reachability boundary while the SDK
  /// still reports a connected transport. The timeline needs this dedicated
  /// gate so its top probe cannot retry during that window.
  @Published public private(set) var isOlderPaginationSuspendedForNetworkBreak = false
  private var pendingNewMessageIds = [PendingNewMessageItem]()
  private var receivedMessagesWhileMultiSelect = false
  private var pendingHistoryNewMessages = [V2NIMMessage]()
  private var revokedPendingMessageIds = Set<String>()
  private var remoteTypingTimeoutTask: Task<Void, Never>?
  private var lastSentTypingState = false
  private var subscribedPresenceAccountId: String?
  private var messageContextById = [String: V2NIMMessage]()
  private var oldestHistoryAnchorMessage: V2NIMMessage?
  private var newestHistoryAnchorMessage: V2NIMMessage?
  private var pinnedMessageInfoById = [String: PinnedMessageDisplayInfo]()
  private var pinnedMessageRequestGeneration = 0
  private var didLoadPinnedMessageInfo = false
  private var isInsertingAIWelcomeMessage = false
  private var didInsertAIWelcomeMessage = false
  private var pendingMentionTriggerLocation: Int?
  private var senderDisplayInfoByAccountId = [String: SenderDisplayInfo]()

  private struct PinnedMessageDisplayInfo: Equatable {
    var operatorId: String?
    var operatorName: String?
  }

  private struct PendingOlderHistoryLoad {
    var request: ChatHistoryLoadRequest
    var requestStartedWhileNetworkBroken: Bool
  }

  private struct NativeBoundaryPresentationLifecycle {
    var id = UUID()
    var didComplete = false
    var didDisappear = false
    var didReturn = false
  }

  private struct SenderDisplayInfo {
    var senderName: String?
    var avatarURL: URL?
  }

  private struct OutgoingTextPresentation {
    var content: MessageContentState
    var textHighlights: [MessageTextHighlightState]
  }

  private struct InputTranslationSegment {
    var sourceText: String
    var outputPrefix: String
    var outputSuffix: String
    var translatedText: String?
    var mention: ChatMentionState?
  }

  private struct InputTranslationBatch {
    var requestId: String
    var accountId: String
    var promptKey: String
    var targetLanguage: String
    var segments: [InputTranslationSegment]
    var activeSegmentIndex: Int?
    var activeRequestId: String?
  }

  private struct PendingNewMessageItem: Equatable {
    var primaryId: String
    var aliases: Set<String>
  }

  private enum PendingReplyAttachmentDownload {
    case video(row: MessageRowState, media: MessageMediaState)
    case file(row: MessageRowState, file: MessageFileState)

    var row: MessageRowState {
      switch self {
      case let .video(row, _), let .file(row, _):
        return row
      }
    }
  }

  public init(context: ChatSessionContext,
              config: ChatSwiftUIConfig = ChatSwiftUIConfig(),
              initialRows: [MessageRowState] = [],
              historyLoader: ChatHistoryLoading = NEChatKitHistoryLoader(),
              sendPipeline: ChatTextSending = NEChatKitSendPipeline(),
              operationPerformer: ChatMessageOperationPerforming = NEChatKitMessageOperationPerformer(),
              outgoingMessageFactory: ChatOutgoingMessageFactory = ChatOutgoingMessageFactory(),
              aiStreamActionPerformer: AIStreamActionPerforming? = nil,
              readReceiptLoader: ChatReadReceiptStateLoading = NEChatKitReadReceiptStateLoader(),
              readSynchronizer: ChatReadSynchronizing = NEChatKitReadSynchronizer(),
              resourceDownloader: ChatResourceDownloading = NEChatKitResourceDownloader(),
              clientEventSource: IMKitClient = .instance,
              topicRepo: TopicRepo = .shared,
              aiRepo: AIRepo = .shared,
              currentAccountProvider: @escaping () -> String? = { IMKitClient.instance.account() },
              isApplicationActiveProvider: (() -> Bool)? = nil) {
    self.context = context
    self.config = config
    self.historyLoader = historyLoader
    self.sendPipeline = sendPipeline
    self.operationPerformer = operationPerformer
    self.outgoingMessageFactory = outgoingMessageFactory
    self.aiStreamActionPerformer = aiStreamActionPerformer ??
      config.aiStreamActionPerformer ??
      NEChatKitAIStreamActionPerformer()
    self.readReceiptLoader = readReceiptLoader
    self.readSynchronizer = readSynchronizer
    self.resourceDownloader = resourceDownloader
    self.clientEventSource = clientEventSource
    self.topicRepo = topicRepo
    self.aiRepo = aiRepo
    self.currentAccountProvider = currentAccountProvider
    self.isApplicationActiveProvider = isApplicationActiveProvider ?? config.isApplicationActiveProvider
    currentTopic = context.topic
    let accountId = currentAccountProvider() ?? ""
    selectedInputTranslationLanguage = UserDefaults.standard.string(forKey: accountId + "_language") ?? ""
    state = ChatSessionState(phase: .idle, rows: initialRows)
    refreshInitialP2PPresenceState()
    refreshTopicState()
    refreshMoreActions()
    state.input.emojis = config.emojisProvider?() ?? ChatInputState.defaultEmojis()
    state.input.validation = makeInputValidation(for: state.input.text)
    refreshAnchors()
    cacheMessageContext(context.pendingMessages)
    if context.anchorMessage != nil {
      isHistoryContextActive = true
    }
    updateInputSendEnabledState()
  }

  deinit {
    listenerBinder.cancel()
  }

  public var title: String {
    config.titleProvider?(context) ??
      state.topic?.title ??
      state.sessionTitle ??
      context.title ??
      context.sessionName ??
      context.conversationId
  }

  public var timelineScrollTarget: ChatTimelineScrollTarget? {
    state.timelineScrollTarget
  }

  public var headerActions: [ChatHeaderAction] {
    ChatHeaderAction.allCases.filter(isHeaderActionAvailable)
  }

  private var activeContext: ChatSessionContext {
    context.replacingTopic(currentTopic)
  }

  public func onAppear() {
    nativeBoundaryPageDidAppearIfNeeded()
    isSystemNetworkReachable = clientEventSource.swiftUICurrentNetworkAvailable
    isSDKTransportConnectedAfterNetworkBreak =
      clientEventSource.swiftUICurrentConnectStatus == .CONNECT_STATUS_CONNECTED
    state.clientRuntime.isNetworkBroken = !isSystemNetworkReachable
    refreshP2PDisplayStateIfNeeded()
    guard !didAppear else {
      return
    }
    didAppear = true
    refreshMoreActions()
    attachListeners()
    if IMKitConfigCenter.shared.enableAIUser {
      NEAIUserManager.shared.getAIUserList()
    }
    clearConversationUnreadForChatLifecycle()
    loadInitialIfNeeded()
    if !state.rows.isEmpty {
      loadNewerMessagesIfPossible()
      refreshReadReceiptsIfNeeded(for: state.rows.compactMap { messageContextMessage(for: $0) })
    }
    restoreTimelinePositionAfterReturnIfNeeded()
    refreshContactDisplayInfosIfNeeded()
    refreshTeamMemberDisplayInfosIfNeeded()
    validateTeamLifecycleIfNeeded()
    refreshTeamTitleIfNeeded()
    refreshTeamInputMuteStateIfNeeded()
    refreshPinnedMessagesIfNeeded()
    loadTeamTopMessageIfNeeded()
    syncReadState(for: [])
  }

  public func onDisappear() {
    guard didAppear else {
      return
    }
    if state.route.currentRoute == nil, isPageVisible {
      clearConversationUnreadForChatLifecycle()
    }
    flushPendingReadStateBeforePageExit()
    // UIKit clears isCurrentPage in viewWillDisappear for every exit path.
    // Keep the same invariant so a retained SwiftUI chat cannot send reads
    // while an outer navigation destination covers it.
    setPageVisible(false)
    nativeBoundaryPageDidDisappearIfNeeded()
    // SwiftUI may clear currentRoute before delivering onDisappear for a
    // system boundary or full-screen preview. The route-scoped timeline
    // snapshot remains the reliable signal that this chat is only covered.
    if state.route.currentRoute != nil ||
      hasRouteTimelineRestoreSnapshot ||
      nativeBoundaryPresentationLifecycle != nil {
      sendLocalTypingStateIfNeeded(false, force: true)
      stopActiveMedia()
      return
    }
    didAppear = false
    config.conversationAtReminderClearHandler?(context.conversationId)
    if shouldCaptureTimelineRestoreOnDisappear {
      if !hasRouteTimelineRestoreSnapshot {
        captureTimelineRestoreAnchor()
      }
    } else {
      if !hasRouteTimelineRestoreSnapshot {
        discardTimelinePositionRestore()
      }
    }
    cancelTimelineBottomPinning()
    sendLocalTypingStateIfNeeded(false, force: true)
    stopActiveMedia()
    listenerBinder.cancel()
    invalidateTransientRequests(
      preservingNativeBoundaryRequest: state.route.handlingState == .handling
    )
  }

  private var shouldCaptureTimelineRestoreOnDisappear: Bool {
    true
  }

  public func consumeToast(_ toast: ChatToastState) {
    guard state.toast?.id == toast.id else {
      return
    }
    state.toast = nil
  }

  public func retryInitialLoad() {
    guard case .failed = state.phase else {
      return
    }
    if state.rows.isEmpty {
      loadInitialIfNeeded()
    } else {
      loadOlderMessages()
    }
  }

  public var canLoadOlderMessages: Bool {
    !isOlderPaginationSuspendedForNetworkBreak &&
      state.hasMoreOlder &&
      !state.isLoadingOlder
  }

  public func loadOlderMessages(visibleAnchorId: String? = nil) {
    guard canLoadOlderMessages else {
      logHistoryTriggerBlocked(
        reason: "viewModelGuard",
        visibleAnchorId: visibleAnchorId
      )
      return
    }

    let isInitialLoad = state.rows.isEmpty
    if !isInitialLoad {
      cancelTimelineBottomPinning()
    }
    let prependAnchorId = isInitialLoad ? nil : firstExistingRowId(
      matching: [
        visibleAnchorId,
        visibleTimelineAnchorId,
        state.rows.first?.id,
      ]
    )
    pendingPrependAnchorId = prependAnchorId
    pendingPrependLoadedCount = 0
    pendingPrependLoadedTailId = nil
    let requestStartedWhileNetworkBroken = !isHistoryTransportReady
    state.isLoadingOlder = true
    state.phase = .loadingMore
    let request = ChatHistoryLoadRequest(
      conversationId: context.conversationId,
      context: activeContext,
      anchorMessageId: state.oldestAnchorMessageId,
      anchorMessage: historyAnchorMessage(
        oldestHistoryAnchorMessage,
        matching: state.oldestAnchorMessageId
      ),
      direction: state.rows.isEmpty ? .initial : .older,
      teamReadReceiptDisplayLimit: config.maxTeamReadReceiptCount,
      imageThumbSize: config.imageThumbSize
    )
    let pendingLoad = PendingOlderHistoryLoad(
      request: request,
      requestStartedWhileNetworkBroken: requestStartedWhileNetworkBroken
    )
    if state.isLoadingNewer {
      pendingOlderHistoryLoad = pendingLoad
      NEChatSwiftUILogger.log(
        "offlineHistory olderQueuedBehindNewer conversationId=\(context.conversationId) anchorId=\(request.anchorMessageId ?? "nil") rows=\(state.rows.count)"
      )
    } else {
      startOlderHistoryLoad(pendingLoad)
    }
  }

  private func startOlderHistoryLoad(_ pendingLoad: PendingOlderHistoryLoad) {
    pendingOlderHistoryLoad = nil
    state.isLoadingOlder = true
    state.phase = .loadingMore
    historyRequestGeneration += 1
    let generation = historyRequestGeneration
    logHistoryRequest(pendingLoad.request, placement: .prepend, generation: generation)
    historyLoader.load(pendingLoad.request) { [weak self] result in
      Task { @MainActor in
        guard let self else {
          return
        }
        guard self.historyRequestGeneration == generation else {
          NEChatSwiftUILogger.log(
            "history ignored placement=prepend generation=\(generation) current=\(self.historyRequestGeneration)"
          )
          return
        }
        self.handleHistoryResult(
          result,
          placement: .prepend,
          requestStartedWhileNetworkBroken: pendingLoad.requestStartedWhileNetworkBroken
        )
      }
    }
  }

  private func startPendingOlderHistoryLoadIfNeeded() {
    guard let pendingLoad = pendingOlderHistoryLoad,
          state.isLoadingOlder,
          !state.isLoadingNewer,
          !isOlderPaginationSuspendedForNetworkBreak else {
      return
    }
    NEChatSwiftUILogger.log(
      "offlineHistory olderDequeuedAfterNewer conversationId=\(context.conversationId) anchorId=\(pendingLoad.request.anchorMessageId ?? "nil") rows=\(state.rows.count)"
    )
    startOlderHistoryLoad(pendingLoad)
  }

  public func loadNewerMessages() {
    guard isHistoryContextActive,
          state.hasMoreNewer,
          !state.isLoadingOlder,
          !state.isLoadingNewer else {
      return
    }

    loadNewerMessagesIfPossible(requiresMoreNewer: true)
  }

  public func updateInputText(_ text: String) {
    guard state.input.isEnabled else {
      return
    }
    let previousText = state.input.text
    let editRange = boundedInputSelection(state.input.selectedRange, in: previousText)
    let normalized = normalizedInputTextAfterMentionEdit(
      previousText: previousText,
      previousMentions: state.input.mentions,
      proposedText: text,
      preferredEditRange: editRange
    )
    applyInputTextState(text: normalized.text, mentions: normalized.mentions)
    if normalized.text != text {
      state.input.selectedRange = selectionAfterNormalizedEdit(
        previousText: previousText,
        normalizedText: state.input.text,
        preferredEditRange: editRange
      )
    } else {
      state.input.selectedRange = boundedInputSelection(editRange, in: state.input.text)
    }
    updatePendingMentionTriggerLocation(
      previousText: previousText,
      currentText: state.input.text,
      preferredEditRange: editRange
    )
  }

  public func updateInputSelection(_ selectedRange: NSRange) {
    let boundedRange = boundedInputSelection(selectedRange, in: state.input.text)
    guard boundedRange.length == 0 else {
      state.input.selectedRange = boundedRange
      return
    }

    for mention in state.input.mentions {
      guard let mentionRange = utf16Range(for: mention, in: state.input.text),
            boundedRange.location > mentionRange.location,
            boundedRange.location < NSMaxRange(mentionRange) else {
        continue
      }
      state.input.selectedRange = NSRange(location: NSMaxRange(mentionRange), length: 0)
      return
    }
    state.input.selectedRange = boundedRange
  }

  public func updateRichTextTitle(_ title: String) {
    guard state.input.isEnabled else {
      return
    }
    state.input.richTextTitle = NECommonTextLimit.limitedUTF16(title, limit: richTextTitleCharacterLimit)
    updateInputSendEnabledState()
  }

  public func richTextTitleLimitReached() {
    state.toast = ChatToastState(
      message: String(
        format: NEChatUIKitSwiftUIBundle.localized(
          "chat_rich_text_title_limit",
          value: "The title can contain up to %d characters"
        ),
        richTextTitleCharacterLimit
      ),
      style: .warning
    )
  }

  public func insertInputLineBreak() {
    guard state.input.isEnabled,
          IMKitConfigCenter.shared.enableRichTextMessage else {
      return
    }
    state.input.isRichTextExpanded = true
    updateInputSendEnabledState()
  }

  public func setRichTextInputExpanded(_ isExpanded: Bool) {
    guard state.input.isEnabled,
          IMKitConfigCenter.shared.enableRichTextMessage else {
      return
    }
    state.input.isRichTextExpanded = isExpanded
    if isExpanded {
      state.input.mode = .text
      state.inputTranslation = nil
      inputAreaDidExpand()
    }
    updateInputSendEnabledState()
  }

  public func setInputMode(_ mode: ChatInputMode) {
    guard state.input.isEnabled else {
      return
    }
    if state.input.recording.isActive || state.input.isRecording {
      cancelActiveVoiceRecording()
    }
    guard state.input.mode != mode else {
      return
    }
    state.input.mode = mode
    if mode != .text {
      inputAreaDidExpand()
    }
  }

  public func inputAreaDidExpand() {
    dismissOperations()
    guard isPageVisible, state.multiSelect == nil else {
      return
    }
    if isHistoryContextActive {
      reloadLatestMessagesFromHistoryContext(scrollToLatestAfterReload: true)
      return
    }
    preservesTimelinePositionAfterInputDismissal = false
    scrollTimelineToLatestForInputAreaChange()
  }

  public func inputFocusDidChange(_ focused: Bool) {
    guard isInputAreaFocused != focused else {
      return
    }
    isInputAreaFocused = focused
    if focused {
      dismissOperations()
      preservesTimelinePositionAfterInputDismissal = false
      inputAreaDidExpand()
    }
  }

  public func timelineInteractionWillDismissInput() {
    if isInputAreaFocused {
      preservesTimelinePositionAfterInputDismissal = true
    }
    isProgrammaticallyScrollingToLatest = false
    clearInterruptedTimelineScrollTargetIfNeeded()
    cancelTimelineBottomPinning()
  }

  public func inputAreaDidContract() {
    guard isPageVisible, state.multiSelect == nil, !isHistoryContextActive else {
      return
    }
    guard !preservesTimelinePositionAfterInputDismissal else {
      preservesTimelinePositionAfterInputDismissal = false
      cancelTimelineBottomPinning()
      return
    }
    scrollTimelineToLatestForInputAreaChange()
  }

  public func collapseInputArea() {
    isProgrammaticallyScrollingToLatest = false
    clearInterruptedTimelineScrollTargetIfNeeded()
    cancelTimelineBottomPinning()
    if state.input.recording.isActive || state.input.isRecording {
      cancelActiveVoiceRecording()
    }
    if state.input.mode != .text {
      state.input.mode = .text
    }
    state.input.isRichTextExpanded = false
    state.inputTranslation = nil
    state.input.collapseRevision += 1
  }

  /// UIKit dismisses the keyboard when the chat timeline is touched without
  /// changing the selected rich-text input presentation.
  public func dismissInputKeyboard() {
    state.input.collapseRevision += 1
  }

  public func dismissInputForOperationMenu() {
    if isInputAreaFocused {
      preservesTimelinePositionAfterInputDismissal = true
    }
    isProgrammaticallyScrollingToLatest = false
    clearInterruptedTimelineScrollTargetIfNeeded()
    cancelTimelineBottomPinning()
    if state.input.recording.isActive || state.input.isRecording {
      cancelActiveVoiceRecording()
    }
    if state.input.mode != .text {
      state.input.mode = .text
    }
    state.inputTranslation = nil
    state.input.collapseRevision += 1
  }

  public func beginVoiceRecording() {
    guard state.input.isEnabled else {
      return
    }
    guard let handler = config.audioRecordingHandler else {
      state.input.recording = ChatVoiceRecordingState(
        phase: .failed(NEChatUIKitSwiftUIBundle.localized("chat_audio_recording_requires_service", value: "Audio recording service is not connected yet"))
      )
      state.input.isRecording = false
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_audio_recording_requires_service", value: "Audio recording service is not connected yet"),
        style: .info
      )
      return
    }

    voiceRecordingGeneration += 1
    let generation = voiceRecordingGeneration
    let request = ChatAudioRecordRequest(context: context)
    state.input.isRecording = true
    state.input.recording = ChatVoiceRecordingState(phase: .preparing)
    handler.beginRecording(request) { [weak self] progress in
      Task { @MainActor in
        guard let self = self, self.voiceRecordingGeneration == generation else {
          return
        }
        self.state.input.isRecording = true
        let currentPhase = self.state.input.recording.phase == .cancelling
          ? ChatVoiceRecordingPhase.cancelling
          : .recording
        self.state.input.recording = ChatVoiceRecordingState(phase: currentPhase, progress: progress)
        if let remainingTime = progress.remainingTime, remainingTime <= 0 {
          self.endVoiceRecording(cancelled: false)
        }
      }
    } completion: { [weak self] result in
      Task { @MainActor in
        guard let self = self, self.voiceRecordingGeneration == generation else {
          return
        }
        switch result {
        case .success:
          self.state.input.isRecording = true
          if self.state.input.recording.phase == .preparing {
            self.state.input.recording = ChatVoiceRecordingState(phase: .recording)
          }
        case .failure(let error):
          self.state.input.isRecording = false
          let message = self.audioRecordingFailureMessage(for: error)
          self.state.input.recording = ChatVoiceRecordingState(phase: .failed(message))
          self.state.toast = ChatToastState(message: message, style: .error)
          self.state.input.recording = ChatVoiceRecordingState()
        }
      }
    }
  }

  public func updateVoiceRecording(cancelled: Bool) {
    guard state.input.recording.isActive else {
      return
    }

    state.input.recording.phase = cancelled ? .cancelling : .recording
  }

  public func endVoiceRecording(cancelled: Bool) {
    guard let handler = config.audioRecordingHandler,
          state.input.recording.isActive else {
      voiceRecordingGeneration += 1
      state.input.isRecording = false
      state.input.recording = ChatVoiceRecordingState()
      return
    }

    voiceRecordingGeneration += 1
    let generation = voiceRecordingGeneration
    let request = ChatAudioRecordRequest(context: context)
    if cancelled || state.input.recording.phase == .cancelling {
      state.input.isRecording = false
      state.input.recording = ChatVoiceRecordingState()
      handler.cancelRecording(request) { [weak self] result in
        Task { @MainActor in
          guard let self = self, self.voiceRecordingGeneration == generation else {
            return
          }
          if case let .failure(error) = result {
            self.state.toast = ChatToastState(message: self.audioRecordingFailureMessage(for: error), style: .error)
          }
        }
      }
      return
    }

    state.input.recording.phase = .finishing
    handler.finishRecording(request) { [weak self] result in
      Task { @MainActor in
        guard let self = self, self.voiceRecordingGeneration == generation else {
          return
        }
        self.state.input.isRecording = false
        self.state.input.recording = ChatVoiceRecordingState()
        switch result {
        case .success(let recordResult):
          if let toast = recordResult.toast {
            self.state.toast = toast
          }
          if self.state.input.isEnabled, let payload = recordResult.payload {
            self.sendPayload(payload)
          }
        case .failure(let error):
          self.state.toast = ChatToastState(message: self.audioRecordingFailureMessage(for: error), style: .error)
        }
      }
    }
  }

  public func cancelReply() {
    state.input.reply = nil
  }

  public func insertMention(accountId: String,
                            displayName: String? = nil) {
    insertMention(
      ChatMentionTargetState(accountId: accountId, displayName: displayName),
      replacingTrailingAt: false
    )
  }

  public func insertMention(_ target: ChatMentionTargetState,
                            replacingTrailingAt: Bool = false) {
    guard state.input.isEnabled else {
      return
    }
    let normalizedAccountId = target.mentionAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAccountId.isEmpty else {
      return
    }

    let mentionText = "@\(target.mentionDisplayName)"
    var text = state.input.text
    var mentions = state.input.mentions
    var insertionLocation = min(max(0, state.input.selectedRange.location), text.utf16.count)
    if replacingTrailingAt {
      if let triggerRange = pendingMentionTriggerRange(in: text) {
        text = removeRange(triggerRange, from: text)
        mentions = shiftMentions(mentions, afterRemoving: triggerRange)
        insertionLocation = triggerRange.lowerBound
      } else if insertionLocation > 0,
                isAtCharacter(at: insertionLocation - 1, in: text) {
        let triggerRange = (insertionLocation - 1) ..< insertionLocation
        text = removeRange(triggerRange, from: text)
        mentions = shiftMentions(mentions, afterRemoving: triggerRange)
        insertionLocation = triggerRange.lowerBound
      }
    }
    pendingMentionTriggerLocation = nil

    let insertedText = "\(mentionText) "
    mentions = shiftMentions(mentions, by: insertedText.utf16.count, from: insertionLocation)
    text = insertString(insertedText, into: text, at: insertionLocation)
    let start = insertionLocation
    let end = start + mentionText.utf16.count - 1

    state.input.mentionedAccountIds.insert(normalizedAccountId)
    mentions.append(ChatMentionState(
      accountId: normalizedAccountId,
      displayText: mentionText,
      start: start,
      end: end
    ))
    applyInputTextState(text: text, mentions: mentions)
    let cursorLocation = insertionLocation + insertedText.utf16.count
    state.input.selectedRange = boundedInputSelection(
      NSRange(location: cursorLocation, length: 0),
      in: state.input.text
    )
  }

  public func requestMentionSelection(trigger: ChatMentionSelectionTrigger = .programmatic) {
    guard IMKitConfigCenter.shared.enableAtMessage,
          let request = mentionSelectionRequest(trigger: trigger) else {
      return
    }

    guard let handler = config.mentionSelectionHandler else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_mention_requires_selector", value: "Mention selection requires a SwiftUI selection handler."),
        style: .info
      )
      return
    }

    mentionSelectionGeneration += 1
    let generation = mentionSelectionGeneration
    if request.source == .teamMembers {
      requestTeamMentionSelection(request, trigger: trigger, handler: handler, generation: generation)
      return
    }

    handler.selectMentionTargets(request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.mentionSelectionGeneration == generation else {
          return
        }
        self.handleMentionSelectionResult(result, trigger: trigger)
      }
    }
  }

  private func requestTeamMentionSelection(_ request: ChatMentionSelectionRequest,
                                           trigger: ChatMentionSelectionTrigger,
                                           handler: ChatMentionSelectionHandling,
                                           generation: Int) {
    guard let teamId = Self.teamId(from: context) else {
      return
    }
    TeamRepo.shared.swiftUIAllowsAtAll(
      teamId: teamId,
      currentAccountId: currentAccountProvider()
    ) { [weak self] allowsAllMembers, _ in
      Task { @MainActor in
        guard let self, self.mentionSelectionGeneration == generation else {
          return
        }
        var resolvedRequest = request
        resolvedRequest.allowsAllMembers = allowsAllMembers
        self.selectMentionTargets(resolvedRequest, trigger: trigger, handler: handler, generation: generation)
      }
    }
  }

  private func selectMentionTargets(_ request: ChatMentionSelectionRequest,
                                    trigger: ChatMentionSelectionTrigger,
                                    handler: ChatMentionSelectionHandling,
                                    generation: Int) {
    handler.selectMentionTargets(request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.mentionSelectionGeneration == generation else {
          return
        }
        self.handleMentionSelectionResult(result, trigger: trigger)
      }
    }
  }

  private func cancelActiveVoiceRecording() {
    voiceRecordingGeneration += 1
    let generation = voiceRecordingGeneration
    state.input.isRecording = false
    state.input.recording = ChatVoiceRecordingState()

    guard let handler = config.audioRecordingHandler else {
      return
    }

    let request = ChatAudioRecordRequest(context: context)
    handler.cancelRecording(request) { [weak self] result in
      Task { @MainActor in
        guard let self, self.voiceRecordingGeneration == generation else {
          return
        }
        if case let .failure(error) = result {
          self.state.toast = ChatToastState(message: self.audioRecordingFailureMessage(for: error), style: .error)
        }
      }
    }
  }

  /// Keeps the SwiftUI chat lifecycle aligned with UIKit: leaving a chat or
  /// starting/receiving a call must not leave the recorder or player active.
  public func stopActiveMedia() {
    if state.input.recording.isActive || state.input.isRecording {
      cancelActiveVoiceRecording()
    }

    guard let messageId = state.audioPlayback.messageId else {
      return
    }

    audioPlaybackGeneration += 1
    let generation = audioPlaybackGeneration
    state.audioPlayback = ChatAudioPlaybackState()

    guard let row = row(id: messageId),
          let audio = audioState(from: row.content) else {
      // Row not found (e.g. collection message) — still request the
      // playback handler to stop audio using a minimal request.
      updateAudioPlayingState(messageId: messageId, isPlaying: false)
      let request = ChatAudioPlaybackRequest(
        messageId: messageId,
        audio: MessageAudioState(duration: 0, isPlaying: false),
        context: context
      )
      config.audioPlaybackHandler?.stopAudio(request) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.audioPlaybackGeneration == generation else {
            return
          }
          self.state.audioPlayback = ChatAudioPlaybackState()
        }
      }
      return
    }

    updateAudioPlayingState(messageId: messageId, isPlaying: false)
    let request = ChatAudioPlaybackRequest(messageId: messageId, audio: audio, context: context)
    config.audioPlaybackHandler?.stopAudio(request) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.audioPlaybackGeneration == generation else {
          return
        }
        self.state.audioPlayback = ChatAudioPlaybackState()
      }
    }
  }

  public func appendEmoji(_ emoji: ChatEmojiState) {
    guard state.input.isEnabled else {
      return
    }
    let text = state.input.text
    let selection = boundedInputSelection(state.input.selectedRange, in: text)
    let nextText = (text as NSString).replacingCharacters(in: selection, with: emoji.text)
    updateInputText(nextText)
    state.input.selectedRange = boundedInputSelection(
      NSRange(location: selection.location + emoji.text.utf16.count, length: 0),
      in: state.input.text
    )
  }

  public func deleteBackward() {
    guard state.input.isEnabled else {
      return
    }
    guard !state.input.text.isEmpty else {
      return
    }
    let previousText = state.input.text
    let selection = boundedInputSelection(state.input.selectedRange, in: previousText)
    var deletionRange = selection
    if deletionRange.length == 0 {
      guard deletionRange.location > 0 else {
        return
      }
      let prefixRange = NSRange(location: 0, length: deletionRange.location)
      let prefix = (previousText as NSString).substring(with: prefixRange)
      if let emoticonRange = MessageEmoticonCatalog.shared.trailingEmoticonRange(in: prefix) {
        let nsRange = NSRange(emoticonRange, in: prefix)
        deletionRange = NSRange(location: nsRange.location, length: nsRange.length)
      } else {
        deletionRange = (previousText as NSString)
          .rangeOfComposedCharacterSequence(at: deletionRange.location - 1)
      }
    }
    let text = (previousText as NSString).replacingCharacters(in: deletionRange, with: "")
    state.input.selectedRange = NSRange(location: deletionRange.location, length: 0)
    updateInputText(text)
  }

  public func handleMoreAction(_ action: ChatMoreActionState) {
    guard state.input.isEnabled else {
      return
    }
    if state.input.recording.isActive || state.input.isRecording {
      cancelActiveVoiceRecording()
    }
    state.input.mode = .more

    guard let currentAction = ChatMoreActionPolicy.action(for: action.id, context: context, config: config),
          currentAction.isEnabled else {
      refreshMoreActions()
      showOperationUnavailableToast()
      return
    }

    if currentAction.id == .translate {
      openInputTranslation()
      return
    }

    let boundaryDisposition = config.nativeBoundaryPolicy.disposition(for: currentAction.id, context: context)
    if case let .internalRoute(route) = boundaryDisposition {
      state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
    } else if let nativeBoundaryHandler = config.nativeBoundaryHandler {
      // App-host actions can present a camera, photo library, or document picker
      // without changing the SwiftUI route. Match UIKit's viewWillDisappear path.
      stopActiveMedia()
      beginNativeBoundaryPresentation()
      let generation = nextBoundaryRequestGeneration()
      state.route.handlingState = .handling
      nativeBoundaryHandler.handle(action: currentAction.id, context: context) { [weak self] result in
        Task { @MainActor in
          guard let self = self, self.boundaryRequestGeneration == generation else {
            return
          }
          self.finishNativeBoundaryPresentation(
            keepsTimelineHidden: self.nativeBoundaryResultKeepsTimelineHidden(result)
          )
          self.handleNativeBoundaryResult(result, fallbackAction: currentAction)
        }
      }
    } else {
      state.route = ChatRouteState(
        currentRoute: .moreAction(currentAction.id, context),
        handlingState: .queued
      )
      state.toast = toast(for: boundaryDisposition, action: currentAction)
    }
  }

  public func openPinnedMessages() {
    guard isHeaderActionAvailable(.pinnedMessages) else {
      showOperationUnavailableToast()
      return
    }
    state.route = ChatRouteState(
      currentRoute: .pinMessages(conversationId: context.conversationId),
      handlingState: .queued
    )
  }

  public func performHeaderAction(_ action: ChatHeaderAction) {
    guard isHeaderActionAvailable(action) else {
      showOperationUnavailableToast()
      return
    }

    switch action {
    case .pinnedMessages:
      openPinnedMessages()
    case .historySearch:
      openHistorySearch()
    case .collectionMessages:
      openCollectionMessages()
    case .aiRobots:
      openAIRobots()
    case .userSetting:
      openUserSetting()
    }
  }

  public func performTitleBarRightAction() {
    if let handler = config.titleBarRightActionHandler {
      handler(context)
      return
    }
    openUserSetting()
  }

  public func focusTopMessage() {
    NEChatSwiftUILogger.log(
      "chatAction topBanner vmStart topId=\(state.topMessage?.id ?? "nil") rowId=\(state.topMessage?.row?.id ?? "nil") rowServerId=\(state.topMessage?.row?.serverId ?? "nil") rows=\(state.rows.count) currentTarget=\(state.timelineScrollTarget?.id ?? "nil") history=\(isHistoryContextActive) bottomVisible=\(isTimelineBottomVisible)"
    )
    guard guardRuntimeAllowsNetworkOperation() else {
      NEChatSwiftUILogger.log("chatAction topBanner blocked reason=network")
      return
    }

    guard let topMessage = state.topMessage else {
      NEChatSwiftUILogger.log("chatAction topBanner branch=noTopMessage openPinnedMessages")
      openPinnedMessages()
      return
    }

    if let row = topMessage.row {
      NEChatSwiftUILogger.log(
        "chatAction topBanner branch=focusMessage rowId=\(row.id) rowServerId=\(row.serverId ?? "nil")"
      )
      focusMessage(row)
      return
    }

    if let loadedRow = row(id: topMessage.id) {
      NEChatSwiftUILogger.log(
        "chatAction topBanner branch=focusLoadedRow rowId=\(loadedRow.id) topId=\(topMessage.id)"
      )
      focusMessage(loadedRow)
      return
    }

    NEChatSwiftUILogger.log("chatAction topBanner branch=notLoaded openPinnedMessages topId=\(topMessage.id)")
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("chat_top_message_not_loaded", value: "Pinned message is not loaded yet"),
      style: .info
    )
    openPinnedMessages()
  }

  public func closeTopMessage() {
    guard case .teamTop = state.topMessage?.source else {
      return
    }
    untopMessage(id: state.topMessage?.id)
  }

  public func focusMessage(_ row: MessageRowState) {
    focusMessage(row, anchorMessage: messageContextMessage(for: row))
  }

  private func focusMessage(_ row: MessageRowState,
                            anchorMessage: V2NIMMessage?) {
    NEChatSwiftUILogger.log(
      "messageJump focus request rowId=\(row.id) serverId=\(row.serverId ?? "nil") rowConversationId=\(row.conversationId ?? "nil") currentConversationId=\(context.conversationId) anchorClientId=\(anchorMessage?.messageClientId ?? "nil") anchorServerId=\(anchorMessage?.messageServerId ?? "nil") anchorTime=\(anchorMessage?.createTime.description ?? "nil") rows=\(state.rows.count) phase=\(String(describing: state.phase)) currentTarget=\(state.timelineScrollTarget?.id ?? "nil") presentationGeneration=\(state.timelinePresentationGeneration)"
    )
    guard row.conversationId == nil || row.conversationId == context.conversationId else {
      self.pendingReplyAttachmentDownload = nil
      NEChatSwiftUILogger.log(
        "messageJump focus rejected rowId=\(row.id) reason=conversationMismatch rowConversationId=\(row.conversationId ?? "nil") currentConversationId=\(context.conversationId)"
      )
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found"),
        style: .warning
      )
      clearRoute()
      return
    }

    if let pendingReplyAttachmentDownload,
       !sameMessage(pendingReplyAttachmentDownload.row, row) {
      self.pendingReplyAttachmentDownload = nil
    }
    if let anchorMessage {
      cacheMessageContext([anchorMessage])
    }
    prepareForExplicitAnchorFocus()
    discardTimelinePositionRestore()
    clearRoute()
    if let loadedId = loadedRowId(matching: row) {
      NEChatSwiftUILogger.log(
        "messageJump focus branch=loaded rowId=\(row.id) loadedId=\(loadedId) rows=\(state.rows.count)"
      )
      commitLoadedExplicitAnchorPresentation(messageId: loadedId)
      startPendingReplyAttachmentDownloadIfReady(matching: row)
      return
    }

    NEChatSwiftUILogger.log(
      "messageJump focus branch=reload rowId=\(row.id) anchorClientId=\(anchorMessage?.messageClientId ?? "nil") rows=\(state.rows.count)"
    )
    beginFocusedHistoryReload(anchorRow: row, anchorMessage: anchorMessage)
    loadMessageContextAroundAnchor(row)
  }

  public func focusReply(for row: MessageRowState) {
    guard state.multiSelect == nil else {
      toggleSelection(for: row.id)
      return
    }

    guard let reply = row.reply else {
      return
    }

    if let loaded = resolvedReplyRow(for: row) {
      let replyTarget = replyRow(from: row, content: loaded.content)
      handleReplyTargetTap(
        replyTarget,
        content: loaded.content,
        anchorMessage: messageContextMessage(for: loaded)
      )
      return
    }

    guard row.conversationId == nil || row.conversationId == context.conversationId,
          reply.conversationId == nil || reply.conversationId == context.conversationId else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found"),
        style: .warning
      )
      return
    }

    if let replyContent = reply.resolvedContent?.value {
      let replyTarget = replyRow(from: row, content: replyContent)
      handleReplyTargetTap(
        replyTarget,
        content: replyContent,
        anchorMessage: messageContextMessage(for: replyTarget)
      )
      return
    }

    loadAndOpenReply(for: row, reply: reply)
  }

  private func loadAndOpenReply(for row: MessageRowState,
                                reply: MessageReplyState) {
    let reference = NEChatReplyReference(
      messageClientId: reply.messageClientId,
      messageServerId: reply.messageServerId,
      senderId: reply.senderId,
      receiverId: reply.receiverId,
      conversationId: reply.conversationId,
      conversationType: V2NIMConversationType(rawValue: reply.conversationType) ??
        V2NIMConversationIdUtil.conversationType(context.conversationId),
      createTime: reply.createTime
    )
    guard reference.isValid else {
      state.toast = ChatToastState(
        message: reply.preview ?? NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found"),
        style: .warning
      )
      return
    }

    let requestId = UUID()
    replyResolutionRequestIds[row.id] = requestId
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("chat_reply_loading", value: "Loading replied message"),
      style: .info
    )
    ChatRepo.shared.findReplyMessage(reference: reference) { [weak self] replyMessage, _ in
      Task { @MainActor in
        guard let self,
              self.replyResolutionRequestIds[row.id] == requestId,
              self.row(id: row.id) != nil else {
          return
        }
        self.replyResolutionRequestIds[row.id] = nil
        self.updateReply(for: row.id, replyMessage: replyMessage)
        guard let replyMessage else {
          self.state.toast = ChatToastState(
            message: NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found"),
            style: .warning
          )
          return
        }
        let replyRow = self.messageRow(from: replyMessage)
        let replyTarget = self.replyRow(from: row, content: replyRow.content)
        self.handleReplyTargetTap(
          replyTarget,
          content: replyRow.content,
          anchorMessage: replyMessage
        )
      }
    }
  }

  public func focusMessage(_ selection: PinMessageSelection) {
    NEChatSwiftUILogger.log(
      "messageJump selection received rowId=\(selection.row.id) serverId=\(selection.row.serverId ?? "nil") anchorClientId=\(selection.anchorMessage?.messageClientId ?? "nil") anchorServerId=\(selection.anchorMessage?.messageServerId ?? "nil") opensConversationOnly=\(selection.opensConversationOnly)"
    )
    if selection.opensConversationOnly {
      NEChatSwiftUILogger.log(
        "messageJump selection branch=openLatest rowId=\(selection.row.id)"
      )
      clearRoute()
      scrollToLatest(animated: false)
      return
    }

    appendPendingHistoryNewMessages(selection.pendingMessages)
    guard let anchorMessage = selection.anchorMessage else {
      NEChatSwiftUILogger.log(
        "messageJump selection branch=rowOnly rowId=\(selection.row.id)"
      )
      focusMessage(selection.row)
      return
    }

    var anchorRow = messageRow(from: anchorMessage)
    if anchorRow.senderName?.isEmpty != false,
       selection.row.senderName?.isEmpty == false {
      anchorRow.senderName = selection.row.senderName
    }
    if anchorRow.avatarURL == nil {
      anchorRow.avatarURL = selection.row.avatarURL
    }
    NEChatSwiftUILogger.log(
      "messageJump selection branch=anchorMessage selectionRowId=\(selection.row.id) mappedRowId=\(anchorRow.id) anchorClientId=\(anchorMessage.messageClientId ?? "nil") anchorServerId=\(anchorMessage.messageServerId ?? "nil")"
    )
    focusMessage(anchorRow, anchorMessage: anchorMessage)
  }

  public func scrollToLatest(animated: Bool = true) {
    guard let lastId = state.rows.last?.id else {
      loadInitialIfNeeded()
      return
    }
    beginTimelineBottomPinning()
    requestTimelineScroll(to: lastId, anchor: .bottom, animated: animated, reason: .jumpToLatest)
  }

  public func openCollectionMessage(_ row: CollectionMessageRowState) {
    guard let messageRow = row.messageRow else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_collection_message_unavailable", value: "Collection message is unavailable"),
        style: .warning
      )
      return
    }

    switch messageRow.content {
    case let .image(media):
      openMediaPreview(row: messageRow, media: media, kind: .image, requiresLoadedRow: false)
    case let .video(media):
      openMediaPreview(row: messageRow, media: media, kind: .video, requiresLoadedRow: false)
    case let .file(file):
      openCollectionFile(row: messageRow, file: file)
    case let .location(location):
      openLocation(row: messageRow, location: location, requiresLoadedRow: false)
    case let .call(call):
      openCall(row: messageRow, call: call, requiresLoadedRow: false)
    case let .multiForward(multiForward):
      openMultiForward(row: messageRow, multiForward: multiForward)
    case let .audio(audio):
      toggleAudioPlayback(row: messageRow, audio: audio, requiresLoadedRow: false)
    case let .text(text):
      openTextPreview(ChatTextPreviewState(
        messageId: messageRow.id,
        body: text,
        source: .utility
      ))
    case let .richText(title, body):
      openTextPreview(ChatTextPreviewState(
        messageId: messageRow.id,
        title: title,
        body: body,
        source: .utility
      ))
    case let .reply(_, boxed):
      openCollectionNestedContent(row: messageRow, content: boxed.value)
    case let .aiStream(text, _, error):
      openTextPreview(ChatTextPreviewState(
        messageId: messageRow.id,
        body: [text, error].compactMap { $0 }.joined(separator: "\n"),
        source: .utility
      ))
    default:
      state.toast = ChatToastState(
        message: row.previewText,
        style: .info
      )
    }
  }

  public func openUtilityMessageContent(_ row: MessageRowState,
                                        unavailableText: String? = nil) {
    switch row.content {
    case let .text(text):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: text,
        source: .utility
      ))
    case let .richText(title, body):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        title: title,
        body: body,
        source: .utility
      ))
    case let .image(media):
      openMediaPreview(row: row, media: media, kind: .image, requiresLoadedRow: false)
    case let .video(media):
      openMediaPreview(row: row, media: media, kind: .video, requiresLoadedRow: false)
    case let .file(file):
      openCollectionFile(row: row, file: file)
    case let .location(location):
      openLocation(row: row, location: location, requiresLoadedRow: false)
    case let .call(call):
      openCall(row: row, call: call, requiresLoadedRow: false)
    case let .multiForward(multiForward):
      openMultiForward(row: row, multiForward: multiForward)
    case let .audio(audio):
      toggleAudioPlayback(row: row, audio: audio, requiresLoadedRow: false)
    case let .reply(_, boxed):
      openUtilityNestedContent(row: row, content: boxed.value)
    case let .aiStream(text, _, error):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: [text, error].compactMap { $0 }.joined(separator: "\n"),
        source: .utility
      ))
    default:
      state.toast = ChatToastState(
        message: unavailableText ?? ChatMessageMapper.previewText(for: row.content),
        style: .info
      )
    }
  }

  private func openUtilityNestedContent(row: MessageRowState,
                                        content: MessageContentState) {
    switch content {
    case let .text(text):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: text,
        source: .utility
      ))
    case let .richText(title, body):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        title: title,
        body: body,
        source: .utility
      ))
    case let .image(media):
      openMediaPreview(row: row, media: media, kind: .image, requiresLoadedRow: false)
    case let .video(media):
      openMediaPreview(row: row, media: media, kind: .video, requiresLoadedRow: false)
    case let .file(file):
      openCollectionFile(row: row, file: file)
    case let .location(location):
      openLocation(row: row, location: location, requiresLoadedRow: false)
    case let .call(call):
      openCall(row: row, call: call, requiresLoadedRow: false)
    case let .multiForward(multiForward):
      openMultiForward(row: row, multiForward: multiForward)
    case let .audio(audio):
      toggleAudioPlayback(row: row, audio: audio, requiresLoadedRow: false)
    case let .reply(_, boxed):
      openUtilityNestedContent(row: row, content: boxed.value)
    case let .aiStream(text, _, error):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: [text, error].compactMap { $0 }.joined(separator: "\n"),
        source: .utility
      ))
    default:
      state.toast = ChatToastState(
        message: ChatMessageMapper.previewText(for: content),
        style: .info
      )
    }
  }

  private func openCollectionNestedContent(row: MessageRowState,
                                           content: MessageContentState) {
    switch content {
    case let .text(text):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: text,
        source: .utility
      ))
    case let .richText(title, body):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        title: title,
        body: body,
        source: .utility
      ))
    case let .image(media):
      openMediaPreview(row: row, media: media, kind: .image, requiresLoadedRow: false)
    case let .video(media):
      openMediaPreview(row: row, media: media, kind: .video, requiresLoadedRow: false)
    case let .file(file):
      openCollectionFile(row: row, file: file)
    case let .location(location):
      openLocation(row: row, location: location, requiresLoadedRow: false)
    case let .call(call):
      openCall(row: row, call: call, requiresLoadedRow: false)
    case let .multiForward(multiForward):
      openMultiForward(row: row, multiForward: multiForward)
    case let .audio(audio):
      toggleAudioPlayback(row: row, audio: audio, requiresLoadedRow: false)
    case let .reply(_, boxed):
      openCollectionNestedContent(row: row, content: boxed.value)
    case let .aiStream(text, _, error):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: [text, error].compactMap { $0 }.joined(separator: "\n"),
        source: .utility
      ))
    default:
      state.toast = ChatToastState(
        message: ChatMessageMapper.previewText(for: content),
        style: .info
      )
    }
  }

  private func openCollectionFile(row: MessageRowState,
                                  file: MessageFileState) {
    if let media = file.imageMediaState {
      openMediaPreview(row: row, media: media, kind: .image, requiresLoadedRow: false)
      return
    }
    if let media = file.videoMediaState {
      openMediaPreview(row: row, media: media, kind: .video, requiresLoadedRow: false)
      return
    }
    openFilePreview(row: row, file: file, requiresLoadedRow: false)
  }

  private func prepareForExplicitAnchorFocus() {
    cancelTimelineBottomPinning()
    isProgrammaticallyScrollingToLatest = false
  }

  private func commitLoadedExplicitAnchorPresentation(messageId: String) {
    let target = makeExplicitAnchorTarget(messageId: messageId)
    var nextState = state
    nextState.timelineScrollTarget = target
    nextState.timelinePresentationGeneration += 1
    state = nextState
    NEChatSwiftUILogger.log(
      "messageJump focusedPresentation commit generation=\(nextState.timelinePresentationGeneration) rows=\(nextState.rows.count) target=\(target.id) messageId=\(target.messageId) loaded=true"
    )
  }

  private func makeExplicitAnchorTarget(messageId: String) -> ChatTimelineScrollTarget {
    scrollTargetSequence += 1
    return ChatTimelineScrollTarget(
      messageId: messageId,
      anchor: .center,
      sequence: scrollTargetSequence,
      animated: false,
      reason: .explicitAnchor,
      scopeId: scrollTargetScopeId
    )
  }

  private func beginFocusedHistoryReload(anchorRow: MessageRowState,
                                         anchorMessage: V2NIMMessage?) {
    let previousRowCount = state.rows.count
    let previousTargetId = state.timelineScrollTarget?.id
    isHistoryContextActive = true
    isTimelineBottomVisible = false
    shouldScrollToLatestAfterReload = false
    clearPendingPrependRestore()
    visibleTimelineAnchorId = nil
    lastStableVisibleTimelineAnchorId = nil
    visibleTimelineRowIds.removeAll()
    appendPendingHistoryNewMessages(pendingNewMessagesFromLoadedRows())
    var nextState = state
    nextState.timelineScrollTarget = nil
    nextState.newMessageIndicator = nil
    nextState.rows = []
    nextState.oldestAnchorMessageId = anchorRow.id
    nextState.newestAnchorMessageId = anchorRow.id
    nextState.isLoadingOlder = true
    nextState.isLoadingNewer = true
    nextState.hasMoreOlder = true
    nextState.hasMoreNewer = true
    nextState.phase = .loading
    state = nextState
    oldestHistoryAnchorMessage = anchorMessage
    newestHistoryAnchorMessage = anchorMessage
    NEChatSwiftUILogger.log(
      "messageJump focusedReload begin rowId=\(anchorRow.id) serverId=\(anchorRow.serverId ?? "nil") anchorClientId=\(anchorMessage?.messageClientId ?? "nil") previousRows=\(previousRowCount) previousTarget=\(previousTargetId ?? "nil") historyGeneration=\(historyRequestGeneration)"
    )
  }

  public func openHistorySearch() {
    guard isHeaderActionAvailable(.historySearch) else {
      showOperationUnavailableToast()
      return
    }
    state.route = ChatRouteState(
      currentRoute: .historySearch(conversationId: context.conversationId),
      handlingState: .queued
    )
  }

  public func openCollectionMessages() {
    guard isHeaderActionAvailable(.collectionMessages) else {
      showOperationUnavailableToast()
      return
    }
    state.route = ChatRouteState(
      currentRoute: .collectionMessages(conversationId: context.conversationId),
      handlingState: .queued
    )
  }

  public func openInputTranslation() {
    guard ChatMoreActionPolicy.action(for: .translate, context: context, config: config)?.isEnabled == true else {
      showOperationUnavailableToast()
      return
    }
    if state.input.recording.isActive || state.input.isRecording {
      cancelActiveVoiceRecording()
    }
    let languages = inputTranslationLanguages()
    state.input.mode = .more
    state.inputTranslation = ChatInputTranslationState(
      selectedLanguage: inputTranslationSelectedLanguage(in: languages),
      languages: languages
    )
  }

  public func closeInputTranslation() {
    inputTranslationRequestId = nil
    inputTranslationBatch = nil
    translatedInputMentions.removeAll()
    state.inputTranslation = nil
  }

  public func selectInputTranslationLanguage(_ language: ChatTranslationLanguageState) {
    guard var inputTranslation = state.inputTranslation else {
      return
    }
    selectedInputTranslationLanguage = language.code
    let accountId = currentAccountProvider() ?? ""
    UserDefaults.standard.set(language.code, forKey: accountId + "_language")
    inputTranslation.selectedLanguage = language.code
    inputTranslation.phase = .idle
    inputTranslation.translatedText = ""
    inputTranslation.requestId = nil
    inputTranslationRequestId = nil
    inputTranslationBatch = nil
    translatedInputMentions.removeAll()
    state.inputTranslation = inputTranslation
  }

  public func startOrUseInputTranslation() {
    guard var inputTranslation = state.inputTranslation else {
      return
    }
    switch inputTranslation.phase {
    case .translated:
      let translatedText = inputTranslation.translatedText
      guard !translatedText.isEmpty else {
        return
      }
      applyInputTextState(text: translatedText, mentions: translatedInputMentions)
      state.input.selectedRange = NSRange(location: state.input.text.utf16.count, length: 0)
      inputTranslation.phase = .idle
      inputTranslation.translatedText = ""
      inputTranslation.requestId = nil
      inputTranslationRequestId = nil
      inputTranslationBatch = nil
      translatedInputMentions.removeAll()
      state.inputTranslation = inputTranslation
    case .translating:
      return
    case .idle:
      let sourceText = state.input.text
      guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        inputTranslation.translatedText = ""
        state.inputTranslation = inputTranslation
        return
      }
      guard guardRuntimeAllowsNetworkOperation() else {
        return
      }
      let requestId = UUID().uuidString
      translatedInputMentions.removeAll()
      inputTranslationRequestId = requestId
      inputTranslation.phase = .translating
      inputTranslation.translatedText = ""
      inputTranslation.requestId = requestId
      state.inputTranslation = inputTranslation
      guard let aiTranslateUser = NEAIUserManager.shared.getAITranslateUser(),
            let accountId = aiTranslateUser.accountId,
            !accountId.isEmpty else {
        finishInputTranslationAsUnavailable(requestId: requestId)
        return
      }
      let promptKey = NEAIUserManager.shared.getTranslatePromptKey()
      let segments = inputTranslationSegments(
        sourceText: sourceText,
        mentions: state.input.mentions
      )
      if segments.count > 1 || !state.input.mentions.isEmpty {
        inputTranslationBatch = InputTranslationBatch(
          requestId: requestId,
          accountId: accountId,
          promptKey: promptKey,
          targetLanguage: inputTranslation.selectedLanguage,
          segments: segments,
          activeSegmentIndex: nil,
          activeRequestId: nil
        )
        translateNextInputSegment()
      } else {
        inputTranslationBatch = nil
        proxyInputTranslation(
          text: sourceText,
          accountId: accountId,
          requestId: requestId,
          batchRequestId: requestId,
          promptKey: promptKey,
          targetLanguage: inputTranslation.selectedLanguage
        )
      }
    }
  }

  private func finishInputTranslationAsUnavailable(requestId: String) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard inputTranslationRequestId == requestId else {
        return
      }
      inputTranslationRequestId = nil
      inputTranslationBatch = nil
      translatedInputMentions.removeAll()
      if var inputTranslation = state.inputTranslation,
         inputTranslation.requestId == requestId {
        inputTranslation.requestId = nil
        inputTranslation.phase = .idle
        state.inputTranslation = inputTranslation
      }
      showOperationUnavailableToast()
    }
  }

  public func openAIRobots() {
    guard isHeaderActionAvailable(.aiRobots) else {
      showOperationUnavailableToast()
      return
    }
    state.route = ChatRouteState(
      currentRoute: .aiRobot(.init(kind: .list, sourceURL: ContactAIRobotListRouter)),
      handlingState: .queued
    )
  }

  public func openUserSetting() {
    guard isHeaderActionAvailable(.userSetting) else {
      showOperationUnavailableToast()
      return
    }
    // UIKit stops reporting reads in viewWillDisappear. SwiftUI route presentation
    // is asynchronous, so hide the timeline before publishing the route as well.
    setPageVisible(false)
    captureTimelinePositionBeforeRoute()
    if context.kind == .team, let teamId = context.sessionId {
      state.route = ChatRouteState(
        currentRoute: .teamSetting(teamId: teamId, context: context),
        handlingState: .queued
      )
      return
    }
    state.route = ChatRouteState(
      currentRoute: .userSetting(context),
      handlingState: .queued
    )
  }

  private func isHeaderActionAvailable(_ action: ChatHeaderAction) -> Bool {
    switch action {
    case .pinnedMessages:
      return IMKitConfigCenter.shared.enablePinMessage
    case .historySearch:
      return true
    case .collectionMessages:
      return IMKitConfigCenter.shared.enableCollectionMessage
    case .aiRobots:
      return IMKitConfigCenter.shared.enableAIUser
    case .userSetting:
      return context.kind == .p2p || context.kind == .team || context.kind == .botSubSession
    }
  }

  public func appendRows(_ rows: [MessageRowState]) {
    guard !rows.isEmpty else {
      return
    }
    var existingRows = state.rows
    let uniqueRows = rows.filter { row in
      if existingRows.contains(where: { sameLoadedMessage($0, row) }) {
        return false
      }
      existingRows.append(row)
      return true
    }
    let displayReadyRows = uniqueRows.map(applyingDisplayCaches(to:))
    state.rows.append(contentsOf: displayReadyRows)
    state.rows.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
    _ = refreshConsistentSenderDisplayInfos()
    pruneMessageContext()
    refreshTimeDividers()
    refreshAnchors()
    if state.phase == .empty || state.phase == .idle {
      state.phase = .loaded
    }
    refreshContactDisplayInfosIfNeeded(for: uniqueRows)
    refreshTeamMemberDisplayInfosIfNeeded(for: uniqueRows)
    resolveRepliesIfNeeded(for: displayReadyRows)
  }

  public func sendText() {
    guard state.input.isEnabled else {
      return
    }
    let rawText = state.input.text
    let text = rawText.trimmingCharacters(in: .whitespaces)
    let richTextTitle = state.input.richTextTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard state.input.isSendEnabled, !text.isEmpty || !richTextTitle.isEmpty else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("null_message_not_support", value: "Empty messages are not supported"),
        style: .warning
      )
      return
    }
    guard !state.input.validation.isOverLimit else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_input_text_too_long", value: "Message is too long"),
        style: .warning
      )
      return
    }
    let replyToMessageId = state.input.reply?.id
    let replyToMessageServerId = state.input.reply?.serverId
    let mentionedAccountIds = state.input.mentionedAccountIds
    let mentions = state.input.mentions
    guard prepareToSendTextValue(
      rawText,
      richTextTitle: richTextTitle,
      replyToMessageId: replyToMessageId,
      replyToMessageServerId: replyToMessageServerId,
      mentionedAccountIds: mentionedAccountIds,
      mentions: mentions
    ) else {
      return
    }
    clearInputAfterSend()
  }

  @discardableResult
  private func sendTextValue(_ text: String,
                             richTextTitle: String? = nil,
                             replyToMessageId: String? = nil,
                             replyToMessageServerId: String? = nil,
                             mentionedAccountIds: Set<String> = [],
                             mentions: [ChatMentionState] = []) -> Bool {
    prepareToSendTextValue(
      text,
      richTextTitle: richTextTitle,
      replyToMessageId: replyToMessageId,
      replyToMessageServerId: replyToMessageServerId,
      mentionedAccountIds: mentionedAccountIds,
      mentions: mentions
    )
  }

  private func prepareToSendTextValue(_ text: String,
                                      richTextTitle: String? = nil,
                                      replyToMessageId: String? = nil,
                                      replyToMessageServerId: String? = nil,
                                      mentionedAccountIds: Set<String> = [],
                                      mentions: [ChatMentionState] = []) -> Bool {
    guard state.input.isEnabled else {
      return false
    }
    let limitedText = NECommonTextLimit.limitedUTF16(text, limit: config.maxTextMessageLength)
    let validMentions = validatedMentions(mentions, in: limitedText)
    let validMentionAccountIdsFromRanges = Set(validMentions.map(\.accountId))
    let validMentionedAccountIds = mentionedAccountIds.isEmpty
      ? validMentionAccountIdsFromRanges
      : mentionedAccountIds.intersection(validMentionAccountIdsFromRanges)
    let trimmed = limitedText.trimmingCharacters(in: .whitespaces)
    let limitedRichTextTitle = NECommonTextLimit
      .limitedUTF16(richTextTitle ?? "", limit: richTextTitleCharacterLimit)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || !limitedRichTextTitle.isEmpty else {
      return false
    }

    let request = ChatSendTextRequest(
      conversationId: context.conversationId,
      context: activeContext,
      text: limitedText,
      richTextTitle: limitedRichTextTitle.isEmpty ? nil : limitedRichTextTitle,
      replyToMessageId: replyToMessageId,
      replyToMessageServerId: replyToMessageServerId,
      mentionedAccountIds: validMentionedAccountIds,
      mentions: validMentions
    )
    sendLocalTypingStateIfNeeded(false, force: true)
    if let preparedTextSender = sendPipeline as? ChatPreparedTextSending {
      let message = preparedTextSender.makeTextMessage(for: request)
      sendPreparedTextRequest(
        request,
        message: message,
        pendingId: ChatMessageMapper.stableMessageId(for: message),
        mentions: validMentions,
        sender: preparedTextSender
      )
    } else {
      sendTextRequest(
        request,
        pendingId: "swiftui-pending-\(UUID().uuidString)",
        mentions: validMentions
      )
    }
    return true
  }

  private func clearInputAfterSend() {
    state.input.text = ""
    state.input.selectedRange = NSRange(location: 0, length: 0)
    state.input.richTextTitle = ""
    state.input.isRichTextExpanded = false
    state.input.isSendEnabled = false
    state.input.validation = makeInputValidation(for: "")
    state.input.reply = nil
    state.input.mentionedAccountIds.removeAll()
    state.input.mentions.removeAll()
  }

  private func sendTextRequest(_ request: ChatSendTextRequest,
                               pendingId: String,
                               mentions: [ChatMentionState]) {
    let pendingRow = ChatMessageMapper.pendingTextRow(
      id: pendingId,
      conversationId: context.conversationId,
      senderId: currentAccountProvider(),
      text: request.text,
      richTextTitle: request.richTextTitle,
      mentions: mentions
    )
    rememberOutgoingTextPresentation(pendingRow, aliases: [pendingId])
    upsertRows([pendingRow])
    requestTimelineScroll(to: pendingId, anchor: .bottom)
    let requestId = beginSendRequest(pendingId: pendingId)

    sendPipeline.sendText(request) { [weak self] progress in
      Task { @MainActor in
        guard let self, self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else {
          return
        }
        self.updateDeliveryState(for: pendingId, deliveryState: .pending(progress: progress))
      }
    } completion: { [weak self] result in
      Task { @MainActor in
        guard let self, self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else {
          return
        }
        self.finishSendRequest(pendingId: pendingId, requestId: requestId)
        self.handleSendResult(result, pendingId: pendingId)
      }
    }
  }

  private func sendPreparedTextRequest(_ request: ChatSendTextRequest,
                                       message: V2NIMMessage,
                                       pendingId: String,
                                       mentions: [ChatMentionState],
                                       sender: ChatPreparedTextSending) {
    cacheMessageContext([message])
    let pendingRow = ChatMessageMapper.pendingTextRow(
      id: pendingId,
      conversationId: context.conversationId,
      senderId: currentAccountProvider(),
      text: request.text,
      richTextTitle: request.richTextTitle,
      mentions: mentions
    )
    rememberOutgoingTextPresentation(
      pendingRow,
      aliases: newMessageAliases(for: message).union([pendingId])
    )
    upsertRows([pendingRow])
    requestTimelineScroll(to: pendingId, anchor: .bottom)
    let requestId = beginSendRequest(pendingId: pendingId)

    sender.sendTextMessage(message, request: request) { [weak self] progress in
      Task { @MainActor in
        guard let self, self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else {
          return
        }
        self.updateDeliveryState(for: pendingId, deliveryState: .pending(progress: progress))
      }
    } completion: { [weak self] result in
      Task { @MainActor in
        guard let self, self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else {
          return
        }
        self.finishSendRequest(pendingId: pendingId, requestId: requestId)
        self.handleSendResult(result, pendingId: pendingId)
      }
    }
  }

  public func sendPayload(_ payload: ChatOutgoingMessagePayload) {
    sendPayload(payload, requiresInputEnabled: true)
  }

  private func sendPayload(_ payload: ChatOutgoingMessagePayload,
                           requiresInputEnabled: Bool) {
    guard !requiresInputEnabled || state.input.isEnabled else {
      return
    }
    guard validateOutgoingPayload(payload) else {
      return
    }
    do {
      let message = try outgoingMessageFactory.message(from: payload)
      cacheMessageContext([message])
      let pendingId = ChatMessageMapper.stableMessageId(for: message)
      if let fingerprint = MessageMediaFingerprint(content: ChatMessageMapper.pendingRow(
        id: pendingId,
        conversationId: context.conversationId,
        senderId: currentAccountProvider(),
        payload: payload
      ).content) {
        pendingMediaFingerprints[pendingId] = fingerprint
      }
      upsertRows([
        ChatMessageMapper.pendingRow(
          id: pendingId,
          conversationId: context.conversationId,
          senderId: currentAccountProvider(),
          payload: payload
        ),
      ])
      requestTimelineScroll(to: pendingId, anchor: .bottom)
      let requestId = beginSendRequest(pendingId: pendingId)

      sendPipeline.sendMessage(message, conversationId: context.conversationId, context: activeContext) { [weak self] progress in
        Task { @MainActor in
          guard let self, self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else {
            return
          }
          self.updateDeliveryState(for: pendingId, deliveryState: .pending(progress: progress))
        }
      } completion: { [weak self] result in
        Task { @MainActor in
          guard let self, self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else {
            return
          }
          self.finishSendRequest(pendingId: pendingId, requestId: requestId)
          self.handleSendResult(result, pendingId: pendingId)
        }
      }
    } catch {
      state.toast = NEChatErrorMessageMapper.toast(for: error)
    }
  }

  public func sendPayloads(_ payloads: [ChatOutgoingMessagePayload]) {
    sendPayloads(payloads, requiresInputEnabled: true)
  }

  private func sendPayloads(_ payloads: [ChatOutgoingMessagePayload],
                            requiresInputEnabled: Bool) {
    guard !requiresInputEnabled || state.input.isEnabled else {
      return
    }
    for payload in payloads {
      sendPayload(payload, requiresInputEnabled: requiresInputEnabled)
    }
  }

  private func validateOutgoingPayload(_ payload: ChatOutgoingMessagePayload) -> Bool {
    guard config.fileSizeLimitMB > 0 else {
      return true
    }
    guard let path = payload.filePathForSizeLimit else {
      return true
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.doubleValue ?? 0
    guard size > 0 else {
      return true
    }
    let limit = config.fileSizeLimitMB * 1024 * 1024
    guard size <= limit else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_file_size_limit", value: "File is too large"),
        style: .warning
      )
      return false
    }
    return true
  }

  public func showOperations(for row: MessageRowState) {
    presentOperations(for: row, selectedText: nil)
  }

  private func presentOperations(for row: MessageRowState, selectedText: String?) {
    guard !row.isUnfinishedAIStream else {
      return
    }
    let isOpeningOperationMenu = state.operationMenu?.messageId != row.id
    var descriptors = ChatOperationPolicy.operationDescriptors(for: row, context: context, config: config)
    if selectedText != nil {
      descriptors = descriptors.filter { $0.operation == .copy }
    }
    operationPluginItems[row.id] = nil
    if let pluginText = operationPluginText(for: row, selectedText: selectedText),
       let pluginItem = messageOperationPluginItem(
      serviceName: NEChatUIKitSwiftUIConstants.aiSearchPluginServiceName,
      text: pluginText
    ) {
      operationPluginItems[row.id] = pluginItem
      descriptors.append(
        ChatOperationDescriptor(
          operation: .plugin,
          title: pluginItem.text,
          imageName: pluginItem.imageName.isEmpty ? "op_collection" : pluginItem.imageName,
          imageResource: pluginItem.imageResource,
          role: .normal
        )
      )
    }
    guard !descriptors.isEmpty else {
      return
    }
    if isOpeningOperationMenu {
      dismissInputForOperationMenu()
      establishedTextSelectionMessageIds.remove(row.id)
      selectedMessageText[row.id] = nil
      if selectedText == nil,
         isSelectableMessageText(row.content) {
        let fullText = copyText(for: row.content)
        if !fullText.isEmpty {
          selectedMessageText[row.id] = (fullText, true)
        }
      }
    }
    state.operationMenu = OperationMenuState(messageId: row.id, descriptors: descriptors)
  }

  public func performAIStreamAction(_ action: AIStreamAction, messageId: String) {
    guard let row = row(id: messageId) else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found"),
        style: .warning
      )
      return
    }
    guard row.isAIStreamTriggeredByCurrentUser else {
      showOperationUnavailableToast()
      return
    }
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }

    let requestId = UUID()
    aiStreamActionRequestIds[messageId] = requestId
    setAIStreamActionPhase(for: messageId, phase: action == .stop ? .stopping : .regenerating)
    aiStreamActionPerformer.perform(action, messageId: messageId) { [weak self] result in
      Task { @MainActor in
        guard let self = self,
              self.aiStreamActionRequestIds[messageId] == requestId,
              self.row(id: messageId) != nil else {
          return
        }
        self.aiStreamActionRequestIds[messageId] = nil
        switch result {
        case .success(let actionResult):
          self.setAIStreamActionPhase(for: messageId, phase: .idle)
          if let message = actionResult.message {
            self.state.toast = ChatToastState(message: message, style: .success)
          }
        case .failure(let error):
          let failureMessage = self.aiStreamActionFailureMessage(for: error)
          self.setAIStreamActionPhase(for: messageId, phase: .idle)
          self.state.toast = ChatToastState(message: failureMessage, style: .error)
        }
      }
    }
  }

  private func aiStreamActionFailureMessage(for error: Error) -> String {
    if (error as NSError).code == aiMessagesNotExist {
      return NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "The message was removed.")
    }
    return NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed")
  }

  private func audioRecordingFailureMessage(for error: Error) -> String {
    NEChatErrorMessageMapper.message(
      for: error,
      fallbackKey: "chat_audio_recording_failed",
      fallbackValue: "Audio recording failed"
    )
  }

  private func audioPlaybackFailureMessage(for error: Error) -> String {
    NEChatErrorMessageMapper.message(
      for: error,
      fallbackKey: "chat_audio_playback_failed",
      fallbackValue: "Audio playback failed"
    )
  }

  private func boundaryFailureToast(for error: Error) -> ChatToastState {
    NEChatErrorMessageMapper.toast(
      for: error,
      fallbackKey: "chat_boundary_failed",
      fallbackValue: "Operation could not be completed"
    )
  }

  private func boundaryErrorState(for error: Error) -> NEChatKitErrorState {
    NEChatErrorMessageMapper.errorState(
      for: error,
      fallbackKey: "chat_boundary_failed",
      fallbackValue: "Operation could not be completed"
    )
  }

  public func handleMessageTap(_ row: MessageRowState) {
    if state.multiSelect != nil {
      toggleSelection(for: row.id)
      return
    }

    switch row.content {
    case let .richText(title, body):
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        title: title,
        body: body,
        source: .message
      ))
    case let .reply(_, boxed):
      handleMessageTap(
        row,
        content: boxed.value,
        source: .message,
        suppressPlainTextPreview: true
      )
    case let .image(media):
      openMediaPreview(row: row, media: media, kind: .image)
    case let .video(media):
      openMediaPreview(row: row, media: media, kind: .video)
    case let .file(file):
      openFilePreview(row: row, file: file)
    case let .audio(audio):
      toggleAudioPlayback(row: row, audio: audio)
    case let .location(location):
      openLocation(row: row, location: location)
    case let .call(call):
      openCall(row: row, call: call)
    case let .multiForward(multiForward):
      openMultiForward(row: row, multiForward: multiForward)
    default:
      break
    }
  }

  private func handleMessageTap(_ row: MessageRowState,
                                content: MessageContentState,
                                source: ChatTextPreviewState.Source,
                                requiresLoadedRow: Bool = true,
                                suppressPlainTextPreview: Bool = false) {
    switch content {
    case let .text(text):
      guard !suppressPlainTextPreview else {
        return
      }
      openTextPreview(ChatTextPreviewState(
        messageId: sourceMessageId(for: row, source: source),
        body: text,
        source: source
      ))
    case let .richText(title, body):
      openTextPreview(ChatTextPreviewState(
        messageId: sourceMessageId(for: row, source: source),
        title: title,
        body: body,
        source: source
      ))
    case let .reply(_, boxed):
      handleMessageTap(
        row,
        content: boxed.value,
        source: source,
        requiresLoadedRow: requiresLoadedRow,
        suppressPlainTextPreview: suppressPlainTextPreview
      )
    case let .image(media):
      openMediaPreview(
        row: row,
        media: media,
        kind: .image,
        requiresLoadedRow: requiresLoadedRow
      )
    case let .video(media):
      openMediaPreview(
        row: row,
        media: media,
        kind: .video,
        requiresLoadedRow: requiresLoadedRow
      )
    case let .file(file):
      openFilePreview(row: row, file: file, requiresLoadedRow: requiresLoadedRow)
    case let .audio(audio):
      toggleAudioPlayback(row: row, audio: audio, requiresLoadedRow: requiresLoadedRow)
    case let .location(location):
      openLocation(row: row, location: location, requiresLoadedRow: requiresLoadedRow)
    case let .call(call):
      openCall(row: row, call: call, requiresLoadedRow: requiresLoadedRow)
    case let .multiForward(multiForward):
      openMultiForward(row: row, multiForward: multiForward)
    case let .aiStream(text, _, error):
      guard !suppressPlainTextPreview else {
        return
      }
      openTextPreview(ChatTextPreviewState(
        messageId: sourceMessageId(for: row, source: source),
        body: [text, error].compactMap { $0 }.joined(separator: "\n"),
        source: source
      ))
    default:
      break
    }
  }

  private func handleReplyTargetTap(_ replyTarget: MessageRowState,
                                    content: MessageContentState,
                                    anchorMessage: V2NIMMessage?) {
    switch content {
    case let .reply(_, boxed):
      handleReplyTargetTap(
        replyTarget,
        content: boxed.value,
        anchorMessage: anchorMessage
      )
    case let .video(media) where media.playableLocalPath == nil:
      pendingReplyAttachmentDownload = .video(row: replyTarget, media: media)
      focusMessage(replyTarget, anchorMessage: anchorMessage)
    case let .file(file) where file.existingLocalPath == nil:
      pendingReplyAttachmentDownload = .file(row: replyTarget, file: file)
      focusMessage(replyTarget, anchorMessage: anchorMessage)
    default:
      handleMessageTap(
        replyTarget,
        content: content,
        source: .reply,
        requiresLoadedRow: false
      )
    }
  }

  private func startPendingReplyAttachmentDownloadIfReady(matching targetRow: MessageRowState) {
    guard let pending = pendingReplyAttachmentDownload,
          sameMessage(pending.row, targetRow),
          let loadedId = loadedRowId(matching: pending.row),
          let loadedRow = row(id: loadedId) else {
      return
    }

    pendingReplyAttachmentDownload = nil
    switch pending {
    case let .video(_, media):
      openMediaPreview(row: loadedRow, media: media, kind: .video)
    case let .file(_, file):
      openFilePreview(row: loadedRow, file: file)
    }
  }

  private func sourceMessageId(for row: MessageRowState,
                               source: ChatTextPreviewState.Source) -> String {
    switch source {
    case .reply:
      return row.reply?.messageClientId ?? row.reply?.messageServerId ?? row.id
    case .message, .utility:
      return row.id
    }
  }

  private func resolvedReplyRow(for messageRow: MessageRowState) -> MessageRowState? {
    guard let reply = messageRow.reply else {
      return nil
    }
    if let messageClientId = reply.messageClientId,
       let loaded = row(id: messageClientId) {
      return loaded
    }
    if let messageServerId = reply.messageServerId,
       let loaded = row(id: messageServerId) {
      return loaded
    }
    return nil
  }

  private func replyRow(from row: MessageRowState,
                        content: MessageContentState) -> MessageRowState {
    guard let reply = row.reply else {
      return row
    }
    var replyRow = row
    replyRow.id = reply.messageClientId ?? reply.messageServerId ?? row.id
    replyRow.serverId = reply.messageServerId
    replyRow.senderId = reply.senderId
    replyRow.senderName = reply.senderName
    replyRow.conversationId = reply.conversationId ?? row.conversationId
    replyRow.content = content
    replyRow.reply = nil
    replyRow.textHighlights = []
    replyRow.timestamp = reply.createTime > 0 ? reply.createTime : row.timestamp
    return replyRow
  }

  public func openTextPreview(_ preview: ChatTextPreviewState) {
    guard !preview.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      preview.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
      return
    }
    state.route = ChatRouteState(
      currentRoute: .textPreview(preview),
      handlingState: .queued
    )
  }

  public func handleURLInteraction(_ url: URL,
                                   displayText: String,
                                   source: ChatURLInteractionSource,
                                   message: MessageRowState? = nil,
                                   preview: ChatTextPreviewState? = nil) {
    guard let urlHandler = config.urlInteractionHandler else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_url_open_requires_boundary", value: "Opening links requires a SwiftUI URL handler."),
        style: .info
      )
      return
    }

    let generation = nextBoundaryRequestGeneration()
    let request = ChatURLInteractionRequest(
      url: url,
      displayText: displayText,
      source: source,
      message: message,
      preview: preview,
      context: context
    )
    urlHandler.handleURLInteraction(request) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.boundaryRequestGeneration == generation,
              self.shouldAcceptURLInteractionResult(source: source, message: message, preview: preview) else {
          return
        }
        self.handleURLInteractionResult(result)
      }
    }
  }

  public func handleAvatarTap(_ row: MessageRowState) {
    guard state.multiSelect == nil else {
      toggleSelection(for: row.id)
      return
    }

    if handleMessageInteraction(.avatarTap, row: row) {
      return
    }

    routeToUserProfile(from: row)
  }

  public func handleAvatarLongPress(_ row: MessageRowState) {
    if handleMessageInteraction(.avatarLongPress, row: row) {
      return
    }
    insertMentionForTeamAvatarIfNeeded(row)
  }

  public func refreshContactDisplayAfterUserProfileReturnIfNeeded(_ route: NEChatSwiftUIRoute) {
    guard case let .userProfile(request) = route else {
      return
    }
    let accountId = request.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !accountId.isEmpty,
          !NEAIUserManager.shared.isAIUser(accountId) else {
      return
    }

    ChatRepo.removeSwiftUIP2PDisplayUser(accountId: accountId)
    pendingContactDisplayAccountIds.remove(accountId)
    let generation = (forcedContactDisplayGenerationByAccountId[accountId] ?? 0) + 1
    forcedContactDisplayGenerationByAccountId[accountId] = generation
    ChatRepo.shared.loadSwiftUIP2PDisplayUser(
      accountId: accountId,
      forceRefresh: true
    ) { [weak self] user, _ in
      Task { @MainActor in
        guard let self,
              self.forcedContactDisplayGenerationByAccountId[accountId] == generation,
              let user else {
          return
        }
        NEChatSwiftUILogger.log(
          "contactDisplay profileReturnRefresh conversationId=\(self.context.conversationId) accountId=\(accountId) generation=\(generation) rows=\(self.state.rows.count)"
        )
        self.mergeContactDisplayInfos([user])
        self.handleContactDisplayChanged([accountId], updatedUsers: [user])
      }
    }
  }

  public func handleMessageInteraction(_ interaction: ChatMessageInteraction,
                                       row: MessageRowState) -> Bool {
    config.messageInteractionHandler?(
      ChatMessageInteractionContext(
        interaction: interaction,
        row: row,
        session: context
      )
    ) ?? false
  }

  public func dismissOperations() {
    if let messageId = state.operationMenu?.messageId {
      selectedMessageText[messageId] = nil
      establishedTextSelectionMessageIds.remove(messageId)
    }
    state.operationMenu = nil
    operationPluginItems.removeAll()
  }

  public func updateTextSelection(_ selectedText: String?,
                                  isFullSelection: Bool,
                                  for messageId: String) {
    if let selectedText, !selectedText.isEmpty {
      let previousSelection = selectedMessageText[messageId]
      let didSelectionChange = previousSelection?.text != selectedText ||
        previousSelection?.isFullSelection != isFullSelection
      selectedMessageText[messageId] = (selectedText, isFullSelection)
      establishedTextSelectionMessageIds.insert(messageId)
      if state.operationMenu?.messageId == messageId,
         didSelectionChange,
         let row = row(id: messageId) {
        presentOperations(
          for: row,
          selectedText: isFullSelection ? nil : selectedText
        )
      }
    } else {
      if state.operationMenu?.messageId == messageId,
         selectedMessageText[messageId] != nil,
         !establishedTextSelectionMessageIds.contains(messageId) {
        return
      }
      selectedMessageText[messageId] = nil
      establishedTextSelectionMessageIds.remove(messageId)
      if state.operationMenu?.messageId == messageId {
        dismissOperations()
      }
    }
  }

  public func performOperation(_ operation: MessageOperation, messageId: String) {
    let pluginItem = operation == .plugin ? operationPluginItems[messageId] : nil
    let selectedText = selectedMessageText[messageId]?.text
    dismissOperations()

    guard let row = row(id: messageId) else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found"),
        style: .warning
      )
      return
    }

    if operation == .plugin {
      guard let pluginItem else {
        showOperationUnavailableToast()
        return
      }
      pluginItem.performAction()
      return
    }

    guard isOperationCurrentlyAllowed(operation, for: row) else {
      showOperationUnavailableToast()
      return
    }

    switch operation {
    case .copy:
      copyMessage(row, selectedText: selectedText)
    case .delete:
      state.pendingConfirmation = .deleteMessage(messageId: messageId)
    case .revoke:
      state.pendingConfirmation = .revokeMessage(messageId: messageId)
    case .reply:
      replyToMessage(row)
    case .forward:
      requestForward(messageIds: [messageId], merged: false)
    case .collect:
      collectMessage(row)
    case .pin:
      pinMessage(row: row, isPinned: row.isPinned)
    case .top:
      topMessage(id: messageId)
    case .untop:
      untopMessage(id: messageId)
    case .readReceipt:
      openReadReceipt(messageId: messageId)
    case .selectText:
      openSelectableText(row)
    case .multiSelect:
      startMultiSelect(with: messageId)
    case .voiceToText:
      voiceToText(id: messageId)
    case .earpiece:
      setAudioRoute(useSpeaker: false)
    case .speaker:
      setAudioRoute(useSpeaker: true)
    case .resend:
      retryFailedMessage(row)
    case .plugin:
      break
    }
  }

  private func messageOperationPluginItem(serviceName: String, text: String) -> OperationItem? {
    guard IMKitConfigCenter.shared.enableAIUser,
          NEAIUserManager.shared.getAISearchUser() != nil else {
      return nil
    }
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return nil
    }
    return IMKitPluginManager.shared.getPlugins(serviceName, text).first { item in
      item.type == .plugin && item.action != nil
    }
  }

  private func operationPluginText(for row: MessageRowState,
                                   selectedText: String?) -> String? {
    if let selectedText {
      return selectedText
    }
    switch row.content {
    case let .text(text), let .aiStream(text, _, _):
      return text
    case let .richText(title, body):
      return body.isEmpty ? title : body
    case let .reply(_, boxed):
      var unwrapped = row
      unwrapped.content = boxed.value
      return operationPluginText(for: unwrapped, selectedText: nil)
    default:
      return nil
    }
  }

  private func isOperationCurrentlyAllowed(_ operation: MessageOperation,
                                           for row: MessageRowState) -> Bool {
    ChatOperationPolicy
      .operationDescriptors(for: row, context: context, config: config)
      .contains { descriptor in
        descriptor.operation == operation && descriptor.isEnabled
      }
  }

  public func copyUtilityMessage(_ row: MessageRowState) {
    guard canCopyUtilityMessage(row) else {
      showOperationUnavailableToast()
      return
    }
    copyMessage(row)
  }

  public func copyCollectionMessage(_ row: MessageRowState) {
    guard NEChatUtilityMessageOperationRules.copyableText(row.content) != nil else {
      showOperationUnavailableToast()
      return
    }
    copyMessage(row)
  }

  private func openSelectableText(_ row: MessageRowState) {
    switch row.content {
    case let .text(text):
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        showOperationUnavailableToast()
        return
      }
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        body: text,
        source: .message
      ))
    case let .richText(title, body):
      let hasTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      guard hasTitle || hasBody else {
        showOperationUnavailableToast()
        return
      }
      openTextPreview(ChatTextPreviewState(
        messageId: row.id,
        title: title,
        body: body,
        source: .message
      ))
    default:
      showOperationUnavailableToast()
    }
  }

  private func replyToMessage(_ row: MessageRowState) {
    guard state.input.isEnabled else {
      return
    }
    state.input.reply = ChatReplyState(
      id: row.id,
      serverId: row.serverId,
      preview: ChatMessageMapper.referencePreviewText(for: row.content),
      senderName: row.senderName ?? row.senderId
    )
    state.input.mode = .text
    insertMentionForTeamReplyIfNeeded(row)
    state.input.focusRevision &+= 1
  }

  private func insertMentionForTeamReplyIfNeeded(_ row: MessageRowState) {
    guard IMKitConfigCenter.shared.enableAtMessage,
          context.kind == .team,
          let teamId = Self.teamId(from: context),
          let senderId = row.senderId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !senderId.isEmpty,
          !IMKitClient.instance.isMe(senderId) else {
      return
    }

    TeamRepo.shared.swiftUITeamMemberDisplayInfos(
      teamId: teamId,
      accountIds: [senderId],
      showAlias: false
    ) { [weak self] infos, _ in
      Task { @MainActor in
        guard let self,
              self.state.input.reply?.id == row.id else { return }
        self.insertMention(ChatMentionTargetState(
          accountId: senderId,
          displayName: infos.first?.displayName ?? senderId
        ))
      }
    }
  }

  private func insertMentionForTeamAvatarIfNeeded(_ row: MessageRowState) {
    guard state.multiSelect == nil else {
      return
    }
    guard IMKitConfigCenter.shared.enableAtMessage,
          context.kind == .team,
          let teamId = Self.teamId(from: context),
          let senderId = row.senderId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !senderId.isEmpty,
          !IMKitClient.instance.isMe(senderId) else {
      return
    }

    TeamRepo.shared.swiftUITeamMemberDisplayInfos(
      teamId: teamId,
      accountIds: [senderId],
      showAlias: false
    ) { [weak self] infos, _ in
      Task { @MainActor in
        guard let self else { return }
        self.insertMention(ChatMentionTargetState(
          accountId: senderId,
          displayName: infos.first?.displayName ?? senderId
        ))
      }
    }
  }

  public func forwardUtilityMessage(_ row: MessageRowState) {
    forwardUtilityMessage(row, resultToastHandler: nil)
  }

  public func forwardUtilityMessage(_ row: MessageRowState,
                                    resultToastHandler: ((ChatToastState) -> Void)?) {
    guard canForwardUtilityMessage(row) else {
      showOperationUnavailableToast()
      return
    }
    requestForward(
      messageIds: [row.id],
      merged: false,
      resultToastHandler: resultToastHandler
    )
  }

  public func forwardUtilityMessage(_ row: MessageRowState, sourceMessage: V2NIMMessage?) {
    forwardUtilityMessage(
      row,
      sourceMessage: sourceMessage,
      resultToastHandler: nil
    )
  }

  public func forwardUtilityMessage(_ row: MessageRowState,
                                    sourceMessage: V2NIMMessage?,
                                    resultToastHandler: ((ChatToastState) -> Void)?) {
    guard let sourceMessage else {
      forwardUtilityMessage(row, resultToastHandler: resultToastHandler)
      return
    }
    guard canForwardUtilityMessage(row) else {
      showOperationUnavailableToast()
      return
    }
    requestForward(
      messageIds: [row.id],
      merged: false,
      depth: 0,
      sourceMessages: [sourceMessage],
      resultToastHandler: resultToastHandler
    )
  }

  public func openReadReceipt(row: MessageRowState) {
    guard context.kind == .team,
          row.readReceipt?.isP2PRead != true,
          row.readReceipt?.unreadCount ?? 0 > 0 else {
      return
    }
    openReadReceipt(messageId: row.id)
  }

  public func openReadReceipt(messageId: String) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    state.route = ChatRouteState(
      currentRoute: .readReceipt(messageId: messageId, conversationId: context.conversationId),
      handlingState: .queued
    )
  }

  public func canCopyUtilityMessage(_ row: MessageRowState) -> Bool {
    isOperationCurrentlyAllowed(.copy, for: row)
  }

  public func canForwardUtilityMessage(_ row: MessageRowState) -> Bool {
    isOperationCurrentlyAllowed(.forward, for: row)
  }

  private func showOperationUnavailableToast() {
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("operation_unavailable", value: "Operation unavailable"),
      style: .warning
    )
  }

  public func reeditMessage(_ row: MessageRowState) {
    guard let reedit = row.reedit, !reedit.text.isEmpty else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_message_not_found", value: "Message not found"),
        style: .warning
      )
      return
    }

    guard !reedit.isExpired else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("editable_time_expired", value: "Time Out"),
        style: .warning
      )
      updateReeditState(for: row.id, expired: true)
      return
    }

    state.input.reply = (reedit.reply ?? row.reply).map {
      ChatReplyState(
        id: $0.messageClientId ?? $0.messageServerId ?? row.id,
        serverId: $0.messageServerId,
        preview: $0.preview ?? NEChatUIKitSwiftUIBundle.localized("chat_reply_loading", value: "Loading replied message"),
        senderName: $0.senderName ?? $0.senderId
      )
    }
    state.input.richTextTitle = NECommonTextLimit.limitedUTF16(
      reedit.title ?? "",
      limit: richTextTitleCharacterLimit
    )
    state.input.isRichTextExpanded = !state.input.richTextTitle.isEmpty
    state.input.mode = .text
    applyInputTextState(text: reedit.text, mentions: reedit.mentions)
  }

  public func confirmPendingAction() {
    guard let pending = state.pendingConfirmation else {
      return
    }
    state.pendingConfirmation = nil

    switch pending {
    case let .deleteMessage(messageId):
      deleteMessage(id: messageId)
    case let .revokeMessage(messageId):
      revokeMessage(id: messageId)
    case let .deleteSelected(messageIds):
      deleteSelectedMessages(ids: messageIds)
      clearSelection()
    case let .forwardSelected(messageIds, invalidMessageIds, merged, depth):
      removeSelectedRows(ids: Set(invalidMessageIds))
      guard !messageIds.isEmpty else {
        return
      }
      requestForward(messageIds: messageIds, merged: merged, depth: depth)
    }
  }

  public func dismissPendingAction() {
    state.pendingConfirmation = nil
  }

  public func toggleSelection(for id: String) {
    guard let row = row(id: id),
          !isRevoked(row.content),
          !row.isUnfinishedAIStream else {
      return
    }
    if state.multiSelect == nil {
      state.multiSelect = MultiSelectState()
      receivedMessagesWhileMultiSelect = false
    }
    _ = state.multiSelect?.selection.toggle(id)
    state.rows = state.rows.map { row in
      var next = row
      next.isSelected = state.multiSelect?.selection.ids.contains(row.id) ?? false
      return next
    }
  }

  public func requestSelectedForward(merged: Bool) {
    let selectedRows = selectedRows()
    guard !selectedRows.isEmpty else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_select_message_first", value: "Select messages first"),
        style: .warning
      )
      return
    }
    let limit = merged ? customMultiForwardLimitCount : customSingleForwardLimitCount
    guard selectedRows.count <= limit else {
      let key = merged ? "multiForward_forward_limit" : "per_item_forward_limit"
      let fallback = merged
        ? "Merged forwarding is limited to %d messages"
        : "Forward one by one is limited to %d messages"
      state.toast = ChatToastState(
        message: String(format: NEChatUIKitSwiftUIBundle.localized(key, value: fallback), limit),
        style: .warning
      )
      return
    }
    let rows = forwardableSelectedRows(selectedRows, merged: merged)
    let invalidIds = Set(selectedRows.map(\.id)).subtracting(rows.map(\.id))
    let ids = rows.map(\.id)
    let depth = mergedForwardDepth(for: rows, merged: merged)
    guard invalidIds.isEmpty else {
      state.pendingConfirmation = .forwardSelected(
        messageIds: ids,
        invalidMessageIds: Array(invalidIds),
        merged: merged,
        depth: depth
      )
      return
    }
    guard !rows.isEmpty else {
      return
    }
    requestForward(messageIds: ids, merged: merged, depth: depth)
  }

  public func requestSelectedDelete() {
    let ids = selectedMessageIds()
    guard !ids.isEmpty else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_select_message_first", value: "Select messages first"),
        style: .warning
      )
      return
    }
    guard ids.count <= deleteMessagesLimitCount else {
      state.toast = ChatToastState(
        message: String(
          format: NEChatUIKitSwiftUIBundle.localized("selete_messages_limit", value: "Delete is limited to %d messages"),
          deleteMessagesLimitCount
        ),
        style: .warning
      )
      return
    }
    state.pendingConfirmation = .deleteSelected(messageIds: ids)
  }

  public func clearSelection() {
    let shouldRestoreMultiSelectJumpIndicator = receivedMessagesWhileMultiSelect
    receivedMessagesWhileMultiSelect = false
    state.multiSelect = nil
    state.rows = state.rows.map { row in
      var next = row
      next.isSelected = false
      return next
    }
    if shouldRestoreMultiSelectJumpIndicator,
       let firstMessageId = pendingNewMessageIds.first?.primaryId ?? state.rows.last?.id {
      setNewMessageIndicator(NewMessageIndicatorState(
        count: pendingNewMessageIds.count,
        firstMessageId: firstMessageId,
        requiresLatestReload: state.newMessageIndicator?.requiresLatestReload == true
      ))
      return
    }
    refreshNewMessageIndicatorState(
      requiresLatestReload: state.newMessageIndicator?.requiresLatestReload == true
    )
  }

  public func clearNewMessageIndicator() {
    receivedMessagesWhilePageHidden = false
    let indicator = state.newMessageIndicator
    NEChatSwiftUILogger.log(
      "chatAction jumpDown vmStart indicatorCount=\(indicator?.count.description ?? "nil") first=\(indicator?.firstMessageId ?? "nil") requiresReload=\(indicator?.requiresLatestReload.description ?? "nil") history=\(isHistoryContextActive) rows=\(state.rows.count) last=\(state.rows.last?.id ?? "nil") currentTarget=\(state.timelineScrollTarget?.id ?? "nil") bottomVisible=\(isTimelineBottomVisible)"
    )
    if indicator?.requiresLatestReload == true || isHistoryContextActive {
      NEChatSwiftUILogger.log("chatAction jumpDown branch=reloadLatest")
      reloadLatestMessagesFromHistoryContext(scrollToLatestAfterReload: true)
      return
    }

    let messagesToMark = pendingNewMessagesFromLoadedRows()
    if let lastId = state.rows.last?.id {
      NEChatSwiftUILogger.log(
        "chatAction jumpDown branch=loadedLatest request id=\(lastId) pendingMark=\(messagesToMark.count)"
      )
      beginTimelineBottomPinning()
      requestTimelineScroll(to: lastId, anchor: .bottom, animated: false, reason: .jumpToLatest)
      NEChatSwiftUILogger.log(
        "chatAction jumpDown hideIndicator target=\(state.timelineScrollTarget?.id ?? "nil") targetAgeMs=\(state.timelineScrollTarget?.ageMilliseconds.description ?? "nil") bottomVisible=\(isTimelineBottomVisible) keepsPinned=\(state.keepsTimelineBottomPinned)"
      )
      setNewMessageIndicator(nil)
      clearPendingNewMessageIds()
    } else if let messageId = state.newMessageIndicator?.firstMessageId {
      NEChatSwiftUILogger.log(
        "chatAction jumpDown branch=indicatorFirst request id=\(messageId) pendingMark=\(messagesToMark.count)"
      )
      requestTimelineScroll(to: messageId, anchor: .bottom, animated: false, reason: .jumpToLatest)
      NEChatSwiftUILogger.log(
        "chatAction jumpDown hideIndicator target=\(state.timelineScrollTarget?.id ?? "nil") targetAgeMs=\(state.timelineScrollTarget?.ageMilliseconds.description ?? "nil") bottomVisible=\(isTimelineBottomVisible) keepsPinned=\(state.keepsTimelineBottomPinned)"
      )
      setNewMessageIndicator(nil)
      clearPendingNewMessageIds()
    } else {
      NEChatSwiftUILogger.log("chatAction jumpDown branch=noTarget")
      setNewMessageIndicator(nil)
      clearPendingNewMessageIds()
    }
    if !messagesToMark.isEmpty {
      syncReadState(for: messagesToMark)
    }
  }

  public func updateVisibleTimelineAnchor(_ messageId: String?) {
    visibleTimelineAnchorId = messageId
    if let stableId = firstExistingRowId(matching: [messageId]) {
      lastStableVisibleTimelineAnchorId = stableId
    }
  }

  public func updateVisibleTimelineRows(_ messageIds: Set<String>) {
    guard isPageVisible,
          isApplicationActiveProvider(),
          !messageIds.isEmpty else {
      return
    }
    if preservesPendingNewMessageIndicatorDuringRouteRestore {
      return
    }
    let shouldSyncAfterPageActivation = needsVisibleReadSyncAfterPageActivation
    if !shouldSyncAfterPageActivation {
      guard visibleTimelineRowIds != messageIds else {
        return
      }
    }
    let newlyVisibleMessageIds = messageIds.subtracting(visibleTimelineRowIds)
    visibleTimelineRowIds = messageIds
    hasConfirmedForegroundTimelineVisibility = true
    if receivedMessagesWhilePageHidden,
       pendingNewMessageIds.contains(where: { !$0.aliases.isDisjoint(with: messageIds) }) {
      // UIKit consumes the foreground new-message prompt once the pending row
      // has actually entered the visible area, even when the bottom probe was
      // already visible before the scene became active.
      receivedMessagesWhilePageHidden = false
    }
    if let stableId = currentFirstVisibleTimelineRowId() {
      lastStableVisibleTimelineAnchorId = stableId
    }
    // UIKit reports reads for what was actually viewed. Do not mark the
    // complete loaded page as read merely because it was fetched from history.
    let messageIdsToSync = shouldSyncAfterPageActivation ? messageIds : newlyVisibleMessageIds
    let visibleMessages = state.rows
      .filter { !self.messageIds(for: $0).isDisjoint(with: messageIdsToSync) }
      .compactMap { messageContextMessage(for: $0) }
    if !visibleMessages.isEmpty {
      // UIKit clears the conversation unread count whenever the current chat has
      // actually displayed new content. Keep message receipts scoped to the
      // visible rows, while also clearing the conversation unread count for
      // newly visible messages that arrive after the page is already active.
      syncReadState(for: visibleMessages, shouldSyncConversationRead: true)
    }
    if shouldSyncAfterPageActivation, !visibleMessages.isEmpty {
      needsVisibleReadSyncAfterPageActivation = false
    }
    guard state.newMessageIndicator != nil || !pendingNewMessageIds.isEmpty else {
      return
    }
    refreshNewMessageIndicatorAfterVisibleRowsChange()
  }

  public func updateLatestTimelineRowVisibility(_ isVisible: Bool) {
    guard isVisible,
          isPageVisible,
          isApplicationActiveProvider(),
          !preservesPendingNewMessageIndicatorDuringRouteRestore,
          state.multiSelect == nil,
          !isHistoryContextActive,
          state.newMessageIndicator != nil || !pendingNewMessageIds.isEmpty else {
      return
    }
    // UIKit clears its jump-down queue when the final cell reaches willDisplay.
    // Keep this independent from the stricter bottom-anchor calculation.
    receivedMessagesWhilePageHidden = false
    isProgrammaticallyScrollingToLatest = false
    clearPendingNewMessageIds()
    setNewMessageIndicator(nil)
  }

  public func setPageVisible(_ visible: Bool) {
    let visible = visible &&
      isApplicationActiveProvider() &&
      nativeBoundaryPresentationLifecycle == nil
    let wasPageVisible = isPageVisible
    if wasPageVisible != visible {
      pageVisibilityGeneration = UUID()
    }
    isPageVisible = visible
    if visible {
      if !wasPageVisible {
        hasConfirmedForegroundTimelineVisibility = false
        visibleTimelineRowIds.removeAll()
        if receivedMessagesWhilePageHidden, !pendingNewMessageIds.isEmpty {
          isTimelineBottomVisible = false
        }
        // The visible-row callbacks may have been suppressed while the scene was
        // inactive. Wait for the timeline to report actual foreground rows before
        // clearing the conversation unread state or sending read receipts.
        needsVisibleReadSyncAfterPageActivation = true
      }
      // When the page becomes visible, reassess the indicator state to enforce mutual
      // exclusivity: if the timeline bottom is still visible, hide the indicator;
      // otherwise ensure it reflects the current pending-new-message count.
      refreshNewMessageIndicatorState(requiresLatestReload: state.newMessageIndicator?.requiresLatestReload == true)
    } else if wasPageVisible {
      // Invalidate callbacks from work started while the timeline was visible.
      // The SDK request itself is not cancellable, but no stale result may
      // reactivate or advance the SwiftUI read state after UIKit would hide it.
      readSyncRequestGeneration += 1
      needsVisibleReadSyncAfterPageActivation = false
      hasConfirmedForegroundTimelineVisibility = false
      visibleTimelineRowIds.removeAll()
      discardPendingReadSync()
      stopActiveMedia()
    }
  }

  public func updateTimelineBottomVisibility(_ isVisible: Bool) {
    NEChatSwiftUILogger.log(
      "chatAction bottomVisibility update incoming=\(isVisible) current=\(isTimelineBottomVisible) indicator=\(state.newMessageIndicator?.count.description ?? "nil") target=\(state.timelineScrollTarget?.id ?? "nil") targetReason=\(state.timelineScrollTarget?.reason.rawValue ?? "nil") keepsPinned=\(state.keepsTimelineBottomPinned) programmaticLatest=\(isProgrammaticallyScrollingToLatest) rows=\(state.rows.count)"
    )
    guard isPageVisible else {
      NEChatSwiftUILogger.log("chatAction bottomVisibility ignored reason=pageHidden")
      return
    }
    if !isVisible {
      if isProgrammaticallyScrollingToLatest {
        NEChatSwiftUILogger.log("chatAction bottomVisibility ignored reason=programmaticLatest")
        return
      }
      if state.keepsTimelineBottomPinned {
        NEChatSwiftUILogger.log("chatAction bottomVisibility ignored reason=keepsPinned")
        return
      }
    }
    let didChange = isTimelineBottomVisible != isVisible
    let needsHiddenIndicatorRefresh = !isVisible &&
      state.newMessageIndicator == nil &&
      !state.rows.isEmpty &&
      state.multiSelect == nil &&
      !isProgrammaticallyScrollingToLatest &&
      !state.keepsTimelineBottomPinned
    guard didChange ||
      needsHiddenIndicatorRefresh ||
      (isVisible && (state.newMessageIndicator != nil || state.keepsTimelineBottomPinned)) else {
      return
    }

    isTimelineBottomVisible = isVisible
    if isVisible {
      if receivedMessagesWhilePageHidden, !pendingNewMessageIds.isEmpty {
        return
      }
      isProgrammaticallyScrollingToLatest = false
      clearPendingNewMessageIds()
      setNewMessageIndicator(nil)
      return
    }

    guard !state.rows.isEmpty,
          state.multiSelect == nil,
          state.newMessageIndicator == nil else {
      return
    }
    if isHistoryContextActive {
      showHistoryJumpIndicatorIfNeeded()
      return
    }
    refreshNewMessageIndicatorState(requiresLatestReload: false)
  }

  @discardableResult
  public func consumeTimelineScrollTarget(id: String? = nil) -> Bool {
    NEChatSwiftUILogger.log(
      "chatAction scrollConsume request id=\(id ?? "nil") current=\(state.timelineScrollTarget?.id ?? "nil") reason=\(state.timelineScrollTarget?.reason.rawValue ?? "nil") messageId=\(state.timelineScrollTarget?.messageId ?? "nil") rows=\(state.rows.count) bottomVisible=\(isTimelineBottomVisible) indicator=\(state.newMessageIndicator?.count.description ?? "nil")"
    )
    if let id,
       state.timelineScrollTarget?.id != id {
      NEChatSwiftUILogger.log(
        "history scrollTarget consume ignored id=\(id) current=\(state.timelineScrollTarget?.id ?? "nil")"
      )
      return false
    }
    let consumedTarget = state.timelineScrollTarget
    clearNewMessageIndicatorIfNeeded(afterConsuming: consumedTarget)
    setTimelineScrollTarget(nil)
    var didCompleteRouteTimelineRestore = false
    if consumedTarget?.reason == .explicitAnchor,
       preservesPendingNewMessageIndicatorDuringRouteRestore {
      preservesPendingNewMessageIndicatorDuringRouteRestore = false
      refreshNewMessageIndicatorAfterVisibleRowsChange()
      didCompleteRouteTimelineRestore = true
    }
    NEChatSwiftUILogger.log("chatAction scrollConsume cleared")
    return didCompleteRouteTimelineRestore
  }

  public func markRouteHandled() {
    state.route.handlingState = .handled
  }

  public func confirmTeamLifecycleAlert() {
    guard let alert = state.teamLifecycleAlert else {
      return
    }
    if alert.shouldDeleteConversation {
      NotificationCenter.default.post(
        name: NENotificationName.deleteConversationNotificationName,
        object: alert.conversationId
      )
    }
    state.teamLifecycleAlert = nil
    state.route = ChatRouteState()
    state.forwardSheet = nil
    state.toast = ChatToastState(message: alert.message, style: .warning)
    NotificationCenter.default.post(
      name: NENotificationName.popGroupChatVC,
      object: nil,
      userInfo: ["teamId": alert.teamId]
    )
  }

  public func closeTeamLifecycleRouteIfNeeded() {
    guard let alert = state.teamLifecycleAlert,
          !alert.requiresUserConfirmation else {
      return
    }
    confirmTeamLifecycleAlert()
  }

  public func dismissTeamLifecycleAlert() {
    state.teamLifecycleAlert = nil
  }

  @discardableResult
  public func handleLocalTeamLifecycleExit(teamId: String) -> Bool {
    guard context.kind == .team,
          Self.teamId(from: context) == teamId else {
      return false
    }
    localTeamLifecycleExitInFlightIds.remove(teamId)
    locallyCompletedTeamLifecycleIds.insert(teamId)
    state.teamLifecycleAlert = nil
    clearRoute()
    return true
  }

  private func handleLocalTeamLifecycleExitStarted(teamId: String) {
    guard context.kind == .team,
          Self.teamId(from: context) == teamId else {
      return
    }
    localTeamLifecycleExitInFlightIds.insert(teamId)
    state.teamLifecycleAlert = nil
  }

  private func handleLocalTeamLifecycleExitFailed(teamId: String) {
    guard context.kind == .team,
          Self.teamId(from: context) == teamId,
          localTeamLifecycleExitInFlightIds.remove(teamId) != nil else {
      return
    }
    validateTeamLifecycleIfNeeded()
  }

  public func openRoute(_ route: NEChatSwiftUIRoute) {
    captureTimelinePositionBeforeRoute()
    state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
  }

  public func clearRoute() {
    state.route = ChatRouteState()
    state.forwardSheet = nil
    forwardSourceMessagesByRequestKey.removeAll()
    refreshP2PDisplayStateIfNeeded()
  }

  public func handleMultiForwardPreviewLoadFailure(_ error: NEChatKitErrorState) {
    let message = error.code == 0
      ? error.message
      : NEChatUIKitSwiftUIBundle.localized(
        "multiForward_open_failed",
        value: "Information not retrieved."
      )
    clearRoute()
    state.toast = ChatToastState(message: message, style: .warning)
  }

  public func updateForwardComment(_ comment: String) {
    state.forwardSheet?.comment = comment
  }

  public func toggleForwardTarget(_ target: ChatForwardTargetState) {
    guard state.forwardSheet?.recentTargets.contains(target) == true else {
      return
    }

    if state.forwardSheet?.selectedTargetIds.contains(target.id) == true {
      state.forwardSheet?.selectedTargetIds.remove(target.id)
    } else {
      state.forwardSheet?.selectedTargetIds.insert(target.id)
    }
  }

  public func submitForwardSheet() {
    guard let forwardSheet = state.forwardSheet else {
      return
    }

    let selectedTargets = forwardSheet.selectedTargets
    guard !selectedTargets.isEmpty else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_forward_select_target_first", value: "Select a target first"),
        style: .warning
      )
      return
    }

    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }

    let comment = forwardSheet.comment.trimmingCharacters(in: .whitespacesAndNewlines)
    let selection = ChatForwardSelectionResult(
      targets: selectedTargets,
      comment: comment.isEmpty ? nil : comment
    )
    let sourceMessages = takeForwardSourceMessages(for: forwardSheet.request)
    state.forwardSheet = nil
    clearRoute()
    updateRecentForwardTargets(selectedTargets)
    if sourceMessages.isEmpty {
      forwardMessages(messageIds: forwardSheet.request.messageIds,
                      selection: selection,
                      merged: forwardSheet.request.merged,
                      depth: forwardSheet.request.depth)
    } else {
      forwardMessages(messages: sourceMessages,
                      selection: selection,
                      merged: forwardSheet.request.merged,
                      depth: forwardSheet.request.depth)
    }
    clearSelection()
  }

  public func dismissForwardSheet() {
    discardForwardSourceMessages(for: state.forwardSheet?.request)
    state.forwardSheet = nil
    clearRoute()
  }

  private func startMultiSelect(with messageId: String) {
    if state.multiSelect == nil {
      state.multiSelect = MultiSelectState()
      receivedMessagesWhileMultiSelect = false
    }
    if state.multiSelect?.selection.ids.contains(messageId) != true {
      _ = state.multiSelect?.selection.toggle(messageId)
    }
    state.rows = state.rows.map { row in
      var next = row
      next.isSelected = state.multiSelect?.selection.ids.contains(row.id) ?? false
      return next
    }
  }

  private func requestForward(messageIds: [String], merged: Bool, depth: Int = 0) {
    requestForward(
      messageIds: messageIds,
      merged: merged,
      depth: depth,
      sourceMessages: [],
      resultToastHandler: nil
    )
  }

  private func requestForward(messageIds: [String],
                              merged: Bool,
                              depth: Int = 0,
                              resultToastHandler: ((ChatToastState) -> Void)?) {
    requestForward(
      messageIds: messageIds,
      merged: merged,
      depth: depth,
      sourceMessages: [],
      resultToastHandler: resultToastHandler
    )
  }

  private func requestForward(messageIds: [String],
                              merged: Bool,
                              depth: Int,
                              sourceMessages: [V2NIMMessage],
                              resultToastHandler: ((ChatToastState) -> Void)? = nil) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let request = ChatForwardRequest(
      context: context,
      messageIds: messageIds,
      merged: merged,
      depth: depth,
      isFromMessageMultiSelect: state.multiSelect != nil
    )
    rememberForwardSourceMessages(sourceMessages, for: request)
    guard let handler = config.forwardSelectionHandler else {
      presentForwardSheet(request)
      return
    }

    forwardRequestGeneration += 1
    let generation = forwardRequestGeneration
    state.route.handlingState = .handling
    handler.selectForwardTargets(request) { [weak self] result in
      Task { @MainActor in
        guard let self = self, self.forwardRequestGeneration == generation else {
          return
        }
        switch result {
        case .success(let selection):
          self.state.route.handlingState = .handled
          guard !selection.targets.isEmpty else {
            self.discardForwardSourceMessages(for: request)
            self.clearRoute()
            return
          }
          self.submitForwardSelection(
            selection,
            for: request,
            resultToastHandler: resultToastHandler
          )
        case .failure(let error):
          self.discardForwardSourceMessages(for: request)
          self.state.route.handlingState = .failed(self.boundaryErrorState(for: error))
          self.presentForwardResultToast(
            self.boundaryFailureToast(for: error),
            using: resultToastHandler
          )
        }
      }
    }
  }

  private func presentForwardSheet(messageIds: [String], merged: Bool) {
    presentForwardSheet(ChatForwardRequest(
      context: context,
      messageIds: messageIds,
      merged: merged,
      isFromMessageMultiSelect: true
    ))
  }

  private func rememberForwardSourceMessages(_ messages: [V2NIMMessage],
                                             for request: ChatForwardRequest) {
    let key = forwardSourceMessageKey(for: request)
    if messages.isEmpty {
      forwardSourceMessagesByRequestKey[key] = nil
    } else {
      forwardSourceMessagesByRequestKey[key] = messages
    }
  }

  private func takeForwardSourceMessages(for request: ChatForwardRequest) -> [V2NIMMessage] {
    forwardSourceMessagesByRequestKey.removeValue(forKey: forwardSourceMessageKey(for: request)) ?? []
  }

  private func discardForwardSourceMessages(for request: ChatForwardRequest?) {
    guard let request else {
      return
    }
    forwardSourceMessagesByRequestKey[forwardSourceMessageKey(for: request)] = nil
  }

  private func forwardSourceMessageKey(for request: ChatForwardRequest) -> String {
    ([
      request.context.conversationId,
      request.merged ? "merged" : "single",
      "\(request.depth)",
    ] + request.messageIds).joined(separator: "|")
  }

  private func presentForwardSheet(_ request: ChatForwardRequest) {
    let recentTargets = config.recentForwardProvider?.recentForwardTargets(for: request) ?? []
    let selectedIds: Set<String> = recentTargets.count == 1 ? Set([recentTargets[0].id]) : []
    state.forwardSheet = ChatForwardSheetState(
      request: request,
      recentTargets: recentTargets,
      selectedTargetIds: selectedIds
    )
    state.route = ChatRouteState(
      currentRoute: .forwardMessages(conversationId: context.conversationId, messageIds: request.messageIds, merged: request.merged),
      handlingState: .queued
    )
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("chat_forward_route_ready", value: "Forward route is ready"),
      style: .info
    )
  }

  private func presentForwardSheet(_ request: ChatForwardRequest,
                                   fixedTargets: [ChatForwardTargetState]) {
    state.forwardSheet = ChatForwardSheetState(
      request: request,
      fixedTargets: fixedTargets
    )
    state.route = ChatRouteState(
      currentRoute: .forwardMessages(conversationId: context.conversationId, messageIds: request.messageIds, merged: request.merged),
      handlingState: .queued
    )
  }

  private func submitForwardSelection(_ selection: ChatForwardSelectionResult,
                                      for request: ChatForwardRequest,
                                      resultToastHandler: ((ChatToastState) -> Void)? = nil) {
    let sourceMessages = takeForwardSourceMessages(for: request)
    if resultToastHandler == nil {
      clearRoute()
    } else {
      // UIKit leaves the history result controller visible while the native
      // target picker dismisses, so completion feedback belongs to that page.
      state.forwardSheet = nil
      state.route.handlingState = .handled
    }
    updateRecentForwardTargets(selection.targets)
    if sourceMessages.isEmpty {
      forwardMessages(messageIds: request.messageIds,
                      selection: selection,
                      merged: request.merged,
                      depth: request.depth,
                      resultToastHandler: resultToastHandler)
    } else {
      forwardMessages(messages: sourceMessages,
                      selection: selection,
                      merged: request.merged,
                      depth: request.depth,
                      resultToastHandler: resultToastHandler)
    }
    clearSelection()
  }

  private func updateRecentForwardTargets(_ targets: [ChatForwardTargetState]) {
    let conversationIds = targets.map(\.conversationId).filter { !$0.isEmpty }
    guard !conversationIds.isEmpty else {
      return
    }
    SettingRepo.shared.updateRecentForward(conversationIds)
  }

  private func selectedMessageIds() -> [String] {
    Array(state.multiSelect?.selection.ids ?? [])
  }

  private func selectedRows() -> [MessageRowState] {
    let ids = state.multiSelect?.selection.ids ?? []
    return state.rows.filter { ids.contains($0.id) || ids.contains($0.serverId ?? "") }
  }

  private func forwardableSelectedRows(_ rows: [MessageRowState], merged: Bool) -> [MessageRowState] {
    rows.filter { isForwardableSelectedRow($0, merged: merged) }
  }

  private func isForwardableSelectedRow(_ row: MessageRowState, merged: Bool) -> Bool {
    guard isSent(row.deliveryState) else {
      return false
    }
    switch primaryMessageContent(row.content) {
    case .tip, .revoke:
      return false
    case .audio, .call:
      return merged
    case let .aiStream(_, isFinished, _):
      return isFinished
    case let .multiForward(multiForward):
      return !merged || multiForward.depth < customMultiForwardMaxDepth
    default:
      return true
    }
  }

  private func primaryMessageContent(_ content: MessageContentState) -> MessageContentState {
    if case let .reply(_, boxed) = content {
      return primaryMessageContent(boxed.value)
    }
    return content
  }

  private func mergedForwardDepth(for rows: [MessageRowState], merged: Bool) -> Int {
    guard merged else {
      return 0
    }
    let maxNestedDepth = rows.reduce(0) { current, row in
      if case let .multiForward(multiForward) = row.content {
        return max(current, multiForward.depth)
      }
      return current
    }
    return maxNestedDepth + 1
  }

  private func isSent(_ deliveryState: MessageDeliveryState) -> Bool {
    switch deliveryState {
    case .none, .sent, .read:
      return true
    case .pending, .failed:
      return false
    }
  }

  private func removeSelectedRows(ids: Set<String>) {
    guard !ids.isEmpty else {
      return
    }
    for id in ids {
      _ = state.multiSelect?.selection.toggle(id)
    }
    state.rows = state.rows.map { row in
      var next = row
      next.isSelected = state.multiSelect?.selection.ids.contains(row.id) ?? false
      return next
    }
  }

  private func attachListeners() {
    guard !listenerBinder.isActive else {
      return
    }

    let token = ChatRepo.shared.addChatEventListener(
      NEChatEvent(
        sendMessage: { [weak self] message in
          Task { @MainActor in
            self?.handleSentMessageState(message)
          }
        },
        sendMessageFailed: { [weak self] message, error in
          Task { @MainActor in
            self?.handleSendFailure(message, error: error)
          }
        },
        receiveMessages: { [weak self] messages in
          Task { @MainActor in
            self?.handleReceivedMessages(messages)
          }
        },
        receiveP2PMessageReadReceipts: { [weak self] receipts in
          Task { @MainActor in
            self?.handleP2PReadReceipts(receipts)
          }
        },
        receiveTeamMessageReadReceipts: { [weak self] receipts in
          Task { @MainActor in
            self?.handleTeamReadReceipts(receipts)
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
            self?.handleDeletedMessages(notifications)
          }
        },
        clearHistoryNotifications: { [weak self] notifications in
          Task { @MainActor in
            self?.handleClearHistoryNotifications(notifications)
          }
        },
        receiveMessagesModified: { [weak self] messages in
          Task { @MainActor in
            self?.handleModifiedMessages(messages)
          }
        }
      )
    )
    listenerBinder.bind(token)

    let clientToken = clientEventSource.addClientEventListener(
      NEIMKitClientEvent(
        dataSync: { [weak self] type, syncState, error in
          Task { @MainActor in
            self?.handleDataSync(type: type, syncState: syncState, error: error)
          }
        },
        connectStatus: { [weak self] status in
          Task { @MainActor in
            self?.handleConnectStatus(status)
          }
        },
        connectFailed: { [weak self] error in
          Task { @MainActor in
            self?.handleConnectFailed(error)
          }
        },
        disconnected: { [weak self] error in
          Task { @MainActor in
            self?.handleDisconnected(error)
          }
        },
        loginStatus: { [weak self] status in
          Task { @MainActor in
            self?.handleLoginStatus(status)
          }
        },
        loginFailed: { [weak self] error in
          Task { @MainActor in
            self?.handleLoginFailed(error)
          }
        },
        kickedOffline: { [weak self] detail in
          Task { @MainActor in
            self?.handleKickedOffline(detail)
          }
        }
      )
    )
    listenerBinder.bind(clientToken)

    if let reachabilityManager = networkReachabilityManager {
      reachabilityManager.listenerQueue = .main
      reachabilityManager.listener = { [weak self] status in
        Task { @MainActor in
          self?.handleSystemReachability(status)
        }
      }
      reachabilityManager.startListening()
      listenerBinder.bind(NEChatKitListenerToken { [weak reachabilityManager] in
        reachabilityManager?.listener = nil
        reachabilityManager?.stopListening()
      })
    }

    let mediaStopCancellable = NotificationCenter.default
      .publisher(for: .neChatMediaPlaybackShouldStop)
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.stopActiveMedia()
        }
      }
    listenerBinder.bind(NEChatKitListenerToken {
      mediaStopCancellable.cancel()
    })

    let callKitStopCancellable = NotificationCenter.default
      .publisher(for: Notification.Name("kCallKitShowNoti"))
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.stopActiveMedia()
        }
      }
    listenerBinder.bind(NEChatKitListenerToken {
      callKitStopCancellable.cancel()
    })

    if IMKitConfigCenter.shared.enableAIUser {
      let aiUserToken = NEAIUserManager.shared.addAIUserChangeHandler { [weak self] _ in
        Task { @MainActor in
          self?.refreshMoreActions()
          self?.refreshCachedContactDisplayInfos()
          self?.refreshTeamMemberDisplayInfosIfNeeded()
          self?.insertAIWelcomeMessageIfNeeded()
        }
      }
      listenerBinder.bind(aiUserToken)
    }

    let aiModelToken = aiRepo.addAIModelCallEventListener(
      NEAIModelCallEvent(proxyModelCall: { [weak self] result in
        Task { @MainActor in
          self?.handleInputTranslationResult(result)
        }
      })
    )
    listenerBinder.bind(aiModelToken)

    let contactToken = ContactRepo.shared.addContactEventListener(
      NEContactEvent(
        userProfileChanged: { [weak self] users in
          Task { @MainActor in
            let displayUsers = users.map { NEUserWithFriend(user: $0) }
            self?.mergeContactDisplayInfos(displayUsers)
            self?.handleContactDisplayChanged(users.compactMap(\.accountId), updatedUsers: displayUsers)
          }
        },
        friendAdded: { [weak self] friend in
          Task { @MainActor in
            guard let accountId = friend.accountId else {
              return
            }
            ChatRepo.removeSwiftUIP2PDisplayUser(accountId: accountId)
            let displayUser = NEUserWithFriend(friend: friend)
            self?.mergeContactDisplayInfos([displayUser])
            self?.handleContactDisplayChanged([accountId], updatedUsers: [displayUser])
          }
        },
        friendDeleted: { [weak self] accountId, _ in
          Task { @MainActor in
            self?.contactDisplayInfoByAccountId.removeValue(forKey: accountId)
            self?.handleContactDisplayChanged([accountId])
          }
        },
        friendInfoChanged: { [weak self] friend in
          Task { @MainActor in
            let displayUser = NEUserWithFriend(friend: friend)
            self?.mergeContactDisplayInfos([displayUser])
            self?.handleContactDisplayChanged(
              [friend.accountId].compactMap { $0 },
              updatedUsers: [displayUser]
            )
          }
        },
        contactChanged: { [weak self] changeType, contacts in
          Task { @MainActor in
            let displayContacts = Self.contactDisplayInfos(from: contacts, changeType: changeType)
            let accountIds = displayContacts.compactMap { $0.user?.accountId ?? $0.friend?.accountId }
            self?.mergeContactDisplayInfos(displayContacts)
            self?.handleContactDisplayChanged(accountIds, updatedUsers: displayContacts)
          }
        }
      )
    )
    listenerBinder.bind(contactToken)

    let didTapHeaderCancellable = NotificationCenter.default
      .publisher(for: NENotificationName.didTapHeader)
      .sink { [weak self] notification in
        guard let user = notification.object as? NEUserWithFriend else {
          return
        }
        Task { @MainActor in
          self?.mergeContactDisplayInfos([user])
        }
      }
    listenerBinder.bind(NEChatKitListenerToken {
      didTapHeaderCancellable.cancel()
    })

    let friendCacheToken = NEFriendUserCache.shared.addFriendCacheInitListener { [weak self] in
      Task { @MainActor in
        self?.handleFriendCacheInitialized()
      }
    }
    listenerBinder.bind(friendCacheToken)

    refreshRobotAwareMoreActionsIfNeeded()
    bindP2PPresenceListenersIfNeeded()

    if context.kind == .team {
      let teamToken = TeamRepo.shared.addTeamEventListener(
        NETeamEvent(
          teamDismissed: { [weak self] team in
            Task { @MainActor in
              self?.handleTeamDismissed(team)
            }
          },
          teamLeft: { [weak self] team, isKicked in
            Task { @MainActor in
              self?.handleTeamLeft(team, isKicked: isKicked)
            }
          },
          teamInfoUpdated: { [weak self] team in
            Task { @MainActor in
              self?.handleTeamInfoUpdated(team)
            }
          },
          teamMemberJoined: { [weak self] members in
            Task { @MainActor in
              self?.handleTeamMembersJoined(members)
            }
          },
          teamMemberKicked: { [weak self] _, members in
            Task { @MainActor in
              self?.handleTeamMembershipChanged(members)
            }
          },
          teamMemberLeft: { [weak self] members in
            Task { @MainActor in
              self?.handleTeamMembershipChanged(members)
            }
          },
          teamMemberInfoUpdated: { [weak self] members in
            Task { @MainActor in
              self?.handleTeamMemberInfoUpdated(members)
            }
          }
        )
      )
      listenerBinder.bind(teamToken)

      let teamId = Self.teamId(from: context) ?? ""
      let localExitStartedCancellable = NotificationCenter.default
        .publisher(for: NENotificationName.localTeamLifecycleExitStarted)
        .sink { [weak self] notification in
          guard let notificationTeamId = notification.userInfo?["teamId"] as? String,
                notificationTeamId == teamId else {
            return
          }
          Task { @MainActor in
            self?.handleLocalTeamLifecycleExitStarted(teamId: teamId)
          }
        }
      listenerBinder.bind(NEChatKitListenerToken {
        localExitStartedCancellable.cancel()
      })

      let localExitFailedCancellable = NotificationCenter.default
        .publisher(for: NENotificationName.localTeamLifecycleExitFailed)
        .sink { [weak self] notification in
          guard let notificationTeamId = notification.userInfo?["teamId"] as? String,
                notificationTeamId == teamId else {
            return
          }
          Task { @MainActor in
            self?.handleLocalTeamLifecycleExitFailed(teamId: teamId)
          }
        }
      listenerBinder.bind(NEChatKitListenerToken {
        localExitFailedCancellable.cancel()
      })

      // Keep lifecycle state deduplicated while the route host performs dismissal.
      let popCancellable = NotificationCenter.default
        .publisher(for: NENotificationName.popGroupChatVC)
        .sink { [weak self] notification in
          guard let notificationTeamId = notification.userInfo?["teamId"] as? String,
                notificationTeamId == teamId else {
            return
          }
          Task { @MainActor in
            self?.handleLocalTeamLifecycleExit(teamId: teamId)
          }
        }
      listenerBinder.bind(NEChatKitListenerToken {
        popCancellable.cancel()
      })
    }

    if context.usesTopicHistory {
      let topicToken = topicRepo.addTopicEventListener(
        NETopicEvent(
          topicAdded: { [weak self] topic in
            Task { @MainActor in
              self?.handleTopicAdded(topic)
            }
          },
          topicsRemoved: { [weak self] topics in
            Task { @MainActor in
              self?.handleTopicsRemoved(topics)
            }
          },
          topicUpdated: { [weak self] topic in
            Task { @MainActor in
              self?.handleTopicUpdated(topic)
            }
          }
        )
      )
      listenerBinder.bind(topicToken)
    }
  }

  private func invalidateTransientRequests(preservingNativeBoundaryRequest: Bool = false) {
    historyRequestGeneration += 1
    pendingOlderHistoryLoad = nil
    operationRequestGeneration += 1
    if !preservingNativeBoundaryRequest {
      boundaryRequestGeneration += 1
    }
    voiceRecordingGeneration += 1
    audioPlaybackGeneration += 1
    forwardRequestGeneration += 1
    readSyncRequestGeneration += 1
    discardPendingReadSync()
    readReceiptRefreshGeneration += 1
    topMessageRequestGeneration += 1
    teamTitleRequestGeneration += 1
    moreActionRefreshGeneration += 1
    userProfileRouteGeneration += 1
    teamLifecycleRequestGeneration += 1
    teamMemberDisplayRequestGeneration += 1
    teamMemberDisplayInfoByAccountId.removeAll()
    teamMemberDisplayInfoGenerationByAccountId.removeAll()
    outgoingTextPresentationByMessageId.removeAll()
    sendRequestIds.removeAll()
    handledSendFailureTipAttempts.removeAll()
    operationRequestIds.removeAll()
    replyResolutionRequestIds.removeAll()
    inputTranslationRequestId = nil
    inputTranslationBatch = nil
    translatedInputMentions.removeAll()
    voiceToTextRequestIds.removeAll()
    aiStreamActionRequestIds.removeAll()
    mentionSelectionGeneration += 1
    remoteTypingTimeoutTask?.cancel()
    remoteTypingTimeoutTask = nil
    lastSentTypingState = false
    unsubscribeP2POnlineStateIfNeeded()
    state.p2pPresence.isTyping = false
    state.p2pPresence.lastTypingTime = nil
    state.input.recording = ChatVoiceRecordingState()
    state.audioPlayback = ChatAudioPlaybackState()
    state.route.handlingState = .idle
    state.isLoadingOlder = false
    state.isLoadingNewer = false
    clearPendingPrependRestore()
    visibleTimelineAnchorId = nil
  }

  public func captureTimelinePositionBeforeRoute() {
    guard !hasRouteTimelineRestoreSnapshot else {
      return
    }
    cancelTimelineBottomPinning()
    captureTimelineRestoreAnchor(routeScoped: true)
  }

  public func restoreTimelinePositionAfterRouteReturnIfNeeded() {
    restoreTimelinePositionAfterReturnIfNeeded()
  }

  public func discardTimelinePositionRestore() {
    timelineRestoreAnchorId = nil
    timelineRestoreBottomMessageId = nil
    timelineRestoreWasAtBottom = true
    hasRouteTimelineRestoreSnapshot = false
    preservesPendingNewMessageIndicatorDuringRouteRestore = false
  }

  private func captureTimelineRestoreAnchor(routeScoped: Bool = false) {
    timelineRestoreAnchorId = firstExistingRowId(matching: [
      visibleTimelineAnchorId,
      currentFirstVisibleTimelineRowId(),
      lastStableVisibleTimelineAnchorId,
    ])
    timelineRestoreWasAtBottom = isTimelineBottomVisible && isLatestTimelineRowVisibleInCurrentSnapshot()
    timelineRestoreBottomMessageId = timelineRestoreWasAtBottom ? state.rows.last?.id : nil
    if routeScoped {
      hasRouteTimelineRestoreSnapshot = true
    }
  }

  private func currentFirstVisibleTimelineRowId() -> String? {
    state.rows.first { row in
      !messageIds(for: row).isDisjoint(with: visibleTimelineRowIds)
    }?.id
  }

  private func isLatestTimelineRowVisibleInCurrentSnapshot() -> Bool {
    guard let latestRow = state.rows.last else {
      return true
    }
    guard !visibleTimelineRowIds.isEmpty else {
      return isTimelineBottomVisible
    }
    return !messageIds(for: latestRow).isDisjoint(with: visibleTimelineRowIds)
  }

  private var hasPendingNewMessagesReceivedWhilePageHidden: Bool {
    receivedMessagesWhilePageHidden && !pendingNewMessageIds.isEmpty
  }

  private func restoreTimelinePositionAfterReturnIfNeeded() {
    preservesPendingNewMessageIndicatorDuringRouteRestore = false
    let shouldRestoreBottomPositionAfterHiddenMessages =
      hasPendingNewMessagesReceivedWhilePageHidden

    // When no messages arrived while the page was hidden, keep the usual
    // bottom-following behavior instead of restoring a previous position.
    if timelineRestoreWasAtBottom,
       !shouldRestoreBottomPositionAfterHiddenMessages {
      timelineRestoreAnchorId = nil
      timelineRestoreBottomMessageId = nil
      timelineRestoreWasAtBottom = true
      hasRouteTimelineRestoreSnapshot = false
      return
    }

    if shouldRestoreBottomPositionAfterHiddenMessages,
       let bottomMessageId = timelineRestoreBottomMessageId,
       indexOfRow(matching: bottomMessageId) != nil {
      timelineRestoreAnchorId = nil
      timelineRestoreBottomMessageId = nil
      timelineRestoreWasAtBottom = true
      hasRouteTimelineRestoreSnapshot = false
      cancelTimelineBottomPinning()
      preservesPendingNewMessageIndicatorDuringRouteRestore = true
      requestTimelineScroll(
        to: bottomMessageId,
        anchor: .bottom,
        animated: false,
        reason: .explicitAnchor
      )
      return
    }

    guard let anchorId = timelineRestoreAnchorId,
          indexOfRow(matching: anchorId) != nil else {
      timelineRestoreAnchorId = nil
      timelineRestoreBottomMessageId = nil
      timelineRestoreWasAtBottom = true
      hasRouteTimelineRestoreSnapshot = false
      return
    }
    if let target = state.timelineScrollTarget,
       !canReplaceScrollTargetForTimelineRestore(target) {
      timelineRestoreAnchorId = nil
      timelineRestoreBottomMessageId = nil
      timelineRestoreWasAtBottom = true
      hasRouteTimelineRestoreSnapshot = false
      return
    }
    timelineRestoreAnchorId = nil
    timelineRestoreBottomMessageId = nil
    timelineRestoreWasAtBottom = true
    hasRouteTimelineRestoreSnapshot = false
    cancelTimelineBottomPinning()
    requestTimelineScroll(to: anchorId, anchor: .top, animated: false, reason: .explicitAnchor)
  }

  private func canReplaceScrollTargetForTimelineRestore(_ target: ChatTimelineScrollTarget) -> Bool {
    switch target.reason {
    case .initialLatest, .jumpToLatest:
      return true
    case .normal:
      return target.anchor == .bottom
    case .explicitAnchor, .prependRestore:
      return false
    }
  }

  private func makeInputValidation(for text: String) -> ChatInputValidationState {
    ChatInputValidationState(
      characterCount: NECommonTextLimit.utf16Count(of: text),
      characterLimit: config.maxTextMessageLength
    )
  }

  private func refreshMoreActions() {
    state.input.moreActions = ChatMoreActionPolicy.actions(for: context, config: config)
  }

  private func refreshRobotAwareMoreActionsIfNeeded() {
    guard context.kind == .p2p,
          let sessionId = targetSessionId(),
          !sessionId.isEmpty else {
      return
    }

    moreActionRefreshGeneration += 1
    let generation = moreActionRefreshGeneration
    NEAIRobotManager.shared.checkIfRobot(sessionId) { [weak self] _ in
      Task { @MainActor in
        guard let self,
              self.didAppear,
              self.moreActionRefreshGeneration == generation else {
          return
        }
        self.refreshMoreActions()
      }
    }
  }

  private func refreshInitialP2PPresenceState() {
    guard isP2PTypingPresenceAvailable(),
          let accountId = targetSessionId() else {
      state.p2pPresence = P2PChatPresenceState()
      return
    }
    state.p2pPresence = P2PChatPresenceState(
      accountId: accountId,
      onlineState: isP2POnlineStatusAvailable()
        ? SubscribeRepo.shared.cachedSwiftUIOnlineState(accountId: accountId)
        : .unknown
    )
  }

  private func bindP2PPresenceListenersIfNeeded() {
    guard isP2PTypingPresenceAvailable(),
          let accountId = targetSessionId() else {
      return
    }

    state.p2pPresence.accountId = accountId
    state.p2pPresence.onlineState = SubscribeRepo.shared.cachedSwiftUIOnlineState(accountId: accountId)

    let typingToken = ChatRepo.shared.addP2PTypingEventListener(conversationId: context.conversationId) { [weak self] event in
      Task { @MainActor in
        self?.handleRemoteTypingEvent(event)
      }
    }
    listenerBinder.bind(typingToken)

    guard isP2POnlineStatusAvailable(accountId: accountId) else {
      return
    }

    let subscribeToken = SubscribeRepo.shared.addSubscribeEventListener(
      NESubscribeEvent(userStatusChanged: { [weak self] statuses in
        Task { @MainActor in
          self?.handleUserStatusChanged(statuses)
        }
      })
    )
    listenerBinder.bind(subscribeToken)

    subscribeP2POnlineState(accountId: accountId)
  }

  private func subscribeP2POnlineState(accountId: String? = nil) {
    let targetAccountId = accountId ?? targetSessionId()
    guard let targetAccountId, !targetAccountId.isEmpty,
          isP2POnlineStatusAvailable(accountId: targetAccountId) else {
      return
    }

    subscribedPresenceAccountId = targetAccountId
    SubscribeRepo.shared.subscribeSwiftUIOnlineState(accountId: targetAccountId) { [weak self] onlineState, error in
      Task { @MainActor in
        guard let self,
              self.subscribedPresenceAccountId == targetAccountId else {
          return
        }
        self.state.p2pPresence.accountId = targetAccountId
        self.state.p2pPresence.onlineState = onlineState
        if let error {
          self.state.clientRuntime.lastErrorMessage = error.localizedDescription
          NEChatSwiftUILogger.log("p2pPresence subscribe failed accountId=\(targetAccountId) error=\(error.localizedDescription)")
        }
      }
    }
  }

  private func unsubscribeP2POnlineStateIfNeeded() {
    guard let accountId = subscribedPresenceAccountId else {
      return
    }
    subscribedPresenceAccountId = nil
    SubscribeRepo.shared.unsubscribeSwiftUIOnlineState(accountId: accountId)
  }

  private func isP2PTypingPresenceAvailable() -> Bool {
    context.kind == .p2p && config.isP2PPresenceEnabled
  }

  private func isP2POnlineStatusAvailable(accountId: String? = nil) -> Bool {
    guard isP2PTypingPresenceAvailable(),
          IMKitConfigCenter.shared.enableOnlineStatus else {
      return false
    }
    let targetAccountId = accountId ?? targetSessionId()
    guard let targetAccountId, !targetAccountId.isEmpty else {
      return false
    }
    return !NEAIUserManager.shared.isAIUser(targetAccountId)
  }

  private func updateLocalTypingStateForInput(trimmedText: String) {
    guard isP2PTypingPresenceAvailable() else {
      return
    }
    let isTyping = !trimmedText.isEmpty
    sendLocalTypingStateIfNeeded(isTyping, force: isTyping)
  }

  private func sendLocalTypingStateIfNeeded(_ isTyping: Bool, force: Bool = false) {
    guard isP2PTypingPresenceAvailable() else {
      return
    }
    guard force || lastSentTypingState != isTyping else {
      return
    }
    lastSentTypingState = isTyping
    ChatRepo.shared.sendP2PTypingState(conversationId: context.conversationId, isTyping: isTyping) { _ in }
  }

  private func handleRemoteTypingEvent(_ event: NEChatTypingEvent) {
    guard isP2PTypingPresenceAvailable(),
          event.accountId == targetSessionId() else {
      return
    }
    state.p2pPresence.accountId = event.accountId
    state.p2pPresence.isTyping = event.isTyping
    state.p2pPresence.lastTypingTime = event.isTyping ? Date() : nil
    if event.isTyping {
      scheduleRemoteTypingTimeout()
    } else {
      remoteTypingTimeoutTask?.cancel()
      remoteTypingTimeoutTask = nil
    }
  }

  private func handleUserStatusChanged(_ statuses: [V2NIMUserStatus]) {
    guard let accountId = targetSessionId(),
          isP2POnlineStatusAvailable(accountId: accountId),
          let status = statuses.first(where: { $0.accountId == accountId }) else {
      return
    }
    state.p2pPresence.accountId = accountId
    state.p2pPresence.onlineState = NESwiftUIUserOnlineState(status: status)
  }

  private func scheduleRemoteTypingTimeout() {
    remoteTypingTimeoutTask?.cancel()
    remoteTypingTimeoutTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard !Task.isCancelled else {
        return
      }
      await MainActor.run {
        self?.endRemoteTypingByTimeout()
      }
    }
  }

  private func endRemoteTypingByTimeout() {
    state.p2pPresence.isTyping = false
    state.p2pPresence.lastTypingTime = nil
    remoteTypingTimeoutTask = nil
  }

  private func targetSessionId() -> String? {
    if let sessionId = context.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !sessionId.isEmpty {
      return sessionId
    }
    return V2NIMConversationIdUtil.conversationTargetId(context.conversationId)
  }

  private func mentionSelectionRequest(trigger: ChatMentionSelectionTrigger) -> ChatMentionSelectionRequest? {
    switch context.kind {
    case .team:
      return ChatMentionSelectionRequest(
        context: context,
        source: .teamMembers,
        allowsAllMembers: false,
        trigger: trigger
      )
    case .p2p:
      guard IMKitConfigCenter.shared.enableAIUser,
            let sessionId = targetSessionId(),
            !NEAIUserManager.shared.isAIUser(sessionId) else {
        return nil
      }
      return ChatMentionSelectionRequest(
        context: context,
        source: .aiUsers,
        allowsAllMembers: false,
        trigger: trigger
      )
    case .topic, .botSubSession, .history:
      return nil
    }
  }

  private func routeToUserProfile(from row: MessageRowState) {
    let currentAccountId = currentAccountProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let isSelf = isSelfMessage(row, currentAccountId: currentAccountId)
    let rowSenderId = row.senderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let accountId = isSelf
      ? (currentAccountId.isEmpty ? rowSenderId : currentAccountId)
      : rowSenderId
    guard !accountId.isEmpty else {
      return
    }

    let request = ChatUserProfileRequest(
      accountId: accountId,
      displayName: row.senderName,
      avatarURL: row.avatarURL,
      source: isSelf ? .selfAvatar : .contactAvatar,
      isRobot: false,
      message: row,
      context: context
    )

    if !isSelf, context.kind == .p2p {
      userProfileRouteGeneration += 1
      let generation = userProfileRouteGeneration
      state.route.handlingState = .handling
      NEAIRobotManager.shared.checkIfRobot(accountId) { [weak self] isRobot in
        Task { @MainActor in
          guard let self,
                self.userProfileRouteGeneration == generation,
                self.row(id: row.id) != nil else {
            return
          }
          var robotAwareRequest = request
          robotAwareRequest.isRobot = isRobot
          self.openUserProfile(request: robotAwareRequest)
        }
      }
    } else {
      openUserProfile(request: request)
    }
  }

  private func openUserProfile(request: ChatUserProfileRequest) {
    let fallbackRoute = NEChatSwiftUIRoute.userProfile(request)
    guard let router = config.userProfileRouter else {
      setPageVisible(false)
      state.route = ChatRouteState(currentRoute: fallbackRoute, handlingState: .queued)
      return
    }

    userProfileRouteGeneration += 1
    let generation = userProfileRouteGeneration
    state.route.handlingState = .handling
    router.openUserProfile(request) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.userProfileRouteGeneration == generation else {
          return
        }
        self.handleUserProfileRouteResult(result, fallbackRoute: fallbackRoute)
      }
    }
  }

  private func handleUserProfileRouteResult(_ result: Result<ChatUserProfileRouteResult, Error>,
                                            fallbackRoute: NEChatSwiftUIRoute) {
    switch result {
    case .success(let routeResult):
      switch routeResult {
      case let .route(route):
        setPageVisible(false)
        state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      case let .toast(toast):
        state.route.handlingState = .handled
        state.toast = toast
      case .handled:
        state.route.handlingState = .handled
      }
    case .failure(let error):
      setPageVisible(false)
      state.route = ChatRouteState(currentRoute: fallbackRoute, handlingState: .failed(boundaryErrorState(for: error)))
      state.toast = boundaryFailureToast(for: error)
    }
  }

  private func isSelfMessage(_ row: MessageRowState,
                             currentAccountId: String) -> Bool {
    if row.direction == .outgoing {
      return true
    }
    guard let senderId = row.senderId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !senderId.isEmpty else {
      return false
    }
    if !currentAccountId.isEmpty, senderId == currentAccountId {
      return true
    }
    return IMKitClient.instance.isMe(senderId)
  }

  private func handleMentionSelectionResult(_ result: Result<ChatMentionSelectionResult, Error>,
                                            trigger: ChatMentionSelectionTrigger) {
    switch result {
    case .success(let selection):
      let targets = selection.targets.filter { !$0.mentionAccountId.isEmpty }
      guard !targets.isEmpty else {
        return
      }
      for (index, target) in targets.enumerated() {
        insertMention(target, replacingTrailingAt: trigger == .inputAt && index == 0)
      }
    case .failure(let error):
      state.toast = boundaryFailureToast(for: error)
    }
  }

  private func handleNativeBoundaryResult(_ result: Result<ChatNativeBoundaryResult, Error>,
                                          fallbackAction: ChatMoreActionState) {
    state.input.mode = .more
    switch result {
    case .success(let boundaryResult):
      switch boundaryResult {
      case let .send(payload):
        state.route.handlingState = .handled
        sendPayload(payload, requiresInputEnabled: false)
      case let .sendMultiple(payloads):
        state.route.handlingState = .handled
        sendPayloads(payloads, requiresInputEnabled: false)
      case let .route(route):
        state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      case let .toast(toast):
        state.route.handlingState = .handled
        state.toast = toast
      case .none:
        state.route.handlingState = .handled
      }
    case .failure(let error):
      state.route = ChatRouteState(
        currentRoute: .moreAction(fallbackAction.id, context),
        handlingState: .failed(boundaryErrorState(for: error))
      )
      state.toast = boundaryFailureToast(for: error)
    }
  }

  private func beginNativeBoundaryPresentation() {
    nativeBoundaryPresentationLifecycle = NativeBoundaryPresentationLifecycle()
    captureTimelinePositionBeforeRoute()
    setPageVisible(false)
  }

  private func finishNativeBoundaryPresentation(keepsTimelineHidden: Bool) {
    guard !keepsTimelineHidden else {
      nativeBoundaryPresentationLifecycle = nil
      return
    }
    restoreTimelinePositionAfterRouteReturnIfNeeded()
    guard var lifecycle = nativeBoundaryPresentationLifecycle else {
      return
    }
    lifecycle.didComplete = true
    nativeBoundaryPresentationLifecycle = lifecycle
    if lifecycle.didReturn {
      completeNativeBoundaryReturn(id: lifecycle.id, reactivatesPage: true)
      return
    }

    let lifecycleId = lifecycle.id
    DispatchQueue.main.asyncAfter(deadline: .now() + nativeBoundaryReturnFallbackDelay) { [weak self] in
      guard let self,
            let lifecycle = self.nativeBoundaryPresentationLifecycle,
            lifecycle.id == lifecycleId,
            lifecycle.didComplete,
            !lifecycle.didDisappear else {
        return
      }
      // Confirmation dialogs do not make ChatView disappear. Reactivate only
      // after their dismissal transition settles and this lifecycle is current.
      self.completeNativeBoundaryReturn(id: lifecycleId, reactivatesPage: true)
    }
  }

  private func nativeBoundaryPageDidDisappearIfNeeded() {
    guard var lifecycle = nativeBoundaryPresentationLifecycle else {
      return
    }
    lifecycle.didDisappear = true
    nativeBoundaryPresentationLifecycle = lifecycle
  }

  private func nativeBoundaryPageDidAppearIfNeeded() {
    guard var lifecycle = nativeBoundaryPresentationLifecycle,
          lifecycle.didDisappear else {
      return
    }
    lifecycle.didReturn = true
    nativeBoundaryPresentationLifecycle = lifecycle
    guard lifecycle.didComplete else {
      return
    }
    completeNativeBoundaryReturn(id: lifecycle.id, reactivatesPage: false)
  }

  private func completeNativeBoundaryReturn(id: UUID,
                                            reactivatesPage: Bool) {
    guard nativeBoundaryPresentationLifecycle?.id == id else {
      return
    }
    nativeBoundaryPresentationLifecycle = nil
    if reactivatesPage {
      setPageVisible(true)
    }
  }

  private func nativeBoundaryResultKeepsTimelineHidden(
    _ result: Result<ChatNativeBoundaryResult, Error>
  ) -> Bool {
    switch result {
    case .success(.route), .failure:
      return true
    default:
      return false
    }
  }

  private func toast(for disposition: ChatNativeBoundaryDisposition,
                     action: ChatMoreActionState) -> ChatToastState {
    switch disposition {
    case .internalRoute:
      return ChatToastState(message: action.title, style: .info)
    case .appBoundaryRequired:
      return ChatToastState(
        message: String(format: NEChatUIKitSwiftUIBundle.localized("chat_more_action_requires_boundary_format", value: "%@ requires a SwiftUI native boundary handler."), action.title),
        style: .info
      )
    case .deferred:
      return ChatToastState(
        message: String(format: NEChatUIKitSwiftUIBundle.localized("chat_more_action_deferred_format", value: "%@ is deferred in the first SwiftUI phase."), action.title),
        style: .warning
      )
    }
  }

  private func handleInteractionBoundaryResult(_ result: Result<ChatNativeBoundaryResult, Error>,
                                               fallbackRoute: NEChatSwiftUIRoute,
                                               messageId: String?) {
    if let messageId,
       row(id: messageId) == nil {
      return
    }

    switch result {
    case .success(let boundaryResult):
      switch boundaryResult {
      case let .send(payload):
        sendPayload(payload)
      case let .sendMultiple(payloads):
        sendPayloads(payloads)
      case let .route(route):
        state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      case let .toast(toast):
        state.toast = toast
      case .none:
        break
      }
    case .failure(let error):
      state.route = ChatRouteState(currentRoute: fallbackRoute, handlingState: .failed(boundaryErrorState(for: error)))
      state.toast = boundaryFailureToast(for: error)
    }
  }

  private func shouldAcceptURLInteractionResult(source: ChatURLInteractionSource,
                                                message: MessageRowState?,
                                                preview: ChatTextPreviewState?) -> Bool {
    if source == .multiForwardPreview {
      if case .multiForwardPreview = state.route.currentRoute {
        return true
      }
      return false
    }

    if source == .textPreview {
      switch state.route.currentRoute {
      case .pinMessages, .collectionMessages, .textPreview:
        return true
      default:
        break
      }
    }

    if let message {
      return row(id: message.id) != nil || preview != nil
    }

    guard let preview else {
      return true
    }
    return state.route.currentRoute == .textPreview(preview)
  }

  private func handleURLInteractionResult(_ result: Result<ChatNativeBoundaryResult, Error>) {
    switch result {
    case .success(let boundaryResult):
      switch boundaryResult {
      case let .route(route):
        state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      case let .toast(toast):
        state.toast = toast
      case .send, .sendMultiple:
        state.toast = ChatToastState(
          message: NEChatUIKitSwiftUIBundle.localized("chat_url_open_ignores_send_result", value: "Link opening does not support sending messages."),
          style: .warning
        )
      case .none:
        break
      }
    case .failure(let error):
      state.toast = NEChatErrorMessageMapper.toast(
        for: error,
        fallbackKey: "chat_url_open_failed",
        fallbackValue: "Open link failed"
      )
    }
  }

  private func openMediaPreview(row: MessageRowState,
                                media: MessageMediaState,
                                kind: ChatMediaPreviewKind,
                                requiresLoadedRow: Bool = true) {
    if kind == .video,
       media.playableLocalPath == nil,
       let url = media.url {
      downloadMedia(row: row, media: media, kind: kind, url: url, requiresLoadedRow: requiresLoadedRow)
      return
    }

    let allMediaItems = state.rows.compactMap { row -> ChatMediaItem? in
      let media: MessageMediaState?
      let itemKind: ChatMediaPreviewKind
      let previewTitle = ChatMessageMapper.previewText(for: row.content)
      switch row.content {
      case let .image(m):
        media = m
        itemKind = .image
      case let .video(m):
        media = m
        itemKind = .video
      default:
        return nil
      }
      guard itemKind == kind else { return nil }
      guard let media else { return nil }
      return ChatMediaItem(id: row.id, media: media, kind: itemKind, title: previewTitle)
    }

    let preview = ChatMediaPreviewState(
      id: row.id,
      kind: kind,
      media: media,
      title: ChatMessageMapper.previewText(for: row.content),
      mediaItems: allMediaItems
    )
    let route = NEChatSwiftUIRoute.mediaPreview(preview)

    guard let handler = config.mediaPreviewHandler else {
      state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      return
    }

    let request = ChatMediaPreviewRequest(preview: preview, message: row, context: context)
    beginNativeBoundaryPresentation()
    let generation = nextBoundaryRequestGeneration()
    handler.handleMediaPreview(request) { [weak self] result in
      Task { @MainActor in
        guard let self = self,
              self.boundaryRequestGeneration == generation else {
          return
        }
        self.finishNativeBoundaryPresentation(
          keepsTimelineHidden: self.nativeBoundaryResultKeepsTimelineHidden(result)
        )
        guard !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }
        self.handleInteractionBoundaryResult(
          result,
          fallbackRoute: route,
          messageId: requiresLoadedRow ? row.id : nil
        )
      }
    }
  }

  private func openFilePreview(row: MessageRowState,
                               file: MessageFileState,
                               requiresLoadedRow: Bool = true) {
    if file.existingLocalPath == nil,
       let url = file.url {
      downloadFile(row: row, file: file, url: url, requiresLoadedRow: requiresLoadedRow)
      return
    }

    if let media = file.imageMediaState {
      openMediaPreview(row: row, media: media, kind: .image, requiresLoadedRow: requiresLoadedRow)
      return
    }

    if let media = file.videoMediaState {
      openMediaPreview(row: row, media: media, kind: .video, requiresLoadedRow: requiresLoadedRow)
      return
    }

    let preview = ChatFilePreviewState(id: row.id, file: file)
    let route = NEChatSwiftUIRoute.filePreview(preview)

    guard let handler = config.fileInteractionHandler else {
      state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      return
    }

    let request = ChatFileInteractionRequest(preview: preview, message: row, context: context)
    beginNativeBoundaryPresentation()
    let generation = nextBoundaryRequestGeneration()
    handler.handleFileInteraction(request) { [weak self] result in
      Task { @MainActor in
        guard let self = self,
              self.boundaryRequestGeneration == generation else {
          return
        }
        self.finishNativeBoundaryPresentation(
          keepsTimelineHidden: self.nativeBoundaryResultKeepsTimelineHidden(result)
        )
        guard !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }
        self.handleInteractionBoundaryResult(
          result,
          fallbackRoute: route,
          messageId: requiresLoadedRow ? row.id : nil
        )
      }
    }
  }

  private func downloadMedia(row: MessageRowState,
                             media: MessageMediaState,
                             kind: ChatMediaPreviewKind,
                             url: URL,
                             requiresLoadedRow: Bool) {
    guard let filePath = mediaDownloadPath(for: row, media: media, kind: kind, url: url) else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_file_unavailable", value: "File unavailable"),
        style: .warning
      )
      return
    }

    let generation = beginMediaDownload(rowId: row.id)
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        self?.updateDeliveryState(for: row.id, deliveryState: .pending(progress: Double(progress) / 100.0))
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.finishMediaDownloadIfCurrent(rowId: row.id, generation: generation),
              !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }
        self.updateDeliveryState(for: row.id, deliveryState: .sent)
        if let error {
          self.state.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_video_unavailable",
            fallbackValue: "Video unavailable"
          )
          return
        }

        var downloaded = media
        guard let resolvedLocalPath = self.resolvedDownloadedPath(localPath, fallback: filePath) else {
          self.state.toast = ChatToastState(
            message: NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable"),
            style: .warning
          )
          return
        }
        downloaded.localPath = resolvedLocalPath
        self.updateMediaContent(for: row.id, media: downloaded, kind: kind)
      }
    }
  }

  private func downloadFile(row: MessageRowState,
                            file: MessageFileState,
                            url: URL,
                            requiresLoadedRow: Bool) {
    guard let filePath = fileDownloadPath(for: row, file: file, url: url) else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_file_unavailable", value: "File unavailable"),
        style: .warning
      )
      return
    }

    let generation = beginMediaDownload(rowId: row.id)
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        self?.updateDeliveryState(for: row.id, deliveryState: .pending(progress: Double(progress) / 100.0))
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.finishMediaDownloadIfCurrent(rowId: row.id, generation: generation),
              !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }
        self.updateDeliveryState(for: row.id, deliveryState: .sent)
        if let error {
          self.state.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_file_unavailable",
            fallbackValue: "File unavailable"
          )
          return
        }

        var downloaded = file
        let resolvedLocalPath = self.resolvedDownloadedPath(localPath, fallback: filePath) ?? filePath
        downloaded.localPath = resolvedLocalPath
        downloaded.fileExtension = self.downloadedFileExtension(file: downloaded, localPath: resolvedLocalPath, url: url)
        self.updateContent(for: row.id, content: .file(downloaded))
      }
    }
  }

  private func openLocation(row: MessageRowState,
                            location: MessageLocationState,
                            requiresLoadedRow: Bool = true) {
    let route = NEChatSwiftUIRoute.locationDetail(location)

    guard let handler = config.locationInteractionHandler else {
      state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
      return
    }

    let request = ChatLocationInteractionRequest(location: location, message: row, context: context)
    let generation = nextBoundaryRequestGeneration()
    handler.handleLocationInteraction(request) { [weak self] result in
      Task { @MainActor in
        guard let self = self,
              self.boundaryRequestGeneration == generation,
              !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }
        self.handleInteractionBoundaryResult(
          result,
          fallbackRoute: route,
          messageId: requiresLoadedRow ? row.id : nil
        )
      }
    }
  }

  private func openCall(row: MessageRowState,
                        call: MessageCallState,
                        requiresLoadedRow: Bool = true) {
    let fallbackRoute = NEChatSwiftUIRoute.moreAction(.rtc, context)
    guard let handler = config.callInteractionHandler else {
      state.route = ChatRouteState(currentRoute: fallbackRoute, handlingState: .queued)
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_call_requires_boundary", value: "Call should be handled by the app host."),
        style: .warning
      )
      return
    }

    let request = ChatCallInteractionRequest(call: call, message: row, context: context)
    let generation = nextBoundaryRequestGeneration()
    state.route.handlingState = .handling
    handler.handleCallInteraction(request) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.boundaryRequestGeneration == generation,
              !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }
        self.handleInteractionBoundaryResult(
          result,
          fallbackRoute: fallbackRoute,
          messageId: requiresLoadedRow ? row.id : nil
        )
      }
    }
  }

  private func toggleAudioPlayback(row: MessageRowState,
                                   audio: MessageAudioState,
                                   requiresLoadedRow: Bool = true) {
    guard let handler = config.audioPlaybackHandler else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_audio_playback_requires_service", value: "Audio playback service is not connected yet"),
        style: .info
      )
      return
    }

    let shouldStop = state.audioPlayback.messageId == row.id &&
      (state.audioPlayback.phase == .playing || audio.isPlaying)
    audioPlaybackGeneration += 1
    let generation = audioPlaybackGeneration

    let completion: (Result<ChatAudioPlaybackResult, Error>) -> Void = { [weak self] result in
      Task { @MainActor in
        self?.handleAudioPlaybackResult(
          result,
          messageId: row.id,
          generation: generation,
          requiresLoadedRow: requiresLoadedRow
        )
      }
    }

    if shouldStop {
      state.audioPlayback = ChatAudioPlaybackState()
      updateAudioPlayingState(messageId: row.id, isPlaying: false)
      let request = ChatAudioPlaybackRequest(messageId: row.id, audio: audio, context: context)
      handler.stopAudio(request, completion: completion)
      return
    }

    let playableAudio = audioWithUIKitCompatibleLocalPath(for: row, audio: audio)
    guard playableAudio.existingLocalPath != nil else {
      if let url = playableAudio.url {
        downloadAudioAndPlay(
          row: row,
          audio: playableAudio,
          url: url,
          generation: generation,
          requiresLoadedRow: requiresLoadedRow,
          handler: handler
        )
      } else {
        handleAudioPlaybackResult(
          .failure(ChatAudioPlaybackError.unavailable),
          messageId: row.id,
          generation: generation,
          requiresLoadedRow: requiresLoadedRow
        )
      }
      return
    }

    let request = ChatAudioPlaybackRequest(messageId: row.id, audio: playableAudio, context: context)
    state.audioPlayback = ChatAudioPlaybackState(messageId: row.id, phase: .playing)
    updateAudioPlayingState(messageId: row.id, isPlaying: true)
    handler.playAudio(request, completion: completion)
  }

  private func handleAudioPlaybackResult(_ result: Result<ChatAudioPlaybackResult, Error>,
                                         messageId: String,
                                         generation: Int,
                                         requiresLoadedRow: Bool = true) {
    guard audioPlaybackGeneration == generation,
          !requiresLoadedRow || row(id: messageId) != nil else {
      return
    }

    switch result {
    case .success(.playing):
      state.audioPlayback = ChatAudioPlaybackState(messageId: messageId, phase: .playing)
      updateAudioPlayingState(messageId: messageId, isPlaying: true)
    case .success(.stopped):
      state.audioPlayback = ChatAudioPlaybackState()
      updateAudioPlayingState(messageId: messageId, isPlaying: false)
    case .failure(let error):
      state.audioPlayback = ChatAudioPlaybackState()
      updateAudioPlayingState(messageId: messageId, isPlaying: false)
      state.toast = ChatToastState(message: audioPlaybackFailureMessage(for: error), style: .error)
    }
  }

  private func loadInitialIfNeeded() {
    if state.rows.isEmpty {
      clearPendingPrependRestore()
      visibleTimelineAnchorId = nil
      if let anchorMessage = context.anchorMessage {
        let anchorRow = messageRow(from: anchorMessage)
        focusMessage(anchorRow, anchorMessage: anchorMessage)
        return
      }
      loadOlderMessages()
    } else {
      state.phase = .loaded
    }
  }

  private func handleReceivedMessages(_ messages: [V2NIMMessage]) {
    dismissOperations()
    let currentMessages = messages.filter { message in
      isCurrentMessage(message)
    }
    guard !currentMessages.isEmpty else {
      return
    }
    if !isPageVisible {
      receivedMessagesWhilePageHidden = true
    }

    cacheMessageContext(currentMessages)
    let rows = currentMessages
      .map { messageRow(from: $0) }
    if isHistoryContextActive {
      appendPendingHistoryNewMessages(currentMessages)
      handleTeamInfoNotifications(in: currentMessages)
      handleTeamLifecycleNotifications(in: currentMessages)
      appendNewMessageIndicator(for: rows, requiresLatestReload: true)
      return
    }

    let shouldStickToBottom = shouldStickToBottom(for: rows)
    appendRows(rows)
    handleTeamInfoNotifications(in: currentMessages)
    handleTeamLifecycleNotifications(in: currentMessages)
    if shouldStickToBottom, let lastId = rows.last?.id {
      clearPendingNewMessageIds()
      state.newMessageIndicator = nil
      // Match UIKit's jumpDownMessage path for an incoming message on the
      // active chat page. A normal target waits for settled SwiftUI layout and
      // can miss the first appended row; jumpToLatest scrolls to the stable
      // bottom anchor immediately and retries after layout.
      beginTimelineBottomPinning()
      requestTimelineScroll(
        to: lastId,
        anchor: .bottom,
        animated: false,
        reason: .jumpToLatest
      )
    } else {
      appendNewMessageIndicator(for: rows)
    }
  }

  private func row(id: String) -> MessageRowState? {
    state.rows.first { $0.id == id || $0.serverId == id }
  }

  private func indexOfRow(matching id: String) -> Int? {
    state.rows.firstIndex { $0.id == id || $0.serverId == id }
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

  private func pruneMessageContext() {
    guard !state.rows.isEmpty else {
      messageContextById.removeAll()
      outgoingTextPresentationByMessageId.removeAll()
      return
    }

    var validIds = Set<String>()
    for row in state.rows {
      validIds.formUnion(messageIds(for: row))
    }
    messageContextById = messageContextById.filter { validIds.contains($0.key) }
    outgoingTextPresentationByMessageId = outgoingTextPresentationByMessageId.filter {
      validIds.contains($0.key)
    }
  }

  private func loadedRowId(matching row: MessageRowState) -> String? {
    loadedRowId(matching: row, in: state.rows)
  }

  private func guardRuntimeAllowsNetworkOperation(showToast: Bool = true) -> Bool {
    guard state.clientRuntime.shouldShowNetworkWarning == false else {
      if showToast {
        state.toast = ChatToastState(
          message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
          style: .warning
        )
      }
      return false
    }

    return true
  }

  private func deleteMessage(id: String) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let operationKey = operationRequestKey("delete", ids: [id])
    let requestId = beginOperationRequest(key: operationKey)
    operationPerformer.deleteMessage(id: id) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId, existingMessageIds: [id]) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success:
          self.removeRows(ids: [id])
        case .failure(let error):
          if let toast = self.deleteFailureToast(for: error) {
            self.state.toast = toast
          }
        }
      }
    }
  }

  private func copyMessage(_ row: MessageRowState, selectedText: String? = nil) {
    let text = selectedText ?? copyText(for: row.content)
    guard !text.isEmpty else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_copy_empty", value: "Nothing to copy"),
        style: .warning
      )
      return
    }

    guard let clipboardHandler = config.clipboardHandler else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_copy_requires_boundary", value: "Copy requires a SwiftUI clipboard handler."),
        style: .info
      )
      return
    }

    let operationKey = operationRequestKey("copy", ids: [row.id])
    let requestId = beginOperationRequest(key: operationKey)
    let request = ChatClipboardRequest(text: text, message: row, context: context)
    clipboardHandler.copyText(request) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId, existingMessageIds: [row.id]) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case let .success(boundaryResult):
          switch boundaryResult {
          case let .toast(toast):
            self.state.toast = toast
          case let .route(route):
            self.state.route = ChatRouteState(currentRoute: route, handlingState: .queued)
          case .send, .sendMultiple:
            self.state.toast = ChatToastState(
              message: NEChatUIKitSwiftUIBundle.localized("chat_copy_ignores_send_result", value: "Copy does not support sending messages."),
              style: .warning
            )
          case .none:
            self.state.toast = ChatToastState(
              message: NEChatUIKitSwiftUIBundle.localized("chat_copied", value: "Copied"),
              style: .success
            )
          }
        case let .failure(error):
          self.state.toast = NEChatErrorMessageMapper.toast(
            for: error,
            fallbackKey: "chat_copy_failed",
            fallbackValue: "Copy failed"
          )
        }
      }
    }
  }

  private func copyText(for content: MessageContentState) -> String {
    NEChatUtilityMessageOperationRules.copyableText(content) ??
      ChatMessageMapper.previewText(for: content)
  }

  private func isSelectableMessageText(_ content: MessageContentState) -> Bool {
    switch content {
    case .text, .richText:
      return true
    case let .aiStream(_, isFinished, _):
      return isFinished
    case let .reply(_, boxed):
      return isSelectableMessageText(boxed.value)
    default:
      return false
    }
  }

  private func deleteSelectedMessages(ids: [String]) {
    guard !ids.isEmpty else {
      return
    }
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }

    let group = DispatchGroup()
    let errorLock = NSLock()
    var firstError: Error?
    let operationKey = operationRequestKey("deleteSelected", ids: ids)
    let requestId = beginOperationRequest(key: operationKey)

    for id in ids {
      group.enter()
      operationPerformer.deleteMessage(id: id) { result in
        if case let .failure(error) = result {
          errorLock.lock()
          if firstError == nil {
            firstError = error
          }
          errorLock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId),
              ids.contains(where: { self.row(id: $0) != nil }) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        if let firstError {
          if let toast = self.deleteFailureToast(for: firstError) {
            self.state.toast = toast
          }
        } else {
          let timelineAnchorId = self.firstExistingRowId(matching: [
            self.currentFirstVisibleTimelineRowId(),
            self.visibleTimelineAnchorId,
            self.lastStableVisibleTimelineAnchorId,
          ])
          self.removeRows(ids: Set(ids))
          self.clearSelection()
          // Deleting a multi-selection must retain the reader's position.
          // UIKit reloads around the visible row rather than jumping to the
          // newest message after the action bar is dismissed.
          if let timelineAnchorId = self.firstExistingRowId(matching: [timelineAnchorId]) {
            self.cancelTimelineBottomPinning()
            self.requestTimelineScroll(
              to: timelineAnchorId,
              anchor: .top,
              animated: false,
              reason: .explicitAnchor
            )
          }
        }
      }
    }
  }

  private func deleteFailureToast(for error: Error) -> ChatToastState? {
    if let toast = NEChatErrorMessageMapper.teamMuteToast(for: error) {
      return toast
    }
    let code = (error as NSError).code
    switch code {
    case protocolSendFailed:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
    case protocolTimeout:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
    case fileUploadFailed:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("file_upload_failed", value: "File upload failed"),
        style: .error
      )
    case aiMessagesNotExist:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found"),
        style: .warning
      )
    case teamNormalMemberChatBanned, teamMemberChatBanned:
      return NEChatErrorMessageMapper.toast(for: error, style: .warning)
    default:
      return nil
    }
  }

  private func revokeMessage(id: String) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }

    let targetRow = row(id: id)
    let wasPinned = targetRow?.isPinned == true
    if let targetRow,
       isRevokeTimeExpired(targetRow) {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("ravokable_time_expired", value: "Recall time expired"),
        style: .warning
      )
      return
    }

    let operationKey = operationRequestKey("revoke", ids: [id])
    let requestId = beginOperationRequest(key: operationKey)
    let completion: (Result<ChatOperationResult, Error>) -> Void = { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId, existingMessageIds: [id]) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success(let operationResult):
          self.applyRevokeResult(id: id, row: operationResult.row)
          if wasPinned {
            self.unpinRevokedMessageIfNeeded(id: id)
          }
        case .failure(let error):
          self.state.toast = self.revokeFailureToast(for: error)
        }
      }
    }
    if let targetRow,
       let message = messageContextMessage(for: targetRow) {
      operationPerformer.revokeMessage(message: message, completion: completion)
    } else {
      operationPerformer.revokeMessage(id: id, completion: completion)
    }
  }

  private func revokeFailureToast(for error: Error) -> ChatToastState {
    let code = (error as NSError).code
    switch code {
    case protocolSendFailed, protocolTimeout:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
    case ravokableTimeExpired:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("ravokable_time_expired", value: "Recall time expired"),
        style: .warning
      )
    default:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("ravoked_failed", value: "Message not recalled"),
        style: .error
      )
    }
  }

  private func isRevokeTimeExpired(_ row: MessageRowState) -> Bool {
    guard let timestamp = row.timestamp, timestamp > 0 else {
      return false
    }
    return Int(Date().timeIntervalSince1970 - timestamp) >= config.revokeTimeGapMinutes * 60
  }

  private func unpinRevokedMessageIfNeeded(id: String) {
    operationPerformer.unpinMessage(id: id) { _ in }
  }

  private func pinMessage(row: MessageRowState, isPinned: Bool) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let id = row.id
    let operationKey = operationRequestKey("pin", ids: [id])
    let requestId = beginOperationRequest(key: operationKey)
    let completion: (Result<ChatOperationResult, Error>) -> Void = { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId, existingMessageIds: [id]) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success(let operationResult):
          self.updatePinState(
            for: id,
            isPinned: !isPinned,
            operatorId: isPinned ? nil : self.currentAccountProvider()
          )
          self.refreshTopMessage()
          if let message = operationResult.message {
            self.state.toast = ChatToastState(message: message, style: .success)
          }
        case .failure(let error):
          if let toast = self.pinFailureToast(for: error, isPinned: isPinned) {
            self.state.toast = toast
          }
        }
      }
    }
    if let message = messageContextMessage(for: row) {
      operationPerformer.pinMessage(message: message, isPinned: isPinned, completion: completion)
    } else {
      operationPerformer.pinMessage(id: id, isPinned: isPinned, completion: completion)
    }
  }

  private func loadTeamTopMessageIfNeeded(showFailureToast: Bool = false) {
    guard context.kind == .team,
          IMKitConfigCenter.shared.enableTopMessage else {
      clearTeamTopMessage()
      return
    }

    topMessageRequestGeneration += 1
    let generation = topMessageRequestGeneration
    operationPerformer.loadTopMessage(context: context) { [weak self] result in
      Task { @MainActor in
        guard let self, self.topMessageRequestGeneration == generation else {
          return
        }
        switch result {
        case .success(let operationResult):
          self.applyTeamTopMessage(row: operationResult.row, canClose: operationResult.canCloseTopMessage ?? false)
        case .failure(let error):
          if showFailureToast {
            self.state.toast = self.topMessageFailureToast(for: error, isUntop: false)
          }
        }
      }
    }
  }

  private func topMessage(id: String) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let operationKey = operationRequestKey("top", ids: [id])
    let requestId = beginOperationRequest(key: operationKey)
    operationPerformer.topMessage(id: id, context: context) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId, existingMessageIds: [id]) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success(let operationResult):
          self.applyTeamTopMessage(row: operationResult.row, canClose: operationResult.canCloseTopMessage ?? true)
        case .failure(let error):
          self.state.toast = self.topMessageFailureToast(for: error, isUntop: false)
        }
      }
    }
  }

  private func untopMessage(id: String?) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let operationKey = operationRequestKey("untop", ids: [id].compactMap { $0 })
    let requestId = beginOperationRequest(key: operationKey)
    operationPerformer.untopMessage(id: id, context: context) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey,
                                             requestId: requestId,
                                             existingMessageIds: []) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success:
          self.clearTeamTopMessage()
        case .failure(let error):
          self.state.toast = self.topMessageFailureToast(for: error, isUntop: true)
        }
      }
    }
  }

  private func topMessageFailureToast(for error: Error, isUntop: Bool) -> ChatToastState {
    let code = (error as NSError).code
    switch code {
    case protocolSendFailed, protocolTimeout:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
    case noPermissionOperationCode:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("no_permission_tip", value: "No Permission"),
        style: .warning
      )
    case failedOperation where isUntop:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed"),
        style: .warning
      )
    default:
      return NEChatErrorMessageMapper.toast(for: error)
    }
  }

  private func pinFailureToast(for error: Error, isPinned: Bool) -> ChatToastState? {
    let code = (error as NSError).code
    switch code {
    case pinAlreadyExist where isPinned == false,
         pinNotExist where isPinned:
      return nil
    case protocolSendFailed, protocolTimeout:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
    case pinLimitExceeded where isPinned == false:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("pin_limit_exceeded", value: "Number of pins reaches the limit"),
        style: .warning
      )
    default:
      return NEChatErrorMessageMapper.toast(for: error)
    }
  }

  private func collectMessage(_ row: MessageRowState) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let id = row.id
    let operationKey = operationRequestKey("collect", ids: [id])
    let requestId = beginOperationRequest(key: operationKey)
    operationPerformer.collectMessage(id: id, conversationName: title, displayRow: row) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId, existingMessageIds: [id]) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success(let operationResult):
          self.state.toast = ChatToastState(
            message: operationResult.message ?? NEChatUIKitSwiftUIBundle.localized("chat_collected", value: "Collected"),
            style: .success
          )
        case .failure(let error):
          self.state.toast = self.collectFailureToast(for: error)
        }
      }
    }
  }

  private func collectFailureToast(for error: Error) -> ChatToastState {
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

  private func forwardMessages(messageIds: [String],
                               selection: ChatForwardSelectionResult,
                               merged: Bool,
                               depth: Int = 0,
                               resultToastHandler: ((ChatToastState) -> Void)? = nil) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let forwardsToCurrentConversation = selection.targets.contains {
      $0.conversationId == context.conversationId
    }
    let operationKey = operationRequestKey("forward", ids: messageIds + selection.targets.map(\.conversationId))
    let requestId = beginOperationRequest(key: operationKey)
    operationPerformer.forwardMessages(ids: messageIds,
                                       targets: selection.targets,
                                       comment: selection.comment,
                                       merged: merged,
                                       sourceConversationId: context.conversationId,
                                       sourceConversationName: forwardSourceConversationName,
                                       depth: depth) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success(let operationResult):
          self.presentForwardResultToast(ChatToastState(
            message: operationResult.message ?? NEChatUIKitSwiftUIBundle.localized("chat_forward_sent", value: "Forward sent"),
            style: .success
          ), using: resultToastHandler)
          if forwardsToCurrentConversation {
            self.clearPendingNewMessageIds()
            self.clearNewMessageIndicatorAndScrollToLatest()
          }
        case .failure(let error):
          if let toast = self.forwardFailureToast(for: error) {
            self.presentForwardResultToast(toast, using: resultToastHandler)
          }
        }
      }
    }
  }

  private func forwardMessages(messages: [V2NIMMessage],
                               selection: ChatForwardSelectionResult,
                               merged: Bool,
                               depth: Int = 0,
                               resultToastHandler: ((ChatToastState) -> Void)? = nil) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    let messageIds = messages.compactMap { message in
      if let clientId = message.messageClientId, !clientId.isEmpty {
        return clientId
      }
      if let serverId = message.messageServerId, !serverId.isEmpty {
        return serverId
      }
      return nil
    }
    let forwardsToCurrentConversation = selection.targets.contains {
      $0.conversationId == context.conversationId
    }
    let operationKey = operationRequestKey("forward", ids: messageIds + selection.targets.map(\.conversationId))
    let requestId = beginOperationRequest(key: operationKey)
    operationPerformer.forwardMessages(messages: messages,
                                       targets: selection.targets,
                                       comment: selection.comment,
                                       merged: merged,
                                       sourceConversationId: messages.first?.conversationId ?? context.conversationId,
                                       sourceConversationName: forwardSourceConversationName,
                                       depth: depth) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isOperationRequestCurrent(key: operationKey, requestId: requestId) else {
          return
        }
        self.finishOperationRequest(key: operationKey, requestId: requestId)
        switch result {
        case .success(let operationResult):
          self.presentForwardResultToast(ChatToastState(
            message: operationResult.message ?? NEChatUIKitSwiftUIBundle.localized("chat_forward_sent", value: "Forward sent"),
            style: .success
          ), using: resultToastHandler)
          if forwardsToCurrentConversation {
            self.clearPendingNewMessageIds()
            self.clearNewMessageIndicatorAndScrollToLatest()
          }
        case .failure(let error):
          if let toast = self.forwardFailureToast(for: error) {
            self.presentForwardResultToast(toast, using: resultToastHandler)
          }
        }
      }
    }
  }

  private func presentForwardResultToast(_ toast: ChatToastState,
                                         using resultToastHandler: ((ChatToastState) -> Void)?) {
    if let resultToastHandler {
      resultToastHandler(toast)
    } else {
      state.toast = toast
    }
  }

  private func forwardFailureToast(for error: Error) -> ChatToastState? {
    // UIKit's forwarding send path reports a blacklist failure through the
    // message failure callback. It does not also present a generic failure
    // toast, so keep the SwiftUI forwarding flow equally silent here.
    if (error as NSError).code == inBlackListCode {
      return nil
    }
    return sendFailureToast(for: error) ??
      ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("failed_operation", value: "Operation failed"),
        style: .error
      )
  }

  // UIKit builds the merged-forward title with showAlias: false. A P2P
  // conversation title may be the local friend remark, so do not reuse it.
  private var forwardSourceConversationName: String {
    guard context.kind == .p2p,
          let accountId = V2NIMConversationIdUtil.conversationTargetId(context.conversationId),
          !accountId.isEmpty else {
      return title
    }
    if let aiName = NEAIUserManager.shared.getShowName(accountId),
       !aiName.isEmpty {
      return aiName
    }
    let nickname = NEFriendUserCache.shared.getShowName(accountId, false)
    return nickname.isEmpty ? title : nickname
  }

  private func inputTranslationLanguages() -> [ChatTranslationLanguageState] {
    ChatSwiftUIConfig.defaultInputTranslationLanguages()
  }

  private func inputTranslationSelectedLanguage(in languages: [ChatTranslationLanguageState]) -> String {
    if languages.contains(where: { $0.code == selectedInputTranslationLanguage }) {
      return selectedInputTranslationLanguage
    }
    if languages.contains(where: { $0.code == IMKitConfigCenter.shared.translationTargetLanguage }) {
      return IMKitConfigCenter.shared.translationTargetLanguage
    }
    if let firstLanguage = languages.first?.code {
      return firstLanguage
    }
    return config.defaultTranslationLanguage
  }

  private func inputTranslationSegments(sourceText: String,
                                        mentions: [ChatMentionState]) -> [InputTranslationSegment] {
    let mentions = validatedMentions(mentions, in: sourceText)
      .sorted { $0.start < $1.start }
    guard !mentions.isEmpty else {
      return [translatableInputSegment(sourceText)]
    }

    var segments = [InputTranslationSegment]()
    var cursor = 0
    for mention in mentions {
      guard let mentionRange = range(for: mention, in: sourceText),
            mentionRange.lowerBound >= cursor else {
        continue
      }
      if cursor < mentionRange.lowerBound {
        segments.append(translatableInputSegment(
          inputTextFragment(cursor ..< mentionRange.lowerBound, in: sourceText)
        ))
      }

      let mentionText = inputTextFragment(mentionRange, in: sourceText)
      segments.append(translatableMentionSegment(mentionText, mention: mention))
      cursor = mentionRange.upperBound
    }

    if cursor < sourceText.utf16.count {
      segments.append(translatableInputSegment(
        inputTextFragment(cursor ..< sourceText.utf16.count, in: sourceText)
      ))
    }
    return segments.isEmpty ? [translatableInputSegment(sourceText)] : segments
  }

  private func translatableInputSegment(_ text: String) -> InputTranslationSegment {
    let leadingWhitespace = String(text.prefix(while: \Character.isWhitespace))
    let withoutLeading = text.dropFirst(leadingWhitespace.count)
    let trailingWhitespace = String(withoutLeading.reversed().prefix(while: \Character.isWhitespace).reversed())
    let coreEnd = withoutLeading.index(
      withoutLeading.endIndex,
      offsetBy: -trailingWhitespace.count
    )
    let core = String(withoutLeading[..<coreEnd])
    return InputTranslationSegment(
      sourceText: core,
      outputPrefix: leadingWhitespace,
      outputSuffix: trailingWhitespace,
      translatedText: core.isEmpty ? text : nil,
      mention: nil
    )
  }

  private func translatableMentionSegment(_ text: String,
                                           mention: ChatMentionState) -> InputTranslationSegment {
    let mentionPrefix = text.first == "@" ? "@" : ""
    let name = mentionPrefix.isEmpty ? text : String(text.dropFirst())
    return InputTranslationSegment(
      sourceText: name,
      outputPrefix: mentionPrefix,
      outputSuffix: "",
      translatedText: name.isEmpty ? text : nil,
      mention: mention
    )
  }

  private func inputTextFragment(_ range: Range<Int>, in text: String) -> String {
    let boundedStart = min(max(0, range.lowerBound), text.utf16.count)
    let boundedEnd = min(max(boundedStart, range.upperBound), text.utf16.count)
    return (text as NSString).substring(with: NSRange(
      location: boundedStart,
      length: boundedEnd - boundedStart
    ))
  }

  private func translateNextInputSegment() {
    guard var batch = inputTranslationBatch,
          inputTranslationRequestId == batch.requestId else {
      return
    }
    guard let segmentIndex = batch.segments.firstIndex(where: { $0.translatedText == nil }) else {
      let translated = translatedInputState(from: batch.segments)
      inputTranslationBatch = nil
      finishInputTranslation(
        text: translated.text,
        mentions: translated.mentions,
        requestId: batch.requestId
      )
      return
    }

    let segment = batch.segments[segmentIndex]
    let childRequestId = UUID().uuidString
    batch.activeSegmentIndex = segmentIndex
    batch.activeRequestId = childRequestId
    inputTranslationBatch = batch
    proxyInputTranslation(
      text: segment.sourceText,
      accountId: batch.accountId,
      requestId: childRequestId,
      batchRequestId: batch.requestId,
      promptKey: batch.promptKey,
      targetLanguage: batch.targetLanguage
    )
  }

  private func proxyInputTranslation(text: String,
                                     accountId: String,
                                     requestId: String,
                                     batchRequestId: String,
                                     promptKey: String,
                                     targetLanguage: String) {
    let request = NEAIModelCallRequest(
      accountId: accountId,
      requestId: requestId,
      text: text,
      temperature: NEAIUserManager.shared.getTranslateTemperature(),
      promptVariables: [promptKey: targetLanguage]
    )
    aiRepo.proxyAIModelCall(request) { [weak self] error in
      Task { @MainActor in
        guard let self,
              self.inputTranslationRequestId == batchRequestId,
              let error else {
          return
        }
        if let batch = self.inputTranslationBatch,
           batch.activeRequestId != requestId {
          return
        }
        self.handleInputTranslationFailure(error)
      }
    }
  }

  private func handleInputTranslationResult(_ result: NEAIModelCallResult) {
    if var batch = inputTranslationBatch {
      guard inputTranslationRequestId == batch.requestId,
            result.requestId == batch.activeRequestId,
            let segmentIndex = batch.activeSegmentIndex,
            batch.segments.indices.contains(segmentIndex) else {
        return
      }
      guard result.code == 200 else {
        handleInputTranslationFailure(NSError(
          domain: NEChatUIKitSwiftUIConstants.moduleName,
          code: result.code,
          userInfo: [NSLocalizedDescriptionKey: result.text]
        ))
        return
      }
      let segment = batch.segments[segmentIndex]
      batch.segments[segmentIndex].translatedText = translatedInputSegmentOutput(
        result.text,
        segment: segment
      )
      batch.activeSegmentIndex = nil
      batch.activeRequestId = nil
      inputTranslationBatch = batch
      translateNextInputSegment()
      return
    }

    guard let requestId = inputTranslationRequestId,
          result.requestId == requestId else {
      return
    }
    guard result.code == 200 else {
      handleInputTranslationFailure(NSError(
        domain: NEChatUIKitSwiftUIConstants.moduleName,
        code: result.code,
        userInfo: [NSLocalizedDescriptionKey: result.text]
      ))
      return
    }
    finishInputTranslation(text: result.text, requestId: requestId)
  }

  private func translatedInputSegmentOutput(_ translatedText: String,
                                            segment: InputTranslationSegment) -> String {
    guard segment.mention != nil else {
      return segment.outputPrefix + translatedText + segment.outputSuffix
    }
    var translatedName = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if segment.outputPrefix == "@", translatedName.first == "@" {
      translatedName.removeFirst()
      translatedName = translatedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if translatedName.isEmpty {
      translatedName = segment.sourceText
    }
    return segment.outputPrefix + translatedName + segment.outputSuffix
  }

  private func translatedInputState(
    from segments: [InputTranslationSegment]
  ) -> (text: String, mentions: [ChatMentionState]) {
    var text = ""
    var mentions = [ChatMentionState]()
    var cursor = 0
    for segment in segments {
      let output = segment.translatedText ?? ""
      if var mention = segment.mention, !output.isEmpty {
        mention.displayText = output
        mention.start = cursor
        mention.end = cursor + output.utf16.count - 1
        mentions.append(mention)
      }
      text += output
      cursor += output.utf16.count
    }
    return (text, mentions)
  }

  private func finishInputTranslation(text: String,
                                      mentions: [ChatMentionState] = [],
                                      requestId: String) {
    guard inputTranslationRequestId == requestId,
          var inputTranslation = state.inputTranslation,
          inputTranslation.requestId == requestId else {
      return
    }
    inputTranslationRequestId = nil
    inputTranslationBatch = nil
    translatedInputMentions = mentions
    inputTranslation.requestId = nil
    inputTranslation.phase = .translated
    inputTranslation.translatedText = text
    state.inputTranslation = inputTranslation
  }

  private func handleInputTranslationFailure(_: Error?) {
    inputTranslationRequestId = nil
    inputTranslationBatch = nil
    translatedInputMentions.removeAll()
    if var inputTranslation = state.inputTranslation {
      inputTranslation.requestId = nil
      inputTranslation.phase = .idle
      state.inputTranslation = inputTranslation
    }
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("chat_translate_failed", value: "Translation failed"),
      style: .error
    )
  }

  private func voiceToText(id: String) {
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }

    guard let row = row(id: id),
          let audio = audioState(from: row.content),
          audio.convertedText?.isEmpty != false else {
      return
    }

    let requestId = UUID()
    voiceToTextRequestIds[id] = requestId
    operationPerformer.voiceToText(id: id) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.voiceToTextRequestIds[id] == requestId,
              self.row(id: id) != nil else {
          return
        }
        self.voiceToTextRequestIds[id] = nil
        switch result {
        case .success(let text):
          self.setVoiceToTextState(
            for: id,
            text: text,
            phase: .converted
          )
        case .failure:
          let failureMessage = self.voiceToTextFailureMessage()
          self.clearVoiceToTextState(for: id)
          self.state.toast = ChatToastState(message: failureMessage, style: .error)
        }
      }
    }
  }

  private func setAudioRoute(useSpeaker: Bool) {
    SettingRepo.shared.setHandsetMode(useSpeaker)
    config.audioPlaybackHandler?.setAudioRoute(useSpeaker: useSpeaker)
    state.toast = ChatToastState(
      message: useSpeaker
        ? NEChatUIKitSwiftUIBundle.localized("switch_speaker", value: "Turn on speaker")
        : NEChatUIKitSwiftUIBundle.localized("switch_ear", value: "Turn on earpiece"),
      style: .success
    )
  }

  private func audioState(from content: MessageContentState) -> MessageAudioState? {
    switch content {
    case let .audio(audio):
      return audio
    case let .reply(_, boxed):
      return audioState(from: boxed.value)
    default:
      return nil
    }
  }

  private func openMultiForward(row: MessageRowState,
                                multiForward: MessageMultiForwardState) {
    guard multiForward.url?.isEmpty == false else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("chat_multi_forward_url_missing", value: "Chat history file is missing"),
        style: .warning
      )
      return
    }

    let localPath = (NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)file/") ?? NSTemporaryDirectory()) + multiForwardFileName + row.id
    guard FileManager.default.fileExists(atPath: localPath) || !state.clientRuntime.shouldShowNetworkWarning else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("multiForward_open_failed", value: "Information not retrieved."),
        style: .warning
      )
      return
    }

    state.route = ChatRouteState(
      currentRoute: .multiForwardPreview(ChatMultiForwardPreviewState(
        messageId: row.id,
        multiForward: multiForward
      )),
      handlingState: .queued
    )
  }

  public func retryFailedMessage(_ row: MessageRowState) {
    guard state.multiSelect == nil,
          row.isSendFailureRetryable,
          case .failed = row.deliveryState else {
      return
    }
    guard guardRuntimeAllowsNetworkOperation() else {
      return
    }
    guard let message = messageContextMessage(for: row) else {
      state.toast = ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found"),
        style: .warning
      )
      return
    }

    let pendingId = row.id
    let retryAliases = messageIds(for: row).union([pendingId])
    retrySendMessageAliases.formUnion(retryAliases)
    updateDeliveryState(for: pendingId, deliveryState: .pending(progress: nil))
    let requestId = beginSendRequest(pendingId: pendingId)
    sendPipeline.sendMessage(
      message,
      conversationId: context.conversationId,
      context: activeContext
    ) { [weak self] progress in
      Task { @MainActor in
        guard let self,
              self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else { return }
        self.updateDeliveryState(for: pendingId, deliveryState: .pending(progress: progress))
      }
    } completion: { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.isSendRequestCurrent(pendingId: pendingId, requestId: requestId) else { return }
        self.finishSendRequest(pendingId: pendingId, requestId: requestId)
        self.handleSendResult(result, pendingId: pendingId)
        self.retrySendMessageAliases.subtract(retryAliases)
      }
    }
  }

  private func handleModifiedMessages(_ messages: [V2NIMMessage]) {
    let currentMessages = messages.filter(isCurrentMessage)
    cacheMessageContext(currentMessages)
    let rows = currentMessages
      .map { messageRow(from: $0) }
    guard !rows.isEmpty else {
      return
    }
    upsertRows(rows)
  }

  private func handleDeletedMessages(_ notifications: [V2NIMMessageDeletedNotification]) {
    let deletedIds = notifications.reduce(into: Set<String>()) { result, notification in
      result.formUnion(messageIds(from: notification.messageRefer))
    }
    guard !deletedIds.isEmpty else {
      return
    }
    removeRows(ids: deletedIds)
  }

  private func handleHistoryResult(_ result: Result<ChatHistoryLoadResult, Error>,
                                   placement: HistoryPlacement,
                                   requestStartedWhileNetworkBroken: Bool = false) {
    switch result {
    case .success(let loadResult):
      cacheMessageContext(loadResult.messages)
      let reachedOfflineOlderBoundary = placement == .prepend &&
        !loadResult.hasMoreOlder &&
        !isHistoryTransportReady
      let shouldSuspendOlderPagination = reachedOfflineOlderBoundary &&
        loadResult.messages.isEmpty
      if placement == .prepend {
        // A non-empty local tail can still report no more history while the
        // remote history source is unavailable. Keep its normal anchor restore,
        // but remember that reconnect must reopen pagination.
        shouldRetryOlderHistoryAfterReconnect = reachedOfflineOlderBoundary
        if shouldSuspendOlderPagination {
          state.clientRuntime.isNetworkBroken = true
          suspendOlderHistoryPaginationForNetworkBreak()
          NEChatSwiftUILogger.log(
            "offlineHistory suspend conversationId=\(context.conversationId) source=emptyResult placement=prepend requestStartedBroken=\(requestStartedWhileNetworkBroken) reachable=\(clientEventSource.swiftUICurrentNetworkAvailable) rows=\(state.rows.count)"
          )
        }
        // Keep the top probe closed while offline. Reconnect reopens pagination
        // without treating this empty result as the real end of history.
        state.hasMoreOlder = shouldSuspendOlderPagination ? false : loadResult.hasMoreOlder
      } else {
        state.hasMoreOlder = loadResult.hasMoreOlder
      }
      if placement == .append {
        state.hasMoreNewer = loadResult.hasMoreNewer
      } else if !isHistoryContextActive {
        state.hasMoreNewer = false
      }
      let shouldJumpToLatestAfterReload = shouldScrollToLatestAfterReload
      let initialLatestTargetId = shouldJumpToLatestAfterReload
        ? nil
        : initialLatestScrollTargetIdIfNeeded(
          rows: loadResult.rows,
          placement: placement
        )
      if let initialLatestTargetId {
        beginTimelineBottomPinning()
        requestInitialLatestScrollTarget(to: initialLatestTargetId)
      }
      let insertedRows = mergeRows(loadResult.rows, placement: placement)
      pendingPrependLoadedCount = placement == .prepend ? insertedRows.count : 0
      pendingPrependLoadedTailId = placement == .prepend ? insertedRows.last?.id : nil
      applyHistoryAnchors(from: loadResult, placement: placement)
      logHistoryResult(loadResult, placement: placement, insertedCount: insertedRows.count)
      state.phase = state.rows.isEmpty ? .empty : .loaded
      insertAIWelcomeMessageIfNeeded()
      refreshTopMessage()
      syncTopicFromRowsIfNeeded(loadResult.rows)
      resolveRepliesIfNeeded(for: loadResult.rows)
      refreshReadReceiptsIfNeeded(for: loadResult.messages)
      syncReadState(for: [])
      if placement == .prepend,
         shouldSuspendOlderPagination {
        shouldScrollToLatestAfterReload = false
        clearPendingPrependRestore()
        state.isLoadingOlder = false
      } else if placement == .prepend,
         pendingPrependAnchorId == nil,
         let lastId = state.rows.last?.id {
        isHistoryContextActive = false
        isTimelineBottomVisible = false
        clearPendingPrependRestore()
        NEChatSwiftUILogger.log(
          "chatAction historyResult latestWindow placement=\(placement.logName) lastId=\(lastId) shouldJumpAfterReload=\(shouldJumpToLatestAfterReload) rows=\(state.rows.count) currentTarget=\(state.timelineScrollTarget?.id ?? "nil")"
        )
        if shouldJumpToLatestAfterReload {
          shouldScrollToLatestAfterReload = false
          beginTimelineBottomPinning()
          requestTimelineScroll(to: lastId, anchor: .bottom, animated: false, reason: .jumpToLatest)
        } else if state.timelineScrollTarget?.messageId != lastId {
          beginTimelineBottomPinning()
          requestTimelineScroll(to: lastId, anchor: .bottom, animated: false, reason: .initialLatest)
        }
        state.isLoadingOlder = false
      } else {
        shouldScrollToLatestAfterReload = false
        restorePrependAnchorIfNeeded()
      }
    case .failure(let error):
      logHistoryFailure(error, placement: placement)
      let isNetworkRelatedFailure = requestStartedWhileNetworkBroken || isNetworkFailure(error)
      let shouldSuspendForNetworkBreak = placement == .prepend &&
        isNetworkRelatedFailure &&
        !isHistoryTransportReady
      if shouldSuspendForNetworkBreak {
        state.clientRuntime.isNetworkBroken = true
        shouldRetryOlderHistoryAfterReconnect = true
        suspendOlderHistoryPaginationForNetworkBreak()
        NEChatSwiftUILogger.log(
          "offlineHistory suspend conversationId=\(context.conversationId) source=failure placement=prepend error=\((error as NSError).code) rows=\(state.rows.count)"
        )
        // Keep the visible top probe from immediately triggering the same
        // failed request. Reconnect reopens pagination in refreshAfterReconnect().
        state.hasMoreOlder = false
      }
      shouldScrollToLatestAfterReload = false
      clearPendingPrependRestore()
      cancelTimelineBottomPinning()
      state.isLoadingOlder = false
      if isNetworkRelatedFailure {
        state.phase = state.rows.isEmpty ? .empty : .loaded
      } else {
        state.phase = state.rows.isEmpty
          ? .failed(NEChatErrorMessageMapper.errorState(
            for: error,
            fallbackKey: "chat_history_load_failed",
            fallbackValue: "Failed to load chat history"
          ))
          : .loaded
        state.toast = NEChatErrorMessageMapper.toast(
          for: error,
          fallbackKey: "chat_history_load_failed",
          fallbackValue: "Failed to load chat history"
        )
      }
      NEChatSwiftUILogger.log(
        "offlineHistory failurePresented conversationId=\(context.conversationId) placement=\(placement.logName) error=\((error as NSError).code) suspended=\(isOlderPaginationSuspendedForNetworkBreak) requestStartedBroken=\(requestStartedWhileNetworkBroken) runtimeBroken=\(state.clientRuntime.isNetworkBroken) reachable=\(clientEventSource.swiftUICurrentNetworkAvailable) toast=\(state.toast?.message ?? "nil") rows=\(state.rows.count)"
      )
    }
  }

  private func handleSendResult(_ result: Result<ChatSendResultState, Error>,
                                pendingId: String) {
    switch result {
    case .success(let sendResult):
      let existingTimestamp = row(id: pendingId)?.timestamp
      var row: MessageRowState
      var aliases: Set<String> = [pendingId]
      if let message = sendResult.result?.message {
        cacheMessageContext([message])
        aliases.formUnion(newMessageAliases(for: message))
        row = messageRow(from: message)
      } else {
        row = sendResult.row
      }
      let isRetry = !retrySendMessageAliases.isDisjoint(with: aliases)
      if isRetry, let existingTimestamp {
        row.timestamp = existingTimestamp
      }
      row = applyingOutgoingTextPresentation(to: row, aliases: aliases)
      rememberOutgoingTextPresentation(row, aliases: aliases.union(messageIds(for: row)))
      replaceOrInsert(row: row, replacing: pendingId)
      removeDuplicateRows()
      state.rows.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
      refreshTimeDividers()
      refreshAnchors()
      state.phase = state.rows.isEmpty ? .empty : .loaded
      syncTopicFromRowIfNeeded(row)
      refreshTopMessage()
      refreshTeamMemberDisplayInfosIfNeeded(for: [row])
      resolveRepliesIfNeeded(for: [row])
      insertAntiSpamTipIfNeeded(sendResult.result, sentRow: row)
      clearPendingNewMessageIds()
      state.newMessageIndicator = nil
      if !isRetry {
        requestScrollToLatestAfterOutgoingSend(preferredMessageId: row.id)
      }
    case .failure(let error):
      let failureMessage = sendFailureDisplayMessage(for: error)
      updateDeliveryState(for: pendingId, deliveryState: .failed(failureMessage))
      if let failedRow = row(id: pendingId),
         let message = messageContextMessage(for: failedRow) {
        insertSendFailureTipIfNeeded(message, error: error as NSError)
      }
      if let toast = sendFailureToast(for: error) {
        state.toast = toast
      }
    }
  }

  private func sendFailureDisplayMessage(for error: Error) -> String? {
    sendFailureToast(for: error)?.message ??
      NEChatUIKitSwiftUIBundle.localized("chat_send_failed", value: "Failed")
  }

  private func sendFailureToast(for error: Error) -> ChatToastState? {
    if let toast = NEChatErrorMessageMapper.teamMuteToast(for: error) {
      return toast
    }
    let code = (error as NSError).code
    switch code {
    case protocolSendFailed, protocolTimeout:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error"),
        style: .warning
      )
    case fileUploadFailed:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("file_upload_failed", value: "File upload failed"),
        style: .error
      )
    case aiMessagesNotExist:
      return ChatToastState(
        message: NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found"),
        style: .warning
      )
    case teamNormalMemberChatBanned, teamMemberChatBanned:
      return NEChatErrorMessageMapper.toast(for: error, style: .warning)
    default:
      return nil
    }
  }

  private func insertAntiSpamTipIfNeeded(_ result: V2NIMSendMessageResult?,
                                         sentRow: MessageRowState) {
    guard IMKitConfigCenter.shared.enableAntiSpamTipMessage,
          let result,
          let tip = antiSpamTipMessage(from: result) else {
      return
    }

    let conversationId = sentRow.conversationId ?? context.conversationId
    let createTime = result.message.map { $0.createTime + 1 }
    let tipMessage = ChatRepo.shared.makeTipMessage(text: tip)
    ChatRepo.shared.insertMessageToLocal(
      message: tipMessage,
      conversationId: conversationId,
      createTime: createTime
    ) { [weak self] _, _ in
      Task { @MainActor in
        guard let self else { return }
        self.upsertRows([self.messageRow(from: tipMessage)])
      }
    }
  }

  private func antiSpamTipMessage(from result: V2NIMSendMessageResult) -> String? {
    guard let antispamResult = result.antispamResult, !antispamResult.isEmpty else {
      return nil
    }

    let pattern = "\\\\*\"label\\\\*\"\\s*:\\s*(\\d+)"
    guard let label = NECommonUtil.extractLabelsWithRegex(from: antispamResult, pattern).first,
          let code = Int(label),
          let reason = antiSpamReason(for: code) else {
      return nil
    }

    return String(
      format: NEChatUIKitSwiftUIBundle.localized("failed_message_reson", value: "The content may involve %@. Please adjust and send."),
      reason
    )
  }

  private func antiSpamReason(for code: Int) -> String? {
    switch code {
    case 100:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_ornography", value: "Pornography")
    case 200:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_advertising", value: "Advertising")
    case 260:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_advertising_law", value: "Advertising Law")
    case 300:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_violence_and_terrorism", value: "Violence and terrorism")
    case 400:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_prohibited", value: "Prohibited")
    case 500:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_political_related", value: "Political-related")
    case 600:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_abuse", value: "Abuse")
    case 700:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_waterlogging", value: "waterlogging")
    case 900:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_others", value: "Others")
    case 1000:
      return NEChatUIKitSwiftUIBundle.localized("failed_message_reson_value_related", value: "value-related")
    default:
      return nil
    }
  }

  private func handleSentMessageState(_ message: V2NIMMessage) {
    guard isCurrentMessage(message) else {
      return
    }
    let stableMessageId = ChatMessageMapper.stableMessageId(for: message)
    if ChatMessageMapper.isRevokeMessage(message), row(id: stableMessageId) == nil {
      // ChatRepo persists a separate revoke tip before forwarding the revoke
      // notification. UIKit only updates that local message when it is already
      // visible; the notification itself replaces the original timeline row.
      return
    }
    let aliases = newMessageAliases(for: message)
    let isRetryStateUpdate = !retrySendMessageAliases.isDisjoint(with: aliases)
    cacheMessageContext([message])
    let row = messageRow(from: message)
    if let pendingId = pendingMediaId(matching: row) {
      replaceOrInsert(row: row, replacing: pendingId)
    } else {
      upsertRows([row])
    }
    refreshTopMessage()
    if !isRetryStateUpdate,
       message.messageType != .MESSAGE_TYPE_TIP,
       message.senderId == currentAccountProvider(),
       let messageId = message.messageClientId {
      clearPendingNewMessageIds()
      state.newMessageIndicator = nil
      requestTimelineScroll(to: messageId, anchor: .bottom)
    }
  }

  private func handleSendFailure(_ message: V2NIMMessage, error: NSError) {
    insertSendFailureTipIfNeeded(message, error: error)
    guard isCurrentMessage(message) else {
      return
    }
    let aliases = newMessageAliases(for: message)
    let existingTimestamp = state.rows.first { existingRow in
      !messageIds(for: existingRow).isDisjoint(with: aliases)
    }?.timestamp
    cacheMessageContext([message])
    var row = messageRow(from: message)
    // Resending mutates the SDK message create time. UIKit keeps the failed
    // model at its existing index, so retain that timeline position as well.
    if let existingTimestamp {
      row.timestamp = existingTimestamp
    }
    row.deliveryState = .failed(sendFailureDisplayMessage(for: error))
    if let pendingId = pendingMediaId(matching: row) {
      replaceOrInsert(row: row, replacing: pendingId)
    } else {
      upsertRows([row])
    }
    if let toast = sendFailureToast(for: error) {
      state.toast = toast
    }
  }

  private func insertSendFailureTipIfNeeded(_ message: V2NIMMessage,
                                            error: NSError) {
    guard error.code == inBlackListCode,
          let conversationId = message.conversationId else {
      return
    }
    let messageId = ChatMessageMapper.stableMessageId(for: message)
    let attemptId = sendAttemptIds[messageId]?.uuidString ?? "external:\(message.createTime)"
    let attemptKey = "blackListTip:\(messageId):\(attemptId)"
    guard handledSendFailureTipAttempts.insert(attemptKey).inserted else {
      return
    }

    let tipMessage = ChatRepo.shared.makeTipMessage(
      text: NEChatUIKitSwiftUIBundle.localized("black_list_tip", value: "You are blocked. Message not sent.")
    )
    let aliases = newMessageAliases(for: message)
    let messageTimestamp = state.rows.first { row in
      !messageIds(for: row).isDisjoint(with: aliases)
    }?.timestamp ?? message.createTime
    ChatRepo.shared.insertMessageToLocal(
      message: tipMessage,
      conversationId: conversationId,
      createTime: messageTimestamp + 1
    ) { [weak self] insertedMessage, insertError in
      Task { @MainActor in
        guard let self else { return }
        if let insertedMessage, conversationId == self.context.conversationId {
          let insertedRow = self.messageRow(from: insertedMessage)
          self.upsertRows([insertedRow])
          self.requestScrollToLatestAfterInsertedSendFailureTip(preferredMessageId: insertedRow.id)
        } else if insertError != nil {
          self.handledSendFailureTipAttempts.remove(attemptKey)
        }
      }
    }
  }

  private func handleRevokeNotifications(_ notifications: [V2NIMMessageRevokeNotification]) {
    for notification in notifications {
      guard notification.messageRefer?.conversationId == context.conversationId,
            let ids = messageRevokeIds(from: notification) else {
        continue
      }
      dismissOperations()
      applyRevokeNotification(ids: ids, notification: notification)
    }
  }

  private func handlePinNotification(_ notification: V2NIMMessagePinNotification) {
    guard notification.pin?.messageRefer?.conversationId == context.conversationId else {
      return
    }

    let ids = messageIds(from: notification.pin?.messageRefer)
    guard !ids.isEmpty else {
      return
    }

    let isPinned = notification.pinState != .MESSAGE_PIN_STEATE_NOT_PINNED
    setPinnedDisplayInfo(
      for: ids,
      operatorId: notification.pin?.operatorId,
      isPinned: isPinned
    )
    state.rows = state.rows.map { row in
      guard ids.contains(row.id) || row.serverId.map(ids.contains) == true else {
        return row
      }
      var next = row
      next.isPinned = isPinned
      if isPinned {
        next = applyingPinnedDisplayInfo(to: next)
      } else {
        next.pinOperatorId = nil
        next.pinOperatorName = nil
      }
      return next
    }
    if isPinned,
       let operatorId = nonEmpty(notification.pin?.operatorId) {
      refreshContactDisplayInfosIfNeeded(accountIds: [operatorId])
      if context.kind == .team {
        refreshTeamMemberDisplayInfosIfNeeded(accountIds: [operatorId])
      }
    }
    refreshTopMessage()
  }

  private func validateTeamLifecycleIfNeeded() {
    guard context.kind == .team,
          IMKitConfigCenter.shared.enableDismissTeamDeleteConversation,
          let teamId = Self.teamId(from: context) else {
      return
    }

    teamLifecycleRequestGeneration += 1
    let generation = teamLifecycleRequestGeneration
    TeamRepo.shared.getTeamInfo(teamId) { [weak self] team, _ in
      Task { @MainActor in
        guard let self, self.teamLifecycleRequestGeneration == generation else {
          return
        }
        if let team, team.isValidTeam == false {
          self.presentTeamLifecycleAlert(reason: .invalid, teamId: team.teamId)
        }
      }
    }
  }

  private func refreshTeamTitleIfNeeded() {
    guard context.kind == .team,
          let teamId = Self.teamId(from: context) else {
      return
    }

    teamTitleRequestGeneration += 1
    let generation = teamTitleRequestGeneration
    TeamRepo.shared.getTeamInfo(teamId) { [weak self] team, _ in
      Task { @MainActor in
        guard let self, self.teamTitleRequestGeneration == generation else {
          return
        }
        self.updateTeamMemberCount(team.map { Int($0.memberCount) })
        self.updateTeamTitle(team?.name)
      }
    }
  }

  private func updateTeamMemberCount(_ count: Int?) {
    teamMemberCount = count
    state.rows = state.rows.map { applyingTeamReadReceiptDisplayState(to: $0) }
  }

  private func updateTeamTitle(_ title: String?) {
    let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedTitle.isEmpty else {
      return
    }
    state.sessionTitle = trimmedTitle
  }

  private func refreshTeamInputMuteStateIfNeeded() {
    guard context.kind == .team,
          let teamId = Self.teamId(from: context) else {
      applyTeamInputMuteState(NETeamChatInputMuteState(isMuted: false))
      return
    }

    teamInputMuteRequestGeneration += 1
    let generation = teamInputMuteRequestGeneration
    TeamRepo.shared.swiftUIChatInputMuteState(
      teamId: teamId,
      currentAccountId: currentAccountProvider(),
      localizer: { key, fallback in
        NEChatUIKitSwiftUIBundle.localized(key, value: fallback)
      }
    ) { [weak self] muteState, _ in
      Task { @MainActor in
        guard let self, self.teamInputMuteRequestGeneration == generation else {
          return
        }
        self.applyTeamInputMuteState(muteState)
      }
    }
  }

  private func applyTeamInputMuteState(_ muteState: NETeamChatInputMuteState) {
    if muteState.isMuted {
      let reason = muteState.reason ?? NEChatUIKitSwiftUIBundle.localized("team_mute", value: "Mute")
      sendLocalTypingStateIfNeeded(false, force: true)
      voiceRecordingGeneration += 1
      state.input.isEnabled = false
      state.input.disabledReason = reason
      state.input.placeholder = reason
      state.input.mode = .text
      state.input.text = ""
      state.input.selectedRange = NSRange(location: 0, length: 0)
      state.input.richTextTitle = ""
      state.input.isRichTextExpanded = false
      state.input.isSendEnabled = false
      state.input.reply = nil
      state.input.mentionedAccountIds.removeAll()
      state.input.mentions.removeAll()
      state.input.recording = ChatVoiceRecordingState()
      state.input.isRecording = false
      state.input.validation = makeInputValidation(for: "")
      return
    }

    state.input.isEnabled = true
    state.input.disabledReason = nil
    state.input.placeholder = nil
    state.input.validation = makeInputValidation(for: state.input.text)
    updateInputSendEnabledState()
  }

  private func refreshTeamMemberDisplayInfosIfNeeded(for rows: [MessageRowState]? = nil,
                                                     accountIds explicitAccountIds: [String] = []) {
    guard context.kind == .team,
          let teamId = Self.teamId(from: context) else {
      return
    }

    let accountIds = teamMemberDisplayAccountIds(from: rows ?? state.rows, explicitAccountIds: explicitAccountIds)
      .filter { accountId in
        shouldLoadTeamMemberDisplayInfo(accountId: accountId) &&
          !pendingTeamMemberDisplayAccountIds.contains(accountId)
      }
    guard !accountIds.isEmpty else {
      return
    }

    pendingTeamMemberDisplayAccountIds.formUnion(accountIds)
    teamMemberDisplayRequestGeneration += 1
    let generation = teamMemberDisplayRequestGeneration
    for accountId in accountIds {
      teamMemberDisplayInfoGenerationByAccountId[accountId] = generation
    }
    TeamRepo.shared.swiftUITeamMemberDisplayInfos(
      teamId: teamId,
      accountIds: accountIds
    ) { [weak self] infos, _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.pendingTeamMemberDisplayAccountIds.subtract(accountIds)
        guard self.didAppear,
              self.context.kind == .team,
              Self.teamId(from: self.context) == teamId else {
          return
        }
        self.applyTeamMemberDisplayInfos(infos, generation: generation)
      }
    }
  }

  private func shouldLoadTeamMemberDisplayInfo(accountId: String) -> Bool {
    guard teamMemberDisplayInfoByAccountId[accountId] == nil else {
      return false
    }
    let display = cachedSenderDisplayInfo(accountId: accountId)
    return display.senderName == nil || display.avatarURL == nil
  }

  private func teamMemberDisplayAccountIds(from rows: [MessageRowState],
                                           explicitAccountIds: [String]) -> [String] {
    var orderedAccountIds = [String]()

    func append(_ accountId: String?) {
      let trimmedId = accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !trimmedId.isEmpty,
            !orderedAccountIds.contains(trimmedId) else {
        return
      }
      orderedAccountIds.append(trimmedId)
    }

    explicitAccountIds.forEach { append($0) }
    for row in rows {
      append(row.senderId)
      append(row.reply?.senderId)
    }
    if let topRow = state.topMessage?.row {
      append(topRow.senderId)
      append(topRow.reply?.senderId)
    }
    return orderedAccountIds
  }

  private func applyTeamMemberDisplayInfos(_ infos: [NETeamMemberDisplayInfo],
                                           generation: Int? = nil,
                                           authoritativeAccountIds: Set<String> = []) {
    guard !infos.isEmpty else {
      return
    }

    for info in infos {
      mergeTeamMemberDisplayInfo(
        info,
        generation: generation,
        isAuthoritative: authoritativeAccountIds.contains(info.accountId)
      )
    }
    applyCachedTeamMemberDisplayInfos()
  }

  private func mergeTeamMemberDisplayInfo(_ info: NETeamMemberDisplayInfo,
                                          generation: Int?,
                                          isAuthoritative: Bool = false) {
    let accountId = info.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !accountId.isEmpty else {
      return
    }

    if let generation,
       let latestGeneration = teamMemberDisplayInfoGenerationByAccountId[accountId],
       latestGeneration != generation {
      return
    }

    if isAuthoritative {
      var next = info
      if let existing = teamMemberDisplayInfoByAccountId[accountId] {
        if nonEmpty(next.avatarURL) == nil {
          next.avatarURL = nonEmpty(existing.avatarURL)
        }
        if nonEmpty(next.avatarName) == nil {
          next.avatarName = nonEmpty(existing.avatarName)
        }
      }
      teamMemberDisplayInfoByAccountId[accountId] = next
      return
    }

    if let existing = teamMemberDisplayInfoByAccountId[accountId] {
      teamMemberDisplayInfoByAccountId[accountId] = mergedTeamMemberDisplayInfo(primary: info, fallback: existing)
    } else {
      teamMemberDisplayInfoByAccountId[accountId] = info
    }
  }

  private func mergedTeamMemberDisplayInfo(primary: NETeamMemberDisplayInfo,
                                           fallback: NETeamMemberDisplayInfo) -> NETeamMemberDisplayInfo {
    var next = primary
    if nonEmpty(next.avatarURL) == nil {
      next.avatarURL = nonEmpty(fallback.avatarURL)
    }
    if nonEmpty(next.avatarName) == nil {
      next.avatarName = nonEmpty(fallback.avatarName)
    }
    if displayNameNeedsFallback(next.displayName, accountId: next.accountId),
       let fallbackName = nonEmpty(fallback.displayName),
       fallbackName != fallback.accountId {
      next.displayName = fallbackName
    }
    if nonEmpty(next.teamNick) == nil {
      next.teamNick = nonEmpty(fallback.teamNick)
    }
    return next
  }

  private func displayNameNeedsFallback(_ value: String, accountId: String) -> Bool {
    guard let name = nonEmpty(value) else {
      return true
    }
    return name == accountId
  }

  private func nonEmpty(_ value: String?) -> String? {
    let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmedValue.isEmpty ? nil : trimmedValue
  }

  private func refreshContactDisplayInfosIfNeeded(for rows: [MessageRowState]? = nil,
                                                  accountIds explicitAccountIds: [String] = []) {
    let accountIds = contactDisplayAccountIds(from: rows ?? state.rows, explicitAccountIds: explicitAccountIds)
      .filter { accountId in
        shouldLoadContactDisplayInfo(accountId: accountId) &&
          !pendingContactDisplayAccountIds.contains(accountId) &&
          !NEAIUserManager.shared.isAIUser(accountId)
      }
    guard !accountIds.isEmpty else {
      return
    }

    pendingContactDisplayAccountIds.formUnion(accountIds)
    contactDisplayRequestGeneration += 1
    let generation = contactDisplayRequestGeneration
    ChatRepo.shared.loadSwiftUIP2PDisplayUsers(accountIds: accountIds) { [weak self] users, _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.pendingContactDisplayAccountIds.subtract(accountIds)
        guard self.didAppear else {
          return
        }
        guard generation <= self.contactDisplayRequestGeneration else {
          return
        }
        self.mergeContactDisplayInfos(users ?? [])
      }
    }
  }

  private func shouldLoadContactDisplayInfo(accountId: String) -> Bool {
    if contactDisplayInfoByAccountId[accountId]?.user != nil {
      return false
    }
    return cachedContactDisplayInfo(accountId: accountId).avatarURL == nil
  }

  private func contactDisplayAccountIds(from rows: [MessageRowState],
                                        explicitAccountIds: [String]) -> [String] {
    var orderedAccountIds = [String]()

    func append(_ accountId: String?) {
      let trimmedId = accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !trimmedId.isEmpty,
            !orderedAccountIds.contains(trimmedId) else {
        return
      }
      orderedAccountIds.append(trimmedId)
    }

    explicitAccountIds.forEach { append($0) }
    for row in rows {
      append(row.senderId)
      append(row.reply?.senderId)
    }
    if let topRow = state.topMessage?.row {
      append(topRow.senderId)
      append(topRow.reply?.senderId)
    }
    return orderedAccountIds
  }

  private func mergeContactDisplayInfos(_ users: [NEUserWithFriend]) {
    guard !users.isEmpty else {
      return
    }

    var changedAccountIds = Set<String>()
    ChatRepo.cacheSwiftUIP2PDisplayUsers(users)
    for user in users {
      guard let accountId = nonEmpty(user.user?.accountId) ?? nonEmpty(user.friend?.accountId) else {
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
    refreshCachedContactDisplayInfos(matching: changedAccountIds.isEmpty ? nil : changedAccountIds)
    refreshP2PSessionTitleIfNeeded(matching: changedAccountIds.isEmpty ? nil : changedAccountIds)
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

  private func applyCachedTeamMemberDisplayInfos() {
    guard !teamMemberDisplayInfoByAccountId.isEmpty else {
      return
    }

    let infoMap = teamMemberDisplayInfoByAccountId
    var didChange = false
    let updatedRows = state.rows.map { row in
      let next = applyingTeamMemberDisplayInfos(infoMap, to: row)
      if next != row {
        didChange = true
      }
      return next
    }
    if didChange {
      state.rows = updatedRows
    }

    if let topMessage = state.topMessage {
      var nextTop = topMessage
      if let topRow = topMessage.row {
        let updatedRow = applyingTeamMemberDisplayInfos(infoMap, to: topRow)
        if updatedRow != topRow {
          nextTop.row = updatedRow
          nextTop.subtitle = updatedRow.senderName ?? updatedRow.senderId
        }
      }
      if nextTop != topMessage {
        state.topMessage = nextTop
        didChange = true
      }
    }

    let propagatedDisplay = refreshConsistentSenderDisplayInfos(matching: Set(infoMap.keys))
    refreshPinnedOperatorNames(matching: Set(infoMap.keys))
    if didChange || propagatedDisplay {
      refreshTopMessage()
    }
  }

  private func refreshCachedContactDisplayInfos(matching accountIds: Set<String>? = nil) {
    var didChange = false
    let updatedRows = state.rows.map { row in
      let next = applyingCachedContactDisplayInfo(to: row, matching: accountIds)
      if next != row {
        didChange = true
      }
      return next
    }
    if didChange {
      state.rows = updatedRows
    }

    if let topMessage = state.topMessage {
      var nextTop = topMessage
      if let topRow = topMessage.row {
        let updatedRow = applyingCachedContactDisplayInfo(to: topRow, matching: accountIds)
        if updatedRow != topRow {
          nextTop.row = updatedRow
          nextTop.subtitle = updatedRow.senderName ?? updatedRow.senderId
        }
      }
      if nextTop != topMessage {
        state.topMessage = nextTop
        didChange = true
      }
    }

    let propagatedDisplay = refreshConsistentSenderDisplayInfos(matching: accountIds)
    refreshPinnedOperatorNames(matching: accountIds)
    if didChange || propagatedDisplay {
      refreshTopMessage()
    }
  }

  private func applyingCachedContactDisplayInfo(to row: MessageRowState,
                                                matching accountIds: Set<String>?) -> MessageRowState {
    var next = row
    if let senderId = row.senderId,
       accountIds?.contains(senderId) ?? true {
      next = applyingCachedContactDisplayInfo(toSender: next, accountId: senderId)
    }

    if var reply = next.reply,
       let senderId = reply.senderId,
       accountIds?.contains(senderId) ?? true {
      let display = cachedContactDisplayInfo(accountId: senderId)
      reply.senderName = display.name ?? reply.senderName
      next.reply = reply
      if case let .reply(_, content) = next.content {
        next.content = .reply(preview: reply.displayPreview, content: content)
      }
    }
    return next
  }

  private func applyingCachedContactDisplayInfo(toSender row: MessageRowState,
                                                accountId: String) -> MessageRowState {
    var next = row
    let display = cachedContactDisplayInfo(accountId: accountId)
    next.senderName = display.name ?? next.senderName
    let avatarName = ChatRepo.swiftUIDisplayName(accountId: accountId, showAlias: false)
    if !avatarName.isEmpty {
      next.avatarName = avatarName
    }
    if let avatarURL = display.avatarURL {
      next.avatarURL = avatarURL
    }
    return next
  }

  private func cachedSenderDisplayInfo(accountId: String) -> SenderDisplayInfo {
    let contactDisplay = cachedContactDisplayInfo(accountId: accountId)
    guard context.kind == .team else {
      return SenderDisplayInfo(senderName: contactDisplay.name, avatarURL: contactDisplay.avatarURL)
    }
    guard let teamDisplay = teamMemberDisplayInfoByAccountId[accountId] else {
      return SenderDisplayInfo(senderName: nil, avatarURL: contactDisplay.avatarURL)
    }
    return SenderDisplayInfo(
      senderName: nonEmpty(teamDisplay.displayName) ?? contactDisplay.name,
      avatarURL: ChatAvatarURLResolver.url(from: teamDisplay.avatarURL) ?? contactDisplay.avatarURL
    )
  }

  private func cachedContactDisplayInfo(accountId: String) -> (name: String?, avatarURL: URL?) {
    if let aiUser = NEAIUserManager.shared.getNEUserById(accountId) {
      return (
        nonEmpty(aiUser.showName()) ?? accountId,
        ChatAvatarURLResolver.url(from: aiUser.user?.avatar)
      )
    }

    let cachedUser = ChatRepo.cachedSwiftUIDisplayUser(accountId: accountId)
    let loadedUser = contactDisplayInfoByAccountId[accountId]
    let hasUser = cachedUser != nil || loadedUser != nil
    return (
      nonEmpty(loadedUser?.showName()) ?? nonEmpty(cachedUser?.showName()) ?? (hasUser ? accountId : nil),
      ChatAvatarURLResolver.url(from: loadedUser?.user?.avatar) ??
        ChatAvatarURLResolver.url(from: cachedUser?.user?.avatar)
    )
  }

  private func refreshP2PSessionTitleIfNeeded(matching accountIds: Set<String>? = nil) {
    guard context.kind == .p2p,
          let accountId = targetSessionId()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !accountId.isEmpty,
          accountIds?.contains(accountId) ?? true,
          let displayName = cachedContactDisplayInfo(accountId: accountId).name else {
      return
    }
    state.sessionTitle = displayName
  }

  private func refreshP2PDisplayStateIfNeeded() {
    guard context.kind == .p2p,
          let accountId = targetSessionId()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !accountId.isEmpty else {
      return
    }
    let accountIds = Set([accountId])
    refreshCachedContactDisplayInfos(matching: accountIds)
    refreshP2PSessionTitleIfNeeded(matching: accountIds)
  }

  private func mergedContactDisplayInfo(accountId: String) -> NEUserWithFriend? {
    let cached = ChatRepo.cachedSwiftUIDisplayUser(accountId: accountId)
    let loaded = contactDisplayInfoByAccountId[accountId]
    guard let loaded else {
      return cached
    }
    guard let cached else {
      return loaded
    }
    return mergedUserWithFriend(
      primary: loaded,
      fallback: cached,
      preserveFallbackFriend: loaded.friend != nil || NEFriendUserCache.shared.isFriend(accountId)
    )
  }

  private func mergedUserWithFriend(primary: NEUserWithFriend,
                                    fallback: NEUserWithFriend,
                                    preserveFallbackFriend: Bool = true) -> NEUserWithFriend {
    NEUserWithFriend(
      user: primary.user ?? fallback.user,
      friend: primary.friend ?? (preserveFallbackFriend ? fallback.friend : nil)
    )
  }

  private func applyingTeamMemberDisplayInfos(_ infoMap: [String: NETeamMemberDisplayInfo],
                                              to row: MessageRowState) -> MessageRowState {
    var next = row
    if let senderId = row.senderId,
       let info = infoMap[senderId] {
      next.senderName = info.displayName
      next.avatarName = nonEmpty(info.avatarName) ?? next.avatarName
      if let avatarURL = ChatAvatarURLResolver.url(from: info.avatarURL) {
        next.avatarURL = avatarURL
      }
    }

    if var reply = row.reply,
       let senderId = reply.senderId,
       let info = infoMap[senderId] {
      reply.senderName = info.displayName
      next.reply = reply
      if case let .reply(_, content) = next.content {
        next.content = .reply(preview: reply.displayPreview, content: content)
      }
    }
    if let message = messageContextMessage(for: row),
       message.messageType == .MESSAGE_TYPE_NOTIFICATION {
      next.content = .tip(ChatMessageMapper.notificationText(for: message) { accountId in
        self.nonEmpty(infoMap[accountId]?.displayName)
      })
    }
    return next
  }

  private func handleTeamMemberDisplayChanged(_ members: [V2NIMTeamMember]) {
    let accountIds = members
      .filter { member in
        guard let teamId = Self.teamId(from: context) else {
          return false
        }
        return member.teamId == teamId
      }
      .map(\.accountId)
    refreshTeamMemberDisplayInfosIfNeeded(accountIds: accountIds)
  }

  private func handleUpdatedTeamMemberDisplayInfos(_ members: [V2NIMTeamMember]) {
    guard let teamId = Self.teamId(from: context) else {
      return
    }
    let currentMembers = members.filter { member in
      member.teamId == teamId && !member.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !currentMembers.isEmpty else {
      return
    }

    let accountIds = Set(currentMembers.map {
      $0.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    })
    requestUpdatedTeamMemberDisplayInfos(teamId: teamId, accountIds: accountIds) { completion in
      TeamRepo.shared.swiftUITeamMemberDisplayInfos(
        teamId: teamId,
        members: currentMembers,
        completion: completion
      )
    }
  }

  private func handleUpdatedTeamMemberDisplayInfos(_ users: [NEUserWithFriend]) {
    guard let teamId = Self.teamId(from: context) else {
      return
    }
    let currentUsers = users.filter { user in
      let accountId = user.user?.accountId ?? user.friend?.accountId
      return accountId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    let accountIds = Set(currentUsers.compactMap { user in
      (user.user?.accountId ?? user.friend?.accountId)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    })
    guard !accountIds.isEmpty else {
      return
    }

    requestUpdatedTeamMemberDisplayInfos(teamId: teamId, accountIds: accountIds) { completion in
      TeamRepo.shared.swiftUITeamMemberDisplayInfos(
        teamId: teamId,
        users: currentUsers,
        completion: completion
      )
    }
  }

  private func requestUpdatedTeamMemberDisplayInfos(
    teamId: String,
    accountIds: Set<String>,
    load: (@escaping ([NETeamMemberDisplayInfo], NSError?) -> Void) -> Void
  ) {
    teamMemberDisplayRequestGeneration += 1
    let generation = teamMemberDisplayRequestGeneration
    for accountId in accountIds {
      teamMemberDisplayInfoGenerationByAccountId[accountId] = generation
    }

    load { [weak self] infos, _ in
      Task { @MainActor in
        guard let self,
              self.didAppear,
              self.context.kind == .team,
              Self.teamId(from: self.context) == teamId else {
          return
        }
        self.applyTeamMemberDisplayInfos(
          infos,
          generation: generation,
          authoritativeAccountIds: accountIds
        )
      }
    }
  }

  private func handleContactDisplayChanged(_ accountIds: [String],
                                           updatedUsers: [NEUserWithFriend] = []) {
    let normalizedIds = Set(accountIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    let targetIds = normalizedIds.isEmpty ? nil : normalizedIds
    refreshCachedContactDisplayInfos(matching: targetIds)
    refreshP2PSessionTitleIfNeeded(matching: targetIds)
    refreshContactDisplayInfosIfNeeded(accountIds: accountIds)
    guard context.kind == .team else {
      return
    }
    if !updatedUsers.isEmpty {
      handleUpdatedTeamMemberDisplayInfos(updatedUsers)
      return
    }
    applyCachedTeamMemberDisplayInfos()
    refreshTeamMemberDisplayInfosIfNeeded(accountIds: accountIds)
  }

  private func handleFriendCacheInitialized() {
    guard didAppear, isPageVisible else {
      return
    }

    refreshCachedContactDisplayInfos()
    refreshContactDisplayInfosIfNeeded()
    guard context.kind == .team else {
      return
    }
    applyCachedTeamMemberDisplayInfos()
    refreshTeamMemberDisplayInfosIfNeeded()
  }

  private func handleTeamDismissed(_ team: V2NIMTeam) {
    guard isCurrentTeam(team) else {
      return
    }
    presentTeamLifecycleAlert(reason: .dismissed, teamId: team.teamId)
  }

  private func handleTeamLeft(_ team: V2NIMTeam, isKicked: Bool) {
    guard isCurrentTeam(team) else {
      return
    }
    presentTeamLifecycleAlert(reason: .left, teamId: team.teamId)
  }

  private func handleTeamInfoUpdated(_ team: V2NIMTeam) {
    guard context.kind == .team,
          Self.teamId(from: context) == team.teamId else {
      return
    }
    updateTeamTitle(team.name)
    updateTeamMemberCount(Int(team.memberCount))
    if team.isValidTeam == false {
      presentTeamLifecycleAlert(reason: .invalid, teamId: team.teamId)
      return
    }
    refreshTeamInputMuteStateIfNeeded()
    loadTeamTopMessageIfNeeded(showFailureToast: false)
  }

  private func handleTeamMemberInfoUpdated(_ members: [V2NIMTeamMember]) {
    guard context.kind == .team else {
      return
    }
    handleUpdatedTeamMemberDisplayInfos(members)
    guard let currentAccountId = currentAccountProvider(),
          members.contains(where: { $0.accountId == currentAccountId }) else {
      return
    }
    refreshTeamInputMuteStateIfNeeded()
    loadTeamTopMessageIfNeeded(showFailureToast: false)
  }

  private func handleTeamMembersJoined(_ members: [V2NIMTeamMember]) {
    handleTeamMembershipChanged(members)
    loadNewerMessagesIfPossible()
  }

  private func handleTeamMembershipChanged(_ members: [V2NIMTeamMember]) {
    handleTeamMemberDisplayChanged(members)
    refreshTeamTitleIfNeeded()
  }

  private func handleTeamInfoNotifications(in messages: [V2NIMMessage]) {
    guard context.kind == .team else {
      return
    }

    for message in messages where isCurrentMessage(message) {
      guard let attachment = message.attachment as? V2NIMMessageNotificationAttachment,
            attachment.type == .MESSAGE_NOTIFICATION_TYPE_TEAM_UPDATE_TINFO,
            let name = attachment.updatedTeamInfo?.name else {
        continue
      }
      updateTeamTitle(name)
    }
  }

  private func handleTeamLifecycleNotifications(in messages: [V2NIMMessage]) {
    guard context.kind == .team,
          IMKitConfigCenter.shared.enableDismissTeamDeleteConversation,
          let currentTeamId = Self.teamId(from: context) else {
      return
    }

    let currentAccountId = currentAccountProvider() ?? ""
    for message in messages where isCurrentMessage(message) {
      guard let attachment = message.attachment as? V2NIMMessageNotificationAttachment else {
        continue
      }
      switch attachment.type {
      case .MESSAGE_NOTIFICATION_TYPE_TEAM_INVITE:
        if !currentAccountId.isEmpty,
           attachment.targetIds?.contains(currentAccountId) == true,
           state.teamLifecycleAlert?.reason == .left {
          state.teamLifecycleAlert = nil
        }
      case .MESSAGE_NOTIFICATION_TYPE_TEAM_LEAVE:
        if !currentAccountId.isEmpty, message.senderId == currentAccountId {
          presentTeamLifecycleAlert(reason: .left, teamId: currentTeamId, requiresUserConfirmation: false)
        }
      case .MESSAGE_NOTIFICATION_TYPE_TEAM_KICK:
        if !currentAccountId.isEmpty, attachment.targetIds?.contains(currentAccountId) == true {
          presentTeamLifecycleAlert(reason: .left, teamId: currentTeamId)
        }
      case .MESSAGE_NOTIFICATION_TYPE_TEAM_DISMISS:
        presentTeamLifecycleAlert(reason: .dismissed, teamId: currentTeamId)
      default:
        break
      }
    }
  }

  private func presentTeamLifecycleAlert(reason: ChatTeamLifecycleReason,
                                         teamId: String,
                                         requiresUserConfirmation: Bool = true) {
    guard IMKitConfigCenter.shared.enableDismissTeamDeleteConversation else {
      return
    }
    guard !localTeamLifecycleExitInFlightIds.contains(teamId) else {
      return
    }
    let conversationId = V2NIMConversationIdUtil.teamConversationId(teamId) ?? context.conversationId
    let shouldRequireConfirmation = requiresUserConfirmation &&
      !locallyCompletedTeamLifecycleIds.contains(teamId)
    state.teamLifecycleAlert = ChatTeamLifecycleAlertState(
      reason: reason,
      teamId: teamId,
      conversationId: conversationId,
      message: teamLifecycleMessage(for: reason),
      shouldDeleteConversation: true,
      requiresUserConfirmation: shouldRequireConfirmation
    )
  }

  private func teamLifecycleMessage(for reason: ChatTeamLifecycleReason) -> String {
    switch reason {
    case .invalid:
      return NEChatUIKitSwiftUIBundle.localized("team_not_exist", value: "Team does not exist")
    case .dismissed:
      return NEChatUIKitSwiftUIBundle.localized("team_has_been_removed", value: "This group is disbanded")
    case .left:
      return NEChatUIKitSwiftUIBundle.localized("team_has_been_quit", value: "You have been removed")
    }
  }

  private func isCurrentTeam(_ team: V2NIMTeam) -> Bool {
    context.kind == .team && Self.teamId(from: context) == team.teamId
  }

  private func handleClearHistoryNotifications(_ notifications: [V2NIMClearHistoryNotification]) {
    guard notifications.contains(where: { $0.conversationId == context.conversationId }) else {
      return
    }
    state.rows.removeAll()
    refreshAnchors()
    refreshTopMessage()
    state.phase = .empty
  }

  private func insertAIWelcomeMessageIfNeeded() {
    guard state.phase == .empty,
          state.rows.isEmpty,
          context.kind == .p2p,
          !isInsertingAIWelcomeMessage,
          !didInsertAIWelcomeMessage,
          let accountId = targetSessionId(),
          NEAIUserManager.shared.isAIUser(accountId),
          let welcomeText = NEAIUserManager.shared.getWelcomeText(accountId) else {
      return
    }

    isInsertingAIWelcomeMessage = true
    let message = ChatRepo.shared.makeTextMessage(text: welcomeText)
    ChatRepo.shared.insertMessageToLocal(
      message: message,
      conversationId: context.conversationId,
      senderId: accountId
    ) { [weak self] insertedMessage, error in
      Task { @MainActor in
        guard let self else { return }
        self.isInsertingAIWelcomeMessage = false
        guard error == nil, let insertedMessage else {
          return
        }
        self.didInsertAIWelcomeMessage = true
        self.cacheMessageContext([insertedMessage])
        self.upsertRows([self.messageRow(from: insertedMessage)])
        self.state.phase = .loaded
      }
    }

    ChatRepo.shared.ensureSwiftUIConversationExists(context.conversationId)
  }

  private func handleP2PReadReceipts(_ receipts: [V2NIMP2PMessageReadReceipt]) {
    let readTimestamps = receipts
      .filter { $0.conversationId == context.conversationId }
      .map(\.timestamp)
    guard let readTimestamp = readTimestamps.max() else {
      return
    }

    state.rows = state.rows.map { row in
      guard shouldApplyReadReceipt(to: row),
            let createTime = row.timestamp,
            createTime <= readTimestamp else {
        return row
      }
      var next = row
      next.deliveryState = .read
      next.readReceipt = MessageReadReceiptState(
        readCount: 1,
        unreadCount: 0,
        isP2PRead: true,
        timestamp: readTimestamp
      )
      return next
    }
  }

  private func handleTeamReadReceipts(_ receipts: [V2NIMTeamMessageReadReceipt]) {
    var receiptMap = [String: V2NIMTeamMessageReadReceipt]()
    for receipt in receipts where receipt.conversationId == context.conversationId {
      guard let messageId = receipt.messageClientId, !messageId.isEmpty else {
        continue
      }
      receiptMap[messageId] = receipt
    }
    guard !receiptMap.isEmpty else {
      return
    }

    state.rows = state.rows.map { row in
      guard shouldApplyReadReceipt(to: row),
            let receipt = receiptMap[row.id] else {
        return row
      }
      var next = row
      next.deliveryState = .read
      next.readReceipt = MessageReadReceiptState(
        readCount: Int(receipt.readCount),
        unreadCount: Int(receipt.unreadCount),
        isP2PRead: false,
        displayLimit: config.maxTeamReadReceiptCount
      )
      return next
    }
  }

  private func handleDataSync(type: V2NIMDataSyncType,
                              syncState: V2NIMDataSyncState,
                              error: V2NIMError?) {
    let phase = dataSyncPhase(from: syncState, error: error)
    state.clientRuntime.dataSync = ChatDataSyncState(
      type: type.rawValue,
      phase: phase,
      errorMessage: error?.desc
    )
    if let error {
      state.clientRuntime.lastErrorMessage = error.desc
      NEChatSwiftUILogger.log("dataSync failed type=\(type.rawValue) syncState=\(syncState.rawValue) error=\(error.desc ?? "")")
    }

    if phase == .completed {
      handleCompletedDataSync(type)
    }
  }

  private func handleConnectStatus(_ status: V2NIMConnectStatus) {
    switch status {
    case .CONNECT_STATUS_WAITING:
      isSDKTransportConnectedAfterNetworkBreak = false
      state.clientRuntime.connectionPhase = .waiting
      state.clientRuntime.isNetworkBroken = true
      invalidatePinnedMessageRefreshForNetworkBreak()
    case .CONNECT_STATUS_CONNECTED:
      isSDKTransportConnectedAfterNetworkBreak = true
      completeReconnectIfReady(source: "sdkConnected")
    case .CONNECT_STATUS_DISCONNECTED:
      isSDKTransportConnectedAfterNetworkBreak = false
      state.clientRuntime.connectionPhase = .disconnected
      state.clientRuntime.isNetworkBroken = true
      invalidatePinnedMessageRefreshForNetworkBreak()
    default:
      state.clientRuntime.connectionPhase = .unknown
    }
  }

  private func handleConnectFailed(_ error: V2NIMError?) {
    isSDKTransportConnectedAfterNetworkBreak = false
    state.clientRuntime.connectionPhase = .failed
    state.clientRuntime.isNetworkBroken = true
    invalidatePinnedMessageRefreshForNetworkBreak()
    state.clientRuntime.lastErrorMessage = error?.desc
  }

  private func handleDisconnected(_ error: V2NIMError?) {
    isSDKTransportConnectedAfterNetworkBreak = false
    state.clientRuntime.connectionPhase = .disconnected
    state.clientRuntime.isNetworkBroken = true
    invalidatePinnedMessageRefreshForNetworkBreak()
    state.clientRuntime.lastErrorMessage = error?.desc
  }

  private var isHistoryTransportReady: Bool {
    isSystemNetworkReachable &&
      clientEventSource.swiftUICurrentNetworkAvailable &&
      clientEventSource.swiftUICurrentConnectStatus == .CONNECT_STATUS_CONNECTED
  }

  private func handleSystemReachability(_ status: NENetworkReachabilityManager.NetworkReachabilityStatus) {
    // UIKit hides its network banner for every state except notReachable.
    let isReachable = status != .notReachable
    isSystemNetworkReachable = isReachable
    NEChatSwiftUILogger.log(
      "offlineHistory reachability conversationId=\(context.conversationId) status=\(String(describing: status)) reachable=\(isReachable) sdkConnected=\(isSDKTransportConnectedAfterNetworkBreak) runtimeBroken=\(state.clientRuntime.isNetworkBroken) suspended=\(isOlderPaginationSuspendedForNetworkBreak)"
    )

    guard isReachable else {
      state.clientRuntime.connectionPhase = .waiting
      state.clientRuntime.isNetworkBroken = true
      invalidatePinnedMessageRefreshForNetworkBreak()
      return
    }
    completeReconnectIfReady(source: "reachability")
  }

  private func completeReconnectIfReady(source: String) {
    if clientEventSource.swiftUICurrentConnectStatus == .CONNECT_STATUS_CONNECTED {
      isSDKTransportConnectedAfterNetworkBreak = true
    }
    guard isSDKTransportConnectedAfterNetworkBreak,
          isSystemNetworkReachable,
          clientEventSource.swiftUICurrentNetworkAvailable else {
      state.clientRuntime.connectionPhase = .waiting
      state.clientRuntime.isNetworkBroken = true
      NEChatSwiftUILogger.log(
        "offlineHistory reconnectDeferred conversationId=\(context.conversationId) source=\(source) sdkConnected=\(isSDKTransportConnectedAfterNetworkBreak) reachable=\(isSystemNetworkReachable) currentReachable=\(clientEventSource.swiftUICurrentNetworkAvailable)"
      )
      return
    }

    let shouldRefresh = state.clientRuntime.isNetworkBroken ||
      isOlderPaginationSuspendedForNetworkBreak
    state.clientRuntime.connectionPhase = .connected
    state.clientRuntime.isNetworkBroken = false
    state.clientRuntime.lastErrorMessage = nil
    NEChatSwiftUILogger.log(
      "offlineHistory reconnectReady conversationId=\(context.conversationId) source=\(source) shouldRefresh=\(shouldRefresh) suspended=\(isOlderPaginationSuspendedForNetworkBreak)"
    )
    if shouldRefresh {
      refreshAfterReconnect()
    }
  }

  private func isNetworkFailure(_ error: Error) -> Bool {
    let code = (error as NSError).code
    return code == protocolSendFailed || code == protocolTimeout
  }

  private func suspendOlderHistoryPaginationForNetworkBreak() {
    let shouldResumeAfterReconnect = shouldRetryOlderHistoryAfterReconnect ||
      state.hasMoreOlder ||
      state.isLoadingOlder
    let wasSuspended = isOlderPaginationSuspendedForNetworkBreak
    isOlderPaginationSuspendedForNetworkBreak = true
    cancelPrependRestoreForNetworkBreak()
    NEChatSwiftUILogger.log(
      "offlineHistory suspend conversationId=\(context.conversationId) source=connectionChange already=\(wasSuspended) loading=\(state.isLoadingOlder) hasMore=\(state.hasMoreOlder) rows=\(state.rows.count)"
    )
    guard shouldResumeAfterReconnect else {
      return
    }
    shouldRetryOlderHistoryAfterReconnect = true
    state.hasMoreOlder = false

    guard state.isLoadingOlder else {
      return
    }
    pendingOlderHistoryLoad = nil
    historyRequestGeneration += 1
    clearPendingPrependRestore()
    cancelTimelineBottomPinning()
    state.isLoadingOlder = false
    if state.rows.isEmpty {
      state.phase = .failed(NEChatKitErrorState(
        message: NEChatUIKitSwiftUIBundle.localized("network_error", value: "Network error")
      ))
    } else {
      state.phase = .loaded
    }
  }

  private func cancelPrependRestoreForNetworkBreak() {
    clearPendingPrependRestore()
    guard state.timelineScrollTarget?.reason == .prependRestore else {
      return
    }
    NEChatSwiftUILogger.log(
      "offlineHistory cancelPrependRestore conversationId=\(context.conversationId) target=\(state.timelineScrollTarget?.id ?? "nil") rows=\(state.rows.count)"
    )
    setTimelineScrollTarget(nil)
  }

  private func handleLoginStatus(_ status: V2NIMLoginStatus) {
    switch status {
    case .LOGIN_STATUS_LOGINED:
      state.clientRuntime.loginPhase = .loggedIn
      state.clientRuntime.kickedOfflineReason = nil
    case .LOGIN_STATUS_LOGOUT:
      state.clientRuntime.loginPhase = .loggedOut
    default:
      state.clientRuntime.loginPhase = .unknown
    }
  }

  private func handleLoginFailed(_ error: V2NIMError) {
    state.clientRuntime.loginPhase = .failed
    state.clientRuntime.lastErrorMessage = error.desc
    state.toast = NEChatErrorMessageMapper.toast(
      for: error.nserror,
      fallbackKey: "chat_login_failed",
      fallbackValue: "Login failed"
    )
  }

  private func handleKickedOffline(_ detail: V2NIMKickedOfflineDetail) {
    state.clientRuntime.loginPhase = .kickedOffline
    state.clientRuntime.kickedOfflineReason = String(describing: detail.reason)
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("chat_kicked_offline", value: "You were kicked offline"),
      style: .error
    )
  }

  private func handleCompletedDataSync(_ type: V2NIMDataSyncType) {
    if type == .DATA_SYNC_TYPE_MAIN {
      refreshAfterDataSync()
    }

    if context.kind == .team,
       type == .DATA_SYNC_TYPE_TEAM_MEMBER {
      loadTeamTopMessageIfNeeded(showFailureToast: false)
      refreshTeamMemberDisplayInfosIfNeeded()
    }
  }

  private func dataSyncPhase(from syncState: V2NIMDataSyncState,
                             error: V2NIMError?) -> ChatDataSyncPhase {
    if error != nil {
      return .failed
    }
    switch syncState {
    case .DATA_SYNC_STATE_WAITING:
      return .waiting
    case .DATA_SYNC_STATE_SYNCING:
      return .syncing
    case .DATA_SYNC_STATE_COMPLETED:
      return .completed
    default:
      return .idle
    }
  }

  private func refreshAfterReconnect() {
    refreshMoreActions()
    refreshRobotAwareMoreActionsIfNeeded()
    subscribeP2POnlineState()
    schedulePinnedMessageRefreshAfterReconnect()
    loadTeamTopMessageIfNeeded(showFailureToast: false)
    syncReadState(for: [])
    let wasOlderPaginationSuspended = isOlderPaginationSuspendedForNetworkBreak
    NEChatSwiftUILogger.log(
      "offlineHistory resume conversationId=\(context.conversationId) source=reconnect shouldRetry=\(shouldRetryOlderHistoryAfterReconnect) rows=\(state.rows.count)"
    )
    if shouldRetryOlderHistoryAfterReconnect || wasOlderPaginationSuspended {
      shouldRetryOlderHistoryAfterReconnect = false
      state.hasMoreOlder = true
    }
    if wasOlderPaginationSuspended {
      // Publish hasMoreOlder first. SwiftUI onChange closures otherwise observe
      // stale sibling values when both properties change in one transaction.
      DispatchQueue.main.async { [weak self] in
        guard let self,
              self.isHistoryTransportReady,
              !self.state.clientRuntime.isNetworkBroken else {
          return
        }
        self.isOlderPaginationSuspendedForNetworkBreak = false
        NEChatSwiftUILogger.log(
          "offlineHistory resumeCommitted conversationId=\(self.context.conversationId) hasMoreOlder=\(self.state.hasMoreOlder)"
        )
      }
    }
    if !state.rows.isEmpty {
      loadNewerMessagesIfPossible()
    }
    refreshLoadedAIStreamMessages()
    scheduleReadReceiptRefreshAfterReconnect()
  }

  private func scheduleReadReceiptRefreshAfterReconnect() {
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard let self, self.didAppear else {
        return
      }
      self.refreshReadReceiptsIfNeeded(
        for: self.state.rows.compactMap { self.messageContextMessage(for: $0) }
      )
    }
  }

  private func schedulePinnedMessageRefreshAfterReconnect() {
    pinnedMessageRequestGeneration += 1
    let generation = pinnedMessageRequestGeneration
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard let self,
            self.didAppear,
            self.state.clientRuntime.connectionPhase == .connected,
            self.pinnedMessageRequestGeneration == generation else {
        return
      }
      self.refreshPinnedMessagesIfNeeded()
    }
  }

  private func invalidatePinnedMessageRefreshForNetworkBreak() {
    // Keep the last confirmed pin display while offline. The generation bump
    // only prevents a pre-disconnect request from overwriting that cache.
    pinnedMessageRequestGeneration += 1
  }

  private func refreshAfterDataSync() {
    refreshMoreActions()
    refreshRobotAwareMoreActionsIfNeeded()
    refreshCachedContactDisplayInfos()
    refreshContactDisplayInfosIfNeeded()
    syncReadState(for: [])
    if !state.rows.isEmpty {
      loadNewerMessagesIfPossible()
    }
    refreshLoadedAIStreamMessages()
  }

  private func refreshLoadedAIStreamMessages() {
    let ids = state.rows.compactMap { row in
      row.isUnfinishedAIStream ? row.id : nil
    }
    guard !ids.isEmpty else {
      return
    }

    aiStreamRefreshGeneration += 1
    let generation = aiStreamRefreshGeneration
    ChatRepo.shared.getMessageListByIds(ids) { [weak self] messages, _ in
      Task { @MainActor in
        guard let self,
              self.didAppear,
              self.aiStreamRefreshGeneration == generation,
              let messages else {
          return
        }
        self.handleModifiedMessages(messages)
      }
    }
  }

  private func refreshTopicState() {
    guard context.usesTopicHistory else {
      state.topic = nil
      return
    }

    let title = topicDisplayTitle(currentTopic)
    state.topic = ChatTopicState(title: title, isRemoved: false)
  }

  private func topicDisplayTitle(_ topic: V2NIMTopic?) -> String? {
    if let title = topic?.topicName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !title.isEmpty {
      return title
    }
    if currentTopic == nil, context.kind == .botSubSession {
      return NEChatUIKitSwiftUIBundle.localized("bot_sub_session_new_conversation", value: "New conversation")
    }
    if let sessionName = context.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !sessionName.isEmpty {
      return sessionName
    }
    return context.title
  }

  private func handleTopicAdded(_ topic: V2NIMTopic) {
    updateCurrentTopicIfMatching(topic)
  }

  private func handleTopicUpdated(_ topic: V2NIMTopic) {
    updateCurrentTopicIfMatching(topic)
  }

  private func handleTopicsRemoved(_ topics: [V2NIMTopicRefer]) {
    guard let currentTopic else {
      return
    }
    let removed = topics.contains { refer in
      refer.conversationId == context.conversationId &&
        refer.topicId == currentTopic.topicId &&
        refer.createTime == currentTopic.createTime
    }
    guard removed else {
      return
    }
    state.topic = ChatTopicState(title: topicDisplayTitle(currentTopic), isRemoved: true)
    state.toast = ChatToastState(
      message: NEChatUIKitSwiftUIBundle.localized("bot_sub_session_removed", value: "This conversation was removed"),
      style: .warning
    )
  }

  private func updateCurrentTopicIfMatching(_ topic: V2NIMTopic) {
    guard context.usesTopicHistory,
          topic.conversationId == context.conversationId else {
      return
    }
    if let currentTopic {
      guard topic.topicId == currentTopic.topicId,
            topic.createTime == currentTopic.createTime else {
        return
      }
    }
    currentTopic = topic
    refreshTopicState()
  }

  private func syncTopicFromRowIfNeeded(_ row: MessageRowState) {
    guard context.usesTopicHistory,
          currentTopic == nil,
          let refer = row.topicRefer,
          refer.isValid,
          refer.conversationId == context.conversationId else {
      return
    }

    topicRequestGeneration += 1
    let generation = topicRequestGeneration
    let option = V2NIMTopicListOption()
    option.conversationId = context.conversationId
    option.limit = 20
    option.direction = .QUERY_DIRECTION_DESC
    option.beginTime = 0
    option.endTime = 0
    topicRepo.getTopicListByOption(option) { [weak self] result, _ in
      Task { @MainActor in
        guard let self,
              self.topicRequestGeneration == generation,
              self.currentTopic == nil else {
          return
        }
        let referCreateTime = Int64(refer.createTime)
        guard let topic = result?.topicList.first(where: {
          $0.conversationId == refer.conversationId &&
            $0.topicId == refer.topicId &&
            $0.createTime == referCreateTime
        }) else {
          return
        }
        self.currentTopic = topic
        self.refreshTopicState()
      }
    }
  }

  private func syncTopicFromRowsIfNeeded(_ rows: [MessageRowState]) {
    guard currentTopic == nil,
          let row = rows.first(where: { $0.topicRefer?.isValid == true }) else {
      return
    }
    syncTopicFromRowIfNeeded(row)
  }

  private func loadNewerMessagesIfPossible(requiresMoreNewer: Bool = false) {
    guard !state.isLoadingOlder,
          !state.isLoadingNewer,
          let anchor = state.newestAnchorMessageId,
          !anchor.isEmpty else {
      return
    }
    guard !requiresMoreNewer || state.hasMoreNewer else {
      return
    }

    state.isLoadingNewer = true
    let request = ChatHistoryLoadRequest(
      conversationId: context.conversationId,
      context: activeContext,
      anchorMessageId: anchor,
      anchorMessage: historyAnchorMessage(
        newestHistoryAnchorMessage,
        matching: anchor
      ),
      direction: .newer,
      teamReadReceiptDisplayLimit: config.maxTeamReadReceiptCount,
      imageThumbSize: config.imageThumbSize
    )
    historyRequestGeneration += 1
    let generation = historyRequestGeneration
    logHistoryRequest(request, placement: .append, generation: generation)
    historyLoader.load(request) { [weak self] result in
      Task { @MainActor in
        guard let self else {
          return
        }
        guard self.historyRequestGeneration == generation else {
          NEChatSwiftUILogger.log(
            "history ignored placement=append generation=\(generation) current=\(self.historyRequestGeneration)"
          )
          return
        }
        self.handleNewerHistoryResult(result)
      }
    }
  }

  private func handleNewerHistoryResult(_ result: Result<ChatHistoryLoadResult, Error>) {
    state.isLoadingNewer = false

    switch result {
    case .success(let loadResult):
      cacheMessageContext(loadResult.messages)
      let shouldStickToBottom = self.shouldStickToBottom(for: loadResult.rows)
      let insertedRows = mergeRows(loadResult.rows, placement: .append)
      applyHistoryAnchors(from: loadResult, placement: .append)
      logHistoryResult(loadResult, placement: .append, insertedCount: insertedRows.count)
      let didLoadCloserToNow = loadResult.loadedMessageCount > 0
      state.hasMoreNewer = isHistoryContextActive ? loadResult.hasMoreNewer : false
      if isHistoryContextActive,
         !loadResult.hasMoreNewer,
         !didLoadCloserToNow,
         pendingCurrentMessages().isEmpty {
        isHistoryContextActive = false
      }
      state.phase = state.rows.isEmpty ? .empty : .loaded
      syncTopicFromRowsIfNeeded(loadResult.rows)
      refreshTopMessage()
      resolveRepliesIfNeeded(for: loadResult.rows)
      refreshReadReceiptsIfNeeded(for: loadResult.messages)
      syncReadState(for: [])
      if let lastId = insertedRows.last?.id ?? loadResult.rows.last?.id {
        if shouldStickToBottom {
          clearPendingNewMessageIds()
          state.newMessageIndicator = nil
          requestTimelineScroll(to: lastId, anchor: .bottom)
        } else {
          appendNewMessageIndicator(for: loadResult.rows)
        }
      }
    case .failure(let error):
      logHistoryFailure(error, placement: .append)
      state.hasMoreNewer = false
      state.clientRuntime.lastErrorMessage = error.localizedDescription
    }
    startPendingOlderHistoryLoadIfNeeded()
  }

  private func loadMessageContextAroundAnchor(_ row: MessageRowState) {
    let anchor = row.id
    guard !anchor.isEmpty else {
      return
    }

    let olderRequest = ChatHistoryLoadRequest(
      conversationId: context.conversationId,
      context: activeContext,
      anchorMessageId: anchor,
      anchorMessage: messageContextMessage(for: row),
      direction: .older,
      teamReadReceiptDisplayLimit: config.maxTeamReadReceiptCount,
      imageThumbSize: config.imageThumbSize
    )
    historyRequestGeneration += 1
    let generation = historyRequestGeneration
    logHistoryRequest(olderRequest, placement: .prepend, generation: generation)
    historyLoader.load(olderRequest) { [weak self] olderResult in
      Task { @MainActor in
        guard let self else {
          return
        }
        guard self.historyRequestGeneration == generation else {
          NEChatSwiftUILogger.log(
            "history ignored placement=focusedOlder generation=\(generation) current=\(self.historyRequestGeneration)"
          )
          return
        }
        self.loadNewerMessageContextAroundAnchor(
          row,
          olderResult: olderResult,
          generation: generation
        )
      }
    }
  }

  private func loadNewerMessageContextAroundAnchor(_ row: MessageRowState,
                                                   olderResult: Result<ChatHistoryLoadResult, Error>,
                                                   generation: Int) {
    let anchor = row.id
    let newerRequest = ChatHistoryLoadRequest(
      conversationId: context.conversationId,
      context: activeContext,
      anchorMessageId: anchor,
      anchorMessage: messageContextMessage(for: row),
      direction: .newer,
      teamReadReceiptDisplayLimit: config.maxTeamReadReceiptCount,
      imageThumbSize: config.imageThumbSize
    )
    logHistoryRequest(newerRequest, placement: .append, generation: generation)
    historyLoader.load(newerRequest) { [weak self] newerResult in
      Task { @MainActor in
        guard let self else {
          return
        }
        guard self.historyRequestGeneration == generation else {
          NEChatSwiftUILogger.log(
            "history ignored placement=focusedNewer generation=\(generation) current=\(self.historyRequestGeneration)"
          )
          return
        }
        self.handleFocusedHistoryResult(
          olderResult: olderResult,
          newerResult: newerResult,
          targetRow: row,
          generation: generation
        )
      }
    }
  }

  private func handleFocusedHistoryResult(olderResult: Result<ChatHistoryLoadResult, Error>,
                                          newerResult: Result<ChatHistoryLoadResult, Error>,
                                          targetRow: MessageRowState,
                                          generation: Int) {
    switch (olderResult, newerResult) {
    case let (.success(olderLoadResult), .success(newerLoadResult)):
      NEChatSwiftUILogger.log(
        "messageJump focusedReload result generation=\(generation) targetRowId=\(targetRow.id) olderLoaded=\(olderLoadResult.loadedMessageCount) olderRows=\(olderLoadResult.rows.count) newerLoaded=\(newerLoadResult.loadedMessageCount) newerRows=\(newerLoadResult.rows.count) hasMoreOlder=\(olderLoadResult.hasMoreOlder) hasMoreNewer=\(newerLoadResult.hasMoreNewer)"
      )
      let loadedMessages = olderLoadResult.messages + newerLoadResult.messages
      let loadedRows = olderLoadResult.rows + [targetRow] + newerLoadResult.rows
      cacheMessageContext(loadedMessages)
      let didLoadCloserToNow = newerLoadResult.loadedMessageCount > 0
      isHistoryContextActive = newerLoadResult.hasMoreNewer || didLoadCloserToNow || !pendingCurrentMessages().isEmpty
      let presentedRows = commitFocusedHistoryPresentation(
        rows: loadedRows,
        targetRow: targetRow,
        historyGeneration: generation,
        hasMoreOlder: olderLoadResult.hasMoreOlder,
        hasMoreNewer: newerLoadResult.hasMoreNewer,
        oldestAnchorMessageId: olderLoadResult.oldestAnchorMessageId,
        newestAnchorMessageId: newerLoadResult.newestAnchorMessageId,
        oldestAnchorMessage: olderLoadResult.oldestAnchorMessage,
        newestAnchorMessage: newerLoadResult.newestAnchorMessage
      )
      guard !presentedRows.isEmpty else {
        return
      }
      logHistoryResult(olderLoadResult, placement: .prepend, insertedCount: olderLoadResult.rows.count)
      logHistoryResult(newerLoadResult, placement: .append, insertedCount: newerLoadResult.rows.count)
      syncTopicFromRowsIfNeeded(loadedRows)
      refreshTopMessage()
      resolveRepliesIfNeeded(for: loadedRows)
      refreshReadReceiptsIfNeeded(for: loadedMessages)
      syncReadState(for: [])
      showHistoryJumpIndicatorIfNeeded()
    case let (.failure(error), _), let (_, .failure(error)):
      NEChatSwiftUILogger.log(
        "history failure placement=focusedReload messageJump focusedReload failure generation=\(generation) targetRowId=\(targetRow.id) error=\(error.localizedDescription)"
      )
      handleFocusedHistoryFailure(
        error,
        targetRow: targetRow,
        generation: generation
      )
    }
  }

  private func handleFocusedHistoryFailure(_ error: Error,
                                           targetRow: MessageRowState,
                                           generation: Int) {
    logHistoryFailure(error, placement: .prepend)
    let toast = NEChatErrorMessageMapper.toast(
      for: error,
      style: .warning,
      fallbackKey: "chat_history_load_failed",
      fallbackValue: "Failed to load chat history"
    )
    let anchorMessage = messageContextMessage(for: targetRow)
    _ = commitFocusedHistoryPresentation(
      rows: [targetRow],
      targetRow: targetRow,
      historyGeneration: generation,
      hasMoreOlder: false,
      hasMoreNewer: false,
      oldestAnchorMessageId: targetRow.id,
      newestAnchorMessageId: targetRow.id,
      oldestAnchorMessage: anchorMessage,
      newestAnchorMessage: anchorMessage,
      toast: toast
    )
    showHistoryJumpIndicatorIfNeeded()
  }

  @discardableResult
  private func commitFocusedHistoryPresentation(rows: [MessageRowState],
                                                targetRow: MessageRowState,
                                                historyGeneration: Int,
                                                hasMoreOlder: Bool,
                                                hasMoreNewer: Bool,
                                                oldestAnchorMessageId: String?,
                                                newestAnchorMessageId: String?,
                                                oldestAnchorMessage: V2NIMMessage?,
                                                newestAnchorMessage: V2NIMMessage?,
                                                toast: ChatToastState? = nil) -> [MessageRowState] {
    guard historyRequestGeneration == historyGeneration else {
      NEChatSwiftUILogger.log(
        "messageJump focusedPresentation rejected reason=staleHistoryGeneration targetRowId=\(targetRow.id) requested=\(historyGeneration) current=\(historyRequestGeneration)"
      )
      return []
    }
    let presentedRows = preparedFocusedHistoryRows(rows)
    guard let loadedId = loadedRowId(matching: targetRow, in: presentedRows) else {
      NEChatSwiftUILogger.log(
        "messageJump focusedPresentation rejected reason=targetMissing targetRowId=\(targetRow.id) serverId=\(targetRow.serverId ?? "nil") rows=\(presentedRows.count) first=\(presentedRows.first?.id ?? "nil") last=\(presentedRows.last?.id ?? "nil") historyGeneration=\(historyGeneration)"
      )
      return []
    }

    let target = makeExplicitAnchorTarget(messageId: loadedId)
    var nextState = state
    nextState.rows = presentedRows
    nextState.isLoadingOlder = false
    nextState.isLoadingNewer = false
    nextState.hasMoreOlder = hasMoreOlder
    nextState.hasMoreNewer = hasMoreNewer
    nextState.oldestAnchorMessageId = oldestAnchorMessageId ?? presentedRows.first?.id
    nextState.newestAnchorMessageId = newestAnchorMessageId ?? presentedRows.last?.id
    nextState.timelineScrollTarget = target
    nextState.timelinePresentationGeneration += 1
    nextState.phase = presentedRows.isEmpty ? .empty : .loaded
    if let toast {
      nextState.toast = toast
    }
    state = nextState
    refreshTopMessage()

    self.oldestHistoryAnchorMessage = historyAnchorMessage(
      oldestAnchorMessage,
      matching: nextState.oldestAnchorMessageId
    )
    self.newestHistoryAnchorMessage = historyAnchorMessage(
      newestAnchorMessage,
      matching: nextState.newestAnchorMessageId
    )
    pruneMessageContext()
    refreshContactDisplayInfosIfNeeded(for: presentedRows)
    refreshTeamMemberDisplayInfosIfNeeded(for: presentedRows)
    NEChatSwiftUILogger.log(
      "messageJump focusedPresentation commit generation=\(nextState.timelinePresentationGeneration) historyGeneration=\(historyGeneration) rows=\(presentedRows.count) target=\(target.id) messageId=\(target.messageId) oldest=\(nextState.oldestAnchorMessageId ?? "nil") newest=\(nextState.newestAnchorMessageId ?? "nil") topBanner=\(state.topMessage?.id ?? "nil")"
    )
    startPendingReplyAttachmentDownloadIfReady(matching: targetRow)
    return presentedRows
  }

  private func preparedFocusedHistoryRows(_ rows: [MessageRowState]) -> [MessageRowState] {
    var uniqueRows = [MessageRowState]()
    for row in rows.map(applyingDisplayCaches(to:)) {
      if let index = uniqueRows.firstIndex(where: { sameMessage($0, row) }) {
        uniqueRows[index] = preservingTransientMessageState(from: uniqueRows[index], into: row)
      } else {
        uniqueRows.append(row)
      }
    }
    uniqueRows.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }

    var previousTimestamp: TimeInterval?
    for index in uniqueRows.indices {
      guard let timestamp = uniqueRows[index].timestamp,
            timestamp > 0 else {
        uniqueRows[index].timeDividerText = nil
        continue
      }
      let shouldShowDivider = index == uniqueRows.startIndex ||
        (previousTimestamp.map {
          !uniqueRows[index].suppressesTimeDivider && timestamp - $0 > 5 * 60
        } ?? !uniqueRows[index].suppressesTimeDivider)
      uniqueRows[index].timeDividerText = shouldShowDivider
        ? chatTimeDividerText(for: timestamp)
        : nil
      previousTimestamp = timestamp
    }
    return uniqueRows
  }

  private func loadedRowId(matching row: MessageRowState,
                           in rows: [MessageRowState]) -> String? {
    rows.first { existing in
      if existing.id == row.id || existing.serverId == row.id {
        return true
      }
      if let serverId = row.serverId, !serverId.isEmpty,
         existing.id == serverId || existing.serverId == serverId {
        return true
      }
      return sameMessage(existing, row)
    }?.id
  }

  private func syncReadState(for messages: [V2NIMMessage],
                             shouldSyncConversationRead: Bool = true) {
    guard canSynchronizeReadState else {
      return
    }

    for message in messages where isCurrentMessage(message) {
      pendingReadSyncMessagesById[ChatMessageMapper.stableMessageId(for: message)] = message
    }
    pendingConversationReadSync = pendingConversationReadSync || shouldSyncConversationRead
    schedulePendingReadSync()
  }

  private func clearConversationUnreadForChatLifecycle() {
    let conversationId = context.conversationId
    NotificationCenter.default.post(
      name: NENotificationName.conversationUnreadDidClearLocally,
      object: conversationId
    )
    let request = ChatReadSyncRequest(
      context: context,
      currentAccountId: currentAccountProvider(),
      isP2PReadReceiptEnabled: config.isP2PReadReceiptEnabled,
      isTeamReadReceiptEnabled: config.isTeamReadReceiptEnabled,
      shouldSyncConversationRead: true
    )
    readSynchronizer.sync(request) { result in
      switch result {
      case let .success(syncResult):
        NEChatSwiftUILogger.log(
          "conversationUnread lifecycleClear conversationId=\(conversationId) didClearUnread=\(syncResult.didClearUnread)"
        )
      case let .failure(error):
        // Match UIKit: unread cleanup failures are logged without adding a
        // second network warning on top of the existing offline banner.
        NEChatSwiftUILogger.log(
          "conversationUnread lifecycleClearFailed conversationId=\(conversationId) error=\((error as NSError).code)"
        )
      }
    }
  }

  private func flushPendingReadStateBeforePageExit() {
    guard state.route.currentRoute == nil,
          isPageVisible,
          hasConfirmedForegroundTimelineVisibility,
          isApplicationActiveProvider() else {
      return
    }

    pendingConversationReadSync = true
    readSyncDebounceTask?.cancel()
    readSyncDebounceTask = nil
    if isReadSyncInFlight {
      let messages = Array(pendingReadSyncMessagesById.values)
      pendingReadSyncMessagesById.removeAll()
      pendingConversationReadSync = false
      performReadStateSync(
        for: messages,
        shouldSyncConversationRead: true,
        completion: {}
      )
      return
    }
    startPendingReadSync()
  }

  private func schedulePendingReadSync() {
    guard !isReadSyncInFlight,
          canSynchronizeReadState else {
      return
    }
    readSyncDebounceTask?.cancel()
    let visibilityGeneration = pageVisibilityGeneration
    readSyncDebounceTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: readVisibilityConfirmationNanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled,
            let self,
            self.canSynchronizeReadState,
            self.pageVisibilityGeneration == visibilityGeneration else {
        return
      }
      self.readSyncDebounceTask = nil
      self.startPendingReadSync()
    }
  }

  private func startPendingReadSync() {
    guard !isReadSyncInFlight,
          canSynchronizeReadState else {
      discardPendingReadSync()
      return
    }
    let messages = Array(pendingReadSyncMessagesById.values)
    let shouldSyncConversationRead = pendingConversationReadSync
    pendingReadSyncMessagesById.removeAll()
    pendingConversationReadSync = false
    guard shouldSyncConversationRead || !messages.isEmpty else {
      return
    }

    isReadSyncInFlight = true
    performReadStateSync(
      for: messages,
      shouldSyncConversationRead: shouldSyncConversationRead
    ) { [weak self] in
      self?.finishReadStateSync()
    }
  }

  private func finishReadStateSync() {
    isReadSyncInFlight = false
    guard canSynchronizeReadState else {
      discardPendingReadSync()
      return
    }
    guard pendingConversationReadSync || !pendingReadSyncMessagesById.isEmpty else {
      return
    }
    schedulePendingReadSync()
  }

  private func discardPendingReadSync() {
    readSyncDebounceTask?.cancel()
    readSyncDebounceTask = nil
    pendingReadSyncMessagesById.removeAll()
    pendingConversationReadSync = false
  }

  private func performReadStateSync(for messages: [V2NIMMessage],
                                    shouldSyncConversationRead: Bool,
                                    completion: @escaping () -> Void) {
    guard canSynchronizeReadState else {
      completion()
      return
    }

    let currentMessages = messages.filter(isCurrentMessage)
    let request = ChatReadSyncRequest(
      context: context,
      messages: currentMessages,
      currentAccountId: currentAccountProvider(),
      isP2PReadReceiptEnabled: config.isP2PReadReceiptEnabled,
      isTeamReadReceiptEnabled: config.isTeamReadReceiptEnabled,
      shouldSyncConversationRead: shouldSyncConversationRead
    )

    guard shouldSyncConversationRead else {
      readSynchronizer.sync(request) { [weak self] result in
        Task { @MainActor [weak self] in
          defer { completion() }
          guard let self,
                self.canSynchronizeReadState else {
            return
          }
          switch result {
          case .success(let syncResult) where syncResult.markedMessageIds.isEmpty:
            break
          case .success(let syncResult):
            self.state.readSync.phase = .synced
            self.state.readSync.lastSyncedMessageIds = syncResult.markedMessageIds
          case .failure:
            self.handleReadSyncResult(result)
          }
        }
      }
      return
    }

    readSyncRequestGeneration += 1
    let generation = readSyncRequestGeneration
    state.readSync.phase = .syncing
    readSynchronizer.sync(request) { [weak self] result in
      Task { @MainActor [weak self] in
        defer { completion() }
        guard let self,
              self.canSynchronizeReadState,
              self.readSyncRequestGeneration == generation else {
          return
        }
        self.handleReadSyncResult(result)
      }
    }
  }

  private func handleReadSyncResult(_ result: Result<ChatReadSyncResult, Error>) {
    switch result {
    case .success(let syncResult):
      state.readSync = ChatReadSyncState(
        phase: .synced,
        lastReadTime: syncResult.readTime,
        lastSyncedMessageIds: syncResult.markedMessageIds,
        didClearUnread: syncResult.didClearUnread
      )
    case .failure(let error):
      if state.clientRuntime.shouldShowNetworkWarning || isNetworkFailure(error) {
        state.readSync.phase = .idle
        return
      }
      let message = NEChatErrorMessageMapper.message(
        for: error,
        fallbackKey: "chat_read_sync_failed",
        fallbackValue: "Read status sync failed"
      )
      state.readSync.phase = .failed(message)
      state.toast = ChatToastState(message: message, style: .warning)
    }
  }

  private var canSynchronizeReadState: Bool {
    didAppear &&
      isPageVisible &&
      hasConfirmedForegroundTimelineVisibility &&
      isApplicationActiveProvider()
  }

  private func refreshReadReceiptsIfNeeded(for messages: [V2NIMMessage]) {
    guard didAppear else {
      return
    }

    let currentMessages = messages.filter(isCurrentMessage)
    guard !currentMessages.isEmpty else {
      return
    }

    let targetIds = Set(currentMessages.map(ChatMessageMapper.stableMessageId(for:)))
    let targetRows = state.rows.filter { row in
      targetIds.contains(row.id) || row.serverId.map(targetIds.contains) == true
    }
    let request = ChatReadReceiptStateLoadRequest(
      conversationId: context.conversationId,
      kind: context.kind,
      messages: currentMessages,
      rows: targetRows,
      currentAccountId: currentAccountProvider(),
      teamReadReceiptDisplayLimit: config.maxTeamReadReceiptCount
    )
    guard request.shouldLoad else {
      return
    }

    let generation = readReceiptRefreshGeneration
    readReceiptLoader.load(request) { [weak self] result in
      Task { @MainActor in
        guard let self,
              self.readReceiptRefreshGeneration == generation else {
          return
        }
        self.applyLoadedReadReceipts(result)
      }
    }
  }

  private func applyLoadedReadReceipts(_ result: Result<[MessageRowState], Error>) {
    guard case .success(let rows) = result,
          !rows.isEmpty else {
      return
    }

    for row in rows {
      guard let readReceipt = row.readReceipt,
            let index = indexOfRow(matching: row.id),
            shouldApplyReadReceipt(to: state.rows[index]) else {
        continue
      }
      state.rows[index].readReceipt = readReceipt
      state.rows[index].deliveryState = .read
    }
  }

  private func shouldApplyReadReceipt(to row: MessageRowState) -> Bool {
    guard row.direction == .outgoing,
          row.isReadReceiptEnabled,
          !isRevoked(row.content) else {
      return false
    }

    switch row.deliveryState {
    case .sent, .read:
      return true
    default:
      return false
    }
  }

  private func isRevoked(_ content: MessageContentState) -> Bool {
    switch content {
    case .revoke:
      return true
    case let .reply(_, boxed):
      return isRevoked(boxed.value)
    default:
      return false
    }
  }

  private func applyHistoryAnchors(from loadResult: ChatHistoryLoadResult,
                                   placement: HistoryPlacement) {
    switch placement {
    case .prepend:
      state.oldestAnchorMessageId = loadResult.oldestAnchorMessageId ?? state.rows.first?.id
      oldestHistoryAnchorMessage = historyAnchorMessage(
        loadResult.oldestAnchorMessage,
        matching: state.oldestAnchorMessageId
      )
      state.newestAnchorMessageId = state.rows.last?.id ?? loadResult.newestAnchorMessageId
      newestHistoryAnchorMessage = historyAnchorMessage(
        newestHistoryAnchorMessage,
        matching: state.newestAnchorMessageId
      )
    case .append:
      state.oldestAnchorMessageId = state.rows.first?.id ?? loadResult.oldestAnchorMessageId
      oldestHistoryAnchorMessage = historyAnchorMessage(
        oldestHistoryAnchorMessage,
        matching: state.oldestAnchorMessageId
      )
      state.newestAnchorMessageId = loadResult.newestAnchorMessageId ?? state.rows.last?.id
      newestHistoryAnchorMessage = historyAnchorMessage(
        loadResult.newestAnchorMessage,
        matching: state.newestAnchorMessageId
      )
    }
  }

  private func applyFocusedHistoryAnchors(older: ChatHistoryLoadResult,
                                          newer: ChatHistoryLoadResult) {
    state.oldestAnchorMessageId = older.oldestAnchorMessageId ?? state.rows.first?.id
    oldestHistoryAnchorMessage = historyAnchorMessage(
      older.oldestAnchorMessage,
      matching: state.oldestAnchorMessageId
    )
    state.newestAnchorMessageId = newer.newestAnchorMessageId ?? state.rows.last?.id
    newestHistoryAnchorMessage = historyAnchorMessage(
      newer.newestAnchorMessage,
      matching: state.newestAnchorMessageId
    )
  }

  private func logHistoryRequest(_ request: ChatHistoryLoadRequest,
                                 placement: HistoryPlacement,
                                 generation: Int) {
    NEChatSwiftUILogger.log(
      "history request conversationId=\(context.conversationId) placement=\(placement.logName) direction=\(request.direction) generation=\(generation) anchorId=\(request.anchorMessageId ?? "nil") anchorClientId=\(request.anchorMessage?.messageClientId ?? "nil") rows=\(state.rows.count) hasMoreOlder=\(state.hasMoreOlder) hasMoreNewer=\(state.hasMoreNewer) isLoadingOlder=\(state.isLoadingOlder) isLoadingNewer=\(state.isLoadingNewer) scrollTarget=\(state.timelineScrollTarget?.id ?? "nil")"
    )
  }

  private func logHistoryResult(_ loadResult: ChatHistoryLoadResult,
                                placement: HistoryPlacement,
                                insertedCount: Int) {
    let uniqueRowIdCount = Set(state.rows.map(\.id)).count
    NEChatSwiftUILogger.log(
      "history result conversationId=\(context.conversationId) placement=\(placement.logName) loaded=\(loadResult.loadedMessageCount) rows=\(loadResult.rows.count) inserted=\(insertedCount) totalRows=\(state.rows.count) uniqueRowIds=\(uniqueRowIdCount) duplicateRowIds=\(duplicateRowIdsSummary()) hasMoreOlder=\(state.hasMoreOlder) hasMoreNewer=\(state.hasMoreNewer) oldest=\(state.oldestAnchorMessageId ?? "nil") newest=\(state.newestAnchorMessageId ?? "nil") nextOldest=\(loadResult.oldestAnchorMessageId ?? "nil") nextNewest=\(loadResult.newestAnchorMessageId ?? "nil")"
    )
  }

  private func logHistoryFailure(_ error: Error,
                                 placement: HistoryPlacement) {
    NEChatSwiftUILogger.log(
      "history failure conversationId=\(context.conversationId) placement=\(placement.logName) errorCode=\((error as NSError).code) rows=\(state.rows.count) hasMoreOlder=\(state.hasMoreOlder) hasMoreNewer=\(state.hasMoreNewer)"
    )
  }

  private func logHistoryTriggerBlocked(reason: String,
                                        visibleAnchorId: String?) {
    NEChatSwiftUILogger.log(
      "history trigger blocked conversationId=\(context.conversationId) reason=\(reason) visibleAnchorId=\(visibleAnchorId ?? "nil") rows=\(state.rows.count) hasMoreOlder=\(state.hasMoreOlder) hasMoreNewer=\(state.hasMoreNewer) isLoadingOlder=\(state.isLoadingOlder) isLoadingNewer=\(state.isLoadingNewer) oldest=\(state.oldestAnchorMessageId ?? "nil") newest=\(state.newestAnchorMessageId ?? "nil") scrollTarget=\(state.timelineScrollTarget?.id ?? "nil")"
    )
  }

  private func duplicateRowIdsSummary() -> String {
    var counts = [String: Int]()
    for row in state.rows {
      counts[row.id, default: 0] += 1
    }
    let duplicatedIds = counts
      .filter { $0.value > 1 }
      .keys
      .sorted()
    guard !duplicatedIds.isEmpty else {
      return "none"
    }
    return duplicatedIds.prefix(3).joined(separator: ",")
  }

  private func messageContextMessage(id: String?) -> V2NIMMessage? {
    guard let id, !id.isEmpty else {
      return nil
    }
    return messageContextById[id]
  }

  private func historyAnchorMessage(_ preferredMessage: V2NIMMessage?,
                                    matching id: String?) -> V2NIMMessage? {
    guard let id, !id.isEmpty else {
      return nil
    }
    if let preferredMessage,
       message(preferredMessage, matches: id) {
      return preferredMessage
    }
    return messageContextMessage(id: id)
  }

  private func message(_ message: V2NIMMessage,
                       matches id: String) -> Bool {
    if message.messageClientId == id || message.messageServerId == id {
      return true
    }
    return ChatMessageMapper.stableMessageId(for: message) == id
  }

  private func messageContextMessage(for row: MessageRowState) -> V2NIMMessage? {
    if let message = messageContextById[row.id] ??
      row.serverId.flatMap({ messageContextById[$0] }) {
      return message
    }
    let rowIds = messageIds(for: row)
    for id in rowIds {
      if let message = messageContextById[id] {
        return message
      }
    }
    return messageContextById.values.first { message in
      if message.messageClientId == row.id || message.messageServerId == row.id {
        return true
      }
      if let serverId = row.serverId,
         (message.messageClientId == serverId || message.messageServerId == serverId) {
        return true
      }
      return rowIds.contains(
        stableMessageLookupKey(
          conversationId: message.conversationId,
          senderId: message.senderId,
          createTime: message.createTime
        ) ?? ""
      )
    }
  }

  private enum HistoryPlacement {
    case prepend
    case append

    var logName: String {
      switch self {
      case .prepend:
        return "prepend"
      case .append:
        return "append"
      }
    }
  }

  private func firstExistingRowId(matching ids: [String?]) -> String? {
    for id in ids {
      guard let id, indexOfRow(matching: id) != nil else {
        continue
      }
      return id
    }
    return nil
  }

  @discardableResult
  private func mergeRows(_ rows: [MessageRowState], placement: HistoryPlacement) -> [MessageRowState] {
    guard !rows.isEmpty else { return [] }

    var existingRows = state.rows
    let uniqueRows = rows.filter { row in
      if existingRows.contains(where: { sameLoadedMessage($0, row) }) {
        return false
      }
      existingRows.append(row)
      return true
    }

    let displayReadyRows = uniqueRows.map(applyingDisplayCaches(to:))
    guard !displayReadyRows.isEmpty else { return [] }

    let insertedRange: Range<Int>?
    switch placement {
    case .prepend:
      state.rows = displayReadyRows + state.rows
      insertedRange = 0 ..< displayReadyRows.count
    case .append:
      let startIndex = state.rows.count
      state.rows.append(contentsOf: displayReadyRows)
      insertedRange = startIndex ..< state.rows.count
    }
    if shouldSortRowsAfterMerge(displayReadyRows, placement: placement) {
      state.rows.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
      refreshTimeDividers()
    } else {
      refreshTimeDividers(around: insertedRange)
    }
    _ = refreshConsistentSenderDisplayInfos()
    pruneMessageContext()
    refreshAnchors()
    refreshContactDisplayInfosIfNeeded(for: uniqueRows)
    refreshTeamMemberDisplayInfosIfNeeded(for: uniqueRows)
    return displayReadyRows
  }

  private func shouldSortRowsAfterMerge(_ rows: [MessageRowState],
                                        placement: HistoryPlacement) -> Bool {
    guard !rows.isEmpty else {
      return false
    }
    switch placement {
    case .prepend:
      guard let newestInsertedTimestamp = rows.last?.timestamp,
            let firstExistingTimestamp = state.rows.dropFirst(rows.count).first?.timestamp else {
        return false
      }
      return newestInsertedTimestamp > firstExistingTimestamp
    case .append:
      guard let oldestInsertedTimestamp = rows.first?.timestamp,
            state.rows.count > rows.count,
            let lastExistingTimestamp = state.rows.dropLast(rows.count).last?.timestamp else {
        return false
      }
      return oldestInsertedTimestamp < lastExistingTimestamp
    }
  }

  private func initialLatestScrollTargetIdIfNeeded(rows: [MessageRowState],
                                                   placement: HistoryPlacement) -> String? {
    guard placement == .prepend,
          pendingPrependAnchorId == nil,
          state.rows.isEmpty else {
      return nil
    }
    return rows.last?.id
  }

  private func restorePrependAnchorIfNeeded() {
    guard let anchorId = pendingPrependAnchorId,
          let anchorIndex = indexOfRow(matching: anchorId) else {
      clearPendingPrependRestore()
      state.isLoadingOlder = false
      return
    }

    let insertedCount = pendingPrependLoadedCount
    let restoredIndex = max(0, anchorIndex - (insertedCount > 0 ? 1 : 0))
    let scrollId = state.rows[restoredIndex].id
    NEChatSwiftUILogger.log(
      "history prepend anchor retained id=\(scrollId) anchorId=\(anchorId) anchorIndex=\(anchorIndex) restoredIndex=\(restoredIndex) rows=\(state.rows.count) inserted=\(insertedCount) tail=\(pendingPrependLoadedTailId ?? "nil")"
    )
    requestTimelineScroll(
      to: scrollId,
      anchor: .top,
      animated: false,
      reason: .prependRestore
    )
    clearPendingPrependRestore()
    state.isLoadingOlder = false
  }

  private func clearPendingPrependRestore() {
    pendingPrependAnchorId = nil
    pendingPrependLoadedCount = 0
    pendingPrependLoadedTailId = nil
  }

  private func upsertRows(_ rows: [MessageRowState]) {
    guard !rows.isEmpty else {
      return
    }

    for row in rows {
      replaceOrInsert(row: row, replacing: nil)
    }
    removeDuplicateRows()
    state.rows.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
    _ = refreshConsistentSenderDisplayInfos()
    pruneMessageContext()
    refreshTimeDividers()
    refreshAnchors()
    if !state.rows.isEmpty {
      state.phase = .loaded
    }
    syncTopicFromRowsIfNeeded(rows)
    refreshTopMessage()
    refreshContactDisplayInfosIfNeeded(for: rows)
    refreshTeamMemberDisplayInfosIfNeeded(for: rows)
    resolveRepliesIfNeeded(for: rows)
  }

  private func removeDuplicateRows() {
    var uniqueRows = [MessageRowState]()
    for row in state.rows {
      if let index = uniqueRows.firstIndex(where: { sameMessage($0, row) }) {
        uniqueRows[index] = preservingTransientMessageState(from: uniqueRows[index], into: row)
      } else {
        uniqueRows.append(row)
      }
    }
    state.rows = uniqueRows
  }

  private func replaceOrInsert(row: MessageRowState, replacing pendingId: String?) {
    let incomingRow = applyingDisplayCaches(to: row)
    if let pendingId,
       let pendingIndex = state.rows.firstIndex(where: { $0.id == pendingId }) {
      if let existingIndex = state.rows.firstIndex(where: { existing in
        existing.id != pendingId && sameMessage(existing, incomingRow)
      }) {
        state.rows[existingIndex] = preservingTransientMessageState(from: state.rows[existingIndex], into: incomingRow)
        state.rows.remove(at: pendingIndex)
      } else {
        state.rows[pendingIndex] = preservingTransientMessageState(from: state.rows[pendingIndex], into: incomingRow)
      }
      return
    }

    if let index = state.rows.firstIndex(where: { sameMessage($0, incomingRow) }) {
      state.rows[index] = preservingTransientMessageState(from: state.rows[index], into: incomingRow)
    } else {
      state.rows.append(incomingRow)
    }
  }

  private func messageRow(from message: V2NIMMessage) -> MessageRowState {
    let row = ChatMessageMapper.row(
      message: message,
      currentAccountId: currentAccountProvider(),
      imageThumbSize: config.imageThumbSize
    )
    return applyingOutgoingTextPresentation(
      to: row,
      aliases: newMessageAliases(for: message).union(messageIds(for: row))
    )
  }

  private func applyingConfig(to row: MessageRowState) -> MessageRowState {
    var next = row
    if let reedit = row.reedit {
      next.reedit = ChatReeditState(
        text: reedit.text,
        title: reedit.title,
        mentions: reedit.mentions,
        reply: reedit.reply,
        revokeTime: reedit.revokeTime,
        editTimeGapMinutes: config.revokeEditTimeGapMinutes
      )
    }
    if var readReceipt = row.readReceipt, !readReceipt.isP2PRead {
      readReceipt.displayLimit = config.maxTeamReadReceiptCount
      next.readReceipt = readReceipt
    }
    return next
  }

  private func applyingDisplayCaches(to row: MessageRowState) -> MessageRowState {
    var next = applyingConfig(to: row)
    next = applyingCachedContactDisplayInfo(to: next, matching: nil)
    if context.kind == .team {
      next = applyingTeamMemberDisplayInfos(teamMemberDisplayInfoByAccountId, to: next)
    }
    next = applyingKnownSenderDisplayInfo(senderDisplayInfoByAccountId, to: next, matching: nil)
    next = applyingPinnedDisplayInfo(to: next)
    next = applyingTeamReadReceiptDisplayState(to: next)
    return next
  }

  private func applyingTeamReadReceiptDisplayState(to row: MessageRowState) -> MessageRowState {
    guard context.kind == .team,
          row.direction == .outgoing,
          row.isReadReceiptEnabled,
          !isRevoked(row.content),
          let teamMemberCount,
          teamMemberCount > 0 else {
      return row
    }

    var next = row
    if var receipt = next.readReceipt {
      receipt.displayLimit = config.maxTeamReadReceiptCount
      next.readReceipt = receipt
    } else {
      next.readReceipt = MessageReadReceiptState(
        readCount: 0,
        unreadCount: max(0, teamMemberCount - 1),
        isP2PRead: false,
        displayLimit: config.maxTeamReadReceiptCount
      )
    }
    return next
  }

  private func refreshPinnedMessagesIfNeeded() {
    guard IMKitConfigCenter.shared.enablePinMessage,
          !state.clientRuntime.shouldShowNetworkWarning else {
      return
    }

    pinnedMessageRequestGeneration += 1
    let generation = pinnedMessageRequestGeneration
    ChatRepo.shared.getPinnedMessageList(conversationId: context.conversationId) { [weak self] pins, error in
      Task { @MainActor in
        guard let self,
              self.didAppear,
              self.pinnedMessageRequestGeneration == generation,
              error == nil,
              let pins else {
          return
        }
        self.applyPinnedMessages(pins)
      }
    }
  }

  private func applyPinnedMessages(_ pins: [V2NIMMessagePin]) {
    var nextInfo = [String: PinnedMessageDisplayInfo]()
    var operatorIds = [String]()

    for pin in pins {
      let ids = messageIds(from: pin.messageRefer)
      guard !ids.isEmpty else {
        continue
      }
      let operatorId = nonEmpty(pin.operatorId)
      let info = PinnedMessageDisplayInfo(
        operatorId: operatorId,
        operatorName: operatorId.map { displayNameForPinOperator($0) }
      )
      ids.forEach { nextInfo[$0] = info }
      if let operatorId {
        operatorIds.append(operatorId)
      }
    }

    didLoadPinnedMessageInfo = true
    pinnedMessageInfoById = nextInfo
    applyCachedPinnedDisplayInfos()
    refreshContactDisplayInfosIfNeeded(accountIds: operatorIds)
    if context.kind == .team {
      refreshTeamMemberDisplayInfosIfNeeded(accountIds: operatorIds)
    }
  }

  private func applyCachedPinnedDisplayInfos() {
    let updatedRows = state.rows.map(applyingPinnedDisplayInfo(to:))
    if updatedRows != state.rows {
      state.rows = updatedRows
    }

    if let topMessage = state.topMessage,
       let topRow = topMessage.row {
      let updatedTopRow = applyingPinnedDisplayInfo(to: topRow)
      if updatedTopRow != topRow {
        var nextTopMessage = topMessage
        nextTopMessage.row = updatedTopRow
        state.topMessage = nextTopMessage
      }
    }
    refreshTopMessage()
  }

  private func applyingPinnedDisplayInfo(to row: MessageRowState) -> MessageRowState {
    var next = row
    guard !isRevoked(row.content) else {
      next.isPinned = false
      next.pinOperatorId = nil
      next.pinOperatorName = nil
      return next
    }
    let ids = messageIds(for: row)
    if let info = ids.compactMap({ pinnedMessageInfoById[$0] }).first {
      next.isPinned = true
      next.pinOperatorId = info.operatorId
      next.pinOperatorName = info.operatorId.map { displayNameForPinOperator($0) } ?? info.operatorName
      return next
    }

    if didLoadPinnedMessageInfo {
      next.isPinned = false
      next.pinOperatorId = nil
      next.pinOperatorName = nil
    } else if !row.isPinned {
      next.pinOperatorId = nil
      next.pinOperatorName = nil
    }
    return next
  }

  private func setPinnedDisplayInfo(for ids: Set<String>,
                                    operatorId: String?,
                                    isPinned: Bool) {
    guard !ids.isEmpty else {
      return
    }

    if isPinned {
      let normalizedOperatorId = nonEmpty(operatorId) ?? currentAccountProvider()
      let info = PinnedMessageDisplayInfo(
        operatorId: normalizedOperatorId,
        operatorName: normalizedOperatorId.map { displayNameForPinOperator($0) }
      )
      ids.forEach { pinnedMessageInfoById[$0] = info }
    } else {
      ids.forEach { pinnedMessageInfoById.removeValue(forKey: $0) }
    }
  }

  private func refreshPinnedOperatorNames(matching accountIds: Set<String>?) {
    guard !pinnedMessageInfoById.isEmpty else {
      return
    }
    let targetIds = normalizedAccountIds(accountIds)
    var didChange = false

    for (messageId, info) in pinnedMessageInfoById {
      guard let operatorId = nonEmpty(info.operatorId),
            targetIds?.contains(operatorId) ?? true else {
        continue
      }
      let nextName = displayNameForPinOperator(operatorId)
      guard info.operatorName != nextName else {
        continue
      }
      pinnedMessageInfoById[messageId] = PinnedMessageDisplayInfo(
        operatorId: operatorId,
        operatorName: nextName
      )
      didChange = true
    }

    if didChange {
      applyCachedPinnedDisplayInfos()
    }
  }

  private func messageIds(for row: MessageRowState) -> Set<String> {
    var ids = Set([row.id, row.serverId].compactMap(nonEmpty))
    if let stableKey = stableMessageLookupKey(
      conversationId: row.conversationId ?? context.conversationId,
      senderId: row.senderId,
      createTime: row.timestamp
    ) {
      ids.insert(stableKey)
    }
    return ids
  }

  private func messageIds(from refer: V2NIMMessageRefer?) -> Set<String> {
    guard refer?.conversationId == context.conversationId else {
      return []
    }
    var ids = Set([refer?.messageClientId, refer?.messageServerId].compactMap(nonEmpty))
    if let stableKey = stableMessageLookupKey(
      conversationId: refer?.conversationId,
      senderId: refer?.senderId,
      createTime: refer?.createTime
    ) {
      ids.insert(stableKey)
    }
    return ids
  }

  private func displayNameForPinOperator(_ accountId: String) -> String {
    if currentAccountProvider() == accountId {
      return NEChatUIKitSwiftUIBundle.localized("You", value: "you")
    }
    if context.kind == .team,
       let displayName = nonEmpty(teamMemberDisplayInfoByAccountId[accountId]?.displayName) {
      return displayName
    }
    return nonEmpty(ChatRepo.swiftUIDisplayName(accountId: accountId, showAlias: true)) ??
      accountId
  }

  @discardableResult
  private func refreshConsistentSenderDisplayInfos(matching accountIds: Set<String>? = nil) -> Bool {
    let displayInfos = senderDisplayInfos(matching: accountIds)
    guard !displayInfos.isEmpty else {
      return false
    }

    var didChange = false
    let updatedRows = state.rows.map { row in
      let next = applyingKnownSenderDisplayInfo(displayInfos, to: row, matching: accountIds)
      if next != row {
        didChange = true
      }
      return next
    }
    if didChange {
      state.rows = updatedRows
    }

    if let topMessage = state.topMessage,
       let topRow = topMessage.row {
      let updatedTopRow = applyingKnownSenderDisplayInfo(displayInfos, to: topRow, matching: accountIds)
      if updatedTopRow != topRow {
        var nextTopMessage = topMessage
        nextTopMessage.row = updatedTopRow
        nextTopMessage.subtitle = updatedTopRow.senderName ?? updatedTopRow.senderId
        state.topMessage = nextTopMessage
        didChange = true
      }
    }

    return didChange
  }

  private func senderDisplayInfos(matching accountIds: Set<String>?) -> [String: SenderDisplayInfo] {
    let normalizedTargetIds = normalizedAccountIds(accountIds)
    var displayInfos = [String: SenderDisplayInfo]()

    func merge(accountId: String?, senderName: String?, avatarURL: URL?) {
      guard let accountId = normalizedAccountId(accountId),
            normalizedTargetIds?.contains(accountId) ?? true else {
        return
      }

      var displayInfo = displayInfos[accountId] ?? SenderDisplayInfo()
      if let senderName = nonEmpty(senderName),
         senderName != accountId || nonEmpty(displayInfo.senderName) == nil || displayInfo.senderName == accountId {
        displayInfo.senderName = senderName
      }
      if let avatarURL {
        displayInfo.avatarURL = avatarURL
      }
      displayInfos[accountId] = displayInfo
      senderDisplayInfoByAccountId[accountId] = mergedSenderDisplayInfo(
        primary: displayInfo,
        fallback: senderDisplayInfoByAccountId[accountId]
      )
    }

    for accountId in normalizedTargetIds ?? Set(senderDisplayInfoByAccountId.keys) {
      if let cachedInfo = senderDisplayInfoByAccountId[accountId] {
        merge(accountId: accountId, senderName: cachedInfo.senderName, avatarURL: cachedInfo.avatarURL)
      }
    }

    for row in state.rows {
      merge(accountId: row.senderId, senderName: row.senderName, avatarURL: row.avatarURL)
      merge(accountId: row.reply?.senderId, senderName: row.reply?.senderName, avatarURL: nil)
    }
    if let topRow = state.topMessage?.row {
      merge(accountId: topRow.senderId, senderName: topRow.senderName, avatarURL: topRow.avatarURL)
      merge(accountId: topRow.reply?.senderId, senderName: topRow.reply?.senderName, avatarURL: nil)
    }

    let sourceAccountIds = normalizedTargetIds ?? Set(
      (state.rows.flatMap { [$0.senderId, $0.reply?.senderId] } +
        [state.topMessage?.row?.senderId, state.topMessage?.row?.reply?.senderId])
        .compactMap(normalizedAccountId)
    )
    for accountId in sourceAccountIds {
      let display = cachedSenderDisplayInfo(accountId: accountId)
      merge(accountId: accountId, senderName: display.senderName, avatarURL: display.avatarURL)
    }

    return displayInfos.filter { _, displayInfo in
      displayInfo.senderName != nil || displayInfo.avatarURL != nil
    }
  }

  private func mergedSenderDisplayInfo(primary: SenderDisplayInfo,
                                       fallback: SenderDisplayInfo?) -> SenderDisplayInfo {
    guard let fallback else {
      return primary
    }
    return SenderDisplayInfo(
      senderName: nonEmpty(primary.senderName) ?? fallback.senderName,
      avatarURL: primary.avatarURL ?? fallback.avatarURL
    )
  }

  private func applyingKnownSenderDisplayInfo(_ displayInfos: [String: SenderDisplayInfo],
                                              to row: MessageRowState,
                                              matching accountIds: Set<String>?) -> MessageRowState {
    let normalizedTargetIds = normalizedAccountIds(accountIds)
    var next = row
    if let senderId = normalizedAccountId(row.senderId),
       normalizedTargetIds?.contains(senderId) ?? true,
       let displayInfo = displayInfos[senderId] {
      if let senderName = nonEmpty(displayInfo.senderName),
         senderName != senderId || nonEmpty(next.senderName) == nil {
        next.senderName = senderName
      }
      if displayInfo.avatarURL != nil {
        next.avatarURL = displayInfo.avatarURL
      }
    }

    if var reply = next.reply,
       let senderId = normalizedAccountId(reply.senderId),
       normalizedTargetIds?.contains(senderId) ?? true,
       let displayInfo = displayInfos[senderId],
       let senderName = nonEmpty(displayInfo.senderName),
       senderName != senderId || nonEmpty(reply.senderName) == nil {
      reply.senderName = senderName
      next.reply = reply
      if case let .reply(_, content) = next.content {
        next.content = .reply(preview: reply.displayPreview, content: content)
      }
    }
    return next
  }

  private func normalizedAccountIds(_ accountIds: Set<String>?) -> Set<String>? {
    guard let accountIds else {
      return nil
    }
    return Set(accountIds.compactMap(normalizedAccountId))
  }

  private func normalizedAccountId(_ accountId: String?) -> String? {
    nonEmpty(accountId)
  }

  private func preservingTransientMessageState(from existing: MessageRowState,
                                               into incoming: MessageRowState) -> MessageRowState {
    var next = incoming
    if nonEmpty(next.avatarName) == nil {
      next.avatarName = nonEmpty(existing.avatarName)
    }
    if case .revoke = incoming.content {
      next.isPinned = false
      next.pinOperatorId = nil
      next.pinOperatorName = nil
      next.isTopMessage = false
      next.reedit = mergingReeditState(existing: existing.reedit, incoming: incoming.reedit)
    } else {
      next.isTopMessage = incoming.isTopMessage || existing.isTopMessage
    }

    if incoming.direction == .outgoing,
       let readReceipt = existing.readReceipt,
       !isRevoked(incoming.content) {
      next.readReceipt = incoming.readReceipt ?? readReceipt
      if incoming.deliveryState == .sent {
        next.deliveryState = .read
      }
    }

    if incoming.direction == .outgoing,
       !isRevoked(incoming.content) {
      next.content = preservingOutgoingTextPresentation(
        from: existing.content,
        into: next.content
      )
      if next.textHighlights.isEmpty,
         !existing.textHighlights.isEmpty,
         isTextPresentation(next.content) {
        next.textHighlights = existing.textHighlights
      }
    }

    if let voiceToText = existing.voiceToText {
      next.voiceToText = incoming.voiceToText ?? voiceToText
      if case var .audio(audio) = next.content,
         audio.convertedText?.isEmpty != false,
         let convertedText = voiceToText.text,
         !convertedText.isEmpty {
        audio.convertedText = convertedText
        next.content = .audio(audio)
      }
    }
    next.content = preservingLocalMediaDisplayState(from: existing.content, into: next.content)
    if next.senderName?.isEmpty != false {
      next.senderName = existing.senderName
    }
    if next.avatarURL == nil {
      next.avatarURL = existing.avatarURL
    }
    if let senderId = normalizedAccountId(next.senderId) {
      let display = mergedSenderDisplayInfo(
        primary: SenderDisplayInfo(senderName: next.senderName, avatarURL: next.avatarURL),
        fallback: senderDisplayInfoByAccountId[senderId]
      )
      senderDisplayInfoByAccountId[senderId] = display
      if next.senderName?.isEmpty != false {
        next.senderName = display.senderName
      }
      if next.avatarURL == nil {
        next.avatarURL = display.avatarURL
      }
    }
    return next
  }

  private func rememberOutgoingTextPresentation(_ row: MessageRowState,
                                                aliases: Set<String>) {
    guard row.direction == .outgoing,
          isTextPresentation(row.content),
          !isRevoked(row.content) else {
      return
    }
    let presentation = OutgoingTextPresentation(
      content: row.content,
      textHighlights: row.textHighlights
    )
    aliases.union(messageIds(for: row)).forEach { alias in
      outgoingTextPresentationByMessageId[alias] = presentation
    }
  }

  private func applyingOutgoingTextPresentation(to row: MessageRowState,
                                                aliases: Set<String>) -> MessageRowState {
    guard row.direction == .outgoing,
          !isRevoked(row.content),
          let presentation = aliases.compactMap({ outgoingTextPresentationByMessageId[$0] }).first else {
      return row
    }
    var next = row
    next.content = preservingOutgoingTextPresentation(
      from: presentation.content,
      into: next.content
    )
    if next.textHighlights.isEmpty, !presentation.textHighlights.isEmpty {
      next.textHighlights = presentation.textHighlights
    }
    rememberOutgoingTextPresentation(next, aliases: aliases)
    return next
  }

  private func preservingOutgoingTextPresentation(from existing: MessageContentState,
                                                  into incoming: MessageContentState) -> MessageContentState {
    switch (existing, incoming) {
    case let (.richText(existingTitle, existingBody), .richText(incomingTitle, incomingBody)):
      let title = nonEmpty(incomingTitle) ?? existingTitle
      let body = incomingBody.isEmpty && !existingBody.isEmpty ? existingBody : incomingBody
      return .richText(title: title, body: body)
    case let (.richText(existingTitle, existingBody), .text(incomingText)):
      guard incomingText.isEmpty || incomingText == existingTitle else {
        return incoming
      }
      return .richText(title: existingTitle, body: existingBody)
    default:
      return incoming
    }
  }

  private func isTextPresentation(_ content: MessageContentState) -> Bool {
    switch content {
    case .text, .richText:
      return true
    default:
      return false
    }
  }

  private func mergingReeditState(existing: ChatReeditState?,
                                  incoming: ChatReeditState?) -> ChatReeditState? {
    guard var incoming else {
      return existing
    }
    guard let existing else {
      return incoming
    }
    if incoming.mentions.isEmpty {
      incoming.mentions = existing.mentions
    }
    if incoming.reply == nil ||
      (existing.reply?.isResolved == true && incoming.reply?.isResolved != true) {
      incoming.reply = existing.reply
    }
    return incoming
  }

  private func preservingLocalMediaDisplayState(from existing: MessageContentState,
                                                into incoming: MessageContentState) -> MessageContentState {
    switch (existing, incoming) {
    case let (.image(existingMedia), .image(incomingMedia)):
      return .image(preservingLocalMediaDisplayState(from: existingMedia, into: incomingMedia, promoteLocalVideoThumbnail: false))
    case let (.video(existingMedia), .video(incomingMedia)):
      return .video(preservingLocalMediaDisplayState(from: existingMedia, into: incomingMedia, promoteLocalVideoThumbnail: true))
    case let (.file(existingFile), .file(incomingFile)):
      var next = incomingFile
      if next.existingLocalPath == nil,
         existingFile.existingLocalPath != nil {
        next.localPath = existingFile.localPath
      }
      next.fileExtension = nonEmpty(next.fileExtension) ?? existingFile.fileExtension
      return .file(next)
    default:
      return incoming
    }
  }

  private func preservingLocalMediaDisplayState(from existing: MessageMediaState,
                                                into incoming: MessageMediaState,
                                                promoteLocalVideoThumbnail: Bool) -> MessageMediaState {
    var next = incoming
    if next.localPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
       existing.localPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
      next.localPath = existing.localPath
    }
    if next.thumbnailURL == nil {
      if promoteLocalVideoThumbnail,
         let localPath = next.localPath?.trimmingCharacters(in: .whitespacesAndNewlines),
         !localPath.isEmpty {
        next.thumbnailURL = URL(fileURLWithPath: localPath)
      } else {
        next.thumbnailURL = existing.thumbnailURL
      }
    }
    next.width = next.width ?? existing.width
    next.height = next.height ?? existing.height
    next.duration = next.duration ?? existing.duration
    return next
  }

  private func sameMessage(_ lhs: MessageRowState, _ rhs: MessageRowState) -> Bool {
    if sameLoadedMessage(lhs, rhs) {
      return true
    }
    if isPendingMediaMessage(lhs),
       rhs.direction == lhs.direction,
       rhs.senderId == lhs.senderId,
       roughlySameTimestamp(lhs.timestamp, rhs.timestamp),
       sameLocalMediaPayload(lhs.content, rhs.content) {
      return true
    }
    return false
  }

  private func sameLoadedMessage(_ lhs: MessageRowState, _ rhs: MessageRowState) -> Bool {
    if lhs.id == rhs.id {
      return true
    }
    if lhs.direction == .system || rhs.direction == .system {
      return false
    }
    guard let lhsServerId = nonEmpty(lhs.serverId),
          let rhsServerId = nonEmpty(rhs.serverId),
          lhsServerId != "0",
          rhsServerId != "0" else {
      return false
    }
    return lhsServerId == rhsServerId
  }

  private func stableMessageLookupKey(for row: MessageRowState) -> String? {
    stableMessageLookupKey(
      conversationId: row.conversationId ?? context.conversationId,
      senderId: row.senderId,
      createTime: row.timestamp
    )
  }

  private func stableMessageLookupKey(conversationId: String?,
                                      senderId: String?,
                                      createTime: TimeInterval?) -> String? {
    guard let conversationId = nonEmpty(conversationId),
          let senderId = nonEmpty(senderId),
          let createTime,
          createTime > 0 else {
      return nil
    }
    let normalizedTime = Int64((createTime * 1000).rounded())
    return "\(conversationId)|\(senderId)|\(normalizedTime)"
  }

  private func isPendingMediaMessage(_ row: MessageRowState) -> Bool {
    switch row.deliveryState {
    case .pending:
      switch row.content {
      case .audio, .image, .video, .file:
        return true
      default:
        return false
      }
    default:
      return false
    }
  }

  private func roughlySameTimestamp(_ lhs: TimeInterval?,
                                    _ rhs: TimeInterval?) -> Bool {
    guard let lhs, let rhs else {
      return true
    }
    return abs(lhs - rhs) < 5
  }

  private func sameLocalMediaPayload(_ lhs: MessageContentState,
                                     _ rhs: MessageContentState) -> Bool {
    switch (lhs, rhs) {
    case let (.image(left), .image(right)),
         let (.video(left), .video(right)):
      return sameLocalPath(left.localPath, right.localPath) ||
        sameMediaFingerprint(lhs, rhs)
    case let (.audio(left), .audio(right)):
      return sameLocalPath(left.localPath, right.localPath) ||
        sameMediaFingerprint(lhs, rhs)
    case let (.file(left), .file(right)):
      return sameLocalPath(left.localPath, right.localPath) ||
        sameMediaFingerprint(lhs, rhs)
    default:
      return false
    }
  }

  private func pendingMediaId(matching row: MessageRowState) -> String? {
    guard row.direction == .outgoing,
          let fingerprint = MessageMediaFingerprint(content: row.content) else {
      return nil
    }
    return pendingMediaFingerprints.first { key, value in
      guard let pendingRow = state.rows.first(where: { $0.id == key }),
            isPendingMediaMessage(pendingRow),
            pendingRow.senderId == row.senderId,
            roughlySameTimestamp(pendingRow.timestamp, row.timestamp) else {
        return false
      }
      return value.matches(fingerprint)
    }?.key
  }

  private func sameMediaFingerprint(_ lhs: MessageContentState,
                                    _ rhs: MessageContentState) -> Bool {
    guard let lhsFingerprint = MessageMediaFingerprint(content: lhs),
          let rhsFingerprint = MessageMediaFingerprint(content: rhs) else {
      return false
    }
    return lhsFingerprint.matches(rhsFingerprint)
  }

  private func sameLocalPath(_ lhs: String?,
                             _ rhs: String?) -> Bool {
    guard let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines),
          let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines),
          !lhs.isEmpty,
          !rhs.isEmpty else {
      return false
    }
    return lhs == rhs
  }

  private func updateDeliveryState(for id: String, deliveryState: MessageDeliveryState) {
    guard let index = state.rows.firstIndex(where: { $0.id == id }) else {
      return
    }
    state.rows[index].deliveryState = deliveryState
  }

  private func updateMediaContent(for id: String,
                                  media: MessageMediaState,
                                  kind: ChatMediaPreviewKind) {
    guard let index = state.rows.firstIndex(where: { $0.id == id }) else {
      return
    }
    switch kind {
    case .image:
      state.rows[index].content = .image(media)
    case .video:
      state.rows[index].content = .video(media)
    }
  }

  private func beginMediaDownload(rowId: String) -> Int {
    let nextGeneration = (mediaDownloadGenerationByMessageId[rowId] ?? 0) + 1
    mediaDownloadGenerationByMessageId[rowId] = nextGeneration
    updateDeliveryState(for: rowId, deliveryState: .pending(progress: 0))
    return nextGeneration
  }

  private func finishMediaDownloadIfCurrent(rowId: String, generation: Int) -> Bool {
    guard mediaDownloadGenerationByMessageId[rowId] == generation else {
      return false
    }
    mediaDownloadGenerationByMessageId[rowId] = nil
    return true
  }

  private func mediaDownloadPath(for row: MessageRowState,
                                 media: MessageMediaState,
                                 kind: ChatMediaPreviewKind,
                                 url: URL) -> String? {
    let directoryName = kind == .video ? "video" : "image"
    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)\(directoryName)/") else {
      return nil
    }
    let message = messageContextById[row.id] ?? row.serverId.flatMap { messageContextById[$0] }
    let attachment = message?.attachment as? V2NIMMessageFileAttachment
    let messageClientId = nonEmpty(message?.messageClientId)
    path += messageClientId ?? downloadFileBaseName(for: row, preferredMessageClientId: true)
    if let ext = attachmentFileExtension(attachment) ??
      normalizedFileExtension(attachment.map { ($0.name as NSString).pathExtension }) ??
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
    path += downloadFileBaseName(for: row)
    if let ext = normalizedFileExtension(file.fileExtension) ??
      downloadFileExtension(preferredPath: file.localPath, url: url, fallbackName: file.name) {
      path += ".\(ext)"
    }
    return path
  }

  private func audioDownloadPath(for row: MessageRowState,
                                 audio: MessageAudioState,
                                 url: URL) -> String? {
    if let localPath = audio.localPath?.trimmingCharacters(in: .whitespacesAndNewlines),
       !localPath.isEmpty {
      return localPath
    }

    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)audio/") else {
      return nil
    }
    path += downloadFileBaseName(for: row, preferredMessageClientId: true)
    if let ext = downloadFileExtension(preferredPath: audio.localPath, url: url, fallbackName: nil) {
      path += ".\(ext)"
    }
    return path
  }

  private func downloadFileBaseName(for row: MessageRowState,
                                    preferredMessageClientId: Bool = false) -> String {
    let messageClientId = preferredMessageClientId
      ? (messageContextById[row.id] ?? row.serverId.flatMap { messageContextById[$0] })?.messageClientId
      : nil
    let raw = nonEmpty(messageClientId) ?? (row.id.isEmpty ? UUID().uuidString : row.id)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let sanitized = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let name = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return name.isEmpty ? UUID().uuidString : name
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

	  private func audioWithUIKitCompatibleLocalPath(for row: MessageRowState,
	                                                 audio: MessageAudioState) -> MessageAudioState {
    guard audio.existingLocalPath == nil else {
      return audio
    }

    var next = audio
    guard let message = messageContextById[row.id] ?? row.serverId.flatMap({ messageContextById[$0] }),
          let attachment = message.attachment as? V2NIMMessageAudioAttachment else {
      return next
    }

    if next.url == nil {
      next.url = URL(string: attachment.url ?? "")
    }

    guard var path = NEPathUtils.getDirectoryForDocuments(dir: "\(imkitDir)audio/") else {
      return next
    }
    path += message.messageClientId ?? downloadFileBaseName(for: row)
    if let ext = attachment.ext,
       !ext.isEmpty,
       ext.count < 5 {
      path += ext.hasPrefix(".") ? ext : ".\(ext)"
    }
    next.localPath = path
    return next
  }

  private func downloadAudioAndPlay(row: MessageRowState,
                                    audio: MessageAudioState,
                                    url: URL,
                                    generation: Int,
                                    requiresLoadedRow: Bool,
                                    handler: ChatAudioPlaybackHandling) {
    guard let filePath = audioDownloadPath(for: row, audio: audio, url: url) else {
      handleAudioPlaybackResult(
        .failure(ChatAudioPlaybackError.unavailable),
        messageId: row.id,
        generation: generation,
        requiresLoadedRow: requiresLoadedRow
      )
      return
    }

    updateDeliveryState(for: row.id, deliveryState: .pending(progress: 0))
    resourceDownloader.downloadFile(urlString: url.absoluteString, filePath: filePath, progress: { [weak self] progress in
      Task { @MainActor in
        self?.updateDeliveryState(for: row.id, deliveryState: .pending(progress: Double(progress) / 100.0))
      }
    }) { [weak self] localPath, error in
      Task { @MainActor in
        guard let self,
              self.audioPlaybackGeneration == generation,
              !requiresLoadedRow || self.row(id: row.id) != nil else {
          return
        }

        self.updateDeliveryState(for: row.id, deliveryState: .sent)
        if let error {
          self.handleAudioPlaybackResult(
            .failure(error),
            messageId: row.id,
            generation: generation,
            requiresLoadedRow: requiresLoadedRow
          )
          return
        }

        var downloaded = audio
        downloaded.localPath = localPath ?? filePath
        self.updateAudioContent(for: row.id, audio: downloaded)
        let request = ChatAudioPlaybackRequest(messageId: row.id, audio: downloaded, context: self.context)
        self.state.audioPlayback = ChatAudioPlaybackState(messageId: row.id, phase: .playing)
        self.updateAudioPlayingState(messageId: row.id, isPlaying: true)
        handler.playAudio(request) { [weak self] result in
          Task { @MainActor in
            self?.handleAudioPlaybackResult(
              result,
              messageId: row.id,
              generation: generation,
              requiresLoadedRow: requiresLoadedRow
            )
          }
        }
      }
    }
  }

  private func updateAudioContent(for id: String, audio: MessageAudioState) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }
    state.rows[index].content = .audio(audio)
  }

  private enum ChatAudioPlaybackError: Error {
    case unavailable
  }

  private func setTimelineScrollTarget(_ target: ChatTimelineScrollTarget?) {
    let previous = state.timelineScrollTarget
    state.timelineScrollTarget = target
    NEChatSwiftUILogger.log(
      "chatAction scrollRequest publish previous=\(previous?.id ?? "nil") previousReason=\(previous?.reason.rawValue ?? "nil") next=\(target?.id ?? "nil") nextReason=\(target?.reason.rawValue ?? "nil") nextAgeMs=\(target?.ageMilliseconds.description ?? "nil") rows=\(state.rows.count) last=\(state.rows.last?.id ?? "nil") indicator=\(state.newMessageIndicator?.count.description ?? "nil") bottomVisible=\(isTimelineBottomVisible) keepsPinned=\(state.keepsTimelineBottomPinned)"
    )
  }

  private func requestTimelineScroll(to messageId: String,
                                     anchor: ChatTimelineScrollAnchor,
                                     animated: Bool = true,
                                     reason: ChatTimelineScrollTarget.Reason = .normal) {
    let targetsLatestRow = isLatestTimelineRow(messageId)
    NEChatSwiftUILogger.log(
      "chatAction scrollRequest start messageId=\(messageId) anchor=\(anchor.rawValue) reason=\(reason.rawValue) animated=\(animated) targetsLatest=\(targetsLatestRow) rows=\(state.rows.count) first=\(state.rows.first?.id ?? "nil") last=\(state.rows.last?.id ?? "nil") currentTarget=\(state.timelineScrollTarget?.id ?? "nil") bottomVisible=\(isTimelineBottomVisible) history=\(isHistoryContextActive)"
    )
    if anchor == .bottom,
       targetsLatestRow {
      isProgrammaticallyScrollingToLatest = true
    } else if !targetsLatestRow {
      markTimelineAwayFromLatestForProgrammaticScroll()
      clearPendingBottomScrollTargetBeforeExplicitAnchor()
    }
    scrollTargetSequence += 1
    let target = ChatTimelineScrollTarget(
      messageId: messageId,
      anchor: anchor,
      sequence: scrollTargetSequence,
      animated: animated,
      reason: reason,
      scopeId: scrollTargetScopeId
    )
    setTimelineScrollTarget(target)
    NEChatSwiftUILogger.log(
      "chatAction scrollRequest set targetId=\(target.id) messageId=\(target.messageId) anchor=\(target.anchor.rawValue) reason=\(target.reason.rawValue) animated=\(target.animated) ageMs=\(target.ageMilliseconds)"
    )
    if reason == .prependRestore {
      schedulePrependRestoreScrollTargetFallback(target.id)
    } else if reason == .initialLatest {
      scheduleInitialLatestScrollTargetFallback(target.id)
    }
  }

  private func clearPendingBottomScrollTargetBeforeExplicitAnchor() {
    guard let target = state.timelineScrollTarget,
          target.anchor == .bottom else {
      return
    }
    NEChatSwiftUILogger.log(
      "chatAction scrollRequest replacePendingBottom id=\(target.id) reason=\(target.reason.rawValue)"
    )
  }

  private func requestInitialLatestScrollTarget(to messageId: String) {
    shouldScrollToLatestAfterReload = false
    isProgrammaticallyScrollingToLatest = true
    scrollTargetSequence += 1
    let target = ChatTimelineScrollTarget(
      messageId: messageId,
      anchor: .bottom,
      sequence: scrollTargetSequence,
      animated: false,
      reason: .initialLatest,
      scopeId: scrollTargetScopeId
    )
    setTimelineScrollTarget(target)
    scheduleInitialLatestScrollTargetFallback(target.id)
  }

  private func clearInterruptedTimelineScrollTargetIfNeeded() {
    guard let target = state.timelineScrollTarget,
          target.reason != .prependRestore else {
      return
    }
    NEChatSwiftUILogger.log(
      "history scrollTarget clearOnUserScroll id=\(target.id) reason=\(target.reason.rawValue) rows=\(state.rows.count)"
    )
    setTimelineScrollTarget(nil)
  }

  private func scheduleInitialLatestScrollTargetFallback(_ targetId: String?) {
    guard let targetId else {
      return
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: initialLatestScrollTargetFallbackNanoseconds)
      guard self.state.timelineScrollTarget?.id == targetId,
            self.state.timelineScrollTarget?.reason == .initialLatest else {
        return
      }
      NEChatSwiftUILogger.log(
        "history scrollTarget autoConsume id=\(targetId) reason=initialLatest rows=\(self.state.rows.count)"
      )
      self.consumeTimelineScrollTarget(id: targetId)
    }
  }

  private func schedulePrependRestoreScrollTargetFallback(_ targetId: String) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: prependRestoreScrollTargetFallbackNanoseconds)
      guard self.state.timelineScrollTarget?.id == targetId,
            self.state.timelineScrollTarget?.reason == .prependRestore else {
        return
      }
      NEChatSwiftUILogger.log(
        "history scrollTarget autoConsume id=\(targetId) reason=prependRestore rows=\(self.state.rows.count)"
      )
      self.consumeTimelineScrollTarget(id: targetId)
    }
  }

  private func isLatestTimelineRow(_ messageId: String) -> Bool {
    guard let lastRow = state.rows.last else {
      return false
    }
    return lastRow.id == messageId || lastRow.serverId == messageId
  }

  private func markTimelineAwayFromLatestForProgrammaticScroll() {
    shouldScrollToLatestAfterReload = false
    cancelTimelineBottomPinning()
    isProgrammaticallyScrollingToLatest = false
    guard !state.rows.isEmpty else {
      return
    }
    isTimelineBottomVisible = false
    if isHistoryContextActive {
      showHistoryJumpIndicatorIfNeeded()
    } else {
      refreshNewMessageIndicatorState(requiresLatestReload: false)
    }
  }

  private func clearNewMessageIndicatorAndScrollToLatest() {
    if let lastId = state.rows.last?.id {
      beginTimelineBottomPinning()
      requestTimelineScroll(to: lastId, anchor: .bottom, animated: false, reason: .jumpToLatest)
    }
  }

  private func scrollTimelineToLatestForInputAreaChange() {
    if preservesPendingNewMessageIndicatorDuringRouteRestore ||
      hasPendingNewMessagesReceivedWhilePageHidden {
      cancelTimelineBottomPinning()
      return
    }
    guard let lastId = state.rows.last?.id else {
      return
    }
    beginTimelineBottomPinning()
    requestTimelineScroll(to: lastId, anchor: .bottom, animated: false, reason: .jumpToLatest)
  }

  private func requestScrollToLatestAfterOutgoingSend(preferredMessageId: String) {
    let targetId = state.rows.last?.id ?? preferredMessageId
    requestTimelineScroll(to: targetId, anchor: .bottom)
  }

  private func requestScrollToLatestAfterInsertedSendFailureTip(preferredMessageId: String) {
    let targetId = state.rows.last?.id ?? preferredMessageId
    beginTimelineBottomPinning()
    requestTimelineScroll(
      to: targetId,
      anchor: .bottom,
      animated: false,
      reason: .jumpToLatest
    )
  }

  private func beginTimelineBottomPinning() {
    timelineBottomPinGeneration += 1
    let generation = timelineBottomPinGeneration
    if !state.keepsTimelineBottomPinned {
      state.keepsTimelineBottomPinned = true
    }
    NEChatSwiftUILogger.log(
      "chatAction bottomPin begin generation=\(generation) rows=\(state.rows.count) last=\(state.rows.last?.id ?? "nil") target=\(state.timelineScrollTarget?.id ?? "nil") indicator=\(state.newMessageIndicator?.count.description ?? "nil")"
    )
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: initialBottomPinDurationNanoseconds)
      guard self.timelineBottomPinGeneration == generation else {
        return
      }
      self.state.keepsTimelineBottomPinned = false
      NEChatSwiftUILogger.log(
        "chatAction bottomPin end generation=\(generation) rows=\(self.state.rows.count) last=\(self.state.rows.last?.id ?? "nil") target=\(self.state.timelineScrollTarget?.id ?? "nil") indicator=\(self.state.newMessageIndicator?.count.description ?? "nil") bottomVisible=\(self.isTimelineBottomVisible)"
      )
    }
  }

  private func cancelTimelineBottomPinning() {
    timelineBottomPinGeneration += 1
    state.keepsTimelineBottomPinned = false
    NEChatSwiftUILogger.log(
      "chatAction bottomPin cancel generation=\(timelineBottomPinGeneration) rows=\(state.rows.count) target=\(state.timelineScrollTarget?.id ?? "nil")"
    )
  }

  private func clearNewMessageIndicatorIfNeeded(afterConsuming target: ChatTimelineScrollTarget?) {
    guard let target,
          target.anchor == .bottom,
          target.messageId == state.rows.last?.id else {
      NEChatSwiftUILogger.log(
        "chatAction jumpDown consumeClear skip target=\(target?.id ?? "nil") reason=\(target?.reason.rawValue ?? "nil") messageId=\(target?.messageId ?? "nil") last=\(state.rows.last?.id ?? "nil") anchor=\(target?.anchor.rawValue ?? "nil") bottomVisible=\(isTimelineBottomVisible) indicator=\(state.newMessageIndicator?.count.description ?? "nil")"
      )
      return
    }
    isProgrammaticallyScrollingToLatest = false
    NEChatSwiftUILogger.log(
      "chatAction jumpDown consumeClear target=\(target.id) ageMs=\(target.ageMilliseconds) bottomVisible=\(isTimelineBottomVisible) indicator=\(state.newMessageIndicator?.count.description ?? "nil") pending=\(pendingNewMessageIds.count) keepsPinned=\(state.keepsTimelineBottomPinned)"
    )
    if isTimelineBottomVisible {
      setNewMessageIndicator(nil)
      clearPendingNewMessageIds()
    } else {
      restoreJumpIndicatorIfLatestStillHidden()
    }
  }

  private func restoreJumpIndicatorIfLatestStillHidden() {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 120_000_000)
      guard self.state.timelineScrollTarget == nil,
            !self.isTimelineBottomVisible,
            self.state.newMessageIndicator == nil,
            !self.state.keepsTimelineBottomPinned,
            !self.state.rows.isEmpty,
            self.state.multiSelect == nil else {
        return
      }
      self.refreshNewMessageIndicatorState(requiresLatestReload: self.isHistoryContextActive)
    }
  }

  private func shouldStickToBottom(for rows: [MessageRowState]) -> Bool {
    guard !rows.isEmpty,
          isPageVisible,
          state.multiSelect == nil else {
      return false
    }
    // When the indicator is already shown, the user has scrolled away from the bottom.
    // New messages should update the indicator count, not override user scroll position.
    // This enforces mutual exclusivity between the indicator and auto-scroll behavior.
    guard state.newMessageIndicator == nil else {
      return false
    }

    // UIKit inserts the first incoming message directly at the bottom while
    // this chat page is active. SwiftUI's bottom geometry can be stale until
    // after that insertion, which previously deferred the first scroll until
    // the next message arrived. Once an indicator exists, the user has
    // explicitly remained away from the latest message and auto-scroll stops.
    return true
  }

  private func updateContent(for id: String, content: MessageContentState) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }
    state.rows[index].content = content
  }

  private func applyRevokeResult(id: String, row: MessageRowState?) {
    let wasAtBottom = isTimelineBottomVisible && !isHistoryContextActive
    clearTeamTopMessageIfRevoked(
      ids: Set([id, row?.id, row?.serverId].compactMap(nonEmpty))
    )
    guard IMKitConfigCenter.shared.enableInsertLocalMsgWhenRevoke else {
      removeRows(ids: Set([id, row?.id, row?.serverId].compactMap { $0 }))
      keepTimelineAtBottomAfterRevokeIfNeeded(wasAtBottom: wasAtBottom)
      return
    }

    if var row {
      row.reply = nil
      upsertRows([row])
      applyRevokeContent(
        ids: Set([id, row.id, row.serverId].compactMap { $0 }),
        reedit: row.reedit
      )
    } else {
      applyRevokeContent(ids: [id], reedit: nil)
    }
    keepTimelineAtBottomAfterRevokeIfNeeded(wasAtBottom: wasAtBottom)
  }

  private typealias MessageRevokeIds = (clientId: String?, serverId: String?)

  private func messageRevokeIds(from notification: V2NIMMessageRevokeNotification) -> MessageRevokeIds? {
    let clientId = notification.messageRefer?.messageClientId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let serverId = notification.messageRefer?.messageServerId?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clientId?.isEmpty == false || serverId?.isEmpty == false else {
      return nil
    }
    return (clientId, serverId)
  }

  private func applyRevokeNotification(ids: MessageRevokeIds,
                                       notification: V2NIMMessageRevokeNotification) {
    let idSet = Set([ids.clientId, ids.serverId].compactMap { $0 }.filter { !$0.isEmpty })
    guard !idSet.isEmpty else {
      return
    }

    let didDiscardPendingMessage = discardPendingNewMessages(matching: idSet)
    let requiresLatestReload = state.newMessageIndicator?.requiresLatestReload == true
    let wasAtBottom = isTimelineBottomVisible && !isHistoryContextActive
    clearTeamTopMessageIfRevoked(ids: idSet)
    if IMKitConfigCenter.shared.enableInsertLocalMsgWhenRevoke {
      let reedit = reeditState(from: notification, existingRow: row(matching: ids))
      applyRevokeContent(ids: idSet, reedit: reedit)
    } else {
      removeRows(ids: idSet)
    }
    if didDiscardPendingMessage {
      refreshNewMessageIndicatorState(requiresLatestReload: requiresLatestReload)
    }
    keepTimelineAtBottomAfterRevokeIfNeeded(wasAtBottom: wasAtBottom)
  }

  private func keepTimelineAtBottomAfterRevokeIfNeeded(wasAtBottom: Bool) {
    guard wasAtBottom, let lastId = state.rows.last?.id else {
      return
    }
    beginTimelineBottomPinning()
    requestTimelineScroll(
      to: lastId,
      anchor: .bottom,
      animated: false,
      reason: .jumpToLatest
    )
  }

  private func applyRevokeContent(ids: Set<String>, reedit: ChatReeditState?) {
    guard !ids.isEmpty,
          let index = state.rows.firstIndex(where: { ids.contains($0.id) || $0.serverId.map(ids.contains) == true }) else {
      return
    }

    let rowId = state.rows[index].id
    let voiceToTextIds = Set([rowId, state.rows[index].serverId].compactMap { $0 }).union(ids)
    for id in voiceToTextIds {
      voiceToTextRequestIds[id] = nil
    }
    state.rows[index].voiceToText = nil
    state.rows[index].content = .revoke(NEChatUIKitSwiftUIBundle.localized("message_recalled", value: "Message recalled"))
    state.rows[index].isReadReceiptEnabled = false
    state.rows[index].readReceipt = nil
    state.rows[index].reply = nil
    state.rows[index].reedit = mergingReeditState(
      existing: state.rows[index].reedit,
      incoming: reedit
    )
    clearPinStateAfterRevoke(id: state.rows[index].id)
    markMissingReplies(ids: ids)
    resolveRepliesIfNeeded(for: [state.rows[index]])
  }

  private func reeditState(from notification: V2NIMMessageRevokeNotification,
                           existingRow: MessageRowState?) -> ChatReeditState? {
    guard let existingRow,
          let currentAccount = currentAccountProvider(),
          existingRow.senderId == currentAccount,
          let json = NECommonUtil.getDictionaryFromJSONString(notification.serverExtension ?? "") as? [String: Any],
          json[revokeLocalMessage] as? Bool == true,
          let text = json[revokeLocalMessageContent] as? String,
          !text.isEmpty,
          !isAIResponseRow(existingRow) else {
      return nil
    }

    return ChatReeditState(
      text: text,
      title: json[revokeLocalMessageTitle] as? String,
      mentions: mentionStates(fromServerExtension: notification.serverExtension, in: text),
      reply: existingRow.reedit?.reply ?? existingRow.reply,
      revokeTime: revokeTime(from: json),
      editTimeGapMinutes: config.revokeEditTimeGapMinutes
    )
  }

  private func mentionStates(fromServerExtension serverExtension: String?,
                             in text: String) -> [ChatMentionState] {
    guard IMKitConfigCenter.shared.enableAtMessage,
          let serverExtension,
          let json = NECommonUtil.getDictionaryFromJSONString(serverExtension) as? [String: Any],
          let mentionDictionary = json["yxAitMsg"] as? [String: Any] else {
      return []
    }

    var mentions = [ChatMentionState]()
    for (accountId, value) in mentionDictionary {
      guard let dictionary = dictionaryValue(value),
            let segments = dictionary["segments"] as? [Any] else {
        continue
      }

      let displayText = ((dictionary["text"] as? String) ?? "")
        .trimmingCharacters(in: .whitespaces)
      guard !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !displayText.isEmpty else {
        continue
      }

      for segmentValue in segments {
        guard let segment = dictionaryValue(segmentValue),
              let start = integerValue(segment["start"]),
              let end = integerValue(segment["end"]),
              let range = mentionRange(start: start, end: end, displayText: displayText, in: text) else {
          continue
        }
        mentions.append(ChatMentionState(
          accountId: accountId,
          displayText: displayText,
          start: range.lowerBound,
          end: range.upperBound - 1
        ))
      }
    }
    return mentions
  }

  private func mentionRange(start: Int,
                            end: Int,
                            displayText: String,
                            in text: String) -> Range<Int>? {
    guard start >= 0, start <= end else {
      return nil
    }

    let candidates = [
      start ..< end,
      start ..< (end + 1),
    ]

    for candidate in candidates where mentionRange(candidate, matches: displayText, in: text) {
      return candidate
    }

    return nearestRange(
      of: displayText.trimmingCharacters(in: .whitespacesAndNewlines),
      in: text,
      preferredStart: start,
      excluding: []
    )
  }

  private func mentionRange(_ range: Range<Int>,
                            matches displayText: String,
                            in text: String) -> Bool {
    guard range.lowerBound >= 0,
          range.lowerBound < range.upperBound,
          range.upperBound <= text.utf16.count else {
      return false
    }
    let substring = (text as NSString).substring(with: NSRange(
      location: range.lowerBound,
      length: range.count
    ))
    guard substring.first?.isWhitespace != true else {
      return false
    }
    return substring.trimmingCharacters(in: .whitespacesAndNewlines) ==
      displayText.trimmingCharacters(in: .whitespacesAndNewlines)
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

  private func integerValue(_ value: Any?) -> Int? {
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

  private func revokeTime(from json: [String: Any]) -> TimeInterval {
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
    return Date().timeIntervalSince1970
  }

  private func isAIResponseRow(_ row: MessageRowState?) -> Bool {
    guard let row else {
      return false
    }
    if case .aiStream = row.content {
      return true
    }
    return row.senderId != currentAccountProvider() && context.kind == .p2p && row.direction == .incoming
  }

  private func row(matching ids: MessageRevokeIds) -> MessageRowState? {
    state.rows.first { row in
      ids.clientId.map { row.id == $0 } == true ||
        ids.serverId.map { row.serverId == $0 } == true
    }
  }

  private func clearPinStateAfterRevoke(id: String) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }
    pinnedMessageRequestGeneration += 1
    setPinnedDisplayInfo(for: messageIds(for: state.rows[index]), operatorId: nil, isPinned: false)
    state.rows[index].isPinned = false
    state.rows[index].pinOperatorId = nil
    state.rows[index].pinOperatorName = nil
    if state.rows[index].isTopMessage {
      clearTeamTopMessage()
      return
    }
    refreshTopMessage()
  }

  private func clearTeamTopMessageIfRevoked(ids: Set<String>) {
    guard !ids.isEmpty,
          case .teamTop = state.topMessage?.source,
          let topMessage = state.topMessage else {
      return
    }
    var topMessageIds = Set([topMessage.id].compactMap(nonEmpty))
    if let topRow = topMessage.row ?? row(id: topMessage.id) {
      topMessageIds.formUnion(messageIds(for: topRow))
    }
    guard !topMessageIds.isDisjoint(with: ids) else {
      return
    }
    topMessageRequestGeneration += 1
    clearTeamTopMessage()
  }

  private func updateReply(for id: String, replyMessage: V2NIMMessage?) {
    if let replyMessage {
      cacheMessageContext([replyMessage])
    }
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }),
          let pendingReply = replyForResolution(in: state.rows[index]) else {
      return
    }

    let resolvedReply = ChatMessageMapper.resolvingReply(
      pendingReply,
      with: replyMessage,
      currentAccountId: currentAccountProvider(),
      imageThumbSize: config.imageThumbSize
    )
    applyResolvedReply(resolvedReply, toRowAt: index)
    refreshTeamMemberDisplayInfosIfNeeded(for: [state.rows[index]])
  }

  private func resolveRepliesIfNeeded(for rows: [MessageRowState]) {
    for row in rows {
      guard let reply = replyForResolution(in: row),
            replyResolutionRequestIds[row.id] == nil else {
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
          V2NIMConversationIdUtil.conversationType(context.conversationId),
        createTime: reply.createTime
      )
      let requestId = UUID()
      replyResolutionRequestIds[row.id] = requestId
      ChatRepo.shared.findReplyMessage(reference: reference) { [weak self] replyMessage, _ in
        Task { @MainActor in
          guard let self,
                self.replyResolutionRequestIds[row.id] == requestId,
                self.row(id: row.id) != nil else {
            return
          }
          self.replyResolutionRequestIds[row.id] = nil
          self.updateReply(for: row.id, replyMessage: replyMessage)
        }
      }
    }
  }

  private func findResolvedReplyRow(for reply: MessageReplyState) -> MessageRowState? {
    state.rows.first { row in
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
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }),
          var reply = replyForResolution(in: state.rows[index]) else {
      return
    }

    reply.senderId = replyRow.senderId ?? reply.senderId
    reply.senderName = replyRow.senderName ?? reply.senderName
    reply.conversationId = replyRow.conversationId ?? reply.conversationId
    reply.conversationType = V2NIMConversationIdUtil.conversationType(replyRow.conversationId ?? context.conversationId).rawValue
    reply.preview = ChatMessageMapper.referencePreviewText(for: replyRow.content)
    reply.resolvedContent = BoxedMessageContentState(replyRow.content)
    reply.isResolved = true
    applyResolvedReply(reply, toRowAt: index)
    refreshTeamMemberDisplayInfosIfNeeded(for: [state.rows[index], replyRow])
  }

  private func replyForResolution(in row: MessageRowState) -> MessageReplyState? {
    if let reply = row.reply, !reply.isResolved {
      return reply
    }
    if let reply = row.reedit?.reply, !reply.isResolved {
      return reply
    }
    return nil
  }

  private func applyResolvedReply(_ reply: MessageReplyState,
                                  toRowAt index: Int) {
    guard state.rows.indices.contains(index) else {
      return
    }

    if state.rows[index].reply != nil {
      state.rows[index].reply = reply
      if case let .reply(_, content) = state.rows[index].content {
        state.rows[index].content = .reply(preview: reply.displayPreview, content: content)
      }
    }
    if var reedit = state.rows[index].reedit, reedit.reply != nil {
      reedit.reply = reply
      state.rows[index].reedit = reedit
    }
    syncInputReplyIfNeeded(reply, sourceRowId: state.rows[index].id)
  }

  private func syncInputReplyIfNeeded(_ reply: MessageReplyState,
                                      sourceRowId: String) {
    guard let inputReply = state.input.reply else {
      return
    }
    let matchingIds = Set([reply.messageClientId, reply.messageServerId, sourceRowId].compactMap { $0 })
    guard matchingIds.contains(inputReply.id) else {
      return
    }
    state.input.reply = ChatReplyState(
      id: inputReply.id,
      preview: reply.preview ?? NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found"),
      senderName: reply.senderName ?? reply.senderId
    )
  }

  private func updatePinState(for id: String,
                              isPinned: Bool,
                              operatorId: String? = nil) {
    let ids = messageIdsForRowLookup(id)
    setPinnedDisplayInfo(for: ids, operatorId: operatorId, isPinned: isPinned)
    guard let index = state.rows.firstIndex(where: { ids.contains($0.id) || $0.serverId.map(ids.contains) == true }) else {
      return
    }
    state.rows[index].isPinned = isPinned
    if isPinned {
      state.rows[index] = applyingPinnedDisplayInfo(to: state.rows[index])
    } else {
      state.rows[index].pinOperatorId = nil
      state.rows[index].pinOperatorName = nil
    }
  }

  private func messageIdsForRowLookup(_ id: String) -> Set<String> {
    var ids = Set([id])
    if let row = row(id: id) {
      ids.insert(row.id)
      if let serverId = row.serverId, !serverId.isEmpty {
        ids.insert(serverId)
      }
    }
    if let message = messageContextById[id] {
      if let clientId = message.messageClientId, !clientId.isEmpty {
        ids.insert(clientId)
      }
      if let serverId = message.messageServerId, !serverId.isEmpty {
        ids.insert(serverId)
      }
      if let stableKey = stableMessageLookupKey(
        conversationId: message.conversationId,
        senderId: message.senderId,
        createTime: message.createTime
      ) {
        ids.insert(stableKey)
      }
    }
    return ids
  }

  private func refreshTopMessage() {
    guard context.kind == .team else {
      state.topMessage = nil
      return
    }

    if let row = state.rows.first(where: { $0.isTopMessage }) {
      let canClose: Bool
      if case let .teamTop(currentCanClose) = state.topMessage?.source {
        canClose = currentCanClose
      } else {
        canClose = false
      }
      state.topMessage = TopMessageState(
        id: row.id,
        title: ChatMessageMapper.referencePreviewText(for: row.content),
        subtitle: row.senderName ?? row.senderId,
        source: .teamTop(canClose: canClose),
        row: row
      )
      return
    }

    if case let .teamTop(canClose) = state.topMessage?.source,
       let row = state.topMessage?.row {
      state.topMessage = TopMessageState(
        id: row.id,
        title: ChatMessageMapper.referencePreviewText(for: row.content),
        subtitle: row.senderName ?? row.senderId,
        source: .teamTop(canClose: canClose),
        row: row
      )
      return
    }

    state.topMessage = nil
  }

  private func applyTeamTopMessage(row: MessageRowState?, canClose: Bool) {
    clearTopMessageFlag()
    guard var row else {
      refreshTopMessage()
      return
    }

    row.isTopMessage = true
    if let index = state.rows.firstIndex(where: { sameMessage($0, row) }) {
      state.rows[index].isTopMessage = true
      row = state.rows[index]
    }

    state.topMessage = TopMessageState(
      id: row.id,
      title: ChatMessageMapper.referencePreviewText(for: row.content),
      subtitle: row.senderName ?? row.senderId,
      source: .teamTop(canClose: canClose),
      row: row
    )
  }

  private func clearTeamTopMessage() {
    let shouldKeepTimelineAtBottom = state.topMessage != nil &&
      isTimelineBottomVisible &&
      !isHistoryContextActive
    clearTopMessageFlag()
    refreshTopMessage()
    guard shouldKeepTimelineAtBottom else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self,
            self.isPageVisible,
            self.isTimelineBottomVisible,
            !self.isHistoryContextActive else {
        return
      }
      self.scrollTimelineToLatestForInputAreaChange()
    }
  }

  private func clearTopMessageFlag() {
    state.rows = state.rows.map { row in
      guard row.isTopMessage else {
        return row
      }
      var next = row
      next.isTopMessage = false
      return next
    }
    if case .teamTop = state.topMessage?.source {
      state.topMessage = nil
    }
  }

  private static func teamId(from context: ChatSessionContext) -> String? {
    if let sessionId = context.sessionId, !sessionId.isEmpty {
      return sessionId
    }
    if let targetId = V2NIMConversationIdUtil.conversationTargetId(context.conversationId), !targetId.isEmpty {
      return targetId
    }
    return context.conversationId.isEmpty ? nil : context.conversationId
  }

  private func appendNewMessageIndicator(for rows: [MessageRowState],
                                         requiresLatestReload: Bool = false) {
    let incomingRows = rows.filter { $0.direction == .incoming }
    guard !incomingRows.isEmpty else {
      return
    }

    if state.multiSelect != nil {
      receivedMessagesWhileMultiSelect = true
    }
    appendPendingNewMessageRows(incomingRows)
    refreshNewMessageIndicatorState(
      requiresLatestReload: requiresLatestReload || state.newMessageIndicator?.requiresLatestReload == true
    )
  }

  private func appendPendingNewMessageRows(_ rows: [MessageRowState]) {
    guard !rows.isEmpty else {
      return
    }

    var existingAliases = Set(pendingNewMessageIds.flatMap(\.aliases))
    for row in rows where !isPendingNewMessageVisible(row) {
      let aliases = newMessageAliases(for: row)
      guard !aliases.isEmpty,
            existingAliases.isDisjoint(with: aliases) else {
        continue
      }
      existingAliases.formUnion(aliases)
      pendingNewMessageIds.append(PendingNewMessageItem(primaryId: row.id, aliases: aliases))
    }
  }

  private func appendPendingHistoryNewMessages(_ messages: [V2NIMMessage]) {
    guard !messages.isEmpty else {
      return
    }

    var existingIds = Set(pendingCurrentMessages().flatMap(newMessageAliases(for:)))
    for message in messages where isCurrentMessage(message) {
      let aliases = newMessageAliases(for: message)
      guard !aliases.isEmpty,
            existingIds.isDisjoint(with: aliases) else {
        continue
      }
      existingIds.formUnion(aliases)
      pendingHistoryNewMessages.append(message)
    }
  }

  private func refreshNewMessageIndicatorAfterVisibleRowsChange() {
    guard state.newMessageIndicator != nil || !pendingNewMessageIds.isEmpty else {
      return
    }

    if isTimelineBottomVisible {
      if receivedMessagesWhilePageHidden, !pendingNewMessageIds.isEmpty {
        return
      }
      if !pendingNewMessageIds.isEmpty {
        clearPendingNewMessageIds()
      }
      setNewMessageIndicator(nil)
      return
    }

    let previousIds = pendingNewMessageIds
    pendingNewMessageIds.removeAll { item in
      !item.aliases.isDisjoint(with: visibleTimelineRowIds)
    }

    if previousIds != pendingNewMessageIds {
      // Every pending incoming message is already on screen. Do not replace a
      // count-bearing indicator with the generic zero-count jump-down arrow.
      guard !pendingNewMessageIds.isEmpty else {
        setNewMessageIndicator(nil)
        return
      }
      refreshNewMessageIndicatorState(
        requiresLatestReload: state.newMessageIndicator?.requiresLatestReload == true
      )
    }
  }

  private func refreshNewMessageIndicatorState(requiresLatestReload: Bool) {
    guard state.multiSelect == nil else {
      return
    }

    if isTimelineBottomVisible, isPageVisible {
      if receivedMessagesWhilePageHidden, !pendingNewMessageIds.isEmpty {
        let firstMessageId = pendingNewMessageIds.first?.primaryId ?? state.rows.last?.id
        guard let firstMessageId else {
          return
        }
        setNewMessageIndicator(
          NewMessageIndicatorState(
            count: pendingNewMessageIds.count,
            firstMessageId: firstMessageId,
            requiresLatestReload: requiresLatestReload || state.newMessageIndicator?.requiresLatestReload == true
          )
        )
        return
      }
      clearPendingNewMessageIds()
      setNewMessageIndicator(nil)
      return
    }

    let count = pendingNewMessageIds.count
    let firstMessageId = count > 0 ? pendingNewMessageIds.first?.primaryId : state.rows.last?.id
    guard firstMessageId != nil else {
      setNewMessageIndicator(nil)
      return
    }
    setNewMessageIndicator(
      NewMessageIndicatorState(
        count: count,
        firstMessageId: firstMessageId,
        requiresLatestReload: requiresLatestReload || state.newMessageIndicator?.requiresLatestReload == true
      )
    )
  }

  private func setNewMessageIndicator(_ indicator: NewMessageIndicatorState?) {
    guard state.newMessageIndicator != indicator else {
      return
    }
    let previous = state.newMessageIndicator
    state.newMessageIndicator = indicator
    NEChatSwiftUILogger.log(
      "chatAction indicator set previous=\(previous?.count.description ?? "nil") previousFirst=\(previous?.firstMessageId ?? "nil") next=\(indicator?.count.description ?? "nil") nextFirst=\(indicator?.firstMessageId ?? "nil") nextReload=\(indicator?.requiresLatestReload.description ?? "nil") target=\(state.timelineScrollTarget?.id ?? "nil") targetReason=\(state.timelineScrollTarget?.reason.rawValue ?? "nil") bottomVisible=\(isTimelineBottomVisible) pending=\(pendingNewMessageIds.count) rows=\(state.rows.count)"
    )
  }

  private func isPendingNewMessageVisible(_ row: MessageRowState) -> Bool {
    !newMessageAliases(for: row).isDisjoint(with: visibleTimelineRowIds)
  }

  private func clearPendingNewMessageIds() {
    guard !pendingNewMessageIds.isEmpty else {
      return
    }
    NEChatSwiftUILogger.log(
      "chatAction indicator clearPending count=\(pendingNewMessageIds.count) target=\(state.timelineScrollTarget?.id ?? "nil") bottomVisible=\(isTimelineBottomVisible)"
    )
    pendingNewMessageIds.removeAll()
  }

  private func discardPendingNewMessages(matching ids: Set<String>) -> Bool {
    guard !ids.isEmpty else {
      return false
    }

    revokedPendingMessageIds.formUnion(ids)
    pendingHistoryNewMessages.removeAll { message in
      !newMessageAliases(for: message).isDisjoint(with: ids)
    }
    return removePendingNewMessageIds(matching: ids)
  }

  private func removePendingNewMessageIds(matching ids: Set<String>) -> Bool {
    guard !ids.isEmpty, !pendingNewMessageIds.isEmpty else {
      return false
    }
    let previousCount = pendingNewMessageIds.count
    pendingNewMessageIds.removeAll { item in
      !item.aliases.isDisjoint(with: ids)
    }
    return previousCount != pendingNewMessageIds.count
  }

  private func pendingNewMessagesFromLoadedRows() -> [V2NIMMessage] {
    pendingNewMessageIds.compactMap { item in
      for id in item.aliases {
        if let message = messageContextById[id] {
          return message
        }
      }
      if let message = messageContextById[item.primaryId] {
        return message
      }
      return nil
    }
  }

  private func newMessageAliases(for row: MessageRowState) -> Set<String> {
    var aliases = messageIds(for: row)
    if let message = messageContextById[row.id] ??
      row.serverId.flatMap({ messageContextById[$0] }) {
      aliases.formUnion(newMessageAliases(for: message))
    }
    return aliases
  }

  private func newMessageAliases(for message: V2NIMMessage) -> Set<String> {
    var aliases = Set([
      nonEmpty(message.messageClientId),
      nonEmpty(message.messageServerId),
      nonEmpty(ChatMessageMapper.stableMessageId(for: message)),
    ].compactMap { $0 })
    if let stableKey = stableMessageLookupKey(
      conversationId: message.conversationId,
      senderId: message.senderId,
      createTime: message.createTime
    ) {
      aliases.insert(stableKey)
    }
    return aliases
  }

  private func showHistoryJumpIndicatorIfNeeded() {
    guard isHistoryContextActive,
          state.multiSelect == nil else {
      return
    }
    guard !isTimelineBottomVisible else {
      clearPendingNewMessageIds()
      setNewMessageIndicator(nil)
      return
    }

    let pendingRows = pendingCurrentMessages()
      .map { messageRow(from: $0) }
      .filter { $0.direction == .incoming }

    if !pendingRows.isEmpty {
      appendPendingNewMessageRows(pendingRows)
      refreshNewMessageIndicatorState(requiresLatestReload: true)
    } else if !isTimelineBottomVisible {
      setNewMessageIndicator(
        NewMessageIndicatorState(
          count: 0,
          firstMessageId: state.rows.last?.id,
          requiresLatestReload: true
        )
      )
    }
  }

  private func pendingCurrentMessages() -> [V2NIMMessage] {
    var seenIds = Set<String>()
    return (context.pendingMessages + pendingHistoryNewMessages)
      .filter(isCurrentMessage)
      .filter { message in
        newMessageAliases(for: message).isDisjoint(with: revokedPendingMessageIds)
      }
      .filter { message in
        seenIds.insert(ChatMessageMapper.stableMessageId(for: message)).inserted
      }
  }

  private func reloadLatestMessagesFromHistoryContext() {
    reloadLatestMessagesFromHistoryContext(scrollToLatestAfterReload: false)
  }

  private func reloadLatestMessagesFromHistoryContext(scrollToLatestAfterReload: Bool) {
    NEChatSwiftUILogger.log(
      "chatAction reloadLatest start scrollAfter=\(scrollToLatestAfterReload) rows=\(state.rows.count) oldest=\(state.oldestAnchorMessageId ?? "nil") newest=\(state.newestAnchorMessageId ?? "nil") target=\(state.timelineScrollTarget?.id ?? "nil")"
    )
    isHistoryContextActive = false
    shouldScrollToLatestAfterReload = scrollToLatestAfterReload
    isTimelineBottomVisible = true
    historyRequestGeneration += 1
    pendingOlderHistoryLoad = nil
    clearPendingNewMessageIds()
    pendingHistoryNewMessages.removeAll()
    state.newMessageIndicator = nil
    state.isLoadingOlder = false
    state.isLoadingNewer = false
    clearPendingPrependRestore()
    visibleTimelineAnchorId = nil
    state.oldestAnchorMessageId = nil
    state.newestAnchorMessageId = nil
    oldestHistoryAnchorMessage = nil
    newestHistoryAnchorMessage = nil
    state.hasMoreOlder = true
    state.hasMoreNewer = false
    state.rows.removeAll()
    refreshAnchors()
    refreshTopMessage()
    state.phase = .idle
    loadOlderMessages()
  }

  private func voiceToTextFailureMessage() -> String {
    NEChatUIKitSwiftUIBundle.localized("operation_to_text_failed", value: "Voice to text failed")
  }

  private func setVoiceToTextState(for id: String,
                                   text: String?,
                                   phase: MessageVoiceToTextPhase) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }

    let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    state.rows[index].voiceToText = MessageVoiceToTextState(text: normalizedText, phase: phase)
    if case var .audio(audio) = state.rows[index].content,
       normalizedText?.isEmpty == false {
      audio.convertedText = normalizedText
      state.rows[index].content = .audio(audio)
    }
  }

  private func clearVoiceToTextState(for id: String) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }

    state.rows[index].voiceToText = nil
    if case var .audio(audio) = state.rows[index].content {
      audio.convertedText = nil
      state.rows[index].content = .audio(audio)
    }
  }

  private func updateAudioPlayingState(messageId: String, isPlaying: Bool) {
    state.rows = state.rows.map { row in
      var next = row
      guard next.id == messageId || next.serverId == messageId,
            case var .audio(audio) = next.content else {
        if case var .audio(audio) = next.content {
          audio.isPlaying = false
          next.content = .audio(audio)
        }
        return next
      }
      audio.isPlaying = isPlaying
      next.content = .audio(audio)
      return next
    }
  }

  private func setAIStreamActionPhase(for id: String, phase: AIStreamActionPhase) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }) else {
      return
    }
    state.rows[index].aiStreamActionPhase = phase
  }

  private func updateReeditState(for id: String, expired: Bool) {
    guard let index = state.rows.firstIndex(where: { $0.id == id || $0.serverId == id }),
          let reedit = state.rows[index].reedit else {
      return
    }
    state.rows[index].reedit = expired ? nil : reedit
  }

  private func nextBoundaryRequestGeneration() -> Int {
    boundaryRequestGeneration += 1
    return boundaryRequestGeneration
  }

  private func beginSendRequest(pendingId: String) -> UUID {
    let requestId = UUID()
    sendRequestIds[pendingId] = requestId
    sendAttemptIds[pendingId] = requestId
    return requestId
  }

  private func isSendRequestCurrent(pendingId: String,
                                    requestId: UUID) -> Bool {
    guard sendRequestIds[pendingId] == requestId else {
      return false
    }
    return row(id: pendingId) != nil || pendingMediaFingerprints[pendingId] != nil
  }

  private func finishSendRequest(pendingId: String,
                                 requestId: UUID) {
    guard sendRequestIds[pendingId] == requestId else {
      return
    }
    sendRequestIds[pendingId] = nil
    pendingMediaFingerprints[pendingId] = nil
  }

  private func operationRequestKey(_ operation: String,
                                   ids: [String]) -> String {
    let normalizedIds = ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted()
      .joined(separator: ",")
    return "\(operation):\(normalizedIds)"
  }

  private func beginOperationRequest(key: String) -> UUID {
    let requestId = UUID()
    operationRequestIds[key] = "\(operationRequestGeneration):\(requestId.uuidString)"
    return requestId
  }

  private func isOperationRequestCurrent(key: String,
                                         requestId: UUID,
                                         existingMessageIds: [String] = []) -> Bool {
    guard operationRequestIds[key] == "\(operationRequestGeneration):\(requestId.uuidString)" else {
      return false
    }

    guard !existingMessageIds.isEmpty else {
      return true
    }
    return existingMessageIds.allSatisfy { row(id: $0) != nil }
  }

  private func finishOperationRequest(key: String,
                                      requestId: UUID) {
    guard operationRequestIds[key] == "\(operationRequestGeneration):\(requestId.uuidString)" else {
      return
    }
    operationRequestIds[key] = nil
  }

  private func removeRows(ids: Set<String>) {
    let removedRows = state.rows.filter { row in
      !messageIds(for: row).isDisjoint(with: ids)
    }
    state.rows.removeAll { row in
      !messageIds(for: row).isDisjoint(with: ids)
    }
    let removedIds = removedRows.reduce(into: ids) { result, row in
      result.formUnion(messageIds(for: row))
    }
    if var multiSelect = state.multiSelect {
      multiSelect.selection.ids.subtract(removedIds)
      state.multiSelect = multiSelect
    }
    if removePendingNewMessageIds(matching: removedIds) {
      refreshNewMessageIndicatorState(
        requiresLatestReload: state.newMessageIndicator?.requiresLatestReload == true
      )
    }
    refreshNewMessageIndicatorAfterVisibleRowsChange()
    for id in removedIds {
      sendRequestIds[id] = nil
      sendAttemptIds[id] = nil
      voiceToTextRequestIds[id] = nil
      aiStreamActionRequestIds[id] = nil
      replyResolutionRequestIds[id] = nil
    }
    if case .teamTop = state.topMessage?.source,
       let topMessage = state.topMessage,
       removedIds.contains(topMessage.id) || topMessage.row?.serverId.map(removedIds.contains) == true {
      state.topMessage = nil
    }
    refreshTimeDividers()
    refreshAnchors()
    refreshTopMessage()
    markMissingReplies(ids: removedIds)
    pruneMessageContext()
    if state.rows.isEmpty {
      state.phase = .empty
    }
  }

  private func markMissingReplies(ids: Set<String>) {
    guard !ids.isEmpty else {
      return
    }

    state.rows = state.rows.map { row in
      guard var reply = row.reply,
            reply.messageClientId.map(ids.contains) == true ||
            reply.messageServerId.map(ids.contains) == true else {
        return row
      }
      replyResolutionRequestIds[row.id] = nil
      reply.preview = NEChatUIKitSwiftUIBundle.localized("message_not_found", value: "Message not found")
      reply.resolvedContent = nil
      reply.isResolved = false
      var next = row
      next.reply = reply
      if case let .reply(_, content) = next.content {
        next.content = .reply(preview: reply.displayPreview, content: content)
      }
      return next
    }
  }

  private func normalizeMentionsAfterTextChange() {
    state.input.mentions = validatedMentions(state.input.mentions, in: state.input.text)
    state.input.mentionedAccountIds = Set(state.input.mentions.map(\.accountId))
  }

  private func applyInputTextState(text proposedText: String,
                                   mentions: [ChatMentionState]) {
    let text = NECommonTextLimit.limitedUTF16(proposedText, limit: config.maxTextMessageLength)
    if text != state.input.text {
      resetInputTranslationAfterSourceTextChange()
    }
    state.input.text = text
    state.input.mentions = validatedMentions(mentions, in: text)
    state.input.mentionedAccountIds = Set(state.input.mentions.map(\.accountId))
    state.input.validation = makeInputValidation(for: text)
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    updateLocalTypingStateForInput(trimmedText: trimmed)
    if state.input.validation.isOverLimit {
      state.input.isSendEnabled = false
      state.toast = ChatToastState(message: NEChatUIKitSwiftUIBundle.localized("chat_input_text_too_long", value: "Message is too long"), style: .warning)
    } else {
      updateInputSendEnabledState()
    }
  }

  private func resetInputTranslationAfterSourceTextChange() {
    guard var inputTranslation = state.inputTranslation else {
      return
    }
    inputTranslationRequestId = nil
    inputTranslationBatch = nil
    translatedInputMentions.removeAll()
    inputTranslation.phase = .idle
    inputTranslation.translatedText = ""
    inputTranslation.requestId = nil
    state.inputTranslation = inputTranslation
  }

  private func updateInputSendEnabledState() {
    guard state.input.isEnabled else {
      state.input.isSendEnabled = false
      return
    }
    if state.input.validation.isOverLimit {
      state.input.isSendEnabled = false
      return
    }
    let hasText = !state.input.text.trimmingCharacters(in: .whitespaces).isEmpty
    let hasRichTextTitle = !state.input.richTextTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    state.input.isSendEnabled = hasText || hasRichTextTitle
  }

  private func normalizedInputTextAfterMentionEdit(previousText: String,
                                                   previousMentions: [ChatMentionState],
                                                   proposedText: String,
                                                   preferredEditRange: NSRange?) -> (text: String, mentions: [ChatMentionState]) {
    guard !previousMentions.isEmpty else {
      return (proposedText, [])
    }

    let difference = textDifference(
      from: previousText,
      to: proposedText,
      preferredEditRange: preferredEditRange
    )
    var mentions = previousMentions
    var text = proposedText

    if let difference,
       difference.removedCount > 0,
       let tokenRange = mentionTokenRangeAffectedByDeletion(difference.removedRange, mentions: previousMentions, in: previousText) {
      text = removeRange(tokenRange, from: previousText)
      mentions.removeAll { mention in
        mentionTokenRange(for: mention, in: previousText).overlaps(tokenRange)
      }
      mentions = shiftMentions(mentions, afterRemoving: tokenRange)
      return (text, mentions)
    }

    if let difference {
      if difference.removedCount == 0 {
        let insertionLocation = difference.removedRange.lowerBound
        mentions.removeAll { mention in
          guard let mentionRange = range(for: mention, in: previousText) else {
            return true
          }
          return insertionLocation > mentionRange.lowerBound &&
            insertionLocation < mentionRange.upperBound
        }
      }
      mentions = shiftMentions(mentions, by: difference.insertedCount - difference.removedCount, from: difference.removedRange.upperBound)
    } else {
      mentions = relocatedMentions(mentions, from: previousText, to: proposedText)
    }
    return (text, mentions)
  }

  private func mentionTokenRangeAffectedByDeletion(_ removedRange: Range<Int>,
                                                   mentions: [ChatMentionState],
                                                   in text: String) -> Range<Int>? {
    guard let mention = mentions.first(where: { mention in
      range(for: mention, in: text)?.overlaps(removedRange) == true
    }) else {
      return nil
    }
    return mentionTokenRange(for: mention, in: text)
  }

  private func shiftMentions(_ mentions: [ChatMentionState],
                             by delta: Int,
                             from location: Int) -> [ChatMentionState] {
    guard delta != 0 else {
      return mentions
    }
    return mentions.map { mention in
      guard mention.start >= location else {
        return mention
      }
      var shifted = mention
      shifted.start += delta
      shifted.end += delta
      return shifted
    }
  }

  private func shiftMentions(_ mentions: [ChatMentionState],
                             afterRemoving removedRange: Range<Int>) -> [ChatMentionState] {
    mentions.map { mention in
      guard mention.start >= removedRange.upperBound else {
        return mention
      }
      var shifted = mention
      let delta = removedRange.count
      shifted.start -= delta
      shifted.end -= delta
      return shifted
    }
  }

  private func relocatedMentions(_ mentions: [ChatMentionState],
                                 from previousText: String,
                                 to text: String) -> [ChatMentionState] {
    var occupied = [Range<Int>]()
    return mentions.compactMap { mention in
      guard let range = nearestRange(of: mention.displayText,
                                     in: text,
                                     preferredStart: mention.start,
                                     excluding: occupied) else {
        return nil
      }
      occupied.append(range)
      var relocated = mention
      relocated.start = range.lowerBound
      relocated.end = range.upperBound - 1
      return relocated
    }
  }

  private func validatedMentions(_ mentions: [ChatMentionState],
                                 in text: String) -> [ChatMentionState] {
    var occupied = [Range<Int>]()
    let validated = mentions.compactMap { mention -> ChatMentionState? in
      guard !mention.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !mention.displayText.isEmpty else {
        return nil
      }

      if let range = range(for: mention, in: text),
         !occupied.contains(where: { $0.overlaps(range) }) {
        occupied.append(range)
        return mention
      }

      guard let range = nearestRange(of: mention.displayText,
                                     in: text,
                                     preferredStart: mention.start,
                                     excluding: occupied) else {
        return nil
      }
      occupied.append(range)
      var relocated = mention
      relocated.start = range.lowerBound
      relocated.end = range.upperBound - 1
      return relocated
    }
    return validated.sorted { left, right in
      if left.start == right.start {
        return left.end < right.end
      }
      return left.start < right.start
    }
  }

  private func range(for mention: ChatMentionState,
                     in text: String) -> Range<Int>? {
    let exclusiveEnd = mention.end + 1
    guard mention.start >= 0,
          mention.start < exclusiveEnd,
          exclusiveEnd <= text.utf16.count else {
      return nil
    }
    let range = NSRange(location: mention.start, length: exclusiveEnd - mention.start)
    guard (text as NSString).substring(with: range) == mention.displayText else {
      return nil
    }
    return mention.start ..< exclusiveEnd
  }

  private func nearestRange(of needle: String,
                            in text: String,
                            preferredStart: Int,
                            excluding occupied: [Range<Int>]) -> Range<Int>? {
    let source = text as NSString
    let needleLength = needle.utf16.count
    guard needleLength > 0, source.length >= needleLength else {
      return nil
    }
    var ranges = [Range<Int>]()
    var searchStart = 0
    while searchStart < source.length {
      let found = source.range(
        of: needle,
        options: [],
        range: NSRange(location: searchStart, length: source.length - searchStart)
      )
      guard found.location != NSNotFound else {
        break
      }
      let intRange = found.location ..< NSMaxRange(found)
      if !occupied.contains(where: { $0.overlaps(intRange) }) {
        ranges.append(intRange)
      }
      searchStart = NSMaxRange(found)
    }
    return ranges.min { left, right in
      abs(left.lowerBound - preferredStart) < abs(right.lowerBound - preferredStart)
    }
  }

  private func mentionTokenRange(for mention: ChatMentionState,
                                 in text: String) -> Range<Int> {
    let source = text as NSString
    let start = max(0, min(mention.start, source.length))
    let displayEnd = max(start, min(mention.end + 1, source.length))
    var tokenEnd = displayEnd
    if tokenEnd < source.length,
       let scalar = UnicodeScalar(source.character(at: tokenEnd)),
       CharacterSet.whitespacesAndNewlines.contains(scalar) {
        tokenEnd += 1
    }
    return start ..< tokenEnd
  }

  private func removeRange(_ range: Range<Int>,
                           from text: String) -> String {
    guard range.lowerBound >= 0,
          range.lowerBound <= range.upperBound,
          range.upperBound <= text.utf16.count else {
      return text
    }
    return (text as NSString).replacingCharacters(
      in: NSRange(location: range.lowerBound, length: range.count),
      with: ""
    )
  }

  private func insertString(_ insertedText: String,
                            into text: String,
                            at location: Int) -> String {
    let boundedLocation = max(0, min(location, text.utf16.count))
    return (text as NSString).replacingCharacters(
      in: NSRange(location: boundedLocation, length: 0),
      with: insertedText
    )
  }

  private func boundedInputSelection(_ range: NSRange,
                                     in text: String) -> NSRange {
    let utf16Length = text.utf16.count
    let location = min(max(0, range.location), utf16Length)
    let length = min(max(0, range.length), utf16Length - location)
    return NSRange(location: location, length: length)
  }

  private func utf16Range(for mention: ChatMentionState,
                          in text: String) -> NSRange? {
    guard let mentionRange = range(for: mention, in: text) else {
      return nil
    }
    return NSRange(location: mentionRange.lowerBound, length: mentionRange.count)
  }

  private func selectionAfterNormalizedEdit(previousText: String,
                                            normalizedText: String,
                                            preferredEditRange: NSRange?) -> NSRange {
    guard let difference = textDifference(
      from: previousText,
      to: normalizedText,
      preferredEditRange: preferredEditRange
    ) else {
      return boundedInputSelection(state.input.selectedRange, in: normalizedText)
    }
    let location = difference.removedRange.lowerBound
    return boundedInputSelection(NSRange(location: location, length: 0), in: normalizedText)
  }

  private func updatePendingMentionTriggerLocation(previousText: String,
                                                   currentText: String,
                                                   preferredEditRange: NSRange?) {
    guard let difference = textDifference(
      from: previousText,
      to: currentText,
      preferredEditRange: preferredEditRange
    ),
          difference.removedCount == 0,
          difference.insertedCount == 1,
          difference.removedRange.lowerBound < currentText.utf16.count else {
      if let location = pendingMentionTriggerLocation,
         !isAtCharacter(at: location, in: currentText) {
        pendingMentionTriggerLocation = nil
      }
      return
    }
    pendingMentionTriggerLocation = isAtCharacter(at: difference.removedRange.lowerBound, in: currentText)
      ? difference.removedRange.lowerBound
      : nil
  }

  private func pendingMentionTriggerRange(in text: String) -> Range<Int>? {
    guard let location = pendingMentionTriggerLocation,
          isAtCharacter(at: location, in: text) else {
      return nil
    }
    return location ..< location + 1
  }

  private func isAtCharacter(at location: Int,
                             in text: String) -> Bool {
    let source = text as NSString
    guard location >= 0, location < source.length else {
      return false
    }
    return source.character(at: location) == 0x40
  }

  private func textDifference(from oldText: String,
                              to newText: String,
                              preferredEditRange: NSRange? = nil) -> (removedRange: Range<Int>, removedCount: Int, insertedCount: Int)? {
    guard oldText != newText else {
      return nil
    }

    if let preferredEditRange,
       let preferredDifference = textDifference(
         at: preferredEditRange,
         from: oldText,
         to: newText
       ) {
      return preferredDifference
    }

    let oldChars = Array(oldText.utf16)
    let newChars = Array(newText.utf16)
    var prefix = 0
    while prefix < oldChars.count,
          prefix < newChars.count,
          oldChars[prefix] == newChars[prefix] {
      prefix += 1
    }

    var oldSuffix = oldChars.count
    var newSuffix = newChars.count
    while oldSuffix > prefix,
          newSuffix > prefix,
          oldChars[oldSuffix - 1] == newChars[newSuffix - 1] {
      oldSuffix -= 1
      newSuffix -= 1
    }

    return (
      removedRange: prefix ..< oldSuffix,
      removedCount: oldSuffix - prefix,
      insertedCount: newSuffix - prefix
    )
  }

  private func textDifference(at editRange: NSRange,
                              from oldText: String,
                              to newText: String) -> (removedRange: Range<Int>, removedCount: Int, insertedCount: Int)? {
    let oldLength = oldText.utf16.count
    let boundedRange = boundedInputSelection(editRange, in: oldText)
    let prefixLength = boundedRange.location
    let suffixStart = NSMaxRange(boundedRange)
    let suffixLength = oldLength - suffixStart
    let insertedCount = newText.utf16.count - prefixLength - suffixLength
    guard insertedCount >= 0 else {
      return nil
    }

    let oldSource = oldText as NSString
    let newSource = newText as NSString
    let oldPrefix = oldSource.substring(with: NSRange(location: 0, length: prefixLength))
    let oldSuffix = oldSource.substring(with: NSRange(location: suffixStart, length: suffixLength))
    guard newSource.substring(with: NSRange(location: 0, length: prefixLength)) == oldPrefix,
          newSource.substring(with: NSRange(
            location: prefixLength + insertedCount,
            length: suffixLength
          )) == oldSuffix else {
      return nil
    }
    return (
      removedRange: boundedRange.location ..< NSMaxRange(boundedRange),
      removedCount: boundedRange.length,
      insertedCount: insertedCount
    )
  }

  private func refreshAnchors() {
    state.oldestAnchorMessageId = state.rows.first?.id
    state.newestAnchorMessageId = state.rows.last?.id
  }

  private func refreshTimeDividers(around changedRange: Range<Int>? = nil) {
    guard let changedRange else {
      refreshTimeDividers(in: state.rows.indices)
      return
    }
    guard !state.rows.isEmpty else {
      return
    }
    let lowerBound = max(state.rows.startIndex, changedRange.lowerBound - 1)
    let upperBound = min(state.rows.endIndex, changedRange.upperBound + 1)
    refreshTimeDividers(in: lowerBound ..< upperBound)
  }

  private func refreshTimeDividers(in range: Range<Array<MessageRowState>.Index>) {
    guard !range.isEmpty else {
      return
    }
    var previousTimestamp: TimeInterval?
    if range.lowerBound > state.rows.startIndex {
      previousTimestamp = previousComparableTimestamp(before: range.lowerBound)
    }
    for index in range {
      guard let timestamp = state.rows[index].timestamp,
            timestamp > 0 else {
        state.rows[index].timeDividerText = nil
        continue
      }

      let shouldShowDivider: Bool
      if index == state.rows.startIndex {
        shouldShowDivider = true
      } else if let previousTimestamp {
        shouldShowDivider = !state.rows[index].suppressesTimeDivider && timestamp - previousTimestamp > 5 * 60
      } else {
        shouldShowDivider = !state.rows[index].suppressesTimeDivider
      }
      state.rows[index].timeDividerText = shouldShowDivider
        ? chatTimeDividerText(for: timestamp)
        : nil
      previousTimestamp = timestamp
    }
  }

  private func previousComparableTimestamp(before index: Array<MessageRowState>.Index) -> TimeInterval? {
    guard index > state.rows.startIndex else {
      return nil
    }
    var current = index - 1
    while current >= state.rows.startIndex {
      let row = state.rows[current]
      if let timestamp = row.timestamp,
         timestamp > 0 {
        return timestamp
      }
      if current == state.rows.startIndex {
        break
      }
      current -= 1
    }
    return nil
  }

  private func chatTimeDividerText(for timestamp: TimeInterval) -> String {
    ChatUnitFormatter.messageTimeText(timestamp)
  }

  private func isCurrentMessage(_ message: V2NIMMessage) -> Bool {
    switch context.kind {
    case .topic, .botSubSession:
      if let topic = context.topic {
        return message.conversationId == context.conversationId &&
          message.topicRefer?.conversationId == context.conversationId &&
          message.topicRefer?.topicId == topic.topicId &&
          message.topicRefer?.createTime == topic.createTime
      }
      return message.conversationId == context.conversationId
    default:
      return message.conversationId == context.conversationId
    }
  }
}

private struct MessageMediaFingerprint: Equatable {
  var kind: Kind
  var localPath: String?
  var fileName: String?
  var fileSize: UInt64?
  var width: Int?
  var height: Int?
  var duration: Int?

  init?(content: MessageContentState) {
    switch content {
    case let .image(media):
      kind = .image
      localPath = Self.normalizedPath(media.localPath)
      fileName = Self.fileName(from: media.localPath)
      fileSize = Self.fileSize(at: media.localPath)
      width = Self.rounded(media.width)
      height = Self.rounded(media.height)
      duration = nil
    case let .video(media):
      kind = .video
      localPath = Self.normalizedPath(media.localPath)
      fileName = Self.fileName(from: media.localPath)
      fileSize = Self.fileSize(at: media.localPath)
      width = Self.rounded(media.width)
      height = Self.rounded(media.height)
      duration = Self.rounded(media.duration)
    case let .audio(audio):
      kind = .audio
      localPath = Self.normalizedPath(audio.localPath)
      fileName = Self.fileName(from: audio.localPath)
      fileSize = Self.fileSize(at: audio.localPath)
      width = nil
      height = nil
      duration = Self.rounded(audio.duration)
    case let .file(file):
      kind = .file
      localPath = Self.normalizedPath(file.localPath)
      fileName = Self.normalizedDisplayName(file.name, localPath: file.localPath)
      fileSize = Self.fileSize(at: file.localPath)
      width = nil
      height = nil
      duration = nil
    default:
      return nil
    }
  }

  func matches(_ other: MessageMediaFingerprint) -> Bool {
    guard kind == other.kind else {
      return false
    }
    if let localPath, let otherPath = other.localPath, localPath == otherPath {
      return true
    }
    if let fileSize, let otherSize = other.fileSize, fileSize > 0, fileSize == otherSize {
      if fileName == nil || other.fileName == nil || fileName == other.fileName {
        return dimensionsMatch(other) && durationMatches(other)
      }
    }
    if let fileName, let otherName = other.fileName, fileName == otherName {
      return dimensionsMatch(other) && durationMatches(other)
    }
    return false
  }

  private func dimensionsMatch(_ other: MessageMediaFingerprint) -> Bool {
    guard let width, let height, let otherWidth = other.width, let otherHeight = other.height else {
      return true
    }
    return width == otherWidth && height == otherHeight
  }

  private func durationMatches(_ other: MessageMediaFingerprint) -> Bool {
    guard let duration, let otherDuration = other.duration, duration > 0, otherDuration > 0 else {
      return true
    }
    return abs(duration - otherDuration) <= 1
  }

  private static func normalizedPath(_ path: String?) -> String? {
    guard let value = path?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: value).standardizedFileURL.path
  }

  private static func normalizedDisplayName(_ name: String, localPath: String?) -> String? {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty {
      return trimmedName
    }
    return fileName(from: localPath)
  }

  private static func fileName(from path: String?) -> String? {
    guard let normalized = normalizedPath(path) else {
      return nil
    }
    return URL(fileURLWithPath: normalized).lastPathComponent
  }

  private static func fileSize(at path: String?) -> UInt64? {
    guard let normalized = normalizedPath(path),
          let size = (try? FileManager.default.attributesOfItem(atPath: normalized)[.size] as? NSNumber)?.uint64Value else {
      return nil
    }
    return size
  }

  private static func rounded(_ value: Double?) -> Int? {
    guard let value, value.isFinite, value > 0 else {
      return nil
    }
    return Int(value.rounded())
  }

  enum Kind {
    case image
    case video
    case audio
    case file
  }
}
