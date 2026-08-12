// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import SwiftUI
import UIKit

public struct ChatTimelineView: View {
  @State private var rowFrames = [String: CGRect]()
  @State private var selectableTextFrames = [String: CGRect]()
  @StateObject private var runtimeState = TimelineRuntimeState()
  @State private var lastLoadOlderTriggerId: String?
  @State private var lastLoadNewerTriggerId: String?
  @State private var hasUserScrolled = false
  @State private var isMomentumCancellationActive = false
  @State private var scheduledScrollTargetId: String?
  @State private var scheduledScrollTargetReason: ChatTimelineScrollTarget.Reason?
  @State private var lastScrollTargetReason: ChatTimelineScrollTarget.Reason?
  @State private var suppressLoadOlderRetryUntilUserScroll = false
  @State private var suppressLoadOlderRetryUntilNextDrag = false
  @State private var suppressLoadOlderRetryCooldownUntil: TimeInterval = 0
  @State private var pendingPrependRestoreTarget: ChatTimelineScrollTarget?
  @State private var pendingPrependRestoreInitialFirstRowId: String?
  @State private var pendingPrependRestoreInitialRowCount = 0
  @State private var pendingPrependRestoreObservedRowsChange = false
  @State private var initialLatestRevealDeadline: Date?

  public var rows: [MessageRowState]
  public var isLoadingOlder: Bool
  public var isLoadingNewer: Bool
  public var hasMoreOlder: Bool
  public var hasMoreNewer: Bool
  public var isOlderPaginationSuspended: Bool
  public var isMultiSelecting: Bool
  public var isActive: Bool
  public var visibilityMeasurementGeneration: Int
  public var diagnosticConversationId: String
  public var scrollTarget: ChatTimelineScrollTarget?
  public var isScrollTargetCurrent: (ChatTimelineScrollTarget) -> Bool
  public var keepsBottomPinned: Bool
  public var operationMenu: OperationMenuState?
  public var token: ChatThemeToken
  public var shouldShowAvatar: (MessageRowState) -> Bool
  public var shouldShowSenderName: (MessageRowState) -> Bool
  public var customMessageContent: (MessageRowState) -> AnyView?
  public var customMessageLayout: (MessageRowState) -> ChatCustomMessageLayout?
  public var canLoadOlder: (() -> Bool)?
  public var onLoadOlder: (String?) -> Void
  public var onLoadNewer: () -> Void
  public var onVisibleAnchorChange: (String?) -> Void
  public var onVisibleRowsChange: (Set<String>) -> Void
  public var onLatestRowVisibilityChange: (Bool) -> Void
  public var onBottomVisibilityChange: (Bool) -> Void
  public var onScrollInteraction: () -> Void
  public var onScrollTargetConsumed: (String) -> Void
  public var onSelect: (MessageRowState) -> Void
  public var onAvatarTap: (MessageRowState) -> Void
  public var onAvatarLongPress: (MessageRowState) -> Void
  public var onTap: (MessageRowState) -> Void
  public var onAIStreamAction: (AIStreamAction, MessageRowState) -> Void
  public var onReedit: (MessageRowState) -> Void
  public var onReplyTap: (MessageRowState) -> Void
  public var onOpenURL: (URL, String, ChatURLInteractionSource, MessageRowState) -> Void
  public var onReadReceiptTap: ((MessageRowState) -> Void)?
  public var onResendTap: (MessageRowState) -> Void
  public var onLongPress: (MessageRowState) -> Void
  public var onTextSelectionChange: (MessageRowState, String?, Bool) -> Void
  public var onOperationSelect: (MessageOperation, String) -> Void
  public var onOperationDismiss: () -> Void

  public init(rows: [MessageRowState],
              isLoadingOlder: Bool = false,
              isLoadingNewer: Bool = false,
              hasMoreOlder: Bool = true,
              hasMoreNewer: Bool = false,
              isOlderPaginationSuspended: Bool = false,
              isMultiSelecting: Bool = false,
              isActive: Bool = true,
              visibilityMeasurementGeneration: Int = 0,
              diagnosticConversationId: String = "unknown",
              scrollTarget: ChatTimelineScrollTarget? = nil,
              isScrollTargetCurrent: @escaping (ChatTimelineScrollTarget) -> Bool = { _ in true },
              keepsBottomPinned: Bool = false,
              operationMenu: OperationMenuState? = nil,
              token: ChatThemeToken,
              shouldShowAvatar: @escaping (MessageRowState) -> Bool = { _ in true },
              shouldShowSenderName: @escaping (MessageRowState) -> Bool = { row in row.direction == .incoming },
              customMessageContent: @escaping (MessageRowState) -> AnyView? = { _ in nil },
              customMessageLayout: @escaping (MessageRowState) -> ChatCustomMessageLayout? = { _ in nil },
              canLoadOlder: (() -> Bool)? = nil,
              onLoadOlder: @escaping (String?) -> Void = { _ in },
              onLoadNewer: @escaping () -> Void = {},
              onVisibleAnchorChange: @escaping (String?) -> Void = { _ in },
              onVisibleRowsChange: @escaping (Set<String>) -> Void = { _ in },
              onLatestRowVisibilityChange: @escaping (Bool) -> Void = { _ in },
              onBottomVisibilityChange: @escaping (Bool) -> Void = { _ in },
              onScrollInteraction: @escaping () -> Void = {},
              onScrollTargetConsumed: @escaping (String) -> Void = { _ in },
              onSelect: @escaping (MessageRowState) -> Void = { _ in },
              onAvatarTap: @escaping (MessageRowState) -> Void = { _ in },
              onAvatarLongPress: @escaping (MessageRowState) -> Void = { _ in },
              onTap: @escaping (MessageRowState) -> Void = { _ in },
              onAIStreamAction: @escaping (AIStreamAction, MessageRowState) -> Void = { _, _ in },
              onReedit: @escaping (MessageRowState) -> Void = { _ in },
              onReplyTap: @escaping (MessageRowState) -> Void = { _ in },
              onOpenURL: @escaping (URL, String, ChatURLInteractionSource, MessageRowState) -> Void = { _, _, _, _ in },
              onReadReceiptTap: ((MessageRowState) -> Void)? = nil,
              onResendTap: @escaping (MessageRowState) -> Void = { _ in },
              onLongPress: @escaping (MessageRowState) -> Void,
              onTextSelectionChange: @escaping (MessageRowState, String?, Bool) -> Void = { _, _, _ in },
              onOperationSelect: @escaping (MessageOperation, String) -> Void = { _, _ in },
              onOperationDismiss: @escaping () -> Void = {}) {
    self.rows = rows
    self.isLoadingOlder = isLoadingOlder
    self.isLoadingNewer = isLoadingNewer
    self.hasMoreOlder = hasMoreOlder
    self.hasMoreNewer = hasMoreNewer
    self.isOlderPaginationSuspended = isOlderPaginationSuspended
    self.isMultiSelecting = isMultiSelecting
    self.isActive = isActive
    self.visibilityMeasurementGeneration = visibilityMeasurementGeneration
    self.diagnosticConversationId = diagnosticConversationId
    self.scrollTarget = scrollTarget
    self.isScrollTargetCurrent = isScrollTargetCurrent
    self.keepsBottomPinned = keepsBottomPinned
    self.operationMenu = operationMenu
    self.token = token
    self.shouldShowAvatar = shouldShowAvatar
    self.shouldShowSenderName = shouldShowSenderName
    self.customMessageContent = customMessageContent
    self.customMessageLayout = customMessageLayout
    self.canLoadOlder = canLoadOlder
    self.onLoadOlder = onLoadOlder
    self.onLoadNewer = onLoadNewer
    self.onVisibleAnchorChange = onVisibleAnchorChange
    self.onVisibleRowsChange = onVisibleRowsChange
    self.onLatestRowVisibilityChange = onLatestRowVisibilityChange
    self.onBottomVisibilityChange = onBottomVisibilityChange
    self.onScrollInteraction = onScrollInteraction
    self.onScrollTargetConsumed = onScrollTargetConsumed
    self.onSelect = onSelect
    self.onAvatarTap = onAvatarTap
    self.onAvatarLongPress = onAvatarLongPress
    self.onTap = onTap
    self.onAIStreamAction = onAIStreamAction
    self.onReedit = onReedit
    self.onReplyTap = onReplyTap
    self.onOpenURL = onOpenURL
    self.onLongPress = onLongPress
    self.onTextSelectionChange = onTextSelectionChange
    self.onReadReceiptTap = onReadReceiptTap
    self.onResendTap = onResendTap
    self.onOperationSelect = onOperationSelect
    self.onOperationDismiss = onOperationDismiss
  }

