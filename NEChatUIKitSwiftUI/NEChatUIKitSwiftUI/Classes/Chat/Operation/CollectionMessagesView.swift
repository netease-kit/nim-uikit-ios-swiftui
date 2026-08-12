// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import SwiftUI
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK

public struct CollectionMessagesView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: CollectionMessagesViewModel
  @State private var pendingDeleteCollectionId: String?
  @State private var pendingOperationRow: CollectionMessageRowState?
  private let token: ChatThemeToken
  private let onSelect: (CollectionMessageRowState) -> Void
  private let onContentSelect: ((CollectionMessageRowState) -> Void)?
  private let onSelectMessage: (PinMessageSelection) -> Void
  private let onCopy: (MessageRowState) -> Void
  private let onForward: (MessageRowState) -> Void
  private let onForwardMessage: ((MessageRowState, V2NIMMessage?) -> Void)?
  private let onOpenURL: (URL, String, ChatURLInteractionSource, CollectionMessageRowState) -> Void
  private let onBack: (() -> Void)?
  private let canForward: (MessageRowState) -> Bool
  private let playingAudioMessageId: String?
  private let onStopAudioPlayback: () -> Void

  @MainActor
  public init(viewModel: CollectionMessagesViewModel,
              token: ChatThemeToken = .normal,
              onSelect: @escaping (CollectionMessageRowState) -> Void = { _ in },
              onContentSelect: ((CollectionMessageRowState) -> Void)? = nil,
              onSelectMessage: @escaping (PinMessageSelection) -> Void = { _ in },
              onCopy: @escaping (MessageRowState) -> Void = { _ in },
              onForward: @escaping (MessageRowState) -> Void = { _ in },
              onForwardMessage: ((MessageRowState, V2NIMMessage?) -> Void)? = nil,
              onOpenURL: @escaping (URL, String, ChatURLInteractionSource, CollectionMessageRowState) -> Void = { _, _, _, _ in },
              onBack: (() -> Void)? = nil,
              canCopy: @escaping (MessageRowState) -> Bool = { _ in false },
              canForward: @escaping (MessageRowState) -> Bool = { _ in false },
              playingAudioMessageId: String? = nil,
              onStopAudioPlayback: @escaping () -> Void = {
                NotificationCenter.default.post(name: .neChatMediaPlaybackShouldStop, object: nil)
              }) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onSelect = onSelect
    self.onContentSelect = onContentSelect
    self.onSelectMessage = onSelectMessage
    self.onCopy = onCopy
    self.onForward = onForward
    self.onForwardMessage = onForwardMessage
    self.onOpenURL = onOpenURL
    self.onBack = onBack
    self.canForward = canForward
    self.playingAudioMessageId = playingAudioMessageId
    self.onStopAudioPlayback = onStopAudioPlayback
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: NEChatUIKitSwiftUIBundle.localized("chat_collection", value: "Collection"),
        token: token,
        backAction: {
          performBack()
        },
        backgroundColor: token.groupedPageBackground
      )

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(viewModel.rows) { row in
            let displayRow = row.collectionApplyingAudioPlayback(messageId: playingAudioMessageId)
            CollectionMessageRowView(
              row: displayRow,
              token: token,
              downloadProgress: viewModel.mediaDownloadProgressByRowId[row.id],
              onContentSelect: {
                selectContent(row)
              },
              onMore: {
                pendingOperationRow = row
              },
              onOpenURL: { url, displayText in
                onOpenURL(url, displayText, .textPreview, row)
              }
            )
            .padding(.horizontal, cardHorizontalInset)
            .padding(.bottom, 12)
            .onAppear {
              viewModel.loadMoreIfNeeded(currentRow: row)
            }
          }

          if viewModel.phase == .loadingMore {
            NEChatCommonPresentation.inlineLoadingView(token: token)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
          }
        }
        .padding(.top, 12)
      }
      .background(token.groupedPageBackground)
      .refreshable { viewModel.refresh() }
    }
    .background(token.groupedPageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty:
        NEChatCommonPresentation.emptyView(token: token,
          titleKey: "no_collection_message",
          fallbackTitle: NEChatUIKitSwiftUIBundle.localized("no_collection_message", value: "No Favorite Message"),
          imageKind: .user
        )
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.load(reset: true)
        }
      default:
        EmptyView()
      }
    }
    .neCommonTransientOverlay(
      viewModel.toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
    .onAppear { viewModel.load(reset: true) }
    .onDisappear(perform: onStopAudioPlayback)
    .neCommonConfirmationDialog(
      deleteCollectionDialogState,
      onAction: handleDeleteCollectionDialogAction,
      onDismiss: {
        pendingDeleteCollectionId = nil
      }
    )
    .neCommonConfirmationDialog(
      operationDialogState,
      onAction: handleOperationDialogAction,
      onDismiss: {
        pendingOperationRow = nil
      }
    )
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private func performBack() {
    onStopAudioPlayback()
    if let onBack {
      onBack()
    } else {
      dismiss()
    }
  }

  private func selectContent(_ row: CollectionMessageRowState) {
    if viewModel.mediaDownloadProgressByRowId[row.id] != nil {
      return
    }

    // Stop audio before navigating to any sub-page (non-audio content).
    // Must be early so that video/file download paths also trigger the stop.
    if let messageRow = row.messageRow,
       !NEChatUtilityMessageOperationRules.isAudioMessage(messageRow.content) {
      onStopAudioPlayback()
    }

    if viewModel.shouldDownloadVideoBeforePreview(row: row) {
      viewModel.downloadVideo(row: row)
      return
    }
    if viewModel.shouldDownloadAudioBeforePlayback(row: row) {
      viewModel.downloadAudio(row: row) { updatedRow in
        openDownloadedContent(updatedRow)
      }
      return
    }
    if viewModel.shouldDownloadFileBeforePreview(row: row) {
      viewModel.downloadFile(row: row)
      return
    }
    openDownloadedContent(row)
  }

  private func openDownloadedContent(_ row: CollectionMessageRowState) {
    if let messageRow = row.messageRow,
       !NEChatUtilityMessageOperationRules.isAudioMessage(messageRow.content) {
      onStopAudioPlayback()
    }
    if let onContentSelect {
      onContentSelect(row)
    } else {
      select(row)
    }
  }

  private func select(_ row: CollectionMessageRowState) {
    onSelect(row)
    onSelectMessage(viewModel.selection(for: row))
  }

  private func confirmDeleteCollection() {
    guard let id = pendingDeleteCollectionId else {
      return
    }
    pendingDeleteCollectionId = nil
    viewModel.removeCollection(id: id)
  }

  private var deleteCollectionDialogState: NECommonDialogState? {
    guard pendingDeleteCollectionId != nil else {
      return nil
    }

    return NECommonDialogState(
      id: "deleteCollection:\(pendingDeleteCollectionId ?? "")",
      title: NEChatUIKitSwiftUIBundle.localized("collection_delete_confirm", value: "Remove from favorite?"),
      presentationStyle: .alert,
      actions: [
        NECommonDialogAction(
          id: "cancel",
          title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
          role: .cancel
        ),
        NECommonDialogAction(
          id: "confirm",
          title: NEChatUIKitSwiftUIBundle.localized("sure", value: "OK"),
          role: .normal
        ),
      ]
    )
  }

  private func handleDeleteCollectionDialogAction(_ action: NECommonDialogAction) {
    switch action.id {
    case "confirm":
      confirmDeleteCollection()
    default:
      pendingDeleteCollectionId = nil
    }
  }

  private var cardHorizontalInset: CGFloat {
    token.styleMode == .fun ? 0 : 20
  }

  private func shouldShowCopy(for row: MessageRowState) -> Bool {
    // UIKit's collection controller derives copy directly from the collected
    // message, independent of the active chat's operation policy.
    NEChatUtilityMessageOperationRules.copyableText(row.content) != nil
  }

  private func shouldShowForward(for row: MessageRowState) -> Bool {
    guard canForward(row) else {
      return false
    }
    return !NEChatUtilityMessageOperationRules.isAudioMessage(row.content)
  }

  private var operationDialogState: NECommonDialogState? {
    guard let row = pendingOperationRow else {
      return nil
    }
    var actions = [
      NECommonDialogAction(
        id: "delete",
        title: NEChatUIKitSwiftUIBundle.localized("operation_delete_collection", value: "Delete Favorite"),
        imageName: "op_delete",
        imageBundle: NEChatUIKitSwiftUIBundle.bundle
      ),
    ]
    if let messageRow = row.messageRow, shouldShowCopy(for: messageRow) {
      actions.append(NECommonDialogAction(
        id: "copy",
        title: NEChatUIKitSwiftUIBundle.localized("operation_copy", value: "Copy"),
        imageName: "op_copy",
        imageBundle: NEChatUIKitSwiftUIBundle.bundle
      ))
    }
    if let messageRow = row.messageRow, shouldShowForward(for: messageRow) {
      actions.append(NECommonDialogAction(
        id: "forward",
        title: NEChatUIKitSwiftUIBundle.localized("operation_forward", value: "Forward"),
        imageName: "op_forward",
        imageBundle: NEChatUIKitSwiftUIBundle.bundle
      ))
    }
    actions.append(NECommonDialogAction(
      id: "cancel",
      title: NEChatUIKitSwiftUIBundle.localized("cancel", value: "Cancel"),
      role: .cancel
    ))

    return NECommonDialogState(
      id: "collectionOperation:\(row.id)",
      title: "",
      showsTitle: false,
      actions: actions
    )
  }

  private func handleOperationDialogAction(_ action: NECommonDialogAction) {
    guard let row = pendingOperationRow else {
      return
    }
    pendingOperationRow = nil
    switch action.id {
    case "delete":
      pendingDeleteCollectionId = row.id
    case "copy":
      if let messageRow = row.messageRow {
        onCopy(messageRow)
      }
    case "forward":
      if let messageRow = row.messageRow {
        forward(row, messageRow: messageRow)
      }
    default:
      break
    }
  }

  private func forward(_ row: CollectionMessageRowState, messageRow: MessageRowState? = nil) {
    guard let messageRow = messageRow ?? row.messageRow else {
      return
    }
    if let onForwardMessage {
      onForwardMessage(messageRow, viewModel.selection(for: row).anchorMessage)
    } else {
      onForward(messageRow)
    }
  }
}

