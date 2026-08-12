// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import Foundation
import NEChatKit
import NECommonUIKitSwiftUI
import NIMSDK
import SwiftUI

public struct PinMessagesView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: PinMessagesViewModel
  @State private var pendingOperationRow: MessageRowState?
  private let token: ChatThemeToken
  private let onSelect: (MessageRowState) -> Void
  private let onContentSelect: ((MessageRowState) -> Void)?
  private let onSelectMessage: (PinMessageSelection) -> Void
  private let onCopy: (MessageRowState) -> Void
  private let onForward: (MessageRowState) -> Void
  private let onForwardMessage: ((MessageRowState, V2NIMMessage?) -> Void)?
  private let onOpenURL: (URL, String, ChatURLInteractionSource, MessageRowState) -> Void
  private let onBack: (() -> Void)?
  private let canCopy: (MessageRowState) -> Bool
  private let canForward: (MessageRowState) -> Bool
  private let playingAudioMessageId: String?
  private let onStopAudioPlayback: () -> Void

  @MainActor
  public init(viewModel: PinMessagesViewModel,
              token: ChatThemeToken = .normal,
              onSelect: @escaping (MessageRowState) -> Void = { _ in },
              onContentSelect: ((MessageRowState) -> Void)? = nil,
              onSelectMessage: @escaping (PinMessageSelection) -> Void = { _ in },
              onCopy: @escaping (MessageRowState) -> Void = { _ in },
              onForward: @escaping (MessageRowState) -> Void = { _ in },
              onForwardMessage: ((MessageRowState, V2NIMMessage?) -> Void)? = nil,
              onOpenURL: @escaping (URL, String, ChatURLInteractionSource, MessageRowState) -> Void = { _, _, _, _ in },
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
    self.canCopy = canCopy
    self.canForward = canForward
    self.playingAudioMessageId = playingAudioMessageId
    self.onStopAudioPlayback = onStopAudioPlayback
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: NEChatUIKitSwiftUIBundle.localized("operation_pin", value: "Pin"),
        token: token,
        backAction: {
          performBack()
        },
        backgroundColor: token.groupedPageBackground
      )

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(viewModel.rows) { row in
            let displayRow = row.pinApplyingAudioPlayback(messageId: playingAudioMessageId)
            PinMessageCardView(
              row: displayRow,
              token: token,
              downloadProgress: viewModel.mediaDownloadProgressByRowId[row.id],
              onCardSelect: {
                select(row)
              },
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
          }
        }
      }
      .background(token.groupedPageBackground)
    }
    .background(token.groupedPageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .overlay {
      switch viewModel.phase {
      case .loading:
        NEChatCommonPresentation.loadingView(token: token)
      case .empty:
        NEChatCommonPresentation.emptyView(
          token: token,
          titleKey: "no_pin_message",
          fallbackTitle: NEChatUIKitSwiftUIBundle.localized("no_pin_message", value: "No pinned messages"),
          imageKind: emptyImageKind
        )
      case .failed(let error):
        NEChatCommonPresentation.errorView(error, token: token) {
          viewModel.load()
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
    .onAppear { viewModel.load() }
    .onDisappear(perform: onStopAudioPlayback)
    .onChange(of: viewModel.rows.map(\.id)) { rowIds in
      guard let pendingOperationRow,
            !rowIds.contains(pendingOperationRow.id) else {
        return
      }
      self.pendingOperationRow = nil
    }
    .neCommonConfirmationDialog(
      operationDialogState,
      onAction: handleOperationDialogAction,
      onDismiss: {
        pendingOperationRow = nil
      }
    )
  }

  private var cardHorizontalInset: CGFloat {
    token.styleMode == .fun ? 0 : 20
  }

  private var emptyImageKind: NECommonEmptyImageKind {
    token.styleMode == .fun ? .user : .generic
  }

  private func performBack() {
    onStopAudioPlayback()
    if let onBack {
      onBack()
    } else {
      dismiss()
    }
  }

  private func select(_ row: MessageRowState) {
    onStopAudioPlayback()
    onSelect(row)
    onSelectMessage(viewModel.selection(for: row))
  }

  private func selectContent(_ row: MessageRowState) {
    if viewModel.mediaDownloadProgressByRowId[row.id] != nil {
      return
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

  private func openDownloadedContent(_ row: MessageRowState) {
    if !NEChatUtilityMessageOperationRules.isAudioMessage(row.content) {
      onStopAudioPlayback()
    }
    if let onContentSelect {
      onContentSelect(row)
    } else {
      select(row)
    }
  }

  private func shouldShowCopy(for row: MessageRowState) -> Bool {
    guard canCopy(row) else {
      return false
    }
    return NEChatUtilityMessageOperationRules.isTextMessage(row.content)
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
        id: "unpin",
        title: NEChatUIKitSwiftUIBundle.localized("operation_cancel_pin", value: "Unpin"),
        imageName: "op_untop",
        imageBundle: NEChatUIKitSwiftUIBundle.bundle
      ),
    ]
    if shouldShowCopy(for: row) {
      actions.append(NECommonDialogAction(
        id: "copy",
        title: NEChatUIKitSwiftUIBundle.localized("operation_copy", value: "Copy"),
        imageName: "op_copy",
        imageBundle: NEChatUIKitSwiftUIBundle.bundle
      ))
    }
    if shouldShowForward(for: row) {
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
      id: "pinOperation:\(row.id)",
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
    case "unpin":
      viewModel.removePin(row: row)
    case "copy":
      onCopy(row)
    case "forward":
      forward(row)
    default:
      break
    }
  }

  private func forward(_ row: MessageRowState) {
    if let onForwardMessage {
      onForwardMessage(row, viewModel.selection(for: row).anchorMessage)
    } else {
      onForward(row)
    }
  }
}

private extension MessageRowState {
  func pinApplyingAudioPlayback(messageId: String?) -> MessageRowState {
    var next = self
    next.content = next.content.pinApplyingAudioPlayback(isPlaying: id == messageId)
    return next
  }
}

private extension MessageContentState {
  func pinApplyingAudioPlayback(isPlaying: Bool) -> MessageContentState {
    switch self {
    case var .audio(audio):
      audio.isPlaying = isPlaying
      return .audio(audio)
    case let .reply(preview, boxed):
      return .reply(preview: preview, content: BoxedMessageContentState(boxed.value.pinApplyingAudioPlayback(isPlaying: isPlaying)))
    default:
      return self
    }
  }
}

private struct PinMessageContentBoundsPreferenceKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>?

  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = nextValue() ?? value
  }
}