  public var body: some View {
    GeometryReader { timelineGeometry in
      ZStack(alignment: .topLeading) {
        ScrollViewReader { proxy in
          ScrollView {
            timelineRows(
              with: proxy,
              timelineWidth: timelineGeometry.size.width
            )
              .frame(width: timelineGeometry.size.width, alignment: .leading)
              .padding(.top, Self.timelineVerticalPadding)
          }
          .background {
            // Keep prepend-anchor guard coverage for: onContentSizeChange: handleTimelineContentSizeChanged
            TimelineScrollViewProbe(
              runtimeState: runtimeState,
              isActive: isActive,
              immediateBottomTarget: immediateBottomProbeTarget,
              allowsBottomNormalization: { !isOlderPaginationSuspended },
              shouldHandleContentSizeChange: { hasPendingTimelineContentSizeWork },
              onContentSizeChange: { handleTimelineContentSizeChanged(with: proxy) },
              onContentOffsetChange: {
                stabilizeExplicitAnchorAfterNativeGeometryChange(
                  with: proxy,
                  source: "contentOffset"
                )
              }
            )
          }
          .coordinateSpace(name: "chatTimeline")
          .scrollDisabled(isMomentumCancellationActive)
          .opacity(shouldHideInitialLatestPositioning ? 0 : 1)
          .animation(nil, value: shouldHideInitialLatestPositioning)
          .scrollDismissesKeyboard(.immediately)
          .simultaneousGesture(
            DragGesture(minimumDistance: 1)
              .onChanged { value in
                handleTimelineDragChanged(
                  from: value.startLocation,
                  with: proxy
                )
              }
              .onEnded { _ in
                handleTimelineDragEnded()
              }
          )
          .simultaneousGesture(
            SpatialTapGesture().onEnded { _ in
              guard operationMenu == nil else {
                return
              }
              onScrollInteraction()
            }
          )
          .onPreferenceChange(MessageSelectableTextFramePreferenceKey.self) { frames in
            selectableTextFrames = frames
          }
          .onPreferenceChange(TimelineVisibleRowPreferenceKey.self) { visibleRows in
            guard isActive else {
              deactivateTimelinePresentation()
              return
            }
            updateRowFramesIfNeeded(
              visibleRows,
              viewportHeight: timelineGeometry.size.height,
              with: proxy
            )
          }
          .onPreferenceChange(TimelineExplicitAnchorFramePreferenceKey.self) { frames in
            updateExplicitAnchorFrameIfNeeded(frames, with: proxy)
          }
          .onPreferenceChange(TimelineLatestRowFramePreferenceKey.self) { measurement in
            scheduleLatestRowFrameUpdate(measurement, with: proxy)
          }
          .onPreferenceChange(TimelineBottomAnchorFramePreferenceKey.self) { frame in
            scheduleBottomAnchorFrameUpdate(frame, with: proxy)
          }
          .onAppear {
            guard isActive else {
              deactivateTimelinePresentation()
              return
            }
            if isOlderPaginationSuspended {
              updateOlderPaginationSuspension(true)
            }
            runtimeState.rebuildRowOrderIfNeeded(rows: rows)
            syncPresentedScrollTarget()
            updateViewportHeightIfNeeded(timelineGeometry.size.height)
            logImmediateBottomTrace("onAppear.beforeConsume")
            consume(scrollTarget, with: proxy)
            pinBottomIfNeeded(with: proxy)
            updateLatestMessageVisibilityIfNeeded()
          }
          .onChange(of: isActive) { active in
            guard active else {
              deactivateTimelinePresentation()
              return
            }
            runtimeState.rebuildRowOrderIfNeeded(rows: rows)
            syncPresentedScrollTarget()
            updateViewportHeightIfNeeded(timelineGeometry.size.height)
            replayMeasuredVisibleRowsAfterActivation(
              viewportHeight: timelineGeometry.size.height,
              with: proxy
            )
            consume(scrollTarget, with: proxy)
            updateLatestMessageVisibilityIfNeeded()
            DispatchQueue.main.async {
              guard isActive else {
                return
              }
              updateLatestMessageVisibilityIfNeeded()
            }
          }
          .onChange(of: visibilityMeasurementGeneration) { _ in
            guard isActive else {
              return
            }
            replayMeasuredVisibleRowsAfterActivation(
              viewportHeight: timelineGeometry.size.height,
              with: proxy
            )
          }
          .onChange(of: timelineGeometry.size.height) { height in
            guard isActive else {
              return
            }
            updateViewportHeightIfNeeded(height)
            consume(scrollTarget, with: proxy)
            pinBottomIfNeeded(with: proxy)
          }
          .onChange(of: scrollTarget?.id) { _ in
            guard isActive else {
              return
            }
            NEChatSwiftUILogger.log(
              "timeline diagnostic scrollTargetChanged id=\(scrollTarget?.id ?? "nil") reason=\(scrollTarget?.reason.rawValue ?? "nil") ageMs=\(scrollTarget?.ageMilliseconds.description ?? "nil") rows=\(rows.count) scroll=\(runtimeState.scrollMetricsDescription())"
            )
            syncPresentedScrollTarget()
            logImmediateBottomTrace("scrollTargetChanged.beforeConsume")
            consume(scrollTarget, with: proxy)
            if let reason = scrollTarget?.reason {
              lastScrollTargetReason = reason
            } else if lastScrollTargetReason == .prependRestore {
              suppressLoadOlderRetryUntilUserScroll = true
              logLoadOlderDecision("retrySkipped.prependRestore", source: "retry")
              lastScrollTargetReason = nil
            } else {
              lastScrollTargetReason = nil
            }
          }
          .onChange(of: keepsBottomPinned) { _ in
            guard isActive else {
              cancelPinnedBottomScroll()
              return
            }
            NEChatSwiftUILogger.log(
              "timeline diagnostic keepsPinnedChanged value=\(keepsBottomPinned) target=\(scrollTarget?.id ?? "nil") targetReason=\(scrollTarget?.reason.rawValue ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil") rows=\(rows.count) scroll=\(runtimeState.scrollMetricsDescription())"
            )
            if !keepsBottomPinned {
              runtimeState.usesFastInitialBottomPin = false
              cancelPinnedBottomScroll()
            }
            pinBottomIfNeeded(with: proxy)
          }
          .onChange(of: rows.last?.id) { _ in
            guard isActive else {
              return
            }
            runtimeState.rebuildRowOrderIfNeeded(rows: rows)
            syncPresentedScrollTarget()
            runtimeState.latestRowFrame = nil
            runtimeState.bottomAnchorFrame = nil
            pruneVisibleRowsToCurrentRows(with: proxy)
            revealInitialLatestPositioningAfterTimeoutIfNeeded()
            updateLatestMessageVisibilityIfNeeded(latestFrame: nil)
            consume(scrollTarget, with: proxy)
            pinBottomIfNeeded(with: proxy)
          }
          .onChange(of: rows.count) { _ in
            guard isActive else {
              return
            }
            runtimeState.rebuildRowOrderIfNeeded(rows: rows)
            syncPresentedScrollTarget()
            pruneVisibleRowsToCurrentRows(with: proxy)
            markPendingPrependRestoreRowsChangedIfNeeded()
            logTimelineSmoothness("rowsCountChanged")
            if consumePendingPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "rowsCount") {
              return
            }
            schedulePrependContentOffsetCompensation(source: "rowsCount")
            reapplyScheduledPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "rowsCount")
            consume(scrollTarget, with: proxy)
          }
          .onChange(of: rows.first?.id) { _ in
            guard isActive else {
              return
            }
            runtimeState.rebuildRowOrderIfNeeded(rows: rows)
            syncPresentedScrollTarget()
            pruneVisibleRowsToCurrentRows(with: proxy)
            markPendingPrependRestoreRowsChangedIfNeeded()
            logTimelineSmoothness("rowsFirstChanged")
            if consumePendingPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "rowsFirst") {
              resetLoadOlderTriggerIfNeeded()
              return
            }
            schedulePrependContentOffsetCompensation(source: "rowsFirst")
            reapplyScheduledPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "rowsFirst")
            consume(scrollTarget, with: proxy)
            resetLoadOlderTriggerIfNeeded()
          }
          .onChange(of: isLoadingOlder) { loading in
            guard isActive else {
              return
            }
            guard !isOlderPaginationSuspended else {
              logSuspendedTimelineAction("loadingOlderChanged loading=\(loading)", source: "isLoadingOlder")
              return
            }
            logTimelineSmoothness("loadingOlderChanged loading=\(loading)")
            if !loading {
              resetLoadOlderTriggerIfNeeded()
              if completeUnchangedPrependLoadIfNeeded() {
                return
              }
              if consumePendingPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "loadingOlderFinished") {
                return
              }
              schedulePrependContentOffsetCompensation(source: "loadingOlderFinished")
              reapplyScheduledPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "loadingOlderFinished")
            }
          }
          .onChange(of: hasMoreOlder) { hasMore in
            guard isActive else {
              return
            }
            guard !isOlderPaginationSuspended else {
              logSuspendedTimelineAction("hasMoreOlderChanged hasMore=\(hasMore)", source: "hasMoreOlder")
              return
            }
            if !hasMore {
              resetLoadOlderTriggerIfNeeded()
              _ = completeUnchangedPrependLoadIfNeeded()
            } else {
              resetLoadOlderCycleAfterResume(source: "hasMoreOlder")
            }
          }
          .onChange(of: isOlderPaginationSuspended) { suspended in
            updateOlderPaginationSuspension(suspended)
          }
          .onChange(of: isLoadingNewer) { loading in
            guard isActive else {
              return
            }
            if !loading {
              resetLoadNewerTriggerIfNeeded()
            }
          }
          .onChange(of: hasMoreNewer) { hasMore in
            guard isActive else {
              return
            }
            if !hasMore {
              resetLoadNewerTriggerIfNeeded()
            }
          }
        }

        if isLoadingOlder, !isOlderPaginationSuspended {
          NEChatCommonPresentation.inlineLoadingView(token: token)
            .frame(maxWidth: .infinity)
            .frame(height: Self.olderLoadingOverlayHeight)
            .background(token.messageListBackground.opacity(0.96))
            .allowsHitTesting(false)
            .accessibilityLabel(
              NEChatUIKitSwiftUIBundle.localized("loading", value: "Loading")
            )
            .zIndex(0.5)
        }

        if let operationMenu {
          GeometryReader { geometry in
            ForEach(
              Array(operationMenuDismissRegions(for: operationMenu, in: geometry.size).enumerated()),
              id: \.offset
            ) { _, region in
              operationMenuDismissRegion
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
            }

            MessageOperationMenu(
              menu: operationMenu,
              token: token,
              onSelect: onOperationSelect
            )
            .position(operationMenuPosition(for: operationMenu, in: geometry.size))
          }
          .transition(.opacity)
          .zIndex(1)
        }
      }
    }
    .background(token.messageListBackground)
  }

  @ViewBuilder
  private func timelineRows(with proxy: ScrollViewProxy,
                            timelineWidth: CGFloat) -> some View {
    if usesStableOversizedAIRowLayout {
      VStack(spacing: token.rowVerticalSpacing) {
        timelineRowContent(with: proxy, timelineWidth: timelineWidth)
      }
    } else {
      LazyVStack(spacing: token.rowVerticalSpacing) {
        timelineRowContent(with: proxy, timelineWidth: timelineWidth)
      }
    }
  }

  @ViewBuilder
  private func timelineRowContent(with proxy: ScrollViewProxy,
                                  timelineWidth: CGFloat) -> some View {
    timelineHeader
    ForEach(rows) { row in
      timelineRow(
        row,
        with: proxy,
        timelineWidth: timelineWidth
      )
    }
    timelineBottomAnchor
  }

  private var usesStableOversizedAIRowLayout: Bool {
    rows.lazy
      .filter { oversizedAITextLength(in: $0.content) >= Self.oversizedAITextLengthThreshold }
      .prefix(2)
      .count == 2
  }

  private func oversizedAITextLength(in content: MessageContentState) -> Int {
    switch content {
    case let .aiStream(text, _, _):
      return text.utf16.count
    case let .reply(_, boxed):
      return oversizedAITextLength(in: boxed.value)
    default:
      return 0
    }
  }

  private var timelineHeader: some View {
    topLoadProbe
  }

  private func timelineRow(_ row: MessageRowState,
                           with proxy: ScrollViewProxy,
                           timelineWidth: CGFloat) -> some View {
    VStack(spacing: token.rowVerticalSpacing) {
      if let timeDividerText = row.timeDividerText, !timeDividerText.isEmpty {
        timeDivider(timeDividerText)
          .id("time-divider-\(row.id)")
      }

      Group {
        if isMultiSelecting, isMultiSelectable(row) {
          ZStack(alignment: .leading) {
            messageBubble(for: row)
              .frame(
                width: max(0, timelineWidth - Self.multiSelectContentLeading),
                alignment: .leading
              )
              .offset(x: Self.multiSelectContentLeading)

            multiSelectIndicator(for: row)
              .frame(
                width: Self.multiSelectIndicatorSize,
                height: Self.multiSelectIndicatorSize
              )
              .offset(x: Self.multiSelectIndicatorLeading)
          }
          .frame(width: timelineWidth, alignment: .leading)
        } else {
          messageBubble(for: row)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .modifier(ChatTimelineRowSelectionGesture(isEnabled: isMultiSelecting && isMultiSelectable(row)) {
        onSelect(row)
      })
      .background {
        ZStack {
          rowFrameProbe(
            for: row.id,
            measurementGeneration: visibilityMeasurementGeneration
          )
          latestRowFrameProbe(for: row.id)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .id(row.id)
    .background {
      explicitAnchorFrameProbe(for: row.id, with: proxy)
    }
  }

  private func messageBubble(for row: MessageRowState) -> some View {
    MessageBubbleView(
        row: row,
        token: token,
        showsAvatar: shouldShowAvatar(row),
        showsSenderName: shouldShowSenderName(row),
        customContent: customMessageContent(row),
        customLayout: customMessageLayout(row),
        onAvatarTap: onAvatarTap,
        onAvatarLongPress: onAvatarLongPress,
        onAIStreamAction: onAIStreamAction,
        onReedit: onReedit,
        onReplyTap: onReplyTap,
        onOpenURL: onOpenURL,
        onReadReceiptTap: onReadReceiptTap,
        onResendTap: onResendTap,
        onBodyTap: handleBubbleTap,
        onBodyLongPress: handleBubbleLongPress,
        isMultiSelecting: isMultiSelecting,
        isTextSelectionActive: operationMenu?.messageId == row.id,
        onTextSelectionChange: onTextSelectionChange
      )
  }

  private func timeDivider(_ text: String) -> some View {
    Text(text)
      .font(.system(size: token.timeDividerFontSize))
      .foregroundColor(token.secondaryTextColor)
      .padding(.horizontal, 10)
      .frame(height: token.timeCellHeight)
      .background {
        Capsule()
          .fill(token.dividerColor.opacity(0.35))
      }
      .frame(maxWidth: .infinity)
      .accessibilityLabel(text)
  }

  private func handleBubbleTap(row: MessageRowState) {
    onTap(row)
  }

  private func handleBubbleLongPress(row: MessageRowState) {
    if !isMultiSelecting {
      onLongPress(row)
    }
  }

  @ViewBuilder
  private func multiSelectIndicator(for row: MessageRowState) -> some View {
    if isMultiSelecting, isMultiSelectable(row) {
      Button {
        onSelect(row)
      } label: {
        NEChatCommonPresentation.selectionIndicator(
          isSelected: row.isSelected,
          token: token,
          size: Self.multiSelectIndicatorSize
        )
      }
      .buttonStyle(.plain)
    }
  }

  private func isMultiSelectable(_ row: MessageRowState) -> Bool {
    guard row.direction != .system,
          !row.isUnfinishedAIStream else {
      return false
    }
    if case .revoke = row.content {
      return false
    }
    return true
  }

  private var operationMenuTargetsSelectableText: Bool {
    guard let messageId = operationMenu?.messageId,
          let row = rows.first(where: { $0.id == messageId }) else {
      return false
    }
    return isSelectableTextContent(row.content)
  }

  private func isSelectableTextContent(_ content: MessageContentState) -> Bool {
    switch content {
    case .text, .richText:
      return true
    case let .aiStream(_, isFinished, _):
      return isFinished
    case let .reply(_, boxed):
      return isSelectableTextContent(boxed.value)
    default:
      return false
    }
  }

  private var operationMenuDismissRegion: some View {
    Color.black.opacity(0.001)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            onOperationDismiss()
          }
      )
  }

  private func operationMenuDismissRegions(for menu: OperationMenuState,
                                           in containerSize: CGSize) -> [CGRect] {
    let bounds = CGRect(origin: .zero, size: containerSize)
    guard operationMenuTargetsSelectableText else {
      return [bounds]
    }
    guard let selectableFrame = selectableTextFrames[menu.messageId] else {
      return [bounds]
    }

    let protectedFrame = selectableFrame
      .insetBy(dx: -16, dy: -12)
      .intersection(bounds)
    guard !protectedFrame.isNull,
          !protectedFrame.isEmpty else {
      return [bounds]
    }

    return [
      CGRect(x: bounds.minX,
             y: bounds.minY,
             width: bounds.width,
             height: protectedFrame.minY - bounds.minY),
      CGRect(x: bounds.minX,
             y: protectedFrame.maxY,
             width: bounds.width,
             height: bounds.maxY - protectedFrame.maxY),
      CGRect(x: bounds.minX,
             y: protectedFrame.minY,
             width: protectedFrame.minX - bounds.minX,
             height: protectedFrame.height),
      CGRect(x: protectedFrame.maxX,
             y: protectedFrame.minY,
             width: bounds.maxX - protectedFrame.maxX,
             height: protectedFrame.height),
    ].filter { $0.width > 0 && $0.height > 0 }
  }

  private var topLoadProbe: some View {
    Color.clear
      .onAppear {
        runtimeState.isTopLoadProbeVisible = true
      }
      .onDisappear {
        runtimeState.isTopLoadProbeVisible = false
      }
    .frame(height: 1)
  }

  private var timelineBottomAnchor: some View {
    Color.clear
      .frame(height: Self.timelineVerticalPadding)
      .id(Self.timelineBottomAnchorId)
      .onAppear(perform: triggerLoadNewerIfNeeded)
      .background {
        GeometryReader { geometry in
          Color.clear.preference(
            key: TimelineBottomAnchorFramePreferenceKey.self,
            value: geometry.frame(in: .named("chatTimeline"))
          )
        }
      }
  }

  @ViewBuilder
  private func rowFrameProbe(for rowId: String,
                             measurementGeneration: Int) -> some View {
    if isActive {
      GeometryReader { geometry in
        let frame = geometry.frame(in: .named("chatTimeline"))
        Color.clear.preference(
          key: TimelineVisibleRowPreferenceKey.self,
          value: [TimelineVisibleRow(
            id: rowId,
            frame: frame,
            measurementGeneration: measurementGeneration
          )]
        )
      }
    }
  }

  @ViewBuilder
  private func explicitAnchorFrameProbe(for rowId: String,
                                        with proxy: ScrollViewProxy) -> some View {
    if isActive,
       let target = scrollTarget,
       target.reason == .explicitAnchor,
       target.messageId == rowId {
      ZStack {
        GeometryReader { geometry in
          Color.clear.preference(
            key: TimelineExplicitAnchorFramePreferenceKey.self,
            value: [target.id: geometry.frame(in: .named("chatTimeline"))]
          )
        }
        TimelineExplicitAnchorProbe(
          runtimeState: runtimeState,
          targetId: target.id,
          onGeometryChange: {
            stabilizeExplicitAnchorAfterNativeGeometryChange(
              with: proxy,
              source: "targetProbe"
            )
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder
  private func latestRowFrameProbe(for rowId: String) -> some View {
    if rows.last?.id == rowId {
      GeometryReader { geometry in
        Color.clear.preference(
          key: TimelineLatestRowFramePreferenceKey.self,
          value: TimelineLatestRowFrameMeasurement(
            rowId: rowId,
            frame: geometry.frame(in: .named("chatTimeline")),
            measurementGeneration: visibilityMeasurementGeneration
          )
        )
      }
    }
  }

  private func triggerLoadOlderIfNeeded(source: String) {
    let viewModelCanLoadOlder = canLoadOlder?()
    guard !isOlderPaginationSuspended || viewModelCanLoadOlder == true else {
      NEChatSwiftUILogger.log(
        "offlineHistory timelineTrigger blocked conversationId=\(diagnosticConversationId) source=\(source) rows=\(rows.count) hasMoreOlder=\(hasMoreOlder) isLoadingOlder=\(isLoadingOlder) dragGen=\(runtimeState.loadOlderGestureGeneration)"
      )
      logLoadOlderDecision("blocked.networkSuspended", source: source)
      return
    }
    runtimeState.rebuildRowOrderIfNeeded(rows: rows)
    clearLoadOlderTopExitGateIfNeeded()
    guard !isLoadOlderTopExitGateActive else {
      if source != "dragNearTop" {
        logLoadOlderDecision("blocked.topExitGate", source: source)
      }
      return
    }
    guard !isLoadOlderGestureThrottled else {
      if source != "dragNearTop" {
        logLoadOlderDecision("blocked.gestureThrottle", source: source)
      }
      return
    }
    guard !suppressLoadOlderRetryUntilUserScroll else {
      logLoadOlderDecision("blocked.suppressed", source: source)
      return
    }
    clearActivePrependScrollSuppressionIfNeeded()
    guard !isActivePrependScrollSuppression else {
      return
    }
    guard !isPrependRestoreInProgress else {
      logLoadOlderDecision("blocked.prependRestore", source: source)
      return
    }
    guard hasUserScrolled else {
      logLoadOlderDecision("blocked.noUserScroll", source: source)
      return
    }
    guard runtimeState.lastLoadOlderRequestDragGeneration != runtimeState.loadOlderGestureGeneration else {
      logLoadOlderDecision("blocked.dragGenerationConsumed", source: source)
      return
    }
    guard !isScrollTargetBlockingLoadOlder else {
      logLoadOlderDecision("blocked.scrollTarget", source: source)
      return
    }
    guard !rows.isEmpty else {
      logLoadOlderDecision("blocked.emptyRows", source: source)
      return
    }
    guard hasMoreOlder || viewModelCanLoadOlder == true else {
      resetLoadOlderTriggerIfNeeded()
      logLoadOlderDecision("blocked.noMoreOlder", source: source)
      return
    }
    guard !isLoadingOlder || viewModelCanLoadOlder == true else {
      logLoadOlderDecision("blocked.loadingOlder", source: source)
      return
    }
    let triggerId = rows.first?.id
    if lastLoadOlderTriggerId != triggerId {
      lastLoadOlderTriggerId = triggerId
      let loadOlderAnchorId = runtimeState.visibleTopMessageId() ?? rows.first?.id
      flushVisibleRowsNotificationIfNeeded()
      guard preparePrependContentOffsetCompensation(
        triggerId: triggerId,
        anchorId: loadOlderAnchorId
      ) else {
        scheduleLoadOlderAfterScrollViewProbeResolves(
          triggerId: triggerId,
          gestureGeneration: runtimeState.loadOlderGestureGeneration
        )
        return
      }
      onLoadOlder(loadOlderAnchorId)
      activateLoadOlderGestureThrottle()
      activateLoadOlderTopExitGate()
      runtimeState.lastLoadOlderRequestDragGeneration = runtimeState.loadOlderGestureGeneration
      logLoadOlderDecision("fire", source: source, triggerId: triggerId)
    } else {
      logLoadOlderDecision("blocked.duplicateTrigger", source: source, triggerId: triggerId)
    }
  }

  private func triggerLoadNewerIfNeeded() {
    guard hasUserScrolled, scrollTarget == nil, !rows.isEmpty else {
      return
    }
    guard hasMoreNewer else {
      resetLoadNewerTriggerIfNeeded()
      return
    }
    guard !isLoadingNewer else {
      return
    }
    let triggerId = rows.last?.id
    if lastLoadNewerTriggerId != triggerId {
      lastLoadNewerTriggerId = triggerId
      flushVisibleRowsNotificationIfNeeded()
      onLoadNewer()
    }
  }

  private func resetLoadOlderTriggerIfNeeded() {
    guard lastLoadOlderTriggerId != nil else {
      return
    }
    lastLoadOlderTriggerId = nil
    runtimeState.lastLoadOlderDecisionSignature = ""
  }

  private func resetLoadNewerTriggerIfNeeded() {
    guard lastLoadNewerTriggerId != nil else {
      return
    }
    lastLoadNewerTriggerId = nil
  }

  @discardableResult
  private func preparePrependContentOffsetCompensation(triggerId: String?,
                                                      anchorId: String?) -> Bool {
    guard !isOlderPaginationSuspended else {
      logTimelineSmoothness("prependPrepareSkipped reason=networkSuspended")
      return false
    }
    guard let scrollView = runtimeState.resolvedScrollView() else {
      NEChatSwiftUILogger.log(
        "timeline prependCompensation missingScrollView trigger=\(triggerId ?? "nil") rows=\(rows.count) probe=\(runtimeState.scrollProbeView != nil) hierarchy=\(runtimeState.scrollProbeView?.timelineSuperviewTrace() ?? "nil")"
      )
      return false
    }
    runtimeState.pendingPrependCompensation = TimelinePrependCompensationState(
      generation: runtimeState.prependCompensationGeneration + 1,
      triggerId: triggerId,
      firstRowId: rows.first?.id,
      rowCount: rows.count,
      contentHeight: scrollView.contentSize.height,
      contentOffsetY: scrollView.contentOffset.y,
      anchorRowId: anchorId,
      interactionGeneration: runtimeState.dragInteractionGeneration
    )
    runtimeState.prependCompensationGeneration += 1
    NEChatSwiftUILogger.log(
      "timeline prependCompensation prepare generation=\(runtimeState.prependCompensationGeneration) trigger=\(triggerId ?? "nil") anchor=\(anchorId ?? "nil") rows=\(rows.count) first=\(rows.first?.id ?? "nil") visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") height=\(scrollView.contentSize.height) offsetY=\(scrollView.contentOffset.y) insetTop=\(scrollView.adjustedContentInset.top) boundsH=\(scrollView.bounds.height)"
    )
    return true
  }

  private func scheduleLoadOlderAfterScrollViewProbeResolves(triggerId: String?,
                                                             gestureGeneration: Int) {
    let generation = runtimeState.scrollViewResolveRetryGeneration + 1
    runtimeState.scrollViewResolveRetryGeneration = generation
    DispatchQueue.main.async {
      guard runtimeState.scrollViewResolveRetryGeneration == generation,
            canLoadOlder?() ?? (!isOlderPaginationSuspended && hasMoreOlder && !isLoadingOlder),
            lastLoadOlderTriggerId == triggerId,
            runtimeState.loadOlderGestureGeneration == gestureGeneration,
            runtimeState.lastLoadOlderRequestDragGeneration != gestureGeneration,
            !isScrollTargetBlockingLoadOlder,
            !rows.isEmpty else {
        return
      }
      let loadOlderAnchorId = runtimeState.visibleTopMessageId() ?? rows.first?.id
      guard preparePrependContentOffsetCompensation(
        triggerId: triggerId,
        anchorId: loadOlderAnchorId
      ) else {
        logLoadOlderDecision("blocked.missingScrollView", source: "probeRetry", triggerId: triggerId)
        resetLoadOlderTriggerIfNeeded()
        return
      }
      onLoadOlder(loadOlderAnchorId)
      activateLoadOlderGestureThrottle()
      activateLoadOlderTopExitGate()
      runtimeState.lastLoadOlderRequestDragGeneration = gestureGeneration
      logLoadOlderDecision("fireAfterProbe", source: "probeRetry", triggerId: triggerId)
    }
  }

  private func updateOlderPaginationSuspension(_ suspended: Bool) {
    runtimeState.olderPaginationSuspensionGeneration += 1
    let suspensionGeneration = runtimeState.olderPaginationSuspensionGeneration
    NEChatSwiftUILogger.log(
      "offlineHistory timelineSuspension conversationId=\(diagnosticConversationId) changed=\(suspended) suspensionGen=\(suspensionGeneration) rows=\(rows.count) hasMoreOlder=\(hasMoreOlder) isLoadingOlder=\(isLoadingOlder) dragGen=\(runtimeState.loadOlderGestureGeneration) pending=\(runtimeState.pendingPrependCompensation?.generation.description ?? "nil") scheduledTarget=\(scheduledScrollTargetId ?? "nil") scheduledReason=\(scheduledScrollTargetReason?.rawValue ?? "nil") scroll=\(runtimeState.scrollMetricsDescription())"
    )
    if suspended {
      cancelPinnedBottomScroll()
      runtimeState.prependCompensationGeneration += 1
      runtimeState.pendingPrependCompensation = nil
      runtimeState.scheduledPrependCompensationGeneration = nil
      runtimeState.scrollViewResolveRetryGeneration += 1
      runtimeState.loadOlderRetryGeneration += 1
      runtimeState.prependRestoreGeneration += 1
      pendingPrependRestoreTarget = nil
      pendingPrependRestoreInitialFirstRowId = nil
      pendingPrependRestoreInitialRowCount = 0
      pendingPrependRestoreObservedRowsChange = false
      if scheduledScrollTargetReason == .prependRestore {
        scheduledScrollTargetId = nil
        scheduledScrollTargetReason = nil
      }
      if let target = scrollTarget,
         target.reason == .prependRestore,
         !runtimeState.hasConsumedScrollTarget(target.id) {
        runtimeState.markScrollTargetConsumed(target.id)
        onScrollTargetConsumed(target.id)
      }
      isMomentumCancellationActive = false
      suppressLoadOlderRetryUntilUserScroll = true
      runtimeState.suppressLoadOlderUntilNextUserDrag = true
      runtimeState.lastLoadOlderRequestDragGeneration = runtimeState.loadOlderGestureGeneration
      runtimeState.lastLoadOlderDecisionSignature = ""
      stopNetworkBreakMomentumIfNeeded(source: "suspension")
      scheduleNetworkBreakMotionDiagnostics(suspensionGeneration: suspensionGeneration)
      logTimelineSmoothness("networkSuspended suspensionGen=\(suspensionGeneration)")
      return
    }

    resetLoadOlderCycleAfterResume(source: "networkReconnect")
  }

  private func resetLoadOlderCycleAfterResume(source: String) {
    // A reachability change can cancel SwiftUI's DragGesture without delivering
    // onEnded. Drop every marker owned by that stale gesture so the next pull is
    // always a fresh pagination cycle.
    suppressLoadOlderRetryUntilUserScroll = false
    suppressLoadOlderRetryUntilNextDrag = false
    suppressLoadOlderRetryCooldownUntil = 0
    runtimeState.suppressLoadOlderUntilNextUserDrag = false
    runtimeState.loadOlderThrottleUntil = 0
    runtimeState.requiresTopExitBeforeNextLoadOlder = false
    runtimeState.isTimelineDragGestureActive = false
    runtimeState.isDraggingTimeline = false
    runtimeState.loadOlderGestureGeneration += 1
    runtimeState.lastLoadOlderRequestDragGeneration = nil
    runtimeState.loadOlderRetryGeneration += 1
    runtimeState.scrollViewResolveRetryGeneration += 1
    resetLoadOlderTriggerIfNeeded()
    NEChatSwiftUILogger.log(
      "offlineHistory timelineResumeReset conversationId=\(diagnosticConversationId) source=\(source) dragGen=\(runtimeState.loadOlderGestureGeneration) rows=\(rows.count) hasMoreOlder=\(hasMoreOlder)"
    )
  }

  private func schedulePrependContentOffsetCompensation(source: String) {
    guard !isOlderPaginationSuspended else {
      logTimelineSmoothness("prependScheduleSkipped source=\(source) reason=networkSuspended")
      return
    }
    guard !isPrependRestoreInProgress else {
      logTimelineSmoothness("prependScheduleSkipped source=\(source) reason=prependRestore")
      return
    }
    guard let state = runtimeState.pendingPrependCompensation else {
      logTimelineSmoothness("prependScheduleSkipped source=\(source) reason=noPending")
      return
    }
    guard rows.count > state.rowCount else {
      logTimelineSmoothness(
        "prependScheduleSkipped source=\(source) reason=rowCount oldRows=\(state.rowCount)"
      )
      return
    }
    guard rows.first?.id != state.firstRowId else {
      logTimelineSmoothness(
        "prependScheduleSkipped source=\(source) reason=firstUnchanged oldFirst=\(state.firstRowId ?? "nil")"
      )
      return
    }
    let generation = runtimeState.prependCompensationGeneration
    let suspensionGeneration = runtimeState.olderPaginationSuspensionGeneration
    guard runtimeState.scheduledPrependCompensationGeneration != runtimeState.prependCompensationGeneration else {
      logTimelineSmoothness(
        "prependScheduleSkipped source=\(source) reason=alreadyScheduled generation=\(runtimeState.prependCompensationGeneration)"
      )
      return
    }
    runtimeState.scheduledPrependCompensationGeneration = generation
    logTimelineSmoothness(
      "prependSchedule source=\(source) generation=\(generation) oldRows=\(state.rowCount) oldFirst=\(state.firstRowId ?? "nil")"
    )
    applyPrependContentOffsetCompensationIfNeeded(
      generation: generation,
      source: source,
      isFinalAttempt: false
    )
    for (index, delay) in Self.prependContentOffsetCompensationDelays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard !isOlderPaginationSuspended,
              runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration,
              runtimeState.scheduledPrependCompensationGeneration == generation else {
          logTimelineSmoothness(
            "prependAsyncSkipped source=\(source) generation=\(generation) suspensionGen=\(suspensionGeneration) currentSuspensionGen=\(runtimeState.olderPaginationSuspensionGeneration)"
          )
          return
        }
        applyPrependContentOffsetCompensationIfNeeded(
          generation: generation,
          source: source,
          isFinalAttempt: index == Self.prependContentOffsetCompensationDelays.indices.last
        )
      }
    }
  }

  private func handleTimelineContentSizeChanged(with proxy: ScrollViewProxy) {
    guard isActive else {
      return
    }
    guard !isOlderPaginationSuspended else {
      logSuspendedTimelineAction("contentSizeChanged", source: "contentSize")
      return
    }
    runtimeState.rebuildRowOrderIfNeeded(rows: rows)
    stabilizeExplicitAnchorAfterNativeGeometryChange(
      with: proxy,
      source: "contentSize"
    )
    pinBottomIfNeeded(with: proxy)
    guard let generation = runtimeState.pendingPrependCompensation?.generation else {
      logTimelineSmoothness("contentSizeChanged reason=noPending")
      return
    }
    logTimelineSmoothness("contentSizeChanged generation=\(generation)")
    applyPrependContentOffsetCompensationIfNeeded(
      generation: generation,
      source: "contentSize",
      isFinalAttempt: false
    )
  }

  private func stabilizeExplicitAnchorAfterNativeGeometryChange(with proxy: ScrollViewProxy,
                                                                source: String) {
    guard let target = scrollTarget,
          target.reason == .explicitAnchor,
          scheduledScrollTargetId == target.id else {
      return
    }
    refreshExplicitAnchorPosition(
      for: target,
      fallbackFrame: runtimeState.explicitAnchorFrame,
      with: proxy,
      source: source
    )
  }

  private func applyPrependContentOffsetCompensationIfNeeded(generation: Int,
                                                            source: String,
                                                            isFinalAttempt: Bool) {
    guard !isOlderPaginationSuspended else {
      logTimelineSmoothness(
        "prependApplySkipped source=\(source) reason=networkSuspended generation=\(generation)"
      )
      return
    }
    guard runtimeState.prependCompensationGeneration == generation else {
      logTimelineSmoothness(
        "prependApplySkipped source=\(source) reason=generation requested=\(generation) current=\(runtimeState.prependCompensationGeneration)"
      )
      return
    }
    guard !isPrependRestoreInProgress else {
      logTimelineSmoothness("prependApplySkipped source=\(source) reason=prependRestore generation=\(generation)")
      return
    }
    guard var state = runtimeState.pendingPrependCompensation else {
      logTimelineSmoothness("prependApplySkipped source=\(source) reason=noPending generation=\(generation)")
      return
    }
    guard let scrollView = runtimeState.resolvedScrollView() else {
      logTimelineSmoothness("prependApplySkipped source=\(source) reason=noScrollView generation=\(generation)")
      return
    }
    guard rows.count > state.rowCount else {
      logTimelineSmoothness(
        "prependApplySkipped source=\(source) reason=rowCount generation=\(generation) oldRows=\(state.rowCount)"
      )
      return
    }
    guard rows.first?.id != state.firstRowId else {
      logTimelineSmoothness(
        "prependApplySkipped source=\(source) reason=firstUnchanged generation=\(generation) oldFirst=\(state.firstRowId ?? "nil")"
      )
      return
    }
    let currentOffsetY = scrollView.contentOffset.y
    let currentContentHeight = scrollView.contentSize.height
    let velocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
    let preAdjustmentDragging = scrollView.isDragging
    let preAdjustmentDecelerating = scrollView.isDecelerating
    let hasAppliedAnchoredCompensation = state.anchorRowId != nil && state.appliedCount > 0
    let incrementalDeltaHeight = currentContentHeight - state.contentHeight
    guard abs(incrementalDeltaHeight) > Self.minimumPrependContentHeightDelta else {
      if reapplyPrependAnchorHoldIfNeeded(
        scrollView: scrollView,
        state: &state,
        generation: generation,
        source: source,
        isFinalAttempt: isFinalAttempt,
        currentContentHeight: currentContentHeight,
        currentOffsetY: currentOffsetY,
        velocityY: velocityY
      ) {
        return
      }
      if completePrependContentOffsetCompensationIfAnchorRestored(
        state,
        scrollView: scrollView,
        generation: generation,
        source: source,
        isFinalAttempt: isFinalAttempt
      ) {
        return
      }
      NEChatSwiftUILogger.log(
        "timeline prependCompensation waitHeight generation=\(generation) source=\(source) final=\(isFinalAttempt) rows=\(rows.count) oldHeight=\(state.contentHeight) currentHeight=\(scrollView.contentSize.height) offsetY=\(scrollView.contentOffset.y)"
      )
      if isFinalAttempt {
        completePrependContentOffsetCompensation(generation: generation, source: source)
      }
      return
    }
    let compensationBaseOffsetY = hasAppliedAnchoredCompensation ? state.contentOffsetY : currentOffsetY
    let targetOffsetY = clampedPrependContentOffsetY(
      compensationBaseOffsetY + incrementalDeltaHeight,
      in: scrollView
    )
    guard abs(scrollView.contentOffset.y - targetOffsetY) > Self.minimumPrependContentOffsetAdjustment else {
      NEChatSwiftUILogger.log(
        "timeline prependCompensation skipSmall generation=\(generation) source=\(source) final=\(isFinalAttempt) rows=\(rows.count) deltaHeight=\(incrementalDeltaHeight) applied=\(state.appliedCount) baseY=\(compensationBaseOffsetY) targetY=\(targetOffsetY) currentY=\(scrollView.contentOffset.y)"
      )
      state.contentHeight = scrollView.contentSize.height
      state.contentOffsetY = scrollView.contentOffset.y
      runtimeState.pendingPrependCompensation = state
      if completePrependContentOffsetCompensationIfAnchorRestored(
        state,
        scrollView: scrollView,
        generation: generation,
        source: source,
        isFinalAttempt: isFinalAttempt
      ) {
        return
      }
      if isFinalAttempt {
        completePrependContentOffsetCompensation(generation: generation, source: source)
      }
      return
    }
    if shouldSkipAnchoredPrependCompensationForActivePullDown(
      scrollView: scrollView,
      state: state,
      currentOffsetY: currentOffsetY,
      targetOffsetY: targetOffsetY,
      velocityY: velocityY
    ) {
      state.contentHeight = currentContentHeight
      state.contentOffsetY = currentOffsetY
      runtimeState.pendingPrependCompensation = state
      activateActivePrependScrollSuppression()
      activateLoadOlderGestureThrottle()
      NEChatSwiftUILogger.log(
        "timeline prependCompensation skipActivePullDown generation=\(generation) source=\(source) final=\(isFinalAttempt) trigger=\(state.triggerId ?? "nil") anchor=\(state.anchorRowId ?? "nil") rows=\(rows.count) first=\(rows.first?.id ?? "nil") visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") visibleTopIndex=\(runtimeState.visibleTopRowIndex().map(String.init) ?? "nil") deltaHeight=\(incrementalDeltaHeight) applied=\(state.appliedCount) oldHeight=\(currentContentHeight - incrementalDeltaHeight) newHeight=\(currentContentHeight) baselineY=\(state.contentOffsetY) currentY=\(currentOffsetY) targetY=\(targetOffsetY) jumpY=\(targetOffsetY - currentOffsetY) dragging=\(preAdjustmentDragging) decelerating=\(preAdjustmentDecelerating) timelineDragging=\(runtimeState.isDraggingTimeline) velocityY=\(velocityY) interactionGen=\(runtimeState.dragInteractionGeneration) pendingInteractionGen=\(state.interactionGeneration)"
      )
      completePrependContentOffsetCompensation(generation: generation, source: "\(source).activePullDown")
      return
    }
    if shouldSkipPrependCompensationForUserScroll(
      scrollView: scrollView,
      state: state,
      currentOffsetY: currentOffsetY,
      velocityY: velocityY
    ) {
      state.contentHeight = currentContentHeight
      state.contentOffsetY = currentOffsetY
      runtimeState.pendingPrependCompensation = state
      activateActivePrependScrollSuppression()
      activateLoadOlderGestureThrottle()
      NEChatSwiftUILogger.log(
        "timeline prependCompensation skipUserScroll generation=\(generation) source=\(source) final=\(isFinalAttempt) trigger=\(state.triggerId ?? "nil") rows=\(rows.count) first=\(rows.first?.id ?? "nil") visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") deltaHeight=\(incrementalDeltaHeight) applied=\(state.appliedCount) oldHeight=\(currentContentHeight - incrementalDeltaHeight) newHeight=\(currentContentHeight) baselineY=\(state.contentOffsetY) currentY=\(currentOffsetY) dragging=\(preAdjustmentDragging) decelerating=\(preAdjustmentDecelerating) timelineDragging=\(runtimeState.isDraggingTimeline) velocityY=\(velocityY)"
      )
      completePrependContentOffsetCompensation(generation: generation, source: source)
      return
    }
    UIView.performWithoutAnimation {
      scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY), animated: false)
    }
    state.appliedCount += 1
    state.contentHeight = currentContentHeight
    state.contentOffsetY = scrollView.contentOffset.y
    runtimeState.pendingPrependCompensation = state
    NEChatSwiftUILogger.log(
      "timeline prependCompensation apply generation=\(generation) source=\(source) final=\(isFinalAttempt) trigger=\(state.triggerId ?? "nil") rows=\(rows.count) first=\(rows.first?.id ?? "nil") visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") deltaHeight=\(incrementalDeltaHeight) applied=\(state.appliedCount) oldHeight=\(currentContentHeight - incrementalDeltaHeight) newHeight=\(currentContentHeight) baseY=\(compensationBaseOffsetY) fromY=\(currentOffsetY) toY=\(targetOffsetY) currentY=\(scrollView.contentOffset.y) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating) velocityY=\(velocityY)"
    )
    if completePrependContentOffsetCompensationIfAnchorRestored(
      state,
      scrollView: scrollView,
      generation: generation,
      source: source,
      isFinalAttempt: isFinalAttempt
    ) {
      return
    }
    if isFinalAttempt {
      completePrependContentOffsetCompensation(generation: generation, source: source)
    }
  }

  private func completePrependContentOffsetCompensationIfAnchorRestored(_ state: TimelinePrependCompensationState,
                                                                        scrollView: UIScrollView,
                                                                        generation: Int,
                                                                        source: String,
                                                                        isFinalAttempt: Bool) -> Bool {
    guard state.appliedCount > 0,
          let anchorId = state.anchorRowId,
          let anchorIndex = runtimeState.rowIndex(for: anchorId),
          let visibleTopIndex = runtimeState.visibleTopRowIndex() else {
      return false
    }
    let tolerance = max(
      Self.prependCompensationAnchorSettleRowTolerance,
      runtimeState.visibleRowIds.count + 2
    )
    guard abs(visibleTopIndex - anchorIndex) <= tolerance else {
      return false
    }
    NEChatSwiftUILogger.log(
      "timeline prependCompensation anchorRestored generation=\(generation) source=\(source) anchor=\(anchorId) anchorIndex=\(anchorIndex) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") visibleTopIndex=\(visibleTopIndex) tolerance=\(tolerance) rows=\(rows.count) applied=\(state.appliedCount)"
    )
    if isPrependCompensationScrollActive(scrollView), !isFinalAttempt {
      NEChatSwiftUILogger.log(
        "timeline prependCompensation anchorRestoredHold generation=\(generation) source=\(source) anchor=\(anchorId) offsetY=\(scrollView.contentOffset.y) intendedY=\(state.contentOffsetY) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating) timelineDragging=\(runtimeState.isDraggingTimeline) velocityY=\(scrollView.panGestureRecognizer.velocity(in: scrollView).y)"
      )
      return true
    }
    completePrependContentOffsetCompensation(
      generation: generation,
      source: "\(source).anchorRestored"
    )
    return true
  }

  private func reapplyPrependAnchorHoldIfNeeded(scrollView: UIScrollView,
                                                state: inout TimelinePrependCompensationState,
                                                generation: Int,
                                                source: String,
                                                isFinalAttempt: Bool,
                                                currentContentHeight: CGFloat,
                                                currentOffsetY: CGFloat,
                                                velocityY: CGFloat) -> Bool {
    guard state.anchorRowId != nil,
          state.appliedCount > 0 else {
      return false
    }
    let intendedOffsetY = clampedPrependContentOffsetY(state.contentOffsetY, in: scrollView)
    let driftY = currentOffsetY - intendedOffsetY
    guard abs(driftY) > Self.prependCompensationAnchorHoldOffsetThreshold else {
      return false
    }
    UIView.performWithoutAnimation {
      scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: intendedOffsetY), animated: false)
    }
    state.appliedCount += 1
    state.contentHeight = currentContentHeight
    state.contentOffsetY = scrollView.contentOffset.y
    runtimeState.pendingPrependCompensation = state
    NEChatSwiftUILogger.log(
      "timeline prependCompensation anchorHoldReapply generation=\(generation) source=\(source) final=\(isFinalAttempt) trigger=\(state.triggerId ?? "nil") rows=\(rows.count) first=\(rows.first?.id ?? "nil") visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") applied=\(state.appliedCount) fromY=\(currentOffsetY) toY=\(intendedOffsetY) currentY=\(scrollView.contentOffset.y) driftY=\(driftY) contentH=\(currentContentHeight) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating) timelineDragging=\(runtimeState.isDraggingTimeline) velocityY=\(velocityY)"
    )
    if isFinalAttempt {
      completePrependContentOffsetCompensation(generation: generation, source: "\(source).anchorHoldFinal")
    }
    return true
  }

  private func clampedPrependContentOffsetY(_ offsetY: CGFloat,
                                            in scrollView: UIScrollView) -> CGFloat {
    let minimumOffsetY = -scrollView.adjustedContentInset.top
    let maximumOffsetY = max(
      minimumOffsetY,
      scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
    )
    return min(maximumOffsetY, max(minimumOffsetY, offsetY))
  }

  private func isPrependCompensationScrollActive(_ scrollView: UIScrollView) -> Bool {
    scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
  }

  private func shouldSkipAnchoredPrependCompensationForActivePullDown(scrollView: UIScrollView,
                                                                      state: TimelinePrependCompensationState,
                                                                      currentOffsetY: CGFloat,
                                                                      targetOffsetY: CGFloat,
                                                                      velocityY: CGFloat) -> Bool {
    guard state.anchorRowId != nil,
          state.appliedCount == 0,
          !isPrependRestoreInProgress else {
      return false
    }

    let hasNewScrollInteraction = runtimeState.dragInteractionGeneration != state.interactionGeneration
    let isTopRegion = runtimeState.isNearTopVisible(threshold: Self.loadOlderPreloadRowThreshold) ||
      (runtimeState.visibleTopRowIndex() ?? Int.max) <= Self.loadOlderPreloadRowThreshold
    let jumpY = targetOffsetY - currentOffsetY
    let jumpThreshold = max(
      scrollView.bounds.height,
      Self.prependCompensationActivePullDownJumpThreshold
    )
    let isLargeOppositeJump = jumpY > jumpThreshold
    let isPullDownGestureActive = runtimeState.isDraggingTimeline ||
      scrollView.isDragging ||
      scrollView.isDecelerating ||
      velocityY > Self.prependCompensationActivePullDownVelocityFloor

    return hasNewScrollInteraction &&
      isPullDownGestureActive &&
      isTopRegion &&
      isLargeOppositeJump
  }

  private func shouldSkipPrependCompensationForUserScroll(scrollView: UIScrollView,
                                                          state: TimelinePrependCompensationState,
                                                          currentOffsetY: CGFloat,
                                                          velocityY: CGFloat) -> Bool {
    guard state.anchorRowId == nil else {
      return false
    }
    guard !isPrependRestoreInProgress else {
      return false
    }

    let movedFromCompensationBaseline = abs(currentOffsetY - state.contentOffsetY)
    let hasNewScrollInteraction = runtimeState.dragInteractionGeneration != state.interactionGeneration
    let movedTowardOlderMessages = currentOffsetY < state.contentOffsetY - Self.prependCompensationUserScrollOffsetThreshold
    let movedSubstantially = movedFromCompensationBaseline > Self.prependCompensationUserScrollOffsetThreshold * 2
    let isActivelyScrolling = scrollView.isDragging || scrollView.isDecelerating || runtimeState.isDraggingTimeline
    let isFastGesture = abs(velocityY) > Self.prependCompensationUserScrollVelocityThreshold

    return (hasNewScrollInteraction && isActivelyScrolling && movedSubstantially) ||
      (isActivelyScrolling && movedTowardOlderMessages && isFastGesture) ||
      (hasNewScrollInteraction && movedSubstantially)
  }

  private func completePrependContentOffsetCompensation(generation: Int,
                                                        source: String) {
    guard runtimeState.prependCompensationGeneration == generation,
          let state = runtimeState.pendingPrependCompensation else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline prependCompensation complete generation=\(generation) source=\(source) rows=\(rows.count) applied=\(state.appliedCount) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil")"
    )
    logTimelineSmoothness("prependComplete source=\(source) generation=\(generation) applied=\(state.appliedCount)")
    runtimeState.pendingPrependCompensation = nil
    runtimeState.scheduledPrependCompensationGeneration = nil
  }

  private func completeStalePrependContentOffsetCompensationIfNeeded(source: String) {
    guard let state = runtimeState.pendingPrependCompensation,
          rows.count <= state.rowCount || rows.first?.id == state.firstRowId else {
      logTimelineSmoothness("prependCompleteStaleSkipped source=\(source)")
      return
    }
    NEChatSwiftUILogger.log(
      "timeline prependCompensation completeStale generation=\(state.generation) source=\(source) rows=\(rows.count) first=\(rows.first?.id ?? "nil") trigger=\(state.triggerId ?? "nil")"
    )
    runtimeState.prependCompensationGeneration += 1
    runtimeState.pendingPrependCompensation = nil
    runtimeState.scheduledPrependCompensationGeneration = nil
  }

  private func completeUnchangedPrependLoadIfNeeded() -> Bool {
    guard let state = runtimeState.pendingPrependCompensation,
          rows.count <= state.rowCount || rows.first?.id == state.firstRowId else {
      return false
    }

    runtimeState.prependCompensationGeneration += 1
    runtimeState.pendingPrependCompensation = nil
    runtimeState.scheduledPrependCompensationGeneration = nil
    runtimeState.scrollViewResolveRetryGeneration += 1
    runtimeState.loadOlderRetryGeneration += 1
    suppressLoadOlderRetryUntilUserScroll = true
    // Match MJRefresh: a failed/unchanged load ends the current pull cycle.
    // Remaining onChanged callbacks from the same finger drag must not start
    // another request; a new drag clears this gate in handleTimelineDragChanged.
    runtimeState.suppressLoadOlderUntilNextUserDrag = true
    runtimeState.lastLoadOlderDecisionSignature = ""
    logTimelineSmoothness(
      "prependCompleteUnchanged rows=\(rows.count) first=\(rows.first?.id ?? "nil")"
    )
    return true
  }

  private func cancelPendingPrependContentOffsetCompensation(source: String,
                                                            targetId: String) {
    guard let state = runtimeState.pendingPrependCompensation else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline prependCompensation cancel generation=\(state.generation) source=\(source) target=\(targetId) rows=\(rows.count) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil")"
    )
    runtimeState.prependCompensationGeneration += 1
    runtimeState.pendingPrependCompensation = nil
    runtimeState.scheduledPrependCompensationGeneration = nil
  }

  private func updateRowFramesIfNeeded(_ visibleRows: [TimelineVisibleRow],
                                       viewportHeight: CGFloat,
                                       with proxy: ScrollViewProxy) {
    guard isActive else {
      return
    }
    runtimeState.lastMeasuredVisibleRows = visibleRows
    runtimeState.lastMeasuredViewportHeight = viewportHeight
    let currentRowIds = Set(rows.map(\.id))
    let measuredFrames = visibleRows.reduce(into: [String: CGRect]()) { result, row in
      if currentRowIds.contains(row.id) {
        result[row.id] = row.frame
      }
    }
    if operationMenu == nil {
      if !rowFrames.isEmpty {
        rowFrames = [:]
      }
    } else if rowFrames != measuredFrames {
      rowFrames = measuredFrames
    }

    let nextVisibleRowIds: Set<String> = Set(measuredFrames.compactMap { id, frame -> String? in
      guard !frame.isNull,
            !frame.isInfinite,
            frame.maxY > 0,
            frame.minY < viewportHeight else {
        return nil
      }
      return id
    })
    guard runtimeState.visibleRowIds != nextVisibleRowIds else {
      return
    }
    runtimeState.visibleRowIds = nextVisibleRowIds
    scheduleVisibleRowsNotification(with: proxy)
  }

  private func replayMeasuredVisibleRowsAfterActivation(viewportHeight: CGFloat,
                                                        with proxy: ScrollViewProxy) {
    guard !runtimeState.lastMeasuredVisibleRows.isEmpty else {
      return
    }
    let measuredViewportHeight = viewportHeight > 0
      ? viewportHeight
      : runtimeState.lastMeasuredViewportHeight
    runtimeState.lastNotifiedVisibleRowIds.removeAll()
    updateRowFramesIfNeeded(
      runtimeState.lastMeasuredVisibleRows,
      viewportHeight: measuredViewportHeight,
      with: proxy
    )
    if !runtimeState.visibleRowIds.isEmpty {
      scheduleVisibleRowsNotification(with: proxy)
    }
  }

  private func updateExplicitAnchorFrameIfNeeded(_ frames: [String: CGRect],
                                                 with proxy: ScrollViewProxy) {
    guard isActive,
          let target = scrollTarget,
          target.reason == .explicitAnchor else {
      runtimeState.explicitAnchorFrame = nil
      return
    }
    refreshExplicitAnchorPosition(
      for: target,
      fallbackFrame: frames[target.id],
      with: proxy,
      source: "preference"
    )
  }

  private func refreshExplicitAnchorPosition(for target: ChatTimelineScrollTarget,
                                             fallbackFrame: CGRect?,
                                             with proxy: ScrollViewProxy,
                                             source: String) {
    guard isActive,
          scrollTarget?.id == target.id,
          target.reason == .explicitAnchor else {
      return
    }
    let previousFrame = runtimeState.explicitAnchorFrame
    guard let nextFrame = currentExplicitAnchorFrame(
      for: target,
      fallbackFrame: fallbackFrame
    ) else {
      return
    }
    runtimeState.explicitAnchorFrame = nextFrame
    guard scheduledScrollTargetId == target.id,
          runtimeState.viewportHeight > 0 else {
      return
    }
    let isVisible = nextFrame.maxY > 0 && nextFrame.minY < runtimeState.viewportHeight
    let effectiveAnchor = resolvedExplicitAnchor(for: target, frame: nextFrame)
    let isPositioned = isExplicitAnchorPositioned(nextFrame, target: target)
    if previousFrame != nextFrame || !isPositioned {
      NEChatSwiftUILogger.log(
        "messageJump timeline frameEvaluated source=\(source) id=\(target.id) messageId=\(target.messageId) requestedAnchor=\(target.anchor.rawValue) effectiveAnchor=\(effectiveAnchor.rawValue) frame=\(nextFrame) viewportHeight=\(runtimeState.viewportHeight) visible=\(isVisible) positioned=\(isPositioned) initialApplied=\(runtimeState.appliedExplicitAnchorScrollTargetId == target.id) correctionCount=\(runtimeState.explicitAnchorCorrectionCount)"
      )
    }
    guard runtimeState.appliedExplicitAnchorScrollTargetId == target.id else {
      performExplicitAnchorScroll(to: target, with: proxy)
      return
    }
    guard isPositioned else {
      performExplicitAnchorCorrectionIfNeeded(to: target, with: proxy)
      return
    }
    NEChatSwiftUILogger.log(
      "messageJump timeline leaseHeld source=\(source) id=\(target.id) messageId=\(target.messageId) frame=\(nextFrame) viewportHeight=\(runtimeState.viewportHeight) correctionCount=\(runtimeState.explicitAnchorCorrectionCount)"
    )
  }

  private func currentExplicitAnchorFrame(for target: ChatTimelineScrollTarget,
                                          fallbackFrame: CGRect? = nil) -> CGRect? {
    if let nativeFrame = runtimeState.explicitAnchorViewportFrame(targetId: target.id) {
      return nativeFrame
    }
    return fallbackFrame ?? runtimeState.explicitAnchorFrame
  }

  private func resolvedExplicitAnchor(for target: ChatTimelineScrollTarget,
                                      frame: CGRect?) -> ChatTimelineScrollAnchor {
    guard target.reason == .explicitAnchor,
          target.anchor == .center,
          let frame,
          runtimeState.viewportHeight > 0,
          frame.height >= runtimeState.viewportHeight else {
      return target.anchor
    }
    return .top
  }

  private func isExplicitAnchorPositioned(_ frame: CGRect,
                                          target: ChatTimelineScrollTarget) -> Bool {
    guard runtimeState.viewportHeight > 0 else {
      return false
    }
    let isExactlyPositioned: Bool
    switch resolvedExplicitAnchor(for: target, frame: frame) {
    case .top:
      isExactlyPositioned = abs(frame.minY) <= Self.explicitAnchorPositionTolerance
    case .center:
      isExactlyPositioned = abs(frame.midY - runtimeState.viewportHeight / 2) <= Self.explicitAnchorPositionTolerance
    case .bottom:
      isExactlyPositioned = abs(frame.maxY - runtimeState.viewportHeight) <= Self.explicitAnchorPositionTolerance
    }
    if isExactlyPositioned {
      return true
    }
    guard let scrollView = runtimeState.resolvedScrollView(),
          let targetOffsetY = explicitAnchorTargetOffsetY(
            for: frame,
            target: target,
            scrollView: scrollView
          ) else {
      return false
    }
    let isVisible = frame.maxY > 0 && frame.minY < runtimeState.viewportHeight
    return isVisible &&
      abs(targetOffsetY - scrollView.contentOffset.y) <= Self.explicitAnchorPositionTolerance
  }

  private func updateViewportHeightIfNeeded(_ height: CGFloat) {
    guard runtimeState.viewportHeight != height else {
      return
    }
    runtimeState.viewportHeight = height
    runtimeState.lastBottomVisibility = nil
    notifyLatestRowVisibilityIfNeeded(runtimeState.latestRowMeasurement)
    updateLatestMessageVisibilityIfNeeded()
  }

  private func scheduleLatestRowFrameUpdate(_ measurement: TimelineLatestRowFrameMeasurement?,
                                            with proxy: ScrollViewProxy) {
    guard isActive else {
      return
    }
    runtimeState.latestRowMeasurement = measurement
    notifyLatestRowVisibilityIfNeeded(measurement)
    let frame = measurement?.frame
    let currentFrame = runtimeState.hasPendingLatestRowFrame
      ? runtimeState.pendingLatestRowFrame
      : runtimeState.latestRowFrame
    guard currentFrame != frame else {
      return
    }
    runtimeState.pendingLatestRowFrame = frame
    runtimeState.hasPendingLatestRowFrame = true
    scheduleBottomFrameUpdate(with: proxy)
  }

  private func notifyLatestRowVisibilityIfNeeded(_ measurement: TimelineLatestRowFrameMeasurement?) {
    guard isActive,
          let latestRowId = rows.last?.id else {
      return
    }
    let frame = measurement?.rowId == latestRowId ? measurement?.frame : nil
    let isVisible = frame.map { frame in
      !frame.isNull &&
        !frame.isInfinite &&
        runtimeState.viewportHeight > 0 &&
        frame.maxY > 0 &&
        frame.minY < runtimeState.viewportHeight
    } ?? false
    let measurementGeneration = measurement?.measurementGeneration
    guard runtimeState.lastNotifiedLatestRowId != latestRowId ||
      runtimeState.lastNotifiedLatestRowVisibility != isVisible ||
      runtimeState.lastNotifiedLatestRowMeasurementGeneration != measurementGeneration else {
      return
    }
    runtimeState.lastNotifiedLatestRowId = latestRowId
    runtimeState.lastNotifiedLatestRowVisibility = isVisible
    runtimeState.lastNotifiedLatestRowMeasurementGeneration = measurementGeneration
    onLatestRowVisibilityChange(isVisible)
  }

  private func scheduleBottomAnchorFrameUpdate(_ frame: CGRect?,
                                               with proxy: ScrollViewProxy) {
    let currentFrame = runtimeState.hasPendingBottomAnchorFrame
      ? runtimeState.pendingBottomAnchorFrame
      : runtimeState.bottomAnchorFrame
    guard isActive, currentFrame != frame else {
      return
    }
    runtimeState.pendingBottomAnchorFrame = frame
    runtimeState.hasPendingBottomAnchorFrame = true
    scheduleBottomFrameUpdate(with: proxy)
  }

  private func scheduleBottomFrameUpdate(with proxy: ScrollViewProxy) {
    guard !runtimeState.isBottomFrameUpdateScheduled else {
      return
    }
    runtimeState.isBottomFrameUpdateScheduled = true
    runtimeState.bottomFrameUpdateGeneration += 1
    let generation = runtimeState.bottomFrameUpdateGeneration
    DispatchQueue.main.async {
      guard runtimeState.bottomFrameUpdateGeneration == generation else {
        return
      }
      runtimeState.isBottomFrameUpdateScheduled = false
      guard isActive else {
        runtimeState.clearPendingBottomFrames()
        return
      }

      var didChange = false
      if runtimeState.hasPendingLatestRowFrame {
        let frame = runtimeState.pendingLatestRowFrame
        runtimeState.hasPendingLatestRowFrame = false
        runtimeState.pendingLatestRowFrame = nil
        if runtimeState.latestRowFrame != frame {
          runtimeState.latestRowFrame = frame
          didChange = true
        }
      }
      if runtimeState.hasPendingBottomAnchorFrame {
        let frame = runtimeState.pendingBottomAnchorFrame
        runtimeState.hasPendingBottomAnchorFrame = false
        runtimeState.pendingBottomAnchorFrame = nil
        if runtimeState.bottomAnchorFrame != frame {
          runtimeState.bottomAnchorFrame = frame
          didChange = true
        }
      }
      guard didChange else {
        return
      }
      updateLatestMessageVisibilityIfNeeded()
      pinBottomIfNeeded(with: proxy)
    }
  }

  private func cancelPendingBottomFrameUpdate() {
    runtimeState.bottomFrameUpdateGeneration += 1
    runtimeState.isBottomFrameUpdateScheduled = false
    runtimeState.clearPendingBottomFrames()
  }

  private func updateLatestMessageVisibilityIfNeeded(latestFrame: CGRect? = nil,
                                                     bottomFrame: CGRect? = nil) {
    guard rows.last != nil else {
      updateBottomVisibilityIfNeeded(isVisible: true)
      return
    }
    if runtimeState.isContentWithinViewport(tolerance: Self.bottomVisibilityTolerance) {
      reportAllRowsVisibleWhenContentFits()
      updateBottomVisibilityIfNeeded(isVisible: true)
      return
    }
    let frame = latestFrame ?? runtimeState.latestRowFrame
    let bottomFrame = bottomFrame ?? runtimeState.bottomAnchorFrame
    let hasMeasuredBottomFrames = frame != nil && bottomFrame != nil
    let fallbackIsVisible = runtimeState.isAtBottomEdge(tolerance: Self.bottomVisibilityTolerance)
    let isVisible = Self.isTimelineBottomVisible(
      latestFrame: frame,
      bottomFrame: bottomFrame,
      viewportHeight: runtimeState.viewportHeight,
      fallbackIsVisible: fallbackIsVisible
    )
    if shouldLogBottomDiagnostic {
      NEChatSwiftUILogger.log(
        "timeline diagnostic bottomVisibility evaluate visible=\(isVisible) fallback=\(fallbackIsVisible) measured=\(hasMeasuredBottomFrames) latest=\(frame?.debugDescription ?? "nil") bottom=\(bottomFrame?.debugDescription ?? "nil") viewportH=\(runtimeState.viewportHeight) target=\(scrollTarget?.id ?? "nil") targetAgeMs=\(scrollTarget?.ageMilliseconds.description ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil") keepsPinned=\(keepsBottomPinned) scroll=\(runtimeState.scrollMetricsDescription())"
      )
    }
    updateBottomVisibilityIfNeeded(
      isVisible: isVisible,
      forceNotify: isVisible && keepsBottomPinned && hasMeasuredBottomFrames
    )
  }

  private func pinBottomIfNeeded(with proxy: ScrollViewProxy) {
    guard !isOlderPaginationSuspended else {
      logSuspendedTimelineAction("pinBottomSkipped", source: "pinBottom")
      return
    }
    guard isActive,
          keepsBottomPinned,
          !rows.isEmpty else {
      return
    }
    guard scrollTarget?.reason != .jumpToLatest,
          scheduledScrollTargetReason != .jumpToLatest else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic pinBottom skip reason=jumpToLatest target=\(scrollTarget?.id ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil") rows=\(rows.count) scroll=\(runtimeState.scrollMetricsDescription())"
      )
      return
    }

    if runtimeState.isAtBottomEdge(tolerance: Self.bottomVisibilityTolerance) {
      if runtimeState.scheduledPinnedBottomScrollGeneration != nil {
        cancelPinnedBottomScroll()
      }
      return
    }
    guard runtimeState.scheduledPinnedBottomScrollGeneration == nil else {
      return
    }

    runtimeState.pinnedBottomScrollGeneration += 1
    let generation = runtimeState.pinnedBottomScrollGeneration
    let suspensionGeneration = runtimeState.olderPaginationSuspensionGeneration
    runtimeState.scheduledPinnedBottomScrollGeneration = generation
    let delays = runtimeState.usesFastInitialBottomPin && !hasUserScrolled
      ? Self.initialPinnedBottomScrollDelays
      : Self.pinnedBottomScrollDelays
    NEChatSwiftUILogger.log(
      "timeline diagnostic pinBottom schedule generation=\(generation) fast=\(runtimeState.usesFastInitialBottomPin) hasUserScrolled=\(hasUserScrolled) delays=\(delays) target=\(scrollTarget?.id ?? "nil") targetReason=\(scrollTarget?.reason.rawValue ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil") rows=\(rows.count) scroll=\(runtimeState.scrollMetricsDescription())"
    )
    let action = {
      guard !isOlderPaginationSuspended,
            runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration else {
        logSuspendedTimelineAction(
          "pinBottomApplyIgnored generation=\(generation) suspensionGen=\(suspensionGeneration)",
          source: "pinBottom"
        )
        return
      }
      proxy.scrollTo(Self.timelineBottomAnchorId, anchor: .bottom)
    }
    let applyAction: (String) -> Void = { source in
      guard !isOlderPaginationSuspended,
            runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration else {
        logSuspendedTimelineAction(
          "pinBottomApplyIgnored generation=\(generation) suspensionGen=\(suspensionGeneration)",
          source: source
        )
        return
      }
      let before = runtimeState.scrollMetricsDescription()
      action()
      NEChatSwiftUILogger.log(
        "timeline diagnostic pinBottom apply generation=\(generation) source=\(source) before=\(before) afterSync=\(runtimeState.scrollMetricsDescription()) target=\(scrollTarget?.id ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil")"
      )
      DispatchQueue.main.async {
        guard isActive else {
          NEChatSwiftUILogger.log(
            "timeline diagnostic pinBottom afterLayout ignored reason=inactive generation=\(generation) source=\(source)"
          )
          return
        }
        guard !isOlderPaginationSuspended,
              runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration else {
          logSuspendedTimelineAction(
            "pinBottomAfterLayoutIgnored generation=\(generation) suspensionGen=\(suspensionGeneration)",
            source: source
          )
          return
        }
        guard runtimeState.pinnedBottomScrollGeneration == generation else {
          NEChatSwiftUILogger.log(
            "timeline diagnostic pinBottom afterLayout ignored reason=staleGeneration generation=\(generation) current=\(runtimeState.pinnedBottomScrollGeneration) source=\(source)"
          )
          return
        }
        scrollToBottomEdgeIfPossible(animated: false)
        NEChatSwiftUILogger.log(
          "timeline diagnostic pinBottom afterLayout generation=\(generation) source=\(source) scroll=\(runtimeState.scrollMetricsDescription()) target=\(scrollTarget?.id ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil")"
        )
      }
    }
    DispatchQueue.main.async {
      guard runtimeState.pinnedBottomScrollGeneration == generation,
            !isOlderPaginationSuspended,
            runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration,
            isActive,
            keepsBottomPinned,
            !rows.isEmpty else {
        return
      }
      applyAction("async")
    }
    for (index, delay) in delays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        defer {
          if index == delays.count - 1,
             runtimeState.scheduledPinnedBottomScrollGeneration == generation {
            runtimeState.scheduledPinnedBottomScrollGeneration = nil
          }
        }
        guard runtimeState.pinnedBottomScrollGeneration == generation,
              !isOlderPaginationSuspended,
              runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration,
              isActive,
              keepsBottomPinned,
              !rows.isEmpty else {
          return
        }
        applyAction("delay=\(delay)")
      }
    }
  }

  private func cancelPinnedBottomScroll() {
    runtimeState.pinnedBottomScrollGeneration += 1
    runtimeState.scheduledPinnedBottomScrollGeneration = nil
  }

  private func deactivateTimelinePresentation() {
    cancelPinnedBottomScroll()
    cancelPendingBottomFrameUpdate()
    runtimeState.visibleRowsNotificationGeneration += 1
    runtimeState.hasPendingVisibleRowsNotification = false
    runtimeState.lastNotifiedVisibleRowIds.removeAll()
    runtimeState.visibleRowIds.removeAll()
    runtimeState.visibleAnchorId = nil
    runtimeState.lastNotifiedVisibleAnchorId = nil
    runtimeState.scheduledPrependCompensationGeneration = nil
    runtimeState.scrollView = nil
    runtimeState.explicitAnchorFrame = nil
    runtimeState.clearExplicitAnchorProbe()
    runtimeState.appliedExplicitAnchorScrollTargetId = nil
    runtimeState.correctedExplicitAnchorScrollTargetId = nil
    runtimeState.explicitAnchorCorrectionCount = 0
    if !rowFrames.isEmpty {
      rowFrames = [:]
    }
  }

  private func reportAllRowsVisibleWhenContentFits() {
    let visibleRowIds = Set(rows.map(\.id))
    guard runtimeState.visibleRowIds != visibleRowIds ||
      runtimeState.lastNotifiedVisibleRowIds != visibleRowIds else {
      return
    }
    runtimeState.visibleRowIds = visibleRowIds
    deliverVisibleRowsNotificationIfNeeded(with: nil)
  }

  private func updateBottomVisibilityIfNeeded(isVisible: Bool,
                                              forceNotify: Bool = false) {
    guard isActive else {
      return
    }
    guard forceNotify || runtimeState.lastBottomVisibility != isVisible else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic bottomVisibility notify incoming=\(isVisible) previous=\(runtimeState.lastBottomVisibility?.description ?? "nil") force=\(forceNotify) target=\(scrollTarget?.id ?? "nil") targetReason=\(scrollTarget?.reason.rawValue ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil") keepsPinned=\(keepsBottomPinned) scroll=\(runtimeState.scrollMetricsDescription())"
    )
    runtimeState.lastBottomVisibility = isVisible
    onBottomVisibilityChange(isVisible)
  }

  private var shouldLogBottomDiagnostic: Bool {
    keepsBottomPinned ||
      scrollTarget?.reason == .jumpToLatest ||
      scheduledScrollTargetReason == .jumpToLatest
  }

  private func syncPresentedScrollTarget() {
    guard let scrollTarget else {
      runtimeState.presentedScrollTargetId = nil
      runtimeState.presentedScrollTargetMessageId = nil
      runtimeState.presentedScrollTargetAnchor = nil
      runtimeState.presentedScrollTargetReason = nil
      runtimeState.presentedScrollTargetScopeId = nil
      return
    }
    let sequence = Self.scrollTargetSequence(for: scrollTarget)
    let scopeChanged = runtimeState.presentedScrollTargetScopeId != scrollTarget.scopeId
    guard scopeChanged ||
      sequence > runtimeState.presentedScrollTargetSequence ||
      runtimeState.presentedScrollTargetId == scrollTarget.id else {
      return
    }
    if scopeChanged {
      runtimeState.presentedScrollTargetSequence = -1
    }
    if runtimeState.presentedScrollTargetId != scrollTarget.id {
      runtimeState.explicitAnchorFrame = nil
      if runtimeState.explicitAnchorProbeTargetId != scrollTarget.id {
        runtimeState.clearExplicitAnchorProbe()
      }
      runtimeState.appliedExplicitAnchorScrollTargetId = nil
      runtimeState.correctedExplicitAnchorScrollTargetId = nil
      runtimeState.explicitAnchorCorrectionCount = 0
    }
    runtimeState.presentedScrollTargetSequence = sequence
    runtimeState.presentedScrollTargetId = scrollTarget.id
    runtimeState.presentedScrollTargetMessageId = scrollTarget.messageId
    runtimeState.presentedScrollTargetAnchor = scrollTarget.anchor
    runtimeState.presentedScrollTargetReason = scrollTarget.reason
    runtimeState.presentedScrollTargetScopeId = scrollTarget.scopeId
  }

  private func pruneVisibleRowsToCurrentRows(with proxy: ScrollViewProxy) {
    let currentRowIds = Set(rows.map(\.id))
    let nextVisibleRowIds = runtimeState.visibleRowIds.intersection(currentRowIds)
    guard nextVisibleRowIds != runtimeState.visibleRowIds else {
      return
    }
    runtimeState.visibleRowIds = nextVisibleRowIds
    scheduleVisibleRowsNotification(with: proxy)
  }

  private func scheduleVisibleRowsNotification(with proxy: ScrollViewProxy) {
    guard isActive else {
      return
    }
    guard !runtimeState.hasPendingVisibleRowsNotification else {
      return
    }
    runtimeState.hasPendingVisibleRowsNotification = true
    runtimeState.visibleRowsNotificationGeneration += 1
    let generation = runtimeState.visibleRowsNotificationGeneration
    DispatchQueue.main.async {
      guard isActive,
            runtimeState.visibleRowsNotificationGeneration == generation else {
        return
      }
      runtimeState.hasPendingVisibleRowsNotification = false
      deliverVisibleRowsNotificationIfNeeded(with: proxy)
    }
  }

  private func flushVisibleRowsNotificationIfNeeded() {
    runtimeState.visibleRowsNotificationGeneration += 1
    runtimeState.hasPendingVisibleRowsNotification = false
    deliverVisibleRowsNotificationIfNeeded(with: nil)
  }

  private func deliverVisibleRowsNotificationIfNeeded(with proxy: ScrollViewProxy?) {
    runtimeState.rebuildRowOrderIfNeeded(rows: rows)
    syncPresentedScrollTarget()
    logTimelineSmoothness("visibleRowsNotification")
    if let proxy {
      if consumePendingPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "visibleRows") {
        return
      }
      consumeReplacingScrollTargetIfNeeded(scrollTarget, with: proxy, source: "visibleRows")
    }
    schedulePrependContentOffsetCompensation(source: "visibleRows")
    let visibleRowIds = runtimeState.visibleRowIds
    if runtimeState.lastNotifiedVisibleRowIds != visibleRowIds {
      runtimeState.lastNotifiedVisibleRowIds = visibleRowIds
      onVisibleRowsChange(visibleRowIds)
    }

    let nextAnchorId = runtimeState.visibleTopMessageId()
    runtimeState.visibleAnchorId = nextAnchorId
    if runtimeState.lastNotifiedVisibleAnchorId != nextAnchorId {
      runtimeState.lastNotifiedVisibleAnchorId = nextAnchorId
      onVisibleAnchorChange(nextAnchorId)
    }

  }

  private func handleTimelineDragChanged(from startLocation: CGPoint,
                                         with proxy: ScrollViewProxy) {
    guard operationMenu == nil else {
      return
    }
    syncPresentedScrollTarget()
    let startsNewDrag = !runtimeState.isTimelineDragGestureActive
    logTimelineSmoothness("dragChanged startsNewDrag=\(startsNewDrag)")
    runtimeState.usesFastInitialBottomPin = false
    cancelScheduledScrollForUserInteraction()
    cancelPinnedBottomScroll()
    if !hasUserScrolled {
      hasUserScrolled = true
    }
    if startsNewDrag {
      runtimeState.isTimelineDragGestureActive = true
      runtimeState.dragInteractionGeneration += 1
      runtimeState.loadOlderGestureGeneration += 1
      runtimeState.isDraggingTimeline = true
      clearLoadOlderGestureThrottleIfNeeded()
      clearLoadOlderTopExitGateForUserPullIfNeeded()
      if suppressLoadOlderRetryUntilUserScroll,
         !isOlderPaginationSuspended {
        suppressLoadOlderRetryUntilUserScroll = false
        runtimeState.lastLoadOlderDecisionSignature = ""
      }
      onScrollInteraction()
    }
    updateLatestMessageVisibilityIfNeeded()
    runtimeState.rebuildRowOrderIfNeeded(rows: rows)
    if consumePendingPrependRestoreIfNeeded(scrollTarget, with: proxy, source: "dragChanged") {
      return
    }
    clearActivePrependScrollSuppressionIfNeeded()
    clearLoadOlderTopExitGateIfNeeded()
    if isLoadOlderRetryRegionVisible {
      triggerLoadOlderIfNeeded(source: "dragNearTop")
    }
  }

  private func handleTimelineDragEnded() {
    runtimeState.isTimelineDragGestureActive = false
    let generation = runtimeState.dragInteractionGeneration
    logTimelineSmoothness("dragEnded generation=\(generation)")
    if isOlderPaginationSuspended {
      DispatchQueue.main.async {
        stopNetworkBreakMomentumIfNeeded(source: "dragEnded.nextRunLoop")
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollInertiaCooldown) {
      guard runtimeState.dragInteractionGeneration == generation else {
        logTimelineSmoothness(
          "dragEndIgnored generation=\(generation) current=\(runtimeState.dragInteractionGeneration)"
        )
        return
      }
      runtimeState.isDraggingTimeline = false
      updateLatestMessageVisibilityIfNeeded()
      logTimelineSmoothness("dragSettled generation=\(generation)")
    }
  }

  private func consume(_ target: ChatTimelineScrollTarget?,
                       with proxy: ScrollViewProxy) {
    guard let target else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic consumeStart id=\(target.id) ageMs=\(target.ageMilliseconds) messageId=\(target.messageId) reason=\(target.reason.rawValue) anchor=\(target.anchor.rawValue) animated=\(target.animated) rows=\(rows.count) first=\(rows.first?.id ?? "nil") last=\(rows.last?.id ?? "nil") scheduled=\(scheduledScrollTargetId ?? "nil") scheduledReason=\(scheduledScrollTargetReason?.rawValue ?? "nil") consumed=\(runtimeState.hasConsumedScrollTarget(target.id)) scroll=\(runtimeState.scrollMetricsDescription())"
    )
    if target.reason == .prependRestore,
       isOlderPaginationSuspended {
      NEChatSwiftUILogger.log(
        "offlineHistory prependRestoreIgnored conversationId=\(diagnosticConversationId) target=\(target.id) source=consume suspensionGen=\(runtimeState.olderPaginationSuspensionGeneration) scroll=\(runtimeState.scrollMetricsDescription())"
      )
      if scheduledScrollTargetId == target.id {
        scheduledScrollTargetId = nil
        scheduledScrollTargetReason = nil
      }
      clearPendingPrependRestoreTargetIfNeeded(target)
      if !runtimeState.hasConsumedScrollTarget(target.id) {
        runtimeState.markScrollTargetConsumed(target.id)
        onScrollTargetConsumed(target.id)
      }
      return
    }
    guard !runtimeState.hasConsumedScrollTarget(target.id) else {
      NEChatSwiftUILogger.log(
        "timeline scrollTarget skipConsumed id=\(target.id) reason=\(target.reason.rawValue) rows=\(rows.count)"
      )
      onScrollTargetConsumed(target.id)
      return
    }
    guard isPresentedScrollTargetCurrent(target) else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic consumeSkipStale id=\(target.id) presented=\(runtimeState.presentedScrollTargetId ?? "nil") reason=\(target.reason.rawValue) rows=\(rows.count)"
      )
      runtimeState.markScrollTargetConsumed(target.id)
      return
    }
    guard rows.contains(where: { $0.id == target.messageId }) else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic consumeMissingRow id=\(target.id) messageId=\(target.messageId) reason=\(target.reason.rawValue) rows=\(rows.count) first=\(rows.first?.id ?? "nil") last=\(rows.last?.id ?? "nil")"
      )
      consumeMissingPrependRestoreTargetIfNeeded(target)
      return
    }
    guard scheduledScrollTargetId != target.id else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic consumeAlreadyScheduled id=\(target.id) reason=\(target.reason.rawValue) scheduledReason=\(scheduledScrollTargetReason?.rawValue ?? "nil")"
      )
      if target.reason == .explicitAnchor,
         runtimeState.appliedExplicitAnchorScrollTargetId != target.id {
        performExplicitAnchorScroll(to: target, with: proxy)
      }
      reapplyScheduledPrependRestoreIfNeeded(target, with: proxy, source: "consume")
      return
    }

    cancelScheduledScrollBeforeReplacing(with: target)
    scheduledScrollTargetId = target.id
    scheduledScrollTargetReason = target.reason
    if target.reason != .explicitAnchor {
      scheduleScrollTargetConsumptionFallback(for: target)
    }
    if target.reason == .explicitAnchor {
      runtimeState.jumpToLatestGeneration += 1
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic consumeScheduled id=\(target.id) ageMs=\(target.ageMilliseconds) reason=\(target.reason.rawValue) messageId=\(target.messageId) anchor=\(target.anchor.rawValue) scroll=\(runtimeState.scrollMetricsDescription())"
    )
    if isInitialLatestBottomTarget(target) {
      prepareForPriorityBottomScroll()
      runtimeState.usesFastInitialBottomPin = true
      scheduleInitialLatestPositioningReveal(for: target)
      scroll(to: target, with: proxy, animated: false)
      scheduleInitialLatestBottomScroll(to: target, with: proxy)
      pinBottomIfNeeded(with: proxy)
      return
    }

    if isJumpToLatestBottomTarget(target) {
      prepareForPriorityBottomScroll()
      runtimeState.usesFastInitialBottomPin = false
      cancelScrollMomentumThenJump(to: target, with: proxy)
      return
    }

    if target.reason == .prependRestore {
      beginPendingPrependRestoreIfNeeded(target)
      if runtimeState.pendingPrependCompensation != nil {
        cancelPendingPrependContentOffsetCompensation(
          source: "prependRestore",
          targetId: target.id
        )
      }
      performPrependRestoreScroll(to: target, with: proxy, source: "consume")
      return
    }

    if target.anchor != .bottom {
      cancelPinnedBottomScroll()
    }

    if target.reason == .explicitAnchor {
      updateBottomVisibilityIfNeeded(isVisible: false, forceNotify: true)
      if runtimeState.explicitAnchorFrame == nil {
        NEChatSwiftUILogger.log(
          "messageJump timeline registrationPending id=\(target.id) messageId=\(target.messageId) rows=\(rows.count) viewportHeight=\(runtimeState.viewportHeight) action=scrollTo"
        )
      }
      performExplicitAnchorScroll(to: target, with: proxy)
      return
    }

    DispatchQueue.main.async {
      if isLatestBottomTarget(target) {
        prepareForPriorityBottomScroll()
        runtimeState.usesFastInitialBottomPin = false
        scheduleSettledBottomScroll(to: target, with: proxy)
        pinBottomIfNeeded(with: proxy)
        return
      }

      updateBottomVisibilityIfNeeded(isVisible: false, forceNotify: true)
      if target.animated {
        scheduleReliableProgrammaticScroll(to: target, with: proxy)
      } else {
        scroll(to: target, with: proxy, animated: false)
        DispatchQueue.main.async {
          scroll(to: target, with: proxy, animated: false)
          DispatchQueue.main.asyncAfter(deadline: .now() + stableScrollDelay(for: target)) {
            guard scheduledScrollTargetId == target.id else {
              return
            }
            scroll(to: target, with: proxy, animated: false)
            finishScrollTarget(to: target)
          }
        }
      }
    }
  }

  private func consumeReplacingScrollTargetIfNeeded(_ target: ChatTimelineScrollTarget?,
                                                    with proxy: ScrollViewProxy,
                                                    source: String) {
    guard let target,
          target.reason != .prependRestore,
          scheduledScrollTargetId != target.id,
          !runtimeState.hasConsumedScrollTarget(target.id) else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic consumeReplacingCurrent id=\(target.id) source=\(source) scheduled=\(scheduledScrollTargetId ?? "nil") scheduledReason=\(scheduledScrollTargetReason?.rawValue ?? "nil")"
    )
    consume(target, with: proxy)
  }

  private func isPresentedScrollTargetCurrent(_ target: ChatTimelineScrollTarget) -> Bool {
    if target.reason == .prependRestore {
      return true
    }
    if isLatestBottomTarget(target) {
      return isPresentedScrollTargetMatching(target)
    }
    return isScrollTargetCurrent(target) &&
      isPresentedScrollTargetMatching(target)
  }

  private func consumePendingPrependRestoreIfNeeded(_ target: ChatTimelineScrollTarget?,
                                                    with proxy: ScrollViewProxy,
                                                    source: String) -> Bool {
    guard let target,
          target.reason == .prependRestore else {
      return false
    }
    if isOlderPaginationSuspended {
      NEChatSwiftUILogger.log(
        "offlineHistory prependRestoreIgnored conversationId=\(diagnosticConversationId) target=\(target.id) source=\(source) suspensionGen=\(runtimeState.olderPaginationSuspensionGeneration) scroll=\(runtimeState.scrollMetricsDescription())"
      )
      consume(target, with: proxy)
      return true
    }
    guard !runtimeState.hasConsumedScrollTarget(target.id) else {
      return false
    }
    if scheduledScrollTargetId == target.id {
      if completeScheduledPrependRestoreIfSettled(target, source: source) {
        return true
      }
      logSkippedScheduledPrependRestore(target, source: source)
      return true
    }
    guard rows.contains(where: { $0.id == target.messageId }) else {
      consumeMissingPrependRestoreTargetIfNeeded(target)
      return true
    }
    NEChatSwiftUILogger.log(
      "timeline scrollTarget consumePendingPrependRestore id=\(target.id) source=\(source) rows=\(rows.count) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") scheduledTarget=\(scheduledScrollTargetId ?? "nil") pendingCompensation=\(runtimeState.pendingPrependCompensation?.generation.description ?? "nil")"
    )
    consume(target, with: proxy)
    return true
  }

  private func logSkippedScheduledPrependRestore(_ target: ChatTimelineScrollTarget,
                                                 source: String) {
    let signature = [
      "id=\(target.id)",
      "source=\(source)",
      "rows=\(rows.count)",
      "visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil")",
      "scheduledTarget=\(scheduledScrollTargetId ?? "nil")",
    ].joined(separator: " ")
    guard runtimeState.lastPrependRestoreSkipSignature != signature else {
      return
    }
    runtimeState.lastPrependRestoreSkipSignature = signature
    NEChatSwiftUILogger.log("timeline scrollTarget skipScheduledPrependRestore \(signature)")
  }

  private func completeScheduledPrependRestoreIfSettled(_ target: ChatTimelineScrollTarget,
                                                        source: String) -> Bool {
    guard !isOlderPaginationSuspended,
          scheduledScrollTargetId == target.id,
          scheduledScrollTargetReason == .prependRestore,
          runtimeState.visibleTopMessageId() == target.messageId else {
      return false
    }
    NEChatSwiftUILogger.log(
      "timeline scrollTarget completeScheduledPrependRestore id=\(target.id) source=\(source) rows=\(rows.count) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil")"
    )
    finishScrollTarget(to: target)
    return true
  }

  private func cancelScrollMomentumThenJump(to target: ChatTimelineScrollTarget,
                                            with proxy: ScrollViewProxy) {
    let generation = runtimeState.jumpToLatestGeneration + 1
    runtimeState.jumpToLatestGeneration = generation
    NEChatSwiftUILogger.log(
      "timeline diagnostic jumpToLatestStart id=\(target.id) ageMs=\(target.ageMilliseconds) generation=\(generation) scrollBefore=\(runtimeState.scrollMetricsDescription())"
    )
    stopScrollViewMomentumIfNeeded()
    applyImmediateBottomJump(to: target, with: proxy)
    pinBottomIfNeeded(with: proxy)
    updateBottomVisibilityIfNeeded(isVisible: true, forceNotify: true)
    scheduleImmediateBottomJumpRetry(to: target, with: proxy, generation: generation)
  }

  private func applyImmediateBottomJump(to target: ChatTimelineScrollTarget,
                                        with proxy: ScrollViewProxy) {
    NEChatSwiftUILogger.log(
      "timeline diagnostic jumpToLatestApply id=\(target.id) ageMs=\(target.ageMilliseconds) messageId=\(target.messageId) scrollBefore=\(runtimeState.scrollMetricsDescription())"
    )
    scroll(to: target, with: proxy, animated: false)
    scrollToBottomEdgeIfPossible(animated: false)
    NEChatSwiftUILogger.log(
      "timeline diagnostic jumpToLatestApplied id=\(target.id) ageMs=\(target.ageMilliseconds) scrollAfter=\(runtimeState.scrollMetricsDescription())"
    )
  }

  private func scheduleImmediateBottomJumpRetry(to target: ChatTimelineScrollTarget,
                                                with proxy: ScrollViewProxy,
                                                generation: Int) {
    for (index, delay) in Self.immediateBottomJumpRetryDelays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard runtimeState.jumpToLatestGeneration == generation,
              scheduledScrollTargetId == target.id,
              rows.last?.id == target.messageId else {
          NEChatSwiftUILogger.log(
            "timeline diagnostic jumpToLatestRetrySkip id=\(target.id) generation=\(generation) currentGeneration=\(runtimeState.jumpToLatestGeneration) last=\(rows.last?.id ?? "nil")"
          )
          return
        }
        NEChatSwiftUILogger.log(
          "timeline diagnostic jumpToLatestRetry id=\(target.id) generation=\(generation) delay=\(delay)"
        )
        applyImmediateBottomJump(to: target, with: proxy)
        updateBottomVisibilityIfNeeded(isVisible: true, forceNotify: true)
        if index == Self.immediateBottomJumpRetryDelays.indices.last {
          finishScrollTarget(to: target)
        }
      }
    }
  }

  private func scrollToBottomEdgeIfPossible(animated: Bool) {
    guard let scrollView = runtimeState.resolvedScrollView(),
          scrollView.bounds.height > 0 else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic scrollToBottomEdge skip=noScrollView animated=\(animated)"
      )
      return
    }
    let minimumOffsetY = -scrollView.adjustedContentInset.top
    let maximumOffsetY = max(
      minimumOffsetY,
      scrollView.contentSize.height -
        scrollView.bounds.height +
        scrollView.adjustedContentInset.bottom
    )
    guard abs(scrollView.contentOffset.y - maximumOffsetY) > Self.bottomVisibilityTolerance else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic scrollToBottomEdge skip=alreadyAtBottom currentY=\(scrollView.contentOffset.y) maxY=\(maximumOffsetY) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height)"
      )
      return
    }
    let targetOffset = CGPoint(x: scrollView.contentOffset.x, y: maximumOffsetY)
    NEChatSwiftUILogger.log(
      "timeline diagnostic scrollToBottomEdge apply currentY=\(scrollView.contentOffset.y) targetY=\(maximumOffsetY) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) insetTop=\(scrollView.adjustedContentInset.top) insetBottom=\(scrollView.adjustedContentInset.bottom)"
    )
    if animated {
      scrollView.setContentOffset(targetOffset, animated: true)
    } else {
      UIView.performWithoutAnimation {
        scrollView.setContentOffset(targetOffset, animated: false)
      }
    }
  }

  private var immediateBottomProbeTarget: ChatTimelineScrollTarget? {
    guard let scrollTarget,
          isJumpToLatestBottomTarget(scrollTarget) ||
          isInitialLatestBottomTarget(scrollTarget) else {
      return nil
    }
    return scrollTarget
  }

  private var hasPendingTimelineContentSizeWork: Bool {
    if keepsBottomPinned ||
      immediateBottomProbeTarget != nil ||
      runtimeState.pendingPrependCompensation != nil ||
      runtimeState.scheduledPrependCompensationGeneration != nil ||
      pendingPrependRestoreTarget != nil ||
      scheduledScrollTargetReason == .explicitAnchor ||
      scheduledScrollTargetReason == .prependRestore {
      return true
    }
    guard let target = scrollTarget else {
      return false
    }
    if target.reason == .explicitAnchor || target.reason == .prependRestore {
      return !runtimeState.hasConsumedScrollTarget(target.id)
    }
    return false
  }

  private func logImmediateBottomTrace(_ event: String) {
    guard let target = immediateBottomProbeTarget else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic immediateBottom event=\(event) id=\(target.id) ageMs=\(target.ageMilliseconds) reason=\(target.reason.rawValue) rows=\(rows.count) scroll=\(runtimeState.scrollMetricsDescription())"
    )
  }

  private func stopScrollViewMomentumIfNeeded() {
    guard let scrollView = runtimeState.resolvedScrollView() else {
      isMomentumCancellationActive = false
      return
    }
    UIView.performWithoutAnimation {
      scrollView.setContentOffset(scrollView.contentOffset, animated: false)
      scrollView.layer.removeAllAnimations()
    }
    isMomentumCancellationActive = false
  }

  private func beginPendingPrependRestoreIfNeeded(_ target: ChatTimelineScrollTarget) {
    guard !isOlderPaginationSuspended,
          target.reason == .prependRestore else {
      return
    }
    guard pendingPrependRestoreTarget?.id != target.id else {
      return
    }
    pendingPrependRestoreTarget = target
    pendingPrependRestoreInitialFirstRowId = rows.first?.id
    pendingPrependRestoreInitialRowCount = rows.count
    pendingPrependRestoreObservedRowsChange = false
  }

  private func markPendingPrependRestoreRowsChangedIfNeeded() {
    guard pendingPrependRestoreTarget != nil else {
      return
    }
    guard rows.first?.id != pendingPrependRestoreInitialFirstRowId ||
      rows.count != pendingPrependRestoreInitialRowCount else {
      return
    }
    pendingPrependRestoreObservedRowsChange = true
  }

  private func performPrependRestoreScroll(to target: ChatTimelineScrollTarget,
                                           with proxy: ScrollViewProxy,
                                           source: String) {
    guard !isOlderPaginationSuspended else {
      consume(target, with: proxy)
      return
    }
    beginPendingPrependRestoreIfNeeded(target)
    markPendingPrependRestoreRowsChangedIfNeeded()
    runtimeState.prependRestoreGeneration += 1
    let generation = runtimeState.prependRestoreGeneration
    let suspensionGeneration = runtimeState.olderPaginationSuspensionGeneration
    runtimeState.dragInteractionGeneration += 1
    runtimeState.isDraggingTimeline = false
    updateBottomVisibilityIfNeeded(isVisible: false, forceNotify: true)
    NEChatSwiftUILogger.log(
      "timeline scrollTarget applyPrependRestore id=\(target.id) source=\(source) rows=\(rows.count) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil") rowsChanged=\(pendingPrependRestoreObservedRowsChange)"
    )
    scroll(to: target, with: proxy, animated: false)
    for (index, delay) in Self.prependRestoreScrollRetryDelays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard !isOlderPaginationSuspended,
              runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration,
              runtimeState.prependRestoreGeneration == generation,
              scheduledScrollTargetId == target.id,
              rows.contains(where: { $0.id == target.messageId }) else {
          NEChatSwiftUILogger.log(
            "offlineHistory prependRestoreRetryIgnored conversationId=\(diagnosticConversationId) target=\(target.id) source=\(source) generation=\(generation) currentGeneration=\(runtimeState.prependRestoreGeneration) suspensionGen=\(suspensionGeneration) currentSuspensionGen=\(runtimeState.olderPaginationSuspensionGeneration) suspended=\(isOlderPaginationSuspended) scroll=\(runtimeState.scrollMetricsDescription())"
          )
          return
        }
        if completeScheduledPrependRestoreIfSettled(target, source: "\(source).retry") {
          return
        }
        markPendingPrependRestoreRowsChangedIfNeeded()
        scroll(to: target, with: proxy, animated: false)
        if index == Self.prependRestoreScrollRetryDelays.indices.last {
          finishPrependRestoreScrollTarget(to: target, generation: generation)
        }
      }
    }
  }

  private func scheduleInitialLatestBottomScroll(to target: ChatTimelineScrollTarget,
                                                 with proxy: ScrollViewProxy) {
    for (index, delay) in Self.initialLatestBottomScrollDelays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard scheduledScrollTargetId == target.id else {
          return
        }
        scroll(to: target, with: proxy, animated: false)
        scrollToBottomEdgeIfPossible(animated: false)
        if index == Self.initialLatestBottomScrollDelays.indices.last {
          finishSettledBottomScroll(to: target)
        }
      }
    }
  }

  private func prepareForPriorityBottomScroll() {
    runtimeState.dragInteractionGeneration += 1
    runtimeState.isDraggingTimeline = false
  }

  private func scheduleSettledBottomScroll(to target: ChatTimelineScrollTarget,
                                           with proxy: ScrollViewProxy) {
    for (index, delay) in Self.settledBottomScrollDelays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard scheduledScrollTargetId == target.id else {
          return
        }
        scroll(to: target, with: proxy, animated: false)
        scrollToBottomEdgeIfPossible(animated: false)
        if index == Self.settledBottomScrollDelays.indices.last {
          finishSettledBottomScroll(to: target)
        }
      }
    }
  }

  private func scheduleReliableProgrammaticScroll(to target: ChatTimelineScrollTarget,
                                                  with proxy: ScrollViewProxy) {
    if isScheduledPresentedTarget(target) {
      scroll(to: target, with: proxy, animated: true)
    }
    for (index, delay) in Self.programmaticScrollRetryDelays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard isScheduledPresentedTarget(target) else {
          return
        }
        scroll(to: target, with: proxy, animated: false)
        if index == Self.programmaticScrollRetryDelays.indices.last {
          finishProgrammaticScroll(to: target)
        }
      }
    }
  }

  private func performExplicitAnchorScroll(to target: ChatTimelineScrollTarget,
                                           with proxy: ScrollViewProxy) {
    guard isScheduledPresentedTarget(target) else {
      return
    }
    let frame = currentExplicitAnchorFrame(for: target)
    let effectiveAnchor = resolvedExplicitAnchor(
      for: target,
      frame: frame
    )
    NEChatSwiftUILogger.log(
      "messageJump timeline apply phase=initial id=\(target.id) messageId=\(target.messageId) requestedAnchor=\(target.anchor.rawValue) effectiveAnchor=\(effectiveAnchor.rawValue) frame=\(frame?.debugDescription ?? "nil") viewportHeight=\(runtimeState.viewportHeight)"
    )
    runtimeState.appliedExplicitAnchorScrollTargetId = target.id
    scroll(to: target, with: proxy, animated: false)
  }

  private func performExplicitAnchorCorrectionIfNeeded(to target: ChatTimelineScrollTarget,
                                                       with proxy: ScrollViewProxy) {
    guard isScheduledPresentedTarget(target),
          runtimeState.appliedExplicitAnchorScrollTargetId == target.id,
          let frame = currentExplicitAnchorFrame(for: target) else {
      return
    }
    runtimeState.explicitAnchorFrame = frame
    let effectiveAnchor = resolvedExplicitAnchor(
      for: target,
      frame: frame
    )
    runtimeState.explicitAnchorCorrectionCount += 1
    runtimeState.correctedExplicitAnchorScrollTargetId = target.id
    guard let scrollView = runtimeState.resolvedScrollView(),
          let targetOffsetY = explicitAnchorTargetOffsetY(
            for: frame,
            target: target,
            scrollView: scrollView
          ) else {
      NEChatSwiftUILogger.log(
        "messageJump timeline apply phase=correctionProxy id=\(target.id) messageId=\(target.messageId) count=\(runtimeState.explicitAnchorCorrectionCount) requestedAnchor=\(target.anchor.rawValue) effectiveAnchor=\(effectiveAnchor.rawValue) frame=\(frame) viewportHeight=\(runtimeState.viewportHeight)"
      )
      scroll(to: target, with: proxy, animated: false)
      return
    }
    let currentOffsetY = scrollView.contentOffset.y
    NEChatSwiftUILogger.log(
      "messageJump timeline apply phase=correctionOffset id=\(target.id) messageId=\(target.messageId) count=\(runtimeState.explicitAnchorCorrectionCount) requestedAnchor=\(target.anchor.rawValue) effectiveAnchor=\(effectiveAnchor.rawValue) frame=\(frame) viewportHeight=\(runtimeState.viewportHeight) currentOffsetY=\(currentOffsetY) targetOffsetY=\(targetOffsetY)"
    )
    UIView.performWithoutAnimation {
      scrollView.setContentOffset(
        CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY),
        animated: false
      )
      scrollView.layoutIfNeeded()
    }
  }

  private func explicitAnchorTargetOffsetY(for frame: CGRect,
                                           target: ChatTimelineScrollTarget,
                                           scrollView: UIScrollView) -> CGFloat? {
    guard runtimeState.viewportHeight > 0,
          scrollView.bounds.height > 0 else {
      return nil
    }
    let currentAnchorY: CGFloat
    let desiredAnchorY: CGFloat
    switch resolvedExplicitAnchor(for: target, frame: frame) {
    case .top:
      currentAnchorY = frame.minY
      desiredAnchorY = 0
    case .center:
      currentAnchorY = frame.midY
      desiredAnchorY = runtimeState.viewportHeight / 2
    case .bottom:
      currentAnchorY = frame.maxY
      desiredAnchorY = runtimeState.viewportHeight
    }
    let minimumOffsetY = -scrollView.adjustedContentInset.top
    let maximumOffsetY = max(
      minimumOffsetY,
      scrollView.contentSize.height -
        scrollView.bounds.height +
        scrollView.adjustedContentInset.bottom
    )
    return (scrollView.contentOffset.y + currentAnchorY - desiredAnchorY)
      .clamped(to: minimumOffsetY ... maximumOffsetY)
  }

  private func finishProgrammaticScroll(to target: ChatTimelineScrollTarget) {
    guard isScheduledPresentedTarget(target) else {
      return
    }
    finishScrollTarget(to: target)
  }

  private func finishSettledBottomScroll(to target: ChatTimelineScrollTarget) {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.bottomScrollCompletionProbeDelay) {
      guard scheduledScrollTargetId == target.id else {
        return
      }
      let isVisible = isTimelineBottomCurrentlyVisible(fallbackIsVisible: false)
      updateBottomVisibilityIfNeeded(isVisible: isVisible, forceNotify: isVisible)
      finishScrollTarget(to: target)
    }
  }

  private func cancelScheduledScrollForUserInteraction() {
    guard let targetId = scheduledScrollTargetId else {
      return
    }
    if scheduledScrollTargetReason == .prependRestore {
      return
    }
    if scheduledScrollTargetReason == .explicitAnchor {
      NEChatSwiftUILogger.log(
        "messageJump timeline cancel id=\(targetId) messageId=\(scrollTarget?.messageId ?? "nil") reason=userInteraction frame=\(runtimeState.explicitAnchorFrame?.debugDescription ?? "nil") initialApplied=\(runtimeState.appliedExplicitAnchorScrollTargetId == targetId) correctionApplied=\(runtimeState.correctedExplicitAnchorScrollTargetId == targetId)"
      )
    }
    isMomentumCancellationActive = false
    runtimeState.jumpToLatestGeneration += 1
    scheduledScrollTargetId = nil
    scheduledScrollTargetReason = nil
    initialLatestRevealDeadline = nil
    runtimeState.markScrollTargetConsumed(targetId)
    onScrollTargetConsumed(targetId)
  }

  private func cancelScheduledScrollBeforeReplacing(with target: ChatTimelineScrollTarget) {
    guard let targetId = scheduledScrollTargetId,
          targetId != target.id else {
      return
    }
    if scheduledScrollTargetReason == .initialLatest {
      initialLatestRevealDeadline = nil
    }
    if scheduledScrollTargetReason == .jumpToLatest {
      runtimeState.jumpToLatestGeneration += 1
    }
    if scheduledScrollTargetReason == .prependRestore {
      runtimeState.prependRestoreGeneration += 1
      if let pendingPrependRestoreTarget {
        clearPendingPrependRestoreTargetIfNeeded(pendingPrependRestoreTarget)
      }
    }
    scheduledScrollTargetId = nil
    scheduledScrollTargetReason = nil
    isMomentumCancellationActive = false
  }

  private func consumeMissingPrependRestoreTargetIfNeeded(_ target: ChatTimelineScrollTarget) {
    guard target.reason == .prependRestore else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline scrollTarget consumeMissing id=\(target.id) reason=\(target.reason.rawValue) rows=\(rows.count)"
    )
    if scheduledScrollTargetId == target.id {
      scheduledScrollTargetId = nil
      scheduledScrollTargetReason = nil
    }
    clearPendingPrependRestoreTargetIfNeeded(target)
    runtimeState.markScrollTargetConsumed(target.id)
    onScrollTargetConsumed(target.id)
  }

  private func scheduleScrollTargetConsumptionFallback(for target: ChatTimelineScrollTarget) {
    DispatchQueue.main.asyncAfter(deadline: .now() + scrollTargetConsumptionFallbackDelay(for: target)) {
      guard target.reason != .prependRestore || !isOlderPaginationSuspended else {
        return
      }
      guard isScheduledPresentedTarget(target) else {
        return
      }
      NEChatSwiftUILogger.log(
        "timeline scrollTarget fallbackConsume id=\(target.id) reason=\(target.reason.rawValue) rows=\(rows.count)"
      )
      finishScrollTarget(to: target)
    }
  }

  private func reapplyScheduledPrependRestoreIfNeeded(_ target: ChatTimelineScrollTarget?,
                                                      with proxy: ScrollViewProxy,
                                                      source: String) {
    guard !isOlderPaginationSuspended,
          let target = target ?? pendingPrependRestoreTarget,
          target.reason == .prependRestore,
          !runtimeState.hasConsumedScrollTarget(target.id),
          rows.contains(where: { $0.id == target.messageId }) else {
      return
    }
    if scheduledScrollTargetId == target.id {
      if completeScheduledPrependRestoreIfSettled(target, source: source) {
        return
      }
      logSkippedScheduledPrependRestore(target, source: source)
      return
    }
    if scheduledScrollTargetId == nil {
      scheduledScrollTargetId = target.id
      scheduledScrollTargetReason = target.reason
      scheduleScrollTargetConsumptionFallback(for: target)
    }
    guard scheduledScrollTargetId == target.id else {
      return
    }
    guard runtimeState.pendingPrependCompensation == nil else {
      return
    }
    NEChatSwiftUILogger.log(
      "timeline scrollTarget reapplyPrependRestore id=\(target.id) source=\(source) rows=\(rows.count) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil")"
    )
    performPrependRestoreScroll(to: target, with: proxy, source: source)
  }

  private func finishPrependRestoreScrollTarget(to target: ChatTimelineScrollTarget,
                                                generation: Int) {
    guard !isOlderPaginationSuspended,
          runtimeState.prependRestoreGeneration == generation,
          scheduledScrollTargetId == target.id else {
      return
    }
    isMomentumCancellationActive = false
    clearPendingPrependRestoreTargetIfNeeded(target)
    finishScrollTarget(to: target)
  }

  private func finishScrollTarget(to target: ChatTimelineScrollTarget) {
    if target.reason == .explicitAnchor {
      let frame = currentExplicitAnchorFrame(for: target)
      NEChatSwiftUILogger.log(
        "messageJump timeline finish id=\(target.id) messageId=\(target.messageId) effectiveAnchor=\(resolvedExplicitAnchor(for: target, frame: frame).rawValue) frame=\(frame?.debugDescription ?? "nil") viewportHeight=\(runtimeState.viewportHeight) positioned=\(frame.map { isExplicitAnchorPositioned($0, target: target) } ?? false) initialApplied=\(runtimeState.appliedExplicitAnchorScrollTargetId == target.id) correctionApplied=\(runtimeState.correctedExplicitAnchorScrollTargetId == target.id)"
      )
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic finishTarget id=\(target.id) reason=\(target.reason.rawValue) messageId=\(target.messageId) scheduled=\(scheduledScrollTargetId ?? "nil") scroll=\(runtimeState.scrollMetricsDescription())"
    )
    if target.reason == .explicitAnchor {
      runtimeState.explicitAnchorFrame = nil
      runtimeState.clearExplicitAnchorProbe()
      runtimeState.appliedExplicitAnchorScrollTargetId = nil
      runtimeState.correctedExplicitAnchorScrollTargetId = nil
      runtimeState.explicitAnchorCorrectionCount = 0
    }
    if target.reason == .prependRestore {
      runtimeState.prependRestoreGeneration += 1
      isMomentumCancellationActive = false
      clearPendingPrependRestoreTargetIfNeeded(target)
    }
    if target.reason == .initialLatest {
      initialLatestRevealDeadline = nil
    }
    scheduledScrollTargetId = nil
    scheduledScrollTargetReason = nil
    runtimeState.markScrollTargetConsumed(target.id)
    onScrollTargetConsumed(target.id)
  }

  private func isScheduledPresentedTarget(_ target: ChatTimelineScrollTarget) -> Bool {
    guard scheduledScrollTargetId == target.id else {
      return false
    }
    if target.reason == .prependRestore {
      return true
    }
    if isLatestBottomTarget(target) {
      return isPresentedScrollTargetMatching(target)
    }
    return isScrollTargetCurrent(target) &&
      isPresentedScrollTargetMatching(target)
  }

  private func isPresentedScrollTargetMatching(_ target: ChatTimelineScrollTarget) -> Bool {
    guard let presentedId = runtimeState.presentedScrollTargetId else {
      return false
    }
    return presentedId == target.id
  }

  private func scroll(to target: ChatTimelineScrollTarget,
                      with proxy: ScrollViewProxy,
                      animated: Bool) {
    let targetId = scrollProxyTargetId(for: target)
    guard targetId == Self.timelineBottomAnchorId ||
      rows.contains(where: { $0.id == targetId }) else {
      NEChatSwiftUILogger.log(
        "timeline diagnostic scrollProxy skipMissingTarget id=\(target.id) proxyTarget=\(targetId) messageId=\(target.messageId) reason=\(target.reason.rawValue) rows=\(rows.count) first=\(rows.first?.id ?? "nil") last=\(rows.last?.id ?? "nil")"
      )
      return
    }
    let effectiveAnchor = resolvedExplicitAnchor(
      for: target,
      frame: target.reason == .explicitAnchor ? currentExplicitAnchorFrame(for: target) : nil
    )
    NEChatSwiftUILogger.log(
      "timeline diagnostic scrollProxy id=\(target.id) proxyTarget=\(targetId) messageId=\(target.messageId) requestedAnchor=\(target.anchor.rawValue) effectiveAnchor=\(effectiveAnchor.rawValue) reason=\(target.reason.rawValue) animated=\(animated) scrollBefore=\(runtimeState.scrollMetricsDescription())"
    )
    let scrollAction = {
      proxy.scrollTo(targetId, anchor: effectiveAnchor.unitPoint)
    }
    if animated {
      withAnimation(.easeOut(duration: 0.2), scrollAction)
    } else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction, scrollAction)
    }
    NEChatSwiftUILogger.log(
      "timeline diagnostic scrollProxyDone id=\(target.id) proxyTarget=\(targetId) scrollAfter=\(runtimeState.scrollMetricsDescription())"
    )
  }

  private func isLatestBottomTarget(_ target: ChatTimelineScrollTarget) -> Bool {
    target.anchor == .bottom && target.messageId == rows.last?.id
  }

  private func isInitialLatestBottomTarget(_ target: ChatTimelineScrollTarget) -> Bool {
    isLatestBottomTarget(target) &&
      !target.animated &&
      target.reason == .initialLatest
  }

  private func isJumpToLatestBottomTarget(_ target: ChatTimelineScrollTarget) -> Bool {
    isLatestBottomTarget(target) &&
      target.reason == .jumpToLatest
  }

  private func isTimelineBottomCurrentlyVisible(fallbackIsVisible: Bool) -> Bool {
    Self.isTimelineBottomVisible(
      latestFrame: runtimeState.latestRowFrame,
      bottomFrame: runtimeState.bottomAnchorFrame,
      viewportHeight: runtimeState.viewportHeight,
      fallbackIsVisible: fallbackIsVisible
    )
  }

  private func scrollProxyTargetId(for target: ChatTimelineScrollTarget) -> String {
    if isLatestBottomTarget(target) {
      return Self.timelineBottomAnchorId
    }
    return target.messageId
  }

  private var isLoadOlderRetryRegionVisible: Bool {
    runtimeState.isTopLoadProbeVisible ||
      runtimeState.isAtTopEdge(threshold: Self.loadOlderTopEdgeThreshold) ||
      (runtimeState.isDraggingTimeline &&
        runtimeState.isNearTopVisible(threshold: Self.loadOlderPreloadRowThreshold))
  }

  private func activateLoadOlderTopExitGate() {
    runtimeState.requiresTopExitBeforeNextLoadOlder = true
    runtimeState.loadOlderRetryGeneration += 1
  }

  private var isLoadOlderTopExitGateActive: Bool {
    runtimeState.requiresTopExitBeforeNextLoadOlder &&
      isLoadOlderRetryRegionVisible
  }

  private func clearLoadOlderTopExitGateIfNeeded() {
    guard runtimeState.requiresTopExitBeforeNextLoadOlder,
          !isLoadOlderRetryRegionVisible else {
      return
    }
    runtimeState.requiresTopExitBeforeNextLoadOlder = false
    runtimeState.lastLoadOlderDecisionSignature = ""
    runtimeState.loadOlderRetryGeneration += 1
  }

  private func clearLoadOlderTopExitGateForUserPullIfNeeded() {
    guard runtimeState.requiresTopExitBeforeNextLoadOlder,
          runtimeState.isAtTopEdge(threshold: Self.loadOlderTopEdgeThreshold) else {
      return
    }
    runtimeState.requiresTopExitBeforeNextLoadOlder = false
    runtimeState.lastLoadOlderDecisionSignature = ""
    runtimeState.loadOlderRetryGeneration += 1
  }

  private func activateActivePrependScrollSuppression() {
    suppressLoadOlderRetryUntilNextDrag = true
    suppressLoadOlderRetryCooldownUntil = ProcessInfo.processInfo.systemUptime + Self.loadOlderPrependCooldown
    runtimeState.loadOlderRetryGeneration += 1
  }

  private var isActivePrependScrollSuppression: Bool {
    suppressLoadOlderRetryUntilNextDrag &&
      ProcessInfo.processInfo.systemUptime < suppressLoadOlderRetryCooldownUntil
  }

  private func clearActivePrependScrollSuppressionIfNeeded() {
    guard suppressLoadOlderRetryUntilNextDrag,
          (!isActivePrependScrollSuppression || !isLoadOlderRetryRegionVisible) else {
      return
    }
    suppressLoadOlderRetryUntilNextDrag = false
    suppressLoadOlderRetryCooldownUntil = 0
    runtimeState.lastLoadOlderDecisionSignature = ""
    runtimeState.loadOlderRetryGeneration += 1
  }

  private func activateLoadOlderGestureThrottle() {
    runtimeState.suppressLoadOlderUntilNextUserDrag = true
    runtimeState.loadOlderThrottleUntil = ProcessInfo.processInfo.systemUptime + Self.loadOlderGestureThrottleInterval
    runtimeState.loadOlderRetryGeneration += 1
  }

  private var isLoadOlderGestureThrottled: Bool {
    runtimeState.suppressLoadOlderUntilNextUserDrag ||
      ProcessInfo.processInfo.systemUptime < runtimeState.loadOlderThrottleUntil
  }

  private func clearLoadOlderGestureThrottleIfNeeded() {
    guard runtimeState.suppressLoadOlderUntilNextUserDrag ||
      runtimeState.loadOlderThrottleUntil > 0 else {
      return
    }
    guard !isLoadingOlder else {
      return
    }
    if runtimeState.suppressLoadOlderUntilNextUserDrag {
      runtimeState.suppressLoadOlderUntilNextUserDrag = false
      runtimeState.lastLoadOlderDecisionSignature = ""
      runtimeState.loadOlderRetryGeneration += 1
    }
    guard ProcessInfo.processInfo.systemUptime >= runtimeState.loadOlderThrottleUntil else {
      return
    }
    if runtimeState.loadOlderThrottleUntil > 0 {
      runtimeState.loadOlderThrottleUntil = 0
      runtimeState.lastLoadOlderDecisionSignature = ""
      runtimeState.loadOlderRetryGeneration += 1
    }
  }

  private var loadOlderGestureThrottleRemainingDescription: String {
    let remaining = runtimeState.loadOlderThrottleUntil - ProcessInfo.processInfo.systemUptime
    return remaining > 0 ? String(format: "%.3f", remaining) : "0"
  }

  private var shouldHideInitialLatestPositioning: Bool {
    guard !hasUserScrolled,
          scrollTarget?.reason == .initialLatest,
          let deadline = initialLatestRevealDeadline else {
      return false
    }
    return Date() < deadline
  }

  private func scheduleInitialLatestPositioningReveal(for target: ChatTimelineScrollTarget) {
    let deadline = Date().addingTimeInterval(Self.initialLatestPositioningHideTimeout)
    initialLatestRevealDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialLatestPositioningHideTimeout) {
      guard scrollTarget?.id == target.id,
            initialLatestRevealDeadline == deadline else {
        return
      }
      NEChatSwiftUILogger.log(
        "timeline initialLatest revealTimeout id=\(target.id) rows=\(rows.count) visibleTop=\(runtimeState.visibleTopMessageId() ?? "nil")"
      )
      initialLatestRevealDeadline = nil
    }
  }

  private func revealInitialLatestPositioningAfterTimeoutIfNeeded() {
    guard let deadline = initialLatestRevealDeadline,
          Date() >= deadline else {
      return
    }
    initialLatestRevealDeadline = nil
  }

  private var isPrependRestoreInProgress: Bool {
    if let target = scrollTarget,
       target.reason == .prependRestore,
       !runtimeState.hasConsumedScrollTarget(target.id) {
      return true
    }
    return scheduledScrollTargetReason == .prependRestore ||
      pendingPrependRestoreTarget != nil
  }

  private var isScrollTargetBlockingLoadOlder: Bool {
    guard let target = scrollTarget else {
      return false
    }
    if runtimeState.hasConsumedScrollTarget(target.id) {
      return false
    }
    if hasUserScrolled,
       target.reason != .prependRestore,
       scheduledScrollTargetId != target.id {
      return false
    }
    return true
  }

  private func clearPendingPrependRestoreTargetIfNeeded(_ target: ChatTimelineScrollTarget) {
    guard pendingPrependRestoreTarget?.id == target.id else {
      return
    }
    pendingPrependRestoreTarget = nil
    pendingPrependRestoreInitialFirstRowId = nil
    pendingPrependRestoreInitialRowCount = 0
    pendingPrependRestoreObservedRowsChange = false
  }

  private func logLoadOlderDecision(_ reason: String,
                                    source: String,
                                    triggerId: String? = nil) {
    runtimeState.rebuildRowOrderIfNeeded(rows: rows)
    let visibleTopId = runtimeState.visibleTopMessageId()
    let visibleTopIndex = runtimeState.visibleTopRowIndex()
    let scrollView = runtimeState.resolvedScrollView()
    let signature = [
      "reason=\(reason)",
      "source=\(source)",
      "trigger=\(triggerId ?? "nil")",
      "rows=\(rows.count)",
      "first=\(rows.first?.id ?? "nil")",
      "visibleTop=\(visibleTopId ?? "nil")",
      "visibleTopIndex=\(visibleTopIndex.map(String.init) ?? "nil")",
      "topProbe=\(runtimeState.isTopLoadProbeVisible)",
      "nearTop=\(runtimeState.isNearTopVisible(threshold: Self.loadOlderPreloadRowThreshold))",
      "hasUserScrolled=\(hasUserScrolled)",
      "hasMoreOlder=\(hasMoreOlder)",
      "isLoadingOlder=\(isLoadingOlder)",
      "scrollTarget=\(scrollTarget?.id ?? "nil")",
      "suppressOlder=\(suppressLoadOlderRetryUntilUserScroll)",
      "suppressNextDrag=\(suppressLoadOlderRetryUntilNextDrag)",
      "topExitGate=\(runtimeState.requiresTopExitBeforeNextLoadOlder)",
      "suppressUntilDrag=\(runtimeState.suppressLoadOlderUntilNextUserDrag)",
      "throttleLeft=\(loadOlderGestureThrottleRemainingDescription)",
      "offsetY=\(scrollView?.contentOffset.y.description ?? "nil")",
      "contentH=\(scrollView?.contentSize.height.description ?? "nil")",
    ].joined(separator: " ")
    guard runtimeState.lastLoadOlderDecisionSignature != signature else {
      return
    }
    runtimeState.lastLoadOlderDecisionSignature = signature
    NEChatSwiftUILogger.log("timeline loadOlder \(signature)")
  }

  private func logTimelineSmoothness(_ event: String) {
    runtimeState.rebuildRowOrderIfNeeded(rows: rows)
    let visibleTopId = runtimeState.visibleTopMessageId()
    let visibleTopIndex = runtimeState.visibleTopRowIndex()
    let scrollView = runtimeState.resolvedScrollView()
    let pending = runtimeState.pendingPrependCompensation
    let velocityY = scrollView?.panGestureRecognizer.velocity(in: scrollView).y
    let signature = [
      "event=\(event)",
      "rows=\(rows.count)",
      "first=\(rows.first?.id ?? "nil")",
      "last=\(rows.last?.id ?? "nil")",
      "visibleTop=\(visibleTopId ?? "nil")",
      "visibleTopIndex=\(visibleTopIndex.map(String.init) ?? "nil")",
      "visibleCount=\(runtimeState.visibleRowIds.count)",
      "topProbe=\(runtimeState.isTopLoadProbeVisible)",
      "nearTop=\(runtimeState.isNearTopVisible(threshold: Self.loadOlderPreloadRowThreshold))",
      "atTopEdge=\(runtimeState.isAtTopEdge(threshold: Self.loadOlderTopEdgeThreshold))",
      "hasUserScrolled=\(hasUserScrolled)",
      "isLoadingOlder=\(isLoadingOlder)",
      "hasMoreOlder=\(hasMoreOlder)",
      "scrollTarget=\(scrollTarget?.id ?? "nil")",
      "scrollReason=\(scrollTarget?.reason.rawValue ?? "nil")",
      "scheduledTarget=\(scheduledScrollTargetId ?? "nil")",
      "scheduledReason=\(scheduledScrollTargetReason?.rawValue ?? "nil")",
      "pendingRestore=\(pendingPrependRestoreTarget?.id ?? "nil")",
      "restoreRowsChanged=\(pendingPrependRestoreObservedRowsChange)",
      "pendingGen=\(pending?.generation.description ?? "nil")",
      "pendingRows=\(pending?.rowCount.description ?? "nil")",
      "pendingFirst=\(pending?.firstRowId ?? "nil")",
      "pendingAnchor=\(pending?.anchorRowId ?? "nil")",
      "pendingHeight=\(pending?.contentHeight.description ?? "nil")",
      "pendingOffsetY=\(pending?.contentOffsetY.description ?? "nil")",
      "pendingApplied=\(pending?.appliedCount.description ?? "nil")",
      "pendingInteractionGen=\(pending?.interactionGeneration.description ?? "nil")",
      "scheduledPrependGen=\(runtimeState.scheduledPrependCompensationGeneration?.description ?? "nil")",
      "currentPrependGen=\(runtimeState.prependCompensationGeneration)",
      "restoreGen=\(runtimeState.prependRestoreGeneration)",
      "suspended=\(isOlderPaginationSuspended)",
      "suspensionGen=\(runtimeState.olderPaginationSuspensionGeneration)",
      "dragGen=\(runtimeState.dragInteractionGeneration)",
      "timelineDragging=\(runtimeState.isDraggingTimeline)",
      "scrollDragging=\(scrollView?.isDragging.description ?? "nil")",
      "scrollTracking=\(scrollView?.isTracking.description ?? "nil")",
      "scrollDecelerating=\(scrollView?.isDecelerating.description ?? "nil")",
      "velocityY=\(velocityY?.description ?? "nil")",
      "offsetY=\(scrollView?.contentOffset.y.description ?? "nil")",
      "contentH=\(scrollView?.contentSize.height.description ?? "nil")",
      "boundsH=\(scrollView?.bounds.height.description ?? "nil")",
      "insetTop=\(scrollView?.adjustedContentInset.top.description ?? "nil")",
      "insetBottom=\(scrollView?.adjustedContentInset.bottom.description ?? "nil")",
      "suppressOlder=\(suppressLoadOlderRetryUntilUserScroll)",
      "suppressNextDrag=\(suppressLoadOlderRetryUntilNextDrag)",
      "activeSuppression=\(isActivePrependScrollSuppression)",
      "topExitGate=\(runtimeState.requiresTopExitBeforeNextLoadOlder)",
      "suppressUntilDrag=\(runtimeState.suppressLoadOlderUntilNextUserDrag)",
      "throttleLeft=\(loadOlderGestureThrottleRemainingDescription)",
    ].joined(separator: " ")
    guard runtimeState.lastSmoothnessLogSignature != signature else {
      return
    }
    runtimeState.lastSmoothnessLogSignature = signature
    NEChatSwiftUILogger.log("timeline smoothness \(signature)")
  }

  private func logSuspendedTimelineAction(_ action: String,
                                          source: String) {
    let scrollView = runtimeState.resolvedScrollView()
    NEChatSwiftUILogger.log(
      "offlineHistory timelineActionSkipped conversationId=\(diagnosticConversationId) action=\(action) source=\(source) suspensionGen=\(runtimeState.olderPaginationSuspensionGeneration) offsetY=\(scrollView?.contentOffset.y.description ?? "nil") contentH=\(scrollView?.contentSize.height.description ?? "nil") timelineDragging=\(runtimeState.isDraggingTimeline) scrollDragging=\(scrollView?.isDragging.description ?? "nil") scrollTracking=\(scrollView?.isTracking.description ?? "nil") scrollDecelerating=\(scrollView?.isDecelerating.description ?? "nil")"
    )
  }

  private func stopNetworkBreakMomentumIfNeeded(source: String) {
    guard isOlderPaginationSuspended,
          let scrollView = runtimeState.resolvedScrollView() else {
      return
    }
    let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
    let beforeOffset = scrollView.contentOffset
    let animationKeys = scrollView.layer.animationKeys() ?? []
    let minimumOffsetY = -scrollView.adjustedContentInset.top
    let maximumOffsetY = max(
      minimumOffsetY,
      scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
    )
    NEChatSwiftUILogger.log(
      "offlineHistory momentumObserved conversationId=\(diagnosticConversationId) source=\(source) suspensionGen=\(runtimeState.olderPaginationSuspensionGeneration) beforeOffsetY=\(beforeOffset.y) afterOffsetY=\(scrollView.contentOffset.y) validMinY=\(minimumOffsetY) validMaxY=\(maximumOffsetY) velocityY=\(velocity.y) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) insetTop=\(scrollView.adjustedContentInset.top) insetBottom=\(scrollView.adjustedContentInset.bottom) tracking=\(scrollView.isTracking) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating) animations=\(animationKeys) action=observeUIKitMotion clamped=false"
    )
  }

  private func scheduleNetworkBreakMotionDiagnostics(suspensionGeneration: Int) {
    let delays: [TimeInterval] = [0, 0.05, 0.15, 0.35]
    for (index, delay) in delays.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard isOlderPaginationSuspended,
              runtimeState.olderPaginationSuspensionGeneration == suspensionGeneration else {
          return
        }
        let scrollView = runtimeState.resolvedScrollView()
        let velocity = scrollView.map { scrollView in
          scrollView.panGestureRecognizer.velocity(in: scrollView).y
        }
        NEChatSwiftUILogger.log(
          "offlineHistory motionSample conversationId=\(diagnosticConversationId) index=\(index) suspensionGen=\(suspensionGeneration) offsetY=\(scrollView?.contentOffset.y.description ?? "nil") contentH=\(scrollView?.contentSize.height.description ?? "nil") velocityY=\(velocity?.description ?? "nil") tracking=\(scrollView?.isTracking.description ?? "nil") dragging=\(scrollView?.isDragging.description ?? "nil") decelerating=\(scrollView?.isDecelerating.description ?? "nil")"
        )
      }
    }
  }

  private static let timelineVerticalPadding: CGFloat = 12
  private static let olderLoadingOverlayHeight: CGFloat = 36
  private static let multiSelectIndicatorLeading: CGFloat = 16
  private static let multiSelectIndicatorSize: CGFloat = 18
  private static let multiSelectIndicatorSpacing: CGFloat = 8
  private static let multiSelectContentLeading = multiSelectIndicatorLeading +
    multiSelectIndicatorSize + multiSelectIndicatorSpacing
  private static let timelineBottomAnchorId = "chat-timeline-bottom-anchor"
  private static let loadOlderPreloadRowThreshold = 10
  private static let loadOlderTopEdgeThreshold: CGFloat = 36
  private static let loadOlderPrependCooldown: TimeInterval = 0.45
  private static let loadOlderGestureThrottleInterval: TimeInterval = 0.75
  private static let explicitAnchorPositionTolerance: CGFloat = 1
  private static let oversizedAITextLengthThreshold = 2_000
  private static let bottomVisibilityTolerance: CGFloat = 2
  private static let scrollInertiaCooldown: TimeInterval = 0.35
  private static let momentumCancellationDelay: TimeInterval = 0.035
  private static let bottomScrollCompletionProbeDelay: TimeInterval = 0.03
  private static let minimumPrependContentHeightDelta: CGFloat = 1
  private static let minimumPrependContentOffsetAdjustment: CGFloat = 0.5
  private static let prependCompensationAnchorSettleRowTolerance = 12
  private static let prependCompensationAnchorHoldOffsetThreshold: CGFloat = 4
  private static let prependCompensationActivePullDownJumpThreshold: CGFloat = 160
  private static let prependCompensationActivePullDownVelocityFloor: CGFloat = -40
  private static let prependCompensationUserScrollOffsetThreshold: CGFloat = 32
  private static let prependCompensationUserScrollVelocityThreshold: CGFloat = 280
  private static let prependContentOffsetCompensationDelays: [DispatchTimeInterval] = [
    .milliseconds(0),
    .milliseconds(16),
    .milliseconds(33),
    .milliseconds(50),
    .milliseconds(80),
    .milliseconds(120),
    .milliseconds(200),
    .milliseconds(350),
  ]
  private static let prependRestoreScrollRetryDelays: [DispatchTimeInterval] = [
    .milliseconds(0),
    .milliseconds(16),
    .milliseconds(50),
    .milliseconds(120),
    .milliseconds(240),
  ]
  private static let initialLatestBottomScrollDelays: [DispatchTimeInterval] = [
    .milliseconds(0),
    .milliseconds(16),
    .milliseconds(50),
  ]
  private static let immediateBottomJumpRetryDelays: [DispatchTimeInterval] = [
    .milliseconds(0),
    .milliseconds(16),
    .milliseconds(50),
    .milliseconds(120),
    .milliseconds(240),
    .milliseconds(420),
  ]
  private static let initialLatestPositioningHideTimeout: TimeInterval = 0.35
  private static let initialPinnedBottomScrollDelays: [DispatchTimeInterval] = [
    .milliseconds(16),
    .milliseconds(50),
    .milliseconds(120),
  ]
  private static let settledBottomScrollDelays: [DispatchTimeInterval] = [
    .milliseconds(0),
    .milliseconds(16),
    .milliseconds(50),
    .milliseconds(120),
    .milliseconds(240),
    .milliseconds(420),
    .milliseconds(700),
    .milliseconds(1000),
    .milliseconds(1400),
  ]
  private static let programmaticScrollRetryDelays: [DispatchTimeInterval] = [
    .milliseconds(16),
    .milliseconds(50),
    .milliseconds(120),
    .milliseconds(240),
    .milliseconds(420),
  ]
  private static let pinnedBottomScrollDelays: [DispatchTimeInterval] = [
    .milliseconds(16),
    .milliseconds(50),
    .milliseconds(120),
    .milliseconds(240),
    .milliseconds(420),
    .milliseconds(700),
    .milliseconds(1000),
    .milliseconds(1400),
    .milliseconds(1800),
  ]

  private static func isTimelineBottomVisible(latestFrame: CGRect?,
                                              bottomFrame: CGRect?,
                                              viewportHeight: CGFloat,
                                              fallbackIsVisible: Bool) -> Bool {
    if fallbackIsVisible {
      return true
    }
    guard let bottomFrame,
          viewportHeight > 0 else {
      return fallbackIsVisible
    }
    let isBottomAnchorAtViewportBottom = bottomFrame.maxY > 0 &&
      bottomFrame.maxY >= viewportHeight - Self.bottomVisibilityTolerance &&
      bottomFrame.maxY <= viewportHeight + Self.bottomVisibilityTolerance
    guard isBottomAnchorAtViewportBottom else {
      return false
    }
    guard let latestFrame else {
      return true
    }
    return isLatestFrameVisible(latestFrame, viewportHeight: viewportHeight)
  }

  private static func isLatestFrameVisible(_ frame: CGRect, viewportHeight: CGFloat) -> Bool {
    frame.maxY > Self.bottomVisibilityTolerance &&
      frame.minY < viewportHeight - Self.bottomVisibilityTolerance
  }

  private static func scrollTargetSequence(for target: ChatTimelineScrollTarget) -> Int {
    guard let rawSequence = target.id.split(separator: ":", maxSplits: 1).first,
          let sequence = Int(rawSequence) else {
      return -1
    }
    return sequence
  }

  private func stableScrollDelay(for target: ChatTimelineScrollTarget) -> DispatchTimeInterval {
    switch target.anchor {
    case .top:
      return .milliseconds(80)
    case .center:
      return .milliseconds(50)
    case .bottom:
      return .milliseconds(120)
    }
  }

  private func scrollTargetConsumptionFallbackDelay(for target: ChatTimelineScrollTarget) -> TimeInterval {
    switch target.reason {
    case .prependRestore:
      return 0.7
    case .normal:
      return target.animated ? 0.7 : 0.3
    case .initialLatest, .jumpToLatest:
      return 1.8
    case .explicitAnchor:
      return 1.5
    }
  }

  private func operationMenuPosition(for menu: OperationMenuState,
                                     in containerSize: CGSize) -> CGPoint {
    let menuSize = MessageOperationMenu.preferredSize(itemCount: menu.descriptors.count)
    let rowFrame = rowFrames[menu.messageId]
      ?? runtimeState.lastMeasuredVisibleRows.first(where: { $0.id == menu.messageId })?.frame
      ?? CGRect(
        x: 56,
        y: max(0, containerSize.height - menuSize.height - 24),
        width: max(0, containerSize.width - 112),
        height: 56
      )
    let direction = rows.first(where: { $0.id == menu.messageId })?.direction ?? .incoming

    let horizontalMargin: CGFloat = 8
    let leftAlignedX = 56 + menuSize.width / 2
    let rightAlignedX = containerSize.width - 56 - menuSize.width / 2
    let rawX: CGFloat
    switch direction {
    case .outgoing:
      rawX = rightAlignedX
    case .system:
      rawX = containerSize.width / 2
    case .incoming:
      rawX = leftAlignedX
    }

    let verticalGap: CGFloat = 4
    let minimumCenterY = horizontalMargin + menuSize.height / 2
    let maximumCenterY = max(
      minimumCenterY,
      containerSize.height - horizontalMargin - menuSize.height / 2
    )
    let candidateYs = [
      rowFrame.minY - menuSize.height / 2 - verticalGap,
      rowFrame.maxY + menuSize.height / 2 + verticalGap,
      minimumCenterY,
      maximumCenterY,
    ].map { $0.clamped(to: minimumCenterY ... maximumCenterY) }
    let rawY = candidateYs.min { lhs, rhs in
      operationMenuOverlapArea(
        centerY: lhs,
        menuSize: menuSize,
        rowFrame: rowFrame,
        centerX: rawX
      ) < operationMenuOverlapArea(
        centerY: rhs,
        menuSize: menuSize,
        rowFrame: rowFrame,
        centerX: rawX
      )
    } ?? minimumCenterY

    return CGPoint(
      x: rawX.clamped(
        to: horizontalMargin + menuSize.width / 2 ... max(horizontalMargin + menuSize.width / 2, containerSize.width - horizontalMargin - menuSize.width / 2)
      ),
      y: rawY
    )
  }

  private func operationMenuOverlapArea(centerY: CGFloat,
                                        menuSize: CGSize,
                                        rowFrame: CGRect,
                                        centerX: CGFloat) -> CGFloat {
    let menuFrame = CGRect(
      x: centerX - menuSize.width / 2,
      y: centerY - menuSize.height / 2,
      width: menuSize.width,
      height: menuSize.height
    )
    let overlap = menuFrame.intersection(rowFrame)
    guard !overlap.isNull else {
      return 0
    }
    return overlap.width * overlap.height
  }
}