private extension CollectionMessageRowState {
  func collectionApplyingAudioPlayback(messageId: String?) -> CollectionMessageRowState {
    guard let messageRow,
          let updatedMessageRow = messageRow.collectionApplyingAudioPlayback(messageId: messageId) else {
      return self
    }
    var next = self
    next.messageRow = updatedMessageRow
    return next
  }
}

private extension MessageRowState {
  func collectionApplyingAudioPlayback(messageId: String?) -> MessageRowState? {
    guard let updatedContent = content.collectionApplyingAudioPlayback(isPlaying: id == messageId) else {
      return nil
    }
    var next = self
    next.content = updatedContent
    return next
  }
}

private extension MessageContentState {
  func collectionApplyingAudioPlayback(isPlaying: Bool) -> MessageContentState? {
    switch self {
    case var .audio(audio):
      guard audio.isPlaying != isPlaying else {
        return nil
      }
      audio.isPlaying = isPlaying
      return .audio(audio)
    case let .reply(preview, boxed):
      guard let updatedContent = boxed.value.collectionApplyingAudioPlayback(isPlaying: isPlaying) else {
        return nil
      }
      return .reply(preview: preview, content: BoxedMessageContentState(updatedContent))
    default:
      return nil
    }
  }
}

private struct CollectionMessageRowView: View {
  var row: CollectionMessageRowState
  var token: ChatThemeToken
  var downloadProgress: Double?
  var onContentSelect: () -> Void = {}
  var onMore: () -> Void = {}
  var onOpenURL: (URL, String) -> Void = { _, _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Button(action: onContentSelect) {
        CollectionMessageContentView(row: row, token: token, downloadProgress: downloadProgress, onOpenURL: onOpenURL)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 16)
          .padding(.bottom, 12)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Rectangle()
        .fill(NEUIKitSwiftUIStyle.ColorToken.greyLine)
        .frame(height: 0.5)
        .padding(.horizontal, 16)

      Text(row.createTimeText)
        .font(.system(size: 12))
        .foregroundColor(token.secondaryTextColor)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 12)
    }
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
  }

  private var header: some View {
    HStack(spacing: 8) {
      NEChatCommonPresentation.avatarView(
        imageURL: row.avatarURL,
        initials: avatarInitials,
        token: token,
        size: 32,
        cornerRadius: avatarCornerRadius,
        hashID: row.senderId
      )

      VStack(alignment: .leading, spacing: 2) {
        Text(senderText)
          .font(.system(size: 14))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
        Text(conversationText)
          .font(.system(size: 14))
          .foregroundColor(token.secondaryTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
      }

      Spacer(minLength: 8)

      Button {
        onMore()
      } label: {
        NEChatCommonPresentation.commonIconView(
          imageName: "three_point",
          token: token,
          renderingMode: .original,
          size: CGSize(width: 18, height: 18),
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_more", value: "More")
        )
        .frame(width: 50, height: 40, alignment: .center)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_more", value: "More"))
    }
    .padding(.leading, 16)
    .padding(.trailing, 0)
    .padding(.top, 16)
  }

  private var senderText: String {
    row.senderName?.isEmpty == false ? row.senderName ?? "" : row.senderId ?? ""
  }

  private var conversationText: String {
    row.conversationTip?.isEmpty == false ? row.conversationTip ?? "" : row.conversationName ?? row.subtitle ?? ""
  }

    private var avatarInitials: String {
      ChatAvatarDisplayResolver.initials(
      displayName: row.avatarName,
      accountId: row.senderId
    )
  }

  private var cardCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : token.bubbleCornerRadius
  }

  private var avatarCornerRadius: CGFloat {
    token.styleMode == .fun ? token.controlCornerRadius / 2 : token.avatarCornerRadius
  }
}