private struct PinMessageCardView: View {
  @State private var linkActivationGeneration = 0
  var row: MessageRowState
  var token: ChatThemeToken
  var downloadProgress: Double?
  var onCardSelect: () -> Void
  var onContentSelect: () -> Void
  var onMore: () -> Void
  var onOpenURL: (URL, String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Button(action: onCardSelect) {
        Rectangle()
          .fill(token.dividerColor)
          .frame(height: 0.5)
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      contentArea
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
  }

  @ViewBuilder
  private var contentArea: some View {
    ZStack(alignment: .topLeading) {
      if previewContainsLink {
        preview
          .frame(maxWidth: pinMessageContentMaxWidth, alignment: .topLeading)
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 16)
          .contentShape(Rectangle())
          .simultaneousGesture(
            SpatialTapGesture().onEnded { _ in
              scheduleNonLinkContentSelection()
            }
          )
          .anchorPreference(key: PinMessageContentBoundsPreferenceKey.self, value: .bounds) { $0 }
      } else {
        Button(action: onContentSelect) {
          preview
            .frame(maxWidth: pinMessageContentMaxWidth, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: usesFullWidthContentHitArea ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
        .anchorPreference(key: PinMessageContentBoundsPreferenceKey.self, value: .bounds) { $0 }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlayPreferenceValue(PinMessageContentBoundsPreferenceKey.self) { contentBounds in
      if !usesFullWidthContentHitArea, let contentBounds {
        GeometryReader { geometry in
          let contentFrame = geometry[contentBounds]
          let trailingWidth = max(0, geometry.size.width - contentFrame.maxX)
          Button(action: onCardSelect) {
            Color.clear
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .frame(width: trailingWidth, height: geometry.size.height)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .allowsHitTesting(trailingWidth > 0.5)
        }
      }
    }
  }

  private var previewContainsLink: Bool {
    contentContainsLink(row.content)
  }

  private func contentContainsLink(_ content: MessageContentState) -> Bool {
    switch content {
    case let .text(text):
      return ChatLinkTextView.containsLink(in: text)
    case let .richText(title, body):
      return ChatLinkTextView.containsLink(in: title ?? "") ||
        ChatLinkTextView.containsLink(in: body)
    case let .custom(title, body):
      return ChatLinkTextView.containsLink(in: title) ||
        ChatLinkTextView.containsLink(in: body ?? "")
    case let .reply(_, boxed):
      return contentContainsLink(boxed.value)
    default:
      return false
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      Button(action: onCardSelect) {
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
              .font(.system(size: 12))
              .foregroundColor(token.incomingTextColor)
              .lineLimit(1)
              .truncationMode(.tail)
            Text(timeText)
              .font(.system(size: 12))
              .foregroundColor(token.secondaryTextColor)
              .lineLimit(1)
              .truncationMode(.tail)
          }

          Spacer(minLength: 8)
        }
        .padding(.leading, 16)
        .padding(.top, 16)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

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
        .padding(.top, 16)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(NEChatUIKitSwiftUIBundle.localized("chat_more", value: "More"))
    }
  }

  @ViewBuilder
  private var preview: some View {
    switch row.content {
    case let .image(media):
      pinImagePreview(media: media)
    case let .video(media):
      pinVideoPreview(media: media, downloadProgress: downloadProgress)
    case let .audio(audio):
      pinAudioPreview(audio)
    case let .file(file):
      pinFilePreview(file, downloadProgress: downloadProgress)
    case let .location(location):
      pinLocationPreview(location)
    case let .multiForward(multiForward):
      multiForwardPreview(multiForward)
    default:
      textPreview
    }
  }

  private var textPreview: some View {
    Group {
      switch row.content {
      case let .richText(title, body):
        richTextPreview(title: title, body: body)
      case let .custom(title, body):
        richTextPreview(title: title, body: body ?? "")
      case let .reply(_, boxed):
        utilityText(listPreviewText(for: boxed.value), highlights: row.textHighlights, lineLimit: 3)
      default:
        utilityText(ChatMessageMapper.previewText(for: row.content), highlights: row.textHighlights, lineLimit: 3)
      }
    }
  }

  private func richTextPreview(title: String?, body: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      if let title, !title.isEmpty {
        utilityText(title, lineLimit: 1, font: .system(size: pinTextFontSize, weight: .semibold))
      }
      if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        utilityText(body, lineLimit: 2)
      }
    }
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
  private func utilityText(_ text: String,
                           highlights: [MessageTextHighlightState] = [],
                           lineLimit: Int,
                           font: Font = .system(size: 14)) -> some View {
    Group {
      if ChatLinkTextView.containsLink(in: text) {
        ChatLinkTextView(text: text, token: token, baseColor: token.incomingTextColor, highlights: highlights, maxLines: lineLimit) { url, displayText in
          linkActivationGeneration += 1
          onOpenURL(url, displayText)
        }
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

  private func scheduleNonLinkContentSelection() {
    let generation = linkActivationGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      guard linkActivationGeneration == generation else {
        return
      }
      onContentSelect()
    }
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

  private func pinImagePreview(media: MessageMediaState) -> some View {
    ZStack {
      pinMediaBackground
      if let url = media.pinThumbnailDisplayURL {
        pinMediaAsyncImage(url: url, media: media)
      } else {
        pinMediaPlaceholder(label: ChatMessageMapper.previewText(for: row.content))
      }
    }
    .frame(width: pinMediaSize.width, height: pinMediaSize.height)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
  }

  private func pinVideoPreview(media: MessageMediaState, downloadProgress: Double?) -> some View {
    ZStack {
      pinMediaBackground
      if let url = media.pinVideoThumbnailDisplayURL {
        pinMediaAsyncImage(url: url, media: media, fallbackURL: media.pinVideoFallbackDisplayURL)
      } else {
        pinMediaPlaceholder(label: ChatMessageMapper.previewText(for: row.content))
      }

      if let downloadProgress {
        MessageDownloadProgressView(progress: downloadProgress, token: token)
      } else {
        Image("video_play", bundle: NECommonUIKitSwiftUIBundle.bundle)
          .resizable()
          .scaledToFit()
          .frame(width: 60, height: 60)
      }

      if let duration = media.duration, duration > 0 {
        VStack {
          Spacer()
          HStack {
            Spacer()
            Text(ChatUnitFormatter.playTime(duration))
              .font(.system(size: 10))
              .foregroundColor(.white)
              .padding(.horizontal, 4)
              .padding(.vertical, 2)
              .background(Color.black.opacity(0.6))
              .clipShape(RoundedRectangle(cornerRadius: durationBadgeCornerRadius, style: .continuous))
              .padding(.trailing, 7)
              .padding(.bottom, 7)
          }
        }
      }
    }
    .frame(width: pinMediaSize.width, height: pinMediaSize.height)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
  }

  @ViewBuilder
  private func pinMediaAsyncImage(url: URL,
                                  media: MessageMediaState,
                                  fallbackURL: URL? = nil) -> some View {
    ChatCachedAsyncImage(
      url: url,
      fallbackURL: fallbackURL ?? media.pinFallbackDisplayURL
    ) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      pinMediaPlaceholder(label: ChatMessageMapper.previewText(for: row.content))
    }
  }

  @ViewBuilder
  private func pinLocationAsyncImage(url: URL) -> some View {
    ChatCachedAsyncImage(url: url) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      pinLocationMapPlaceholder
    }
  }

  private func pinAudioPreview(_ audio: MessageAudioState) -> some View {
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
        .font(.system(size: pinTextFontSize))
        .foregroundColor(token.incomingTextColor)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
      Spacer(minLength: 0)
    }
    .padding(.leading, 16)
    .padding(.trailing, 12)
    .frame(width: audioWidth(duration: audio.duration),
           height: pinAudioHeight,
           alignment: .leading)
    .background(
      ChatPinResizableImage(
        imageName: pinAudioBackgroundImageName,
        capInsets: pinAudioBackgroundCapInsets
      )
    )
  }

  private func pinFilePreview(_ file: MessageFileState,
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

      VStack(alignment: .leading, spacing: 2) {
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
            .truncationMode(.tail)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(width: token.fileBubbleWidth,
           height: token.fileBubbleHeight,
           alignment: .leading)
    .background(token.panelItemBackground)
    .clipShape(RoundedRectangle(cornerRadius: compactCardCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: compactCardCornerRadius, style: .continuous)
        .stroke(fileBorderColor, lineWidth: 1)
    )
  }

  private func pinLocationPreview(_ location: MessageLocationState) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(location.title)
          .font(.system(size: 16))
          .foregroundColor(token.incomingTextColor)
          .lineLimit(1)
          .truncationMode(.tail)
        if let subtitle = location.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(NEUIKitSwiftUIStyle.ColorToken.lightText)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 10)

      ZStack {
        if let thumbnailURL = location.thumbnailURL {
          pinLocationAsyncImage(url: thumbnailURL)
        } else {
          pinLocationMapPlaceholder
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
    .clipShape(RoundedRectangle(cornerRadius: locationCardCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: locationCardCornerRadius, style: .continuous)
        .stroke(NEUIKitSwiftUIStyle.ColorToken.outline, lineWidth: 1)
    )
  }

  private var pinLocationMapPlaceholder: some View {
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

  private var senderText: String {
    row.senderName?.isEmpty == false ? row.senderName ?? "" : row.senderId ?? ""
  }

    private var avatarInitials: String {
        ChatAvatarDisplayResolver.initials(
            displayName: row.avatarName,
            accountId: row.senderId
        )
    }

  private var timeText: String {
    ChatUnitFormatter.messageTimeText(row.timestamp)
  }

  private var cardCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : token.bubbleCornerRadius
  }

  private var avatarCornerRadius: CGFloat {
    token.styleMode == .fun ? token.controlCornerRadius / 2 : token.avatarCornerRadius
  }

  private var mediaCornerRadius: CGFloat {
    token.bubbleCornerRadius
  }

  private var durationBadgeCornerRadius: CGFloat {
    token.controlCornerRadius / 2
  }

  private var pinTextFontSize: CGFloat {
    14
  }

  private var compactCardWidth: CGFloat {
    276
  }

  private var pinMessageContentMaxWidth: CGFloat {
    switch row.content {
    case .image, .video, .audio, .file, .location, .multiForward:
      return compactCardWidth
    default:
      return .infinity
    }
  }

  private var usesFullWidthContentHitArea: Bool {
    switch row.content {
    case .image, .video, .audio, .file, .location, .multiForward:
      return false
    default:
      return true
    }
  }

  private var compactCardCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : token.bubbleCornerRadius
  }

  private var locationCardCornerRadius: CGFloat {
    token.styleMode == .fun ? 0 : 4
  }

  private var fileBorderColor: Color {
    NEUIKitSwiftUIStyle.ColorToken.border
  }

  private var pinAudioHeight: CGFloat {
    40
  }

  private var pinAudioBackgroundImageName: String {
    token.styleMode == .fun ? "fun_pin_message_audio_bg" : "chat_message_receive"
  }

  private var pinAudioBackgroundCapInsets: EdgeInsets {
    EdgeInsets(top: 35, leading: 25, bottom: 10, trailing: 25)
  }

  private var locationCardWidth: CGFloat {
    NEChatUIKitSwiftUIConstants.locationCardSize.width
  }

  private var locationCardHeight: CGFloat {
    NEChatUIKitSwiftUIConstants.locationCardSize.height
  }

  private var locationMapHeight: CGFloat {
    NEChatUIKitSwiftUIConstants.locationThumbnailHeight
  }

  private func audioWidth(duration: TimeInterval) -> CGFloat {
    let base: CGFloat = 96
    let durationSeconds = ChatUnitFormatter.audioDurationSeconds(duration)
    guard durationSeconds > 2 else {
      return base
    }
    return min(CGFloat(durationSeconds) * 8 + base, token.audioMaxWidth)
  }

  private var pinMediaSize: CGSize {
    guard case let .image(media) = row.content else {
      if case let .video(media) = row.content {
        return pinMediaSize(for: media)
      }
      return CGSize(width: token.mediaThumbnailWidth, height: token.mediaThumbnailMaxHeight)
    }
    return pinMediaSize(for: media)
  }

  private var pinMediaBackground: some View {
    token.dividerColor.opacity(0.6)
  }

  private func pinMediaPlaceholder(label: String) -> some View {
    Image(NEChatCommonPresentation.mediaPlaceholderImageName(token: token),
          bundle: NECommonUIKitSwiftUIBundle.bundle)
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: 84, height: 84)
      .accessibilityLabel(label)
  }

  private func pinMediaSize(for media: MessageMediaState) -> CGSize {
    NEChatUtilityMessageMediaSizer.size(for: media, token: token)
  }

}

enum NEChatUtilityMessageMediaSizer {
  static func size(for media: MessageMediaState, token: ChatThemeToken) -> CGSize {
    let maxSize = CGSize(width: token.mediaThumbnailWidth, height: token.mediaThumbnailMaxHeight)
    guard let width = media.width,
          let height = media.height,
          width > 0,
          height > 0 else {
      return maxSize
    }

    let rawSize = CGSize(width: CGFloat(width), height: CGFloat(height))
    var realSize: CGSize
    if rawSize.width > rawSize.height {
      let width = min(maxSize.width, rawSize.width)
      realSize = CGSize(width: width, height: width * rawSize.height / rawSize.width)
    } else {
      let height = min(maxSize.height, rawSize.height)
      realSize = CGSize(width: height * rawSize.width / rawSize.height, height: height)
    }
    if min(realSize.width, realSize.height) < token.mediaThumbnailMinHeight {
      if realSize.width < realSize.height {
        realSize.width = token.mediaThumbnailMinHeight
      } else {
        realSize.height = token.mediaThumbnailMinHeight
      }
    }
    return realSize
  }
}

enum NEChatUtilityMessageOperationRules {
  static func copyableText(_ content: MessageContentState) -> String? {
    let text: String
    switch content {
    case let .text(value), let .aiStream(value, _, _):
      text = value
    case let .richText(title, body):
      text = body.isEmpty ? title ?? "" : body
    case let .reply(_, boxed):
      return copyableText(boxed.value)
    default:
      return nil
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }

  static func isTextMessage(_ content: MessageContentState) -> Bool {
    copyableText(content) != nil
  }

  static func isAudioMessage(_ content: MessageContentState) -> Bool {
    switch content {
    case .audio:
      return true
    case let .reply(_, boxed):
      return isAudioMessage(boxed.value)
    default:
      return false
    }
  }
}

private struct ChatPinResizableImage: View {
  var imageName: String
  var capInsets: EdgeInsets

  var body: some View {
    Image(imageName, bundle: NEChatUIKitSwiftUIBundle.bundle)
      .renderingMode(.original)
      .resizable(capInsets: capInsets, resizingMode: .stretch)
  }
}

private extension MessageMediaState {
  var pinThumbnailDisplayURL: URL? {
    if let localPath, !localPath.isEmpty {
      return URL(fileURLWithPath: localPath)
    }
    return thumbnailURL ?? url
  }

  var pinFallbackDisplayURL: URL? {
    if let localPath, !localPath.isEmpty {
      return URL(fileURLWithPath: localPath)
    }
    return url ?? thumbnailURL
  }

  var pinVideoThumbnailDisplayURL: URL? {
    thumbnailURL ?? url
  }

  var pinVideoFallbackDisplayURL: URL? {
    url ?? thumbnailURL
  }
}