private struct TimelineVisibleRow: Equatable {
  var id: String
  var frame: CGRect
  var measurementGeneration: Int

  var minY: CGFloat {
    frame.minY
  }
}

private struct TimelineLatestRowFrameMeasurement: Equatable {
  var rowId: String
  var frame: CGRect
  var measurementGeneration: Int
}

private struct TimelineExplicitAnchorFramePreferenceKey: PreferenceKey {
  static var defaultValue = [String: CGRect]()

  static func reduce(value: inout [String: CGRect],
                     nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { _, next in next }
  }
}

private struct ChatTimelineRowSelectionGesture: ViewModifier {
  var isEnabled: Bool
  var onSelect: () -> Void

  func body(content: Content) -> some View {
    if isEnabled {
      content
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    } else {
      content
    }
  }
}

private struct TimelinePrependCompensationState {
  var generation: Int
  var triggerId: String?
  var firstRowId: String?
  var rowCount: Int
  var contentHeight: CGFloat
  var contentOffsetY: CGFloat
  var anchorRowId: String?
  var interactionGeneration: Int
  var appliedCount: Int = 0
}

private final class TimelineRuntimeState: ObservableObject {
  var visibleRowIds = Set<String>()
  var lastMeasuredVisibleRows = [TimelineVisibleRow]()
  var lastMeasuredViewportHeight: CGFloat = 0
  var visibleAnchorId: String?
  var lastNotifiedVisibleRowIds = Set<String>()
  var lastNotifiedVisibleAnchorId: String?
  var visibleRowsNotificationGeneration = 0
  var hasPendingVisibleRowsNotification = false
  var lastBottomVisibility: Bool?
  var latestRowMeasurement: TimelineLatestRowFrameMeasurement?
  var lastNotifiedLatestRowId: String?
  var lastNotifiedLatestRowVisibility: Bool?
  var lastNotifiedLatestRowMeasurementGeneration: Int?
  var latestRowFrame: CGRect?
  var bottomAnchorFrame: CGRect?
  var pendingLatestRowFrame: CGRect?
  var pendingBottomAnchorFrame: CGRect?
  var hasPendingLatestRowFrame = false
  var hasPendingBottomAnchorFrame = false
  var isBottomFrameUpdateScheduled = false
  var bottomFrameUpdateGeneration = 0
  var explicitAnchorFrame: CGRect?
  weak var explicitAnchorProbeView: UIView?
  var explicitAnchorProbeTargetId: String?
  var appliedExplicitAnchorScrollTargetId: String?
  var correctedExplicitAnchorScrollTargetId: String?
  var explicitAnchorCorrectionCount = 0
  var presentedScrollTargetId: String?
  var presentedScrollTargetMessageId: String?
  var presentedScrollTargetAnchor: ChatTimelineScrollAnchor?
  var presentedScrollTargetReason: ChatTimelineScrollTarget.Reason?
  var presentedScrollTargetScopeId: String?
  var presentedScrollTargetSequence = -1
  var viewportHeight: CGFloat = 0
  var pinnedBottomScrollGeneration = 0
  var scheduledPinnedBottomScrollGeneration: Int?
  var usesFastInitialBottomPin = false
  var jumpToLatestGeneration = 0
  var prependRestoreGeneration = 0
  var olderPaginationSuspensionGeneration = 0
  var dragInteractionGeneration = 0
  var loadOlderGestureGeneration = 0
  var lastLoadOlderRequestDragGeneration: Int?
  var isTimelineDragGestureActive = false
  var isDraggingTimeline = false
  var isTopLoadProbeVisible = false
  var requiresTopExitBeforeNextLoadOlder = false
  var suppressLoadOlderUntilNextUserDrag = false
  var loadOlderThrottleUntil: TimeInterval = 0
  var loadOlderRetryGeneration = 0
  var scrollViewResolveRetryGeneration = 0
  var lastLoadOlderDecisionSignature = ""
  var lastSmoothnessLogSignature = ""
  var lastPrependRestoreSkipSignature = ""
  private var consumedScrollTargetIds = [String]()
  weak var scrollView: UIScrollView?
  weak var scrollProbeView: UIView?
  var prependCompensationGeneration = 0
  var scheduledPrependCompensationGeneration: Int?
  var pendingPrependCompensation: TimelinePrependCompensationState?
  private var rowsSignature = ""
  private var rowOrderById = [String: Int]()