private struct CollectionMessageContentView: View {
  var row: CollectionMessageRowState
  var token: ChatThemeToken
  var downloadProgress: Double?
  var onOpenURL: (URL, String) -> Void

  private var messageHighlights: [MessageTextHighlightState] {
    row.messageRow?.textHighlights ?? []
  }

  var body: some View {
    Group {
      if let messageRow = row.messageRow {
        content(for: collectionDisplayContent(messageRow.content))
      } else {
        fallbackText(row.previewText)
      }
    }
  }

  private func collectionDisplayContent(_ content: MessageContentState) -> MessageContentState {
    let unwrapped = unwrappedReplyContent(content)
    if case .multiForward = unwrapped {
      // UIKit selects the collection cell from the underlying custom message
      // type even when the message also carries reply metadata.
      return unwrapped
    }
    return content
  }

  @ViewBuilder
  private func content(for content: MessageContentState) -> some View {
    switch content {
    case let .text(text):
      collectionText(text,
                     highlights: collectionPreviewHighlights(in: text, highlights: messageHighlights),
                     lineLimit: 3,
                     font: collectionTextFont)
        .padding(.horizontal, 16)
    case let .richText(title, body):
      richText(title: title, body: body, highlights: messageHighlights)
        .padding(.horizontal, 16)
    case let .image(media):
      mediaPreview(media: media, isVideo: false)
        .padding(.leading, 16)
    case let .video(media):
      mediaPreview(media: media, isVideo: true, downloadProgress: downloadProgress)
        .padding(.leading, 16)
    case let .audio(audio):
      audioPreview(audio)
        .padding(.leading, 16)
    case let .file(file):
      filePreview(file, downloadProgress: downloadProgress)
        .padding(.leading, 16)
    case let .location(location):
      locationPreview(location)
        .padding(.leading, 16)
    case let .multiForward(multiForward):
      multiForwardPreview(multiForward)
        .padding(.leading, 16)
    case let .reply(_, boxed):
      replyPreview(for: boxed.value)
    case let .custom(title, body):
      richText(title: title, body: body ?? "")
        .padding(.horizontal, 16)
    case let .aiStream(text, _, error):
      collectionText(error ?? text, highlights: messageHighlights, lineLimit: 3, font: collectionTextFont)
        .padding(.horizontal, 16)
    case let .call(call):
      fallbackText(call.summary)
    case let .revoke(text), let .tip(text), let .unsupported(text):
      fallbackText(text)
    }
  }

