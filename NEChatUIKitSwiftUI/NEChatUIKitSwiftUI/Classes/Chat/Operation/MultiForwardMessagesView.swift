// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NEChatKit
import NECommonUIKitSwiftUI
import SwiftUI

public struct MultiForwardMessagesView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  @StateObject private var viewModel: MultiForwardMessagesViewModel
  @State private var childRoute: MultiForwardChildRoute?
  @State private var mediaPreview: ChatMediaPreviewState?
  @State private var suppressedBodyTapRowId: String?
  @State private var bodyTapSuppressionGeneration = 0
  private let token: ChatThemeToken
  private let onSelect: (MessageRowState) -> Void
  private let onOpenURL: (URL, String, ChatURLInteractionSource, MessageRowState) -> Void
  private let browserDestination: ((URL, String) -> AnyView)?
  private let onSaveMedia: ((ChatMediaItem) async throws -> Void)?
  private let onInitialLoadFailure: ((NEChatKitErrorState) -> Void)?
  private let playingAudioMessageId: String?
  @State private var didReportInitialLoadFailure = false

  @MainActor
  public init(viewModel: MultiForwardMessagesViewModel,
              token: ChatThemeToken = .normal,
              onSelect: @escaping (MessageRowState) -> Void = { _ in },
              onOpenURL: @escaping (URL, String, ChatURLInteractionSource, MessageRowState) -> Void = { _, _, _, _ in },
              browserDestination: ((URL, String) -> AnyView)? = nil,
              onSaveMedia: ((ChatMediaItem) async throws -> Void)? = nil,
              onInitialLoadFailure: ((NEChatKitErrorState) -> Void)? = nil,
              playingAudioMessageId: String? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel)
    self.token = token
    self.onSelect = onSelect
    self.onOpenURL = onOpenURL
    self.browserDestination = browserDestination
    self.onSaveMedia = onSaveMedia
    self.onInitialLoadFailure = onInitialLoadFailure
    self.playingAudioMessageId = playingAudioMessageId
  }

  public var body: some View {
    ZStack {
      VStack(spacing: 0) {
        NEChatCommonPresentation.navigationBar(
          title: NEChatUIKitSwiftUIBundle.localized("chat_history", value: "Chat History"),
          token: token,
          backAction: {
            if let chatRouteBackAction {
              chatRouteBackAction()
            } else {
              dismiss()
            }
          }
        )

        content
      }
      .background(token.pageBackground.ignoresSafeArea())

      if let childRoute {
        childRouteDestination(childRoute)
          .environment(\.neChatChildRouteBackAction, childRouteBackAction(for: childRoute))
          .zIndex(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .neCommonTransientOverlay(
      viewModel.toast,
      placement: .top,
      topPadding: 12,
      onDismiss: { viewModel.consumeToast($0) }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
    .onAppear {
      viewModel.load()
    }
    .onChange(of: viewModel.phase) { phase in
      guard case let .failed(error) = phase,
            !didReportInitialLoadFailure,
            let onInitialLoadFailure else {
        return
      }
      didReportInitialLoadFailure = true
      onInitialLoadFailure(error)
    }
    .fullScreenCover(item: $mediaPreview) { preview in
      ChatMediaPreviewView(
        preview: preview,
        token: token,
        onSaveImage: onSaveMedia
      )
    }
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private func childRouteBackAction(for route: MultiForwardChildRoute) -> () -> Void {
    {
      guard childRoute?.id == route.id else {
        return
      }
      childRoute = nil
    }
  }

  @ViewBuilder
  private func childRouteDestination(_ childRoute: MultiForwardChildRoute) -> some View {
    switch childRoute.destination {
    case let .multiForward(preview):
      MultiForwardMessagesView(
        viewModel: MultiForwardMessagesViewModel(
          preview: preview,
          networkOperationGuard: viewModel.networkOperationGuard
        ),
        token: token,
        onSelect: onSelect,
        onOpenURL: onOpenURL,
        browserDestination: browserDestination,
        onSaveMedia: onSaveMedia,
        onInitialLoadFailure: { error in
          guard self.childRoute?.id == childRoute.id else {
            return
          }
          self.childRoute = nil
          viewModel.showLoadFailureToast(error)
        },
        playingAudioMessageId: playingAudioMessageId
      )
      .id(childRoute.id)
    case let .file(preview):
      ChatFilePreviewView(preview: preview, token: token)
        .id(childRoute.id)
    case let .browser(route):
      if let browserDestination {
        browserDestination(route.url, route.title)
          .id(childRoute.id)
      } else {
        EmptyView()
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .idle, .loading:
      NEChatCommonPresentation.loadingView(token: token)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      NEChatCommonPresentation.emptyView(token: token)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      NEChatCommonPresentation.errorView(error, token: token) {
        viewModel.load()
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    default:
      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(viewModel.rows) { row in
            if let timeDividerText = row.timeDividerText, !timeDividerText.isEmpty {
              timeDivider(timeDividerText)
            }
            let displayRow = row.multiForwardApplyingAudioPlayback(messageId: playingAudioMessageId)
            MessageBubbleView(
              row: displayRow,
              token: token,
              onOpenURL: handleOpenURL,
              onBodyTap: { selectedRow in
                if consumeBodyTapSuppression(for: selectedRow.id) {
                  return
                }
                if viewModel.mediaDownloadProgressByRowId[row.id] != nil {
                  return
                }
                if viewModel.shouldDownloadVideoBeforePreview(row: row) {
                  viewModel.downloadVideo(row: row)
                  return
                }
                if viewModel.shouldDownloadFileBeforePreview(row: row) {
                  viewModel.downloadFile(row: row)
                  return
                }
                openSelectedRow(viewModel.currentRow(matching: selectedRow))
              },
              showsAIResponseActions: false
            )
          }
        }
        .padding(.vertical, 10)
      }
    }
  }

  private func timeDivider(_ text: String) -> some View {
    Text(text)
      .font(.system(size: token.timeDividerFontSize))
      .foregroundColor(token.secondaryTextColor)
      .padding(.horizontal, 10)
      .frame(height: token.timeCellHeight)
      .background { Capsule().fill(token.dividerColor.opacity(0.35)) }
      .frame(maxWidth: .infinity)
      .accessibilityLabel(text)
  }

  private func openSelectedRow(_ row: MessageRowState) {
    if case let .multiForward(multiForward) = row.content {
      childRoute = MultiForwardChildRoute(
        destination: .multiForward(
          ChatMultiForwardPreviewState(messageId: row.id, multiForward: multiForward)
        )
      )
      return
    }
    if case let .image(media) = row.content {
      openMediaPreview(row: row, media: media, kind: .image)
      return
    }
    if case let .video(media) = row.content {
      guard media.existingLocalPath != nil else {
        return
      }
      openMediaPreview(row: row, media: media, kind: .video)
      return
    }
    if case let .file(file) = row.content {
      guard file.existingLocalPath != nil else {
        return
      }
      if let media = file.imageMediaState {
        openMediaPreview(row: row, media: media, kind: .image)
        return
      }
      if let media = file.videoMediaState {
        openMediaPreview(row: row, media: media, kind: .video)
        return
      }
      childRoute = MultiForwardChildRoute(
        destination: .file(ChatFilePreviewState(id: row.id, file: file))
      )
      return
    }
    onSelect(row)
  }

  private func handleOpenURL(_ url: URL,
                             displayText: String,
                             source: ChatURLInteractionSource,
                             row: MessageRowState) {
    suppressBodyTap(for: row.id)
    if let scheme = url.scheme?.lowercased(),
       ["http", "https"].contains(scheme),
       browserDestination != nil {
      childRoute = MultiForwardChildRoute(
        destination: .browser(MultiForwardBrowserRoute(
          title: displayText.isEmpty ? url.absoluteString : displayText,
          url: url
        ))
      )
      return
    }
    onOpenURL(url, displayText, source, row)
  }

  private func suppressBodyTap(for rowId: String) {
    bodyTapSuppressionGeneration += 1
    let generation = bodyTapSuppressionGeneration
    suppressedBodyTapRowId = rowId
    DispatchQueue.main.async {
      guard bodyTapSuppressionGeneration == generation,
            suppressedBodyTapRowId == rowId else {
        return
      }
      suppressedBodyTapRowId = nil
    }
  }

  private func consumeBodyTapSuppression(for rowId: String) -> Bool {
    guard suppressedBodyTapRowId == rowId else {
      return false
    }
    bodyTapSuppressionGeneration += 1
    suppressedBodyTapRowId = nil
    return true
  }

  private func openMediaPreview(row: MessageRowState,
                                media: MessageMediaState,
                                kind: ChatMediaPreviewKind) {
    mediaPreview = ChatMediaPreviewState(
      id: row.id,
      kind: kind,
      media: media,
      title: ChatMessageMapper.previewText(for: row.content),
      mediaItems: mediaItems()
    )
  }

  private func mediaItems() -> [ChatMediaItem] {
    viewModel.rows.compactMap { row in
      switch row.content {
      case let .image(media):
        return ChatMediaItem(
          id: row.id,
          media: media,
          kind: .image,
          title: ChatMessageMapper.previewText(for: row.content)
        )
      case let .video(media):
        return ChatMediaItem(
          id: row.id,
          media: media,
          kind: .video,
          title: ChatMessageMapper.previewText(for: row.content)
        )
      case let .file(file):
        guard file.existingLocalPath != nil else {
          return nil
        }
        let kind: ChatMediaPreviewKind
        let media: MessageMediaState
        if let imageMedia = file.imageMediaState {
          kind = .image
          media = imageMedia
        } else if let videoMedia = file.videoMediaState {
          kind = .video
          media = videoMedia
        } else {
          return nil
        }
        return ChatMediaItem(
          id: row.id,
          media: media,
          kind: kind,
          title: ChatMessageMapper.previewText(for: row.content)
        )
      default:
        return nil
      }
    }
  }
}

private struct MultiForwardBrowserRoute {
  var title: String
  var url: URL
}

private struct MultiForwardChildRoute: Identifiable {
  enum Destination {
    case multiForward(ChatMultiForwardPreviewState)
    case file(ChatFilePreviewState)
    case browser(MultiForwardBrowserRoute)
  }

  let id = UUID()
  var destination: Destination
}

private extension MessageRowState {
  func multiForwardApplyingAudioPlayback(messageId: String?) -> MessageRowState {
    var next = self
    next.content = next.content.multiForwardApplyingAudioPlayback(isPlaying: id == messageId)
    return next
  }
}

private extension MessageContentState {
  func multiForwardApplyingAudioPlayback(isPlaying: Bool) -> MessageContentState {
    switch self {
    case var .audio(audio):
      audio.isPlaying = isPlaying
      return .audio(audio)
    case let .reply(preview, boxed):
      return .reply(preview: preview, content: BoxedMessageContentState(boxed.value.multiForwardApplyingAudioPlayback(isPlaying: isPlaying)))
    default:
      return self
    }
  }
}