  func clearPendingBottomFrames() {
    pendingLatestRowFrame = nil
    pendingBottomAnchorFrame = nil
    hasPendingLatestRowFrame = false
    hasPendingBottomAnchorFrame = false
  }

  func rebuildRowOrderIfNeeded(rows: [MessageRowState]) {
    let signature = "\(rows.count):\(rows.first?.id ?? ""):\(rows.last?.id ?? "")"
    guard rowsSignature != signature else {
      return
    }
    rowsSignature = signature
    rowOrderById = rows.enumerated().reduce(into: [String: Int]()) { result, item in
      result[item.element.id] = item.offset
    }
  }

  func visibleTopMessageId() -> String? {
    visibleRowIds.min { lhs, rhs in
      (rowOrderById[lhs] ?? Int.max) < (rowOrderById[rhs] ?? Int.max)
    }
  }

  func visibleTopRowIndex() -> Int? {
    guard let id = visibleTopMessageId() else {
      return nil
    }
    return rowOrderById[id]
  }

  func rowIndex(for id: String) -> Int? {
    rowOrderById[id]
  }

  func isNearTopVisible(threshold: Int) -> Bool {
    guard let index = visibleTopRowIndex() else {
      return false
    }
    return index <= threshold
  }

  func isAtTopEdge(threshold: CGFloat) -> Bool {
    guard let scrollView = resolvedScrollView() else {
      return false
    }
    return scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + threshold
  }