  @ViewBuilder
  private func replyPreview(for content: MessageContentState) -> some View {
    switch unwrappedReplyContent(content) {
    case let .richText(title, body):
      richText(title: title, body: body, highlights: messageHighlights)
        .padding(.horizontal, 16)
    case let .custom(title, body):
      richText(title: title, body: body ?? "", highlights: messageHighlights)
        .padding(.horizontal, 16)
    default:
      let text = listPreviewText(for: content)
      collectionText(text,
                     highlights: collectionPreviewHighlights(in: text, highlights: messageHighlights),
                     lineLimit: 3,
                     font: collectionTextFont)
        .padding(.horizontal, 16)
    }
  }

  private func unwrappedReplyContent(_ content: MessageContentState) -> MessageContentState {
    var current = content
    while case let .reply(_, boxed) = current {
      current = boxed.value
    }
    return current
  }

  private func richText(title: String?,
                        body: String,
                        highlights: [MessageTextHighlightState] = []) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      if let title, !title.isEmpty {
        collectionTitleText(title)
      }
      if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        collectionText(body,
                       highlights: richTextBodyHighlights(in: body, highlights: highlights),
                       lineLimit: 2,
                       font: collectionTextFont)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: previewTextMaxHeight(lineLimit: 3), alignment: .topLeading)
    .clipped()
  }

  private func richTextBodyHighlights(in body: String,
                                      highlights: [MessageTextHighlightState]) -> [MessageTextHighlightState] {
    return normalizedHighlights(
      highlights.compactMap { bodyHighlight($0, in: body) },
      in: body
    )
  }

  private func collectionPreviewHighlights(in text: String,
                                           highlights: [MessageTextHighlightState]) -> [MessageTextHighlightState] {
    let bodyOffset = multilineBodyOffset(in: text)
    return normalizedHighlights(
      highlights.compactMap { collectionPreviewHighlight($0, bodyOffset: bodyOffset, in: text) },
      in: text
    )
  }

  private func collectionPreviewHighlight(_ highlight: MessageTextHighlightState,
                                          bodyOffset: Int?,
                                          in text: String) -> MessageTextHighlightState? {
    guard let bodyOffset else {
      return bodyHighlight(highlight, in: text)
    }
    if let shifted = shiftedHighlight(highlight, offset: bodyOffset, in: text),
       bodyHighlight(shifted, in: text) != nil {
      return shifted
    }
    let start = max(highlight.start, bodyOffset)
    let end = min(highlight.end, text.count)
    guard start < end else {
      return nil
    }
    return bodyHighlight(MessageTextHighlightState(start: start, end: end, kind: highlight.kind), in: text)
  }

  private func shiftedHighlight(_ highlight: MessageTextHighlightState,
                                offset: Int,
                                in text: String) -> MessageTextHighlightState? {
    let start = highlight.start + offset
    let end = highlight.end + offset
    guard start >= 0,
          start < end,
          end <= text.count else {
      return nil
    }
    return MessageTextHighlightState(start: start, end: end, kind: highlight.kind)
  }

  private func multilineBodyOffset(in text: String) -> Int? {
    guard let newlineIndex = text.firstIndex(where: { $0.isNewline }) else {
      return nil
    }
    let offset = text.distance(from: text.startIndex, to: newlineIndex) + 1
    return offset < text.count ? offset : nil
  }

  private func bodyHighlight(_ highlight: MessageTextHighlightState,
                             in text: String) -> MessageTextHighlightState? {
    guard highlight.start >= 0,
          highlight.start < highlight.end,
          highlight.end <= text.count else {
      return nil
    }
    if highlight.kind == .mention,
       substring(for: highlight, in: text)?
       .trimmingCharacters(in: .whitespacesAndNewlines)
       .hasPrefix("@") != true {
      return nil
    }
    return highlight
  }

  private func substring(for highlight: MessageTextHighlightState,
                         in text: String) -> String? {
    guard highlight.start >= 0,
          highlight.start < highlight.end,
          highlight.end <= text.count else {
      return nil
    }
    let lowerBound = text.index(text.startIndex, offsetBy: highlight.start)
    let upperBound = text.index(text.startIndex, offsetBy: highlight.end)
    return String(text[lowerBound ..< upperBound])
  }

  private func normalizedHighlights(_ highlights: [MessageTextHighlightState],
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

  private func listPreviewText(for content: MessageContentState) -> String {
    switch content {
    case let .richText(title, body):
      return [title, body]
        .compactMap { value in
          let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
    case let .reply(preview, boxed):
      let contentPreview = listPreviewText(for: boxed.value)
      return contentPreview.isEmpty ? preview ?? "" : contentPreview
    default:
      return ChatMessageMapper.previewText(for: content)
    }
  }

  @ViewBuilder
  private func collectionText(_ text: String,
                              highlights: [MessageTextHighlightState] = [],
                              lineLimit: Int,
                              font: Font) -> some View {
    Group {
      if ChatLinkTextView.containsLink(in: text) {
        ChatLinkTextView(text: text, token: token, baseColor: token.incomingTextColor, highlights: highlights, maxLines: lineLimit, onOpenURL: onOpenURL)
          .font(font)
          .lineLimit(lineLimit)
          .truncationMode(.tail)
      } else if !highlights.isEmpty {
        MessageHighlightedTextView(text: text, highlights: highlights, token: token, baseColor: token.incomingTextColor)
          .font(font)
          .lineLimit(lineLimit)
          .truncationMode(.tail)
      } else if MessageEmoticonTextView.containsEmoticon(in: text) {
        MessageEmoticonTextView(text: text, token: token, baseColor: token.incomingTextColor)
          .font(font)
          .lineLimit(lineLimit)
          .truncationMode(.tail)
      } else {
        Text(text)
          .font(font)
          .foregroundColor(token.incomingTextColor)
          .lineLimit(lineLimit)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func collectionTitleText(_ text: String) -> some View {
    Group {
      if MessageEmoticonTextView.containsEmoticon(in: text) {
        MessageEmoticonTextView(text: text, token: token, baseColor: token.incomingTextColor)
          .font(collectionTitleFont)
          .lineLimit(1)
          .truncationMode(.tail)
      } else {
        Text(text)
          .font(collectionTitleFont)
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func previewTextMaxHeight(lineLimit: Int) -> CGFloat {
    let lines = max(0, lineLimit)
    guard lines > 0 else {
      return 0
    }
    return CGFloat(lines) * previewTextLineHeight + CGFloat(lines - 1) * previewTextLineSpacing
  }

  private var previewTextLineHeight: CGFloat {
    22
  }

  private var previewTextLineSpacing: CGFloat {
    2
  }

  private func fallbackText(_ text: String) -> some View {
    collectionText(
      text.isEmpty
        ? NEChatUIKitSwiftUIBundle.localized("unkonw_pin_message", value: "Unsupported message type")
        : text,
      lineLimit: 3,
      font: collectionTextFont
    )
    .padding(.horizontal, 16)
  }

  private var collectionTextFont: Font {
    .system(size: collectionTextFontSize)
  }

  private var collectionTitleFont: Font {
    .system(size: collectionTitleFontSize, weight: .semibold)
  }

  private var collectionTitleFontSize: CGFloat {
    row.messageRow?.direction == .outgoing
      ? token.outgoingMessageFontSize
      : token.incomingMessageFontSize
  }

  private var collectionTextFontSize: CGFloat {
    14
  }

  private func mediaPreview(media: MessageMediaState,
                            isVideo: Bool,
                            downloadProgress: Double? = nil) -> some View {
    ZStack {
      token.dividerColor.opacity(0.6)
      if let url = isVideo ? media.collectionVideoThumbnailDisplayURL : media.collectionThumbnailDisplayURL {
        collectionMediaAsyncImage(
          url: url,
          media: media,
          fallbackURL: isVideo ? media.collectionVideoFallbackDisplayURL : nil
        )
      } else {
        mediaPlaceholder(label: row.previewText)
      }

      if isVideo {
        if let downloadProgress {
          MessageDownloadProgressView(progress: downloadProgress, token: token)
        } else {
          Image("video_play", bundle: NECommonUIKitSwiftUIBundle.bundle)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 60, height: 60)
            .accessibilityLabel(row.previewText)
        }

        if let duration = media.duration, duration > 0 {
          VStack {
            Spacer()
            HStack {
              Spacer()
              Text(ChatUnitFormatter.playTime(duration))
                .font(.system(size: 10))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.trailing, 7)
                .padding(.bottom, 7)
            }
          }
        }
      }
    }
    .frame(width: mediaSize(for: media).width, height: mediaSize(for: media).height)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: token.bubbleCornerRadius, style: .continuous))
  }

  @ViewBuilder
  private func collectionMediaAsyncImage(url: URL,
                                         media: MessageMediaState,
                                         fallbackURL: URL? = nil) -> some View {
    ChatCachedAsyncImage(
      url: url,
      fallbackURL: fallbackURL ?? media.collectionFallbackDisplayURL
    ) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      mediaPlaceholder(label: row.previewText)
    }
  }

  @ViewBuilder
  private func collectionLocationAsyncImage(url: URL) -> some View {
    ChatCachedAsyncImage(url: url) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      mapPlaceholder
    }
  }

  private func mediaPlaceholder(label: String) -> some View {
    Image(NEChatCommonPresentation.mediaPlaceholderImageName(token: token),
          bundle: NECommonUIKitSwiftUIBundle.bundle)
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: 84, height: 84)
      .accessibilityLabel(label)
  }

  private func audioPreview(_ audio: MessageAudioState) -> some View {
    HStack(spacing: 12) {
      AudioPlaybackIconView(
        isPlaying: audio.isPlaying,
        direction: .incoming,
        staticImageName: "left_play_3",
        token: token,
        size: CGSize(width: 28, height: 28),
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_message_audio", value: "[Audio]")
      )
      Text(ChatUnitFormatter.audioDurationText(audio.duration))
        .font(.system(size: 14))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
    }
    .padding(.leading, 16)
    .padding(.trailing, 12)
    .frame(width: audioWidth(duration: audio.duration), height: token.minBubbleHeight, alignment: .leading)
    .background(
      collectionAudioBackground
    )
  }

  @ViewBuilder
  private var collectionAudioBackground: some View {
    ChatCollectionResizableImage(
      imageName: collectionAudioBackgroundImageName,
      capInsets: collectionAudioBackgroundCapInsets
    )
  }

  private func filePreview(_ file: MessageFileState,
                           downloadProgress: Double? = nil) -> some View {
    HStack(spacing: 15) {
      ZStack {
        NEChatCommonPresentation.iconView(
          imageName: ChatFileIconResource.imageName(for: file),
          token: token,
          renderingMode: .original,
          size: CGSize(width: 32, height: 32),
          accessibilityLabel: file.name
        )
        if let downloadProgress {
          MessageDownloadProgressView(progress: downloadProgress, token: token)
            .scaleEffect(0.72)
        }
      }
      .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 5) {
        Text(file.name)
          .font(.system(size: 14))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.darkText)
          .lineLimit(1)
          .truncationMode(.middle)
        if let sizeText = file.sizeText, !sizeText.isEmpty {
          Text(sizeText)
            .font(.system(size: 10))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(width: token.fileBubbleWidth, height: token.fileBubbleHeight, alignment: .leading)
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: contentCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: contentCornerRadius, style: .continuous)
        .stroke(fileBorderColor, lineWidth: 1)
    )
  }

  private func locationPreview(_ location: MessageLocationState) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(location.title)
        .font(.system(size: 16))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 16)
        .padding(.top, 10)

      if let subtitle = location.subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
          .lineLimit(1)
          .truncationMode(.tail)
          .padding(.horizontal, 16)
          .padding(.top, 4)
      }

      ZStack {
        if let thumbnailURL = location.thumbnailURL {
          collectionLocationAsyncImage(url: thumbnailURL)
        } else {
          mapPlaceholder
          Text(NEChatUIKitSwiftUIBundle.localized("no_map_plugin", value: "No map plugin"))
            .font(.system(size: 16))
            .foregroundColor(token.secondaryTextColor)
            .lineLimit(1)
            .padding(.bottom, 40)
        }

        if location.thumbnailURL != nil {
          NEChatCommonPresentation.iconView(
            imageName: "location_point",
            token: token,
            renderingMode: .original,
            size: CGSize(width: 24, height: 24),
            accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_location_pin", value: "Pin")
          )
          .offset(y: 15)
        }
      }
      .frame(width: locationCardWidth, height: locationMapHeight)
      .clipped()
      .padding(.top, 4)
    }
    .frame(width: locationCardWidth, height: locationCardHeight, alignment: .topLeading)
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .stroke(NEUIKitSwiftUIStyle.ColorToken.outline, lineWidth: 1)
    )
  }

  private var mapPlaceholder: some View {
    NEChatCommonPresentation.iconView(
      imageName: "map_placeholder_image",
      token: token,
      renderingMode: .original,
      size: CGSize(width: locationCardWidth, height: locationMapHeight),
      accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("chat_location_static_preview", value: "Location")
    )
  }

  private func multiForwardPreview(_ multiForward: MessageMultiForwardState) -> some View {
    ZStack(alignment: .topLeading) {
      multiForwardTitle(multiForward)
        .frame(width: multiForwardTitleWidth, height: 22, alignment: .leading)
        .offset(x: multiForwardContentLeading, y: multiForwardTitleTop)

      MessageMultiForwardSummaryRowsView(
        texts: multiForward.summaries.prefix(3).map(\.compactDisplayText),
        context: .compact,
        width: multiForwardSummaryWidth,
        fontSize: multiForwardSummaryFontSize,
        color: multiForwardSummaryColor,
        token: token
      )
      .frame(width: multiForwardSummaryWidth, height: 60, alignment: .topLeading)
      .clipped()
      .offset(x: multiForwardContentLeading, y: multiForwardSummaryTop)
    }
    .frame(width: compactCardWidth, height: 100, alignment: .topLeading)
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: compactCardCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: compactCardCornerRadius, style: .continuous)
        .stroke(fileBorderColor, lineWidth: 1)
    )
  }

  @ViewBuilder
  private func multiForwardTitle(_ multiForward: MessageMultiForwardState) -> some View {
    if multiForward.hasSessionName {
      HStack(spacing: 0) {
        MessageEmoticonTextView(text: multiForward.title, token: token, baseColor: token.incomingTextColor)
          .font(.system(size: multiForwardTitleFontSize))
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(1)
        Text(NEChatUIKitSwiftUIBundle.localized("chat_history_by", value: "`s messages"))
          .font(.system(size: multiForwardTitleFontSize))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
    } else {
      Text(NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History"))
        .font(.system(size: multiForwardTitleFontSize))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
    }
  }

  private var multiForwardContentLeading: CGFloat {
    token.styleMode == .fun ? 12 + token.funMargin : 16
  }

  private var multiForwardTitleTop: CGFloat {
    token.styleMode == .fun ? 12 : 10
  }

  private var multiForwardSummaryTop: CGFloat {
    token.styleMode == .fun ? 38 : 34
  }

  private var multiForwardTitleWidth: CGFloat {
    compactCardWidth - multiForwardContentLeading - 12
  }

  private var multiForwardSummaryWidth: CGFloat {
    248
  }

  private var multiForwardTitleFontSize: CGFloat {
    token.styleMode == .fun ? 16 : 14
  }

  private var multiForwardSummaryFontSize: CGFloat {
    token.styleMode == .fun ? 12 : 14
  }

  private var multiForwardSummaryColor: Color {
    token.styleMode == .fun ? Color(hex: 0xBBBBBB) : NEUIKitSwiftUIStyle.ColorToken.lightText
  }

  private var locationMapHeight: CGFloat {
    NEChatUIKitSwiftUIConstants.locationThumbnailHeight
  }

  private var locationCardWidth: CGFloat {
    NEChatUIKitSwiftUIConstants.locationCardSize.width
  }

  private var locationCardHeight: CGFloat {
    NEChatUIKitSwiftUIConstants.locationCardSize.height
  }

  private func mediaSize(for media: MessageMediaState) -> CGSize {
    NEChatUtilityMessageMediaSizer.size(for: media, token: token)
  }

  private func audioWidth(duration: TimeInterval) -> CGFloat {
    let base: CGFloat = 96
    let durationSeconds = ChatUnitFormatter.audioDurationSeconds(duration)
    guard durationSeconds > 2 else {
      return base
    }
    return min(CGFloat(durationSeconds) * 8 + base, token.audioMaxWidth)
  }

  private var collectionAudioBackgroundImageName: String {
    token.styleMode == .fun ? "fun_pin_message_audio_bg" : "chat_message_receive"
  }

  private var collectionAudioBackgroundCapInsets: EdgeInsets {
    EdgeInsets(top: 35, leading: 25, bottom: 10, trailing: 25)
  }

  private var compactCardWidth: CGFloat {
    276
  }

  private var compactCardCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : token.bubbleCornerRadius
  }

  private var contentCornerRadius: CGFloat {
    token.bubbleCornerRadius
  }

  private var fileBorderColor: Color {
    NEUIKitSwiftUIStyle.ColorToken.border
  }
}

private struct ChatCollectionResizableImage: View {
  var imageName: String
  var capInsets: EdgeInsets

  var body: some View {
    ChatResizableUIImageView(imageName: imageName, capInsets: capInsets)
  }
}

private extension MessageMediaState {
  var collectionThumbnailDisplayURL: URL? {
    if let localPath, !localPath.isEmpty {
      return URL(fileURLWithPath: localPath)
    }
    return thumbnailURL ?? url
  }

  var collectionFallbackDisplayURL: URL? {
    if let localPath, !localPath.isEmpty {
      return URL(fileURLWithPath: localPath)
    }
    return url ?? thumbnailURL
  }

  var collectionVideoThumbnailDisplayURL: URL? {
    thumbnailURL ?? url ?? localVideoFileURL
  }

  var collectionVideoFallbackDisplayURL: URL? {
    url ?? thumbnailURL ?? localVideoFileURL
  }

  var localVideoFileURL: URL? {
    guard let localPath, !localPath.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: localPath)
  }
}