  func markScrollTargetConsumed(_ id: String) {
    guard !consumedScrollTargetIds.contains(id) else {
      return
    }
    consumedScrollTargetIds.append(id)
    if consumedScrollTargetIds.count > 16 {
      consumedScrollTargetIds.removeFirst(consumedScrollTargetIds.count - 16)
    }
  }

  func hasConsumedScrollTarget(_ id: String) -> Bool {
    consumedScrollTargetIds.contains(id)
  }

  func isContentWithinViewport(tolerance: CGFloat) -> Bool {
    guard let scrollView = resolvedScrollView(),
          scrollView.bounds.height > 0 else {
      return false
    }
    let scrollableHeight = scrollView.contentSize.height +
      scrollView.adjustedContentInset.top +
      scrollView.adjustedContentInset.bottom -
      scrollView.bounds.height
    return scrollableHeight <= tolerance
  }

  func isAtBottomEdge(tolerance: CGFloat) -> Bool {
    guard let scrollView = resolvedScrollView(),
          scrollView.bounds.height > 0 else {
      return false
    }
    let visibleMaxY = scrollView.contentOffset.y +
      scrollView.bounds.height -
      scrollView.adjustedContentInset.bottom
    let contentMaxY = scrollView.contentSize.height
    return visibleMaxY >= contentMaxY - tolerance
  }

  func scrollMetricsDescription() -> String {
    guard let scrollView = resolvedScrollView() else {
      return "scrollView=nil"
    }
    return [
      "offsetY=\(scrollView.contentOffset.y)",
      "contentH=\(scrollView.contentSize.height)",
      "boundsH=\(scrollView.bounds.height)",
      "insetTop=\(scrollView.adjustedContentInset.top)",
      "insetBottom=\(scrollView.adjustedContentInset.bottom)",
      "dragging=\(scrollView.isDragging)",
      "decelerating=\(scrollView.isDecelerating)",
    ].joined(separator: ",")
  }

  func bindExplicitAnchorProbe(_ probeView: UIView,
                               targetId: String) {
    explicitAnchorProbeView = probeView
    explicitAnchorProbeTargetId = targetId
  }

  func clearExplicitAnchorProbe(_ probeView: UIView? = nil) {
    if let probeView,
       explicitAnchorProbeView !== probeView {
      return
    }
    explicitAnchorProbeView = nil
    explicitAnchorProbeTargetId = nil
  }

  func explicitAnchorViewportFrame(targetId: String) -> CGRect? {
    guard explicitAnchorProbeTargetId == targetId,
          let probeView = explicitAnchorProbeView,
          let window = probeView.window else {
      return nil
    }
    guard let anchorScrollView = probeView.enclosingScrollView(),
          !(anchorScrollView is UITextView),
          anchorScrollView.window === window else {
      return nil
    }
    scrollView = anchorScrollView
    let probeFrameInWindow = probeView.convert(probeView.bounds, to: window)
    let viewportFrameInWindow = anchorScrollView.convert(anchorScrollView.bounds, to: window)
    let frameValues = [
      probeFrameInWindow.minX,
      probeFrameInWindow.minY,
      probeFrameInWindow.width,
      probeFrameInWindow.height,
      viewportFrameInWindow.minX,
      viewportFrameInWindow.minY,
    ]
    guard frameValues.allSatisfy(\.isFinite) else {
      return nil
    }
    return CGRect(
      x: probeFrameInWindow.minX - viewportFrameInWindow.minX,
      y: probeFrameInWindow.minY - viewportFrameInWindow.minY,
      width: probeFrameInWindow.width,
      height: probeFrameInWindow.height
    )
  }

  func resolvedScrollView() -> UIScrollView? {
    if let scrollView,
       isUsableTimelineScrollView(scrollView) {
      return scrollView
    }
    scrollView = nil
    if let probe = scrollProbeView {
      scrollView = probe.nearestTimelineScrollView(preferredHeight: viewportHeight)
      if scrollView != nil {
        return scrollView
      }
    }
    scrollView = UIView.activeTimelineScrollView(preferredHeight: viewportHeight)
    return scrollView
  }

  private func isUsableTimelineScrollView(_ scrollView: UIScrollView) -> Bool {
    guard scrollView.window != nil,
          !(scrollView is UITextView),
          scrollView.bounds.height > 0,
          scrollView.bounds.width > 0 else {
      return false
    }
    guard viewportHeight > Self.minimumViewportHeightForScrollViewValidation else {
      return true
    }
    return scrollView.bounds.height + Self.scrollViewViewportHeightTolerance >= viewportHeight
  }

  private static let minimumViewportHeightForScrollViewValidation: CGFloat = 120
  private static let scrollViewViewportHeightTolerance: CGFloat = 24
}

private struct TimelineVisibleRowPreferenceKey: PreferenceKey {
  static var defaultValue: [TimelineVisibleRow] = []

  static func reduce(value: inout [TimelineVisibleRow],
                     nextValue: () -> [TimelineVisibleRow]) {
    value.append(contentsOf: nextValue())
  }
}

private struct TimelineLatestRowFramePreferenceKey: PreferenceKey {
  static var defaultValue: TimelineLatestRowFrameMeasurement? = nil

  static func reduce(value: inout TimelineLatestRowFrameMeasurement?,
                     nextValue: () -> TimelineLatestRowFrameMeasurement?) {
    value = nextValue() ?? value
  }
}

private struct TimelineBottomAnchorFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect? = nil

  static func reduce(value: inout CGRect?,
                     nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}

struct MessageSelectableTextFramePreferenceKey: PreferenceKey {
  static let defaultValue = [String: CGRect]()

  static func reduce(value: inout [String: CGRect],
                     nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

private struct TimelineExplicitAnchorProbe: UIViewRepresentable {
  weak var runtimeState: TimelineRuntimeState?
  var targetId: String
  var onGeometryChange: () -> Void

  func makeUIView(context _: Context) -> TimelineExplicitAnchorProbeView {
    let view = TimelineExplicitAnchorProbeView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
    view.runtimeState = runtimeState
    view.onGeometryChange = onGeometryChange
    runtimeState?.bindExplicitAnchorProbe(view, targetId: targetId)
    view.requestGeometryUpdate()
    return view
  }

  func updateUIView(_ uiView: TimelineExplicitAnchorProbeView,
                    context _: Context) {
    uiView.runtimeState = runtimeState
    uiView.onGeometryChange = onGeometryChange
    runtimeState?.bindExplicitAnchorProbe(uiView, targetId: targetId)
    uiView.requestGeometryUpdate()
  }

  static func dismantleUIView(_ uiView: TimelineExplicitAnchorProbeView,
                              coordinator _: Void) {
    uiView.runtimeState?.clearExplicitAnchorProbe(uiView)
    uiView.onGeometryChange = nil
  }
}

private final class TimelineExplicitAnchorProbeView: UIView {
  weak var runtimeState: TimelineRuntimeState?
  var onGeometryChange: (() -> Void)?
  private var isGeometryUpdateScheduled = false

  override func layoutSubviews() {
    super.layoutSubviews()
    requestGeometryUpdate()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    requestGeometryUpdate()
  }

  func requestGeometryUpdate() {
    guard !isGeometryUpdateScheduled else {
      return
    }
    isGeometryUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.isGeometryUpdateScheduled = false
      guard self.window != nil else {
        return
      }
      self.onGeometryChange?()
    }
  }
}

private struct TimelineScrollViewProbe: UIViewRepresentable {
  weak var runtimeState: TimelineRuntimeState?
  var isActive: Bool
  var immediateBottomTarget: ChatTimelineScrollTarget?
  var allowsBottomNormalization: () -> Bool
  var shouldHandleContentSizeChange: () -> Bool
  var onContentSizeChange: () -> Void
  var onContentOffsetChange: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    context.coordinator.runtimeState = runtimeState
    context.coordinator.isActive = isActive
    context.coordinator.immediateBottomTarget = immediateBottomTarget
    context.coordinator.allowsBottomNormalization = allowsBottomNormalization
    context.coordinator.shouldHandleContentSizeChange = shouldHandleContentSizeChange
    DispatchQueue.main.async {
      runtimeState?.scrollProbeView = view
      context.coordinator.runtimeState = runtimeState
      context.coordinator.isActive = isActive
      guard isActive else {
        runtimeState?.scrollView = nil
        context.coordinator.observe(nil)
        return
      }
      let scrollView = context.coordinator.resolveTimelineScrollView(from: view)
      runtimeState?.scrollView = scrollView
      context.coordinator.immediateBottomTarget = immediateBottomTarget
      context.coordinator.allowsBottomNormalization = allowsBottomNormalization
      context.coordinator.shouldHandleContentSizeChange = shouldHandleContentSizeChange
      context.coordinator.observe(scrollView)
      if context.coordinator.immediateBottomTarget != nil {
        context.coordinator.applyImmediateBottomJumpIfNeeded(to: scrollView, source: "makeUIView")
      }
    }
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.onContentSizeChange = onContentSizeChange
    context.coordinator.onContentOffsetChange = onContentOffsetChange
    context.coordinator.runtimeState = runtimeState
    context.coordinator.isActive = isActive
    context.coordinator.immediateBottomTarget = immediateBottomTarget
    context.coordinator.allowsBottomNormalization = allowsBottomNormalization
    context.coordinator.shouldHandleContentSizeChange = shouldHandleContentSizeChange
    context.coordinator.logProbeUpdate()
    DispatchQueue.main.async {
      runtimeState?.scrollProbeView = uiView
      context.coordinator.runtimeState = runtimeState
      context.coordinator.isActive = isActive
      guard isActive else {
        runtimeState?.scrollView = nil
        context.coordinator.observe(nil)
        return
      }
      let scrollView = context.coordinator.resolveTimelineScrollView(from: uiView)
      runtimeState?.scrollView = scrollView
      context.coordinator.immediateBottomTarget = immediateBottomTarget
      context.coordinator.allowsBottomNormalization = allowsBottomNormalization
      context.coordinator.shouldHandleContentSizeChange = shouldHandleContentSizeChange
      context.coordinator.observe(scrollView)
      if context.coordinator.immediateBottomTarget != nil {
        context.coordinator.applyImmediateBottomJumpIfNeeded(to: scrollView, source: "updateUIView")
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onContentSizeChange: onContentSizeChange,
      onContentOffsetChange: onContentOffsetChange
    )
  }

  final class Coordinator {
    private static let immediateBottomOffsetTolerance: CGFloat = 2
    private static let bottomNormalizationRetryDelays: [TimeInterval] = [
      0.05,
      0.12,
      0.25,
      0.45,
    ]

    var onContentSizeChange: () -> Void
    var onContentOffsetChange: () -> Void
    weak var runtimeState: TimelineRuntimeState?
    var isActive = true
    var immediateBottomTarget: ChatTimelineScrollTarget?
    var allowsBottomNormalization: () -> Bool = { true }
    var shouldHandleContentSizeChange: () -> Bool = { false }
    private weak var observedScrollView: UIScrollView?
    private var contentSizeObservation: NSKeyValueObservation?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var lastContentSize: CGSize = .zero
    private var lastContentOffset: CGPoint = .zero
    private var appliedImmediateBottomKey: String?
    private var bottomNormalizationGeneration = 0
    private var lastProbeDiagnosticSignature = ""
    private var lastProbeUpdateSignature = ""

    init(onContentSizeChange: @escaping () -> Void,
         onContentOffsetChange: @escaping () -> Void) {
      self.onContentSizeChange = onContentSizeChange
      self.onContentOffsetChange = onContentOffsetChange
    }

    func resolveTimelineScrollView(from view: UIView) -> UIScrollView? {
      guard isActive else {
        return nil
      }
      let preferredHeight = runtimeState?.viewportHeight ?? 0
      if let scrollView = view.nearestTimelineScrollView(preferredHeight: preferredHeight) {
        return scrollView
      }
      let fallbackScrollView = runtimeState?.resolvedScrollView()
      if let fallbackScrollView {
        NEChatSwiftUILogger.log(
          "timeline diagnostic probeResolve fallback=runtimeState target=\(immediateBottomTarget?.id ?? "nil") targetAgeMs=\(immediateBottomTarget?.ageMilliseconds.description ?? "nil") offsetY=\(fallbackScrollView.contentOffset.y) contentH=\(fallbackScrollView.contentSize.height) boundsH=\(fallbackScrollView.bounds.height)"
        )
      } else {
        NEChatSwiftUILogger.log(
          "timeline diagnostic probeResolve fallback=nil target=\(immediateBottomTarget?.id ?? "nil") targetAgeMs=\(immediateBottomTarget?.ageMilliseconds.description ?? "nil") preferredH=\(preferredHeight) hierarchy=\(view.timelineSuperviewTrace())"
        )
      }
      return fallbackScrollView
    }

    func observe(_ scrollView: UIScrollView?) {
      guard observedScrollView !== scrollView else {
        return
      }
      contentSizeObservation = nil
      contentOffsetObservation = nil
      bottomNormalizationGeneration += 1
      observedScrollView = scrollView
      lastContentSize = scrollView?.contentSize ?? .zero
      lastContentOffset = scrollView?.contentOffset ?? .zero
      appliedImmediateBottomKey = nil
      logProbeScrollViewChanged(scrollView)
      guard let scrollView else {
        return
      }
      contentSizeObservation = scrollView.observe(
        \.contentSize,
        options: [.new]
      ) { [weak self] _, change in
        guard let self,
              self.isActive,
              let nextSize = change.newValue,
              nextSize != self.lastContentSize else {
          return
        }
        let previousSize = self.lastContentSize
        self.lastContentSize = nextSize
        let shouldDispatchContentSizeChange = self.shouldDispatchContentSizeChange()
        self.normalizeOverscrolledBottomIfNeeded(scrollView, source: "contentSizeObserved")
        self.logProbeMetrics(
          source: "contentSizeObserved",
          scrollView: scrollView,
          detail: "from=\(previousSize) to=\(nextSize)",
          allowsTargetlessDiagnostics: shouldDispatchContentSizeChange
        )
        if self.immediateBottomTarget != nil {
          self.applyImmediateBottomJumpIfNeeded(to: scrollView, source: "contentSizeChanged")
        }
        guard shouldDispatchContentSizeChange else {
          self.logContentSizeChangeSkippedIfNeeded(from: previousSize, to: nextSize)
          return
        }
        DispatchQueue.main.async { [weak self] in
          self?.onContentSizeChange()
        }
      }
      contentOffsetObservation = scrollView.observe(
        \.contentOffset,
        options: [.new]
      ) { [weak self] _, change in
        guard let self,
              self.isActive,
              let nextOffset = change.newValue,
              nextOffset != self.lastContentOffset else {
          return
        }
        let previousOffset = self.lastContentOffset
        self.lastContentOffset = nextOffset
        self.normalizeOverscrolledBottomIfNeeded(scrollView, source: "contentOffsetObserved")
        self.logProbeMetrics(
          source: "contentOffsetObserved",
          scrollView: scrollView,
          detail: "fromY=\(previousOffset.y) toY=\(nextOffset.y)",
          allowsTargetlessDiagnostics: self.shouldHandleContentSizeChange() || self.immediateBottomTarget != nil
        )
        guard self.shouldHandleContentSizeChange(),
              !scrollView.isTracking,
              !scrollView.isDragging,
              !scrollView.isDecelerating else {
          return
        }
        DispatchQueue.main.async { [weak self] in
          self?.onContentOffsetChange()
        }
      }
    }

    func logProbeUpdate() {
      guard isActive else {
        return
      }
      let hasContentSizeWork = shouldHandleContentSizeChange()
      let targetSignature = immediateBottomTarget.map {
        "\($0.id)|\($0.reason.rawValue)"
      } ?? "nil"
      let signature = "\(targetSignature)|work=\(hasContentSizeWork)"
      guard signature != lastProbeUpdateSignature else {
        return
      }
      lastProbeUpdateSignature = signature
      NEChatSwiftUILogger.log(
        "timeline diagnostic probeUpdate target=\(immediateBottomTarget?.id ?? "nil") ageMs=\(immediateBottomTarget?.ageMilliseconds.description ?? "nil") work=\(hasContentSizeWork)"
      )
    }

    func applyImmediateBottomJumpIfNeeded(to scrollView: UIScrollView?, source: String) {
      guard isActive else {
        return
      }
      guard let target = immediateBottomTarget else {
        NEChatSwiftUILogger.log("timeline diagnostic probeImmediate skip source=\(source) reason=noTarget")
        return
      }
      guard let scrollView else {
        NEChatSwiftUILogger.log(
          "timeline diagnostic probeImmediate skip source=\(source) id=\(target.id) ageMs=\(target.ageMilliseconds) reason=noScrollView"
        )
        return
      }
      guard scrollView.bounds.height > 0 else {
        NEChatSwiftUILogger.log(
          "timeline diagnostic probeImmediate skip source=\(source) id=\(target.id) ageMs=\(target.ageMilliseconds) reason=zeroBounds contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) offsetY=\(scrollView.contentOffset.y)"
        )
        return
      }
      let minimumOffsetY = -scrollView.adjustedContentInset.top
      let maximumOffsetY = max(
        minimumOffsetY,
        scrollView.contentSize.height -
          scrollView.bounds.height +
          scrollView.adjustedContentInset.bottom
      )
      let key = [
        target.id,
        String(describing: scrollView.contentSize),
        String(describing: scrollView.bounds.size),
        String(describing: scrollView.adjustedContentInset),
      ].joined(separator: "|")
      let driftY = scrollView.contentOffset.y - maximumOffsetY
      guard appliedImmediateBottomKey != key ||
        abs(driftY) > Self.immediateBottomOffsetTolerance else {
        NEChatSwiftUILogger.log(
          "timeline diagnostic probeImmediate skip source=\(source) id=\(target.id) ageMs=\(target.ageMilliseconds) reason=duplicate offsetY=\(scrollView.contentOffset.y) targetY=\(maximumOffsetY) driftY=\(driftY) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating)"
        )
        return
      }
      let beforeOffsetY = scrollView.contentOffset.y
      UIView.performWithoutAnimation {
        scrollView.setContentOffset(
          CGPoint(x: scrollView.contentOffset.x, y: maximumOffsetY),
          animated: false
        )
        scrollView.layer.removeAllAnimations()
      }
      appliedImmediateBottomKey = key
      NEChatSwiftUILogger.log(
        "timeline diagnostic probeImmediate apply source=\(source) id=\(target.id) ageMs=\(target.ageMilliseconds) beforeY=\(beforeOffsetY) afterY=\(scrollView.contentOffset.y) targetY=\(maximumOffsetY) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) insetTop=\(scrollView.adjustedContentInset.top) insetBottom=\(scrollView.adjustedContentInset.bottom)"
      )
    }

    private func normalizeOverscrolledBottomIfNeeded(_ scrollView: UIScrollView,
                                                     source: String) {
      guard allowsBottomNormalization() else {
        bottomNormalizationGeneration += 1
        NEChatSwiftUILogger.log(
          "offlineHistory bottomNormalizationSkipped source=\(source) offsetY=\(scrollView.contentOffset.y) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height)"
        )
        return
      }
      guard scrollView.bounds.height > 0 else {
        return
      }
      let minimumOffsetY = -scrollView.adjustedContentInset.top
      let maximumOffsetY = max(
        minimumOffsetY,
        scrollView.contentSize.height -
          scrollView.bounds.height +
          scrollView.adjustedContentInset.bottom
      )
      guard scrollView.contentOffset.y > maximumOffsetY + Self.immediateBottomOffsetTolerance else {
        bottomNormalizationGeneration += 1
        return
      }
      guard !scrollView.isDragging,
            !scrollView.isDecelerating else {
        scheduleBottomNormalizationAfterInteraction(scrollView, source: source)
        return
      }
      bottomNormalizationGeneration += 1
      let beforeOffsetY = scrollView.contentOffset.y
      UIView.performWithoutAnimation {
        scrollView.setContentOffset(
          CGPoint(x: scrollView.contentOffset.x, y: maximumOffsetY),
          animated: false
        )
        scrollView.layer.removeAllAnimations()
      }
      lastContentOffset = scrollView.contentOffset
      NEChatSwiftUILogger.log(
        "timeline diagnostic normalizeBottom source=\(source) beforeY=\(beforeOffsetY) afterY=\(scrollView.contentOffset.y) maxY=\(maximumOffsetY) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height)"
      )
    }

    private func scheduleBottomNormalizationAfterInteraction(_ scrollView: UIScrollView,
                                                             source: String) {
      bottomNormalizationGeneration += 1
      let generation = bottomNormalizationGeneration
      retryBottomNormalization(
        scrollView,
        source: source,
        generation: generation,
        delayIndex: 0
      )
    }

    private func retryBottomNormalization(_ scrollView: UIScrollView,
                                          source: String,
                                          generation: Int,
                                          delayIndex: Int) {
      guard Self.bottomNormalizationRetryDelays.indices.contains(delayIndex) else {
        return
      }
      let delay = Self.bottomNormalizationRetryDelays[delayIndex]
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak scrollView] in
        guard let self,
              let scrollView,
              self.isActive,
              self.observedScrollView === scrollView,
              self.bottomNormalizationGeneration == generation else {
          return
        }
        if scrollView.isDragging || scrollView.isDecelerating {
          self.retryBottomNormalization(
            scrollView,
            source: source,
            generation: generation,
            delayIndex: delayIndex + 1
          )
          return
        }
        self.normalizeOverscrolledBottomIfNeeded(
          scrollView,
          source: "\(source).interactionSettled"
        )
      }
    }

    private func logProbeScrollViewChanged(_ scrollView: UIScrollView?) {
      guard let scrollView else {
        NEChatSwiftUILogger.log(
          "timeline diagnostic probeObserve scrollView=nil target=\(immediateBottomTarget?.id ?? "nil") targetAgeMs=\(immediateBottomTarget?.ageMilliseconds.description ?? "nil")"
        )
        return
      }
      NEChatSwiftUILogger.log(
        "timeline diagnostic probeObserve scrollView=\(ObjectIdentifier(scrollView).hashValue) target=\(immediateBottomTarget?.id ?? "nil") targetAgeMs=\(immediateBottomTarget?.ageMilliseconds.description ?? "nil") offsetY=\(scrollView.contentOffset.y) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) insetTop=\(scrollView.adjustedContentInset.top) insetBottom=\(scrollView.adjustedContentInset.bottom) window=\(scrollView.window != nil)"
      )
    }

    private func shouldDispatchContentSizeChange() -> Bool {
      if shouldHandleContentSizeChange() || immediateBottomTarget != nil {
        return true
      }
      return false
    }

    private func logContentSizeChangeSkippedIfNeeded(from previousSize: CGSize,
                                                     to nextSize: CGSize) {
      let widthDelta = abs(nextSize.width - previousSize.width)
      let heightDelta = abs(nextSize.height - previousSize.height)
      let signature = [
        "contentSizeSkip",
        "w=\(Int(widthDelta.rounded()))",
        "h=\(Int(heightDelta.rounded()))",
        "target=\(immediateBottomTarget?.id ?? "nil")",
      ].joined(separator: "|")
      guard signature != lastProbeDiagnosticSignature else {
        return
      }
      lastProbeDiagnosticSignature = signature
      NEChatSwiftUILogger.log(
        "timeline diagnostic contentSizeChanged skip reason=noWork from=\(previousSize) to=\(nextSize) target=\(immediateBottomTarget?.id ?? "nil")"
      )
    }

    private func logProbeMetrics(source: String,
                                 scrollView: UIScrollView,
                                 detail: String,
                                 allowsTargetlessDiagnostics: Bool = true) {
      let target = immediateBottomTarget
      if target == nil,
         !allowsTargetlessDiagnostics {
        return
      }
      let minimumOffsetY = -scrollView.adjustedContentInset.top
      let maximumOffsetY = max(
        minimumOffsetY,
        scrollView.contentSize.height -
          scrollView.bounds.height +
          scrollView.adjustedContentInset.bottom
      )
      let driftY = scrollView.contentOffset.y - maximumOffsetY
      let signature = [
        source,
        target?.id ?? "nil",
        "\(Int(scrollView.contentOffset.y))",
        "\(Int(scrollView.contentSize.height))",
        "\(Int(maximumOffsetY))",
        detail,
      ].joined(separator: "|")
      guard target != nil || abs(driftY) > 2 || source == "contentSizeObserved" else {
        return
      }
      guard signature != lastProbeDiagnosticSignature else {
        return
      }
      lastProbeDiagnosticSignature = signature
      NEChatSwiftUILogger.log(
        "timeline diagnostic probeMetrics source=\(source) \(detail) target=\(target?.id ?? "nil") targetReason=\(target?.reason.rawValue ?? "nil") targetAgeMs=\(target?.ageMilliseconds.description ?? "nil") offsetY=\(scrollView.contentOffset.y) targetY=\(maximumOffsetY) driftY=\(driftY) contentH=\(scrollView.contentSize.height) boundsH=\(scrollView.bounds.height) insetTop=\(scrollView.adjustedContentInset.top) insetBottom=\(scrollView.adjustedContentInset.bottom) dragging=\(scrollView.isDragging) decelerating=\(scrollView.isDecelerating)"
      )
    }
  }
}

private extension UIView {
  static func activeTimelineScrollView(preferredHeight: CGFloat = 0) -> UIScrollView? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .filter { !$0.isHidden && $0.alpha > 0 }
      .compactMap { $0.firstTimelineScrollView(preferredHeight: preferredHeight) }
      .max { lhs, rhs in
        lhs.timelineScrollViewScore(preferredHeight: preferredHeight) <
          rhs.timelineScrollViewScore(preferredHeight: preferredHeight)
      }
  }

  func nearestTimelineScrollView(preferredHeight: CGFloat = 0) -> UIScrollView? {
    if let enclosing = enclosingScrollView(),
       enclosing.isTimelineScrollViewCandidate(preferredHeight: preferredHeight) {
      return enclosing
    }
    let searchRoot = superview ?? window
    return searchRoot?.firstTimelineScrollView(near: self, preferredHeight: preferredHeight)
  }

  func enclosingScrollView() -> UIScrollView? {
    var view = superview
    while let current = view {
      if let scrollView = current as? UIScrollView {
        return scrollView
      }
      view = current.superview
    }
    return nil
  }

  func firstTimelineScrollView(near probe: UIView? = nil,
                               preferredHeight: CGFloat = 0) -> UIScrollView? {
    timelineScrollViewCandidates()
      .max { lhs, rhs in
        lhs.timelineScrollViewScore(near: probe, preferredHeight: preferredHeight) <
          rhs.timelineScrollViewScore(near: probe, preferredHeight: preferredHeight)
      }
  }

  func timelineScrollViewCandidates() -> [UIScrollView] {
    var candidates = [UIScrollView]()
    if let scrollView = self as? UIScrollView,
       !(scrollView is UITextView),
       scrollView.bounds.height > 0,
       scrollView.bounds.width > 0 {
      candidates.append(scrollView)
    }
    for subview in subviews {
      candidates.append(contentsOf: subview.timelineScrollViewCandidates())
    }
    return candidates
  }

  func isTimelineScrollViewCandidate(preferredHeight: CGFloat) -> Bool {
    guard let scrollView = self as? UIScrollView,
          !(scrollView is UITextView),
          scrollView.bounds.height > 0,
          scrollView.bounds.width > 0 else {
      return false
    }
    guard preferredHeight > 120 else {
      return true
    }
    return scrollView.bounds.height + 24 >= preferredHeight
  }

  func timelineScrollViewScore(near probe: UIView? = nil,
                               preferredHeight: CGFloat = 0) -> CGFloat {
    guard let scrollView = self as? UIScrollView else {
      return 0
    }
    let scrollableHeight = max(0, scrollView.contentSize.height - scrollView.bounds.height)
    let areaScore = scrollView.bounds.width * scrollView.bounds.height / 1000
    let scrollableScore = min(scrollableHeight, 10_000) / 10
    let heightScore: CGFloat
    if preferredHeight > 0 {
      heightScore = max(0, 1000 - abs(scrollView.bounds.height - preferredHeight) * 4)
    } else {
      heightScore = 0
    }
    let proximityScore = timelineScrollViewProximityScore(near: probe)
    return heightScore + scrollableScore + areaScore + proximityScore
  }

  func timelineScrollViewProximityScore(near probe: UIView?) -> CGFloat {
    guard let probe,
          let probeFrame = probe.timelineWindowFrame(),
          let scrollFrame = timelineWindowFrame(),
          probe.window === window else {
      return 0
    }
    if scrollFrame.contains(probeFrame) || scrollFrame.intersects(probeFrame) {
      return 2000
    }
    let dx = max(scrollFrame.minX - probeFrame.maxX, probeFrame.minX - scrollFrame.maxX, 0)
    let dy = max(scrollFrame.minY - probeFrame.maxY, probeFrame.minY - scrollFrame.maxY, 0)
    return max(0, 1000 - sqrt(dx * dx + dy * dy))
  }

  func timelineWindowFrame() -> CGRect? {
    guard window != nil,
          !bounds.isEmpty else {
      return nil
    }
    return convert(bounds, to: nil)
  }

  func timelineSuperviewTrace(limit: Int = 8) -> String {
    var names = [String]()
    var current: UIView? = self
    var count = 0
    while let view = current, count < limit {
      names.append(String(describing: type(of: view)))
      current = view.superview
      count += 1
    }
    if let window {
      names.append("window:\(String(describing: type(of: window)))")
    }
    return names.joined(separator: "->")
  }
}

private extension ChatTimelineScrollAnchor {
  var unitPoint: UnitPoint {
    switch self {
    case .top:
      return .top
    case .center:
      return .center
    case .bottom:
      return .bottom
    }
  }
}
