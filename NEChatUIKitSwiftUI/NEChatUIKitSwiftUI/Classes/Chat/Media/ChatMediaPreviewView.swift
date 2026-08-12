// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import AVKit
import Combine
import NECommonUIKitSwiftUI
import SwiftUI

public struct ChatMediaPreviewView: View {
  public var preview: ChatMediaPreviewState
  public var token: ChatThemeToken
  public var onSaveImage: ((ChatMediaItem) async throws -> Void)?
  public var onClose: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var currentIndex: Int
  @State private var isSavingImage = false
  @State private var toast: ChatToastState?

  public init(preview: ChatMediaPreviewState,
              token: ChatThemeToken = .normal,
              onSaveImage: ((ChatMediaItem) async throws -> Void)? = nil,
              onClose: (() -> Void)? = nil) {
    self.preview = preview
    self.token = token
    self.onSaveImage = onSaveImage
    self.onClose = onClose
    let items = Self.mediaItems(for: preview)
    _currentIndex = State(initialValue: items.firstIndex(where: { $0.id == preview.id }) ?? 0)
  }

  private var items: [ChatMediaItem] {
    Self.mediaItems(for: preview)
  }

  private static func mediaItems(for preview: ChatMediaPreviewState) -> [ChatMediaItem] {
    let fallbackItem = ChatMediaItem(id: preview.id,
                                     media: preview.media,
                                     kind: preview.kind,
                                     title: preview.title)
    // UIKit opens videos in a standalone player. Only image previews page
    // through same-kind media.
    guard preview.kind == .image else {
      return [fallbackItem]
    }
    guard !preview.mediaItems.isEmpty else {
      return [fallbackItem]
    }
    let sameKindItems = preview.mediaItems.filter { $0.kind == preview.kind }
    guard !sameKindItems.contains(where: { $0.id == preview.id }) else {
      return sameKindItems
    }
    if preview.media.displayURL != nil {
      return [fallbackItem] + sameKindItems
    }
    return sameKindItems
  }

  public var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      TabView(selection: $currentIndex) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          mediaPage(for: item)
            .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .ignoresSafeArea()

    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      HStack {
        NEChatCommonPresentation.commonIconButton(
          imageName: "close_btn",
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("close", value: "Close"),
          token: token,
          renderingMode: .original,
          size: CGSize(width: 28, height: 28),
          font: .system(size: 16, weight: .semibold),
          foregroundColor: .white
        ) {
          closePreview()
        }

        Spacer()

        if currentItem != nil, onSaveImage != nil {
          saveButton
        }
      }
      .frame(height: 44)
      .padding(.horizontal, 20)
      .padding(.bottom, 27)
      .background(Color.clear)
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .neCommonTransientOverlay(
      toast,
      placement: .center,
      duration: 3,
      onDismiss: { dismissed in
        if dismissed == toast {
          toast = nil
        }
      }
    ) { toast in
      ChatToastView(toast: toast, token: token)
    }
  }

  private var saveButton: some View {
    Group {
      if isSavingImage {
        NEChatCommonPresentation.inlineLoadingView(token: token)
          .frame(width: 28, height: 28)
      } else {
        NEChatCommonPresentation.commonIconButton(
          imageName: "save_btn",
          accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("save", value: "Save"),
          token: token,
          renderingMode: .original,
          size: CGSize(width: 28, height: 28),
          font: .system(size: 16, weight: .semibold),
          foregroundColor: .white
        ) {
          saveCurrentImage()
        }
      }
    }
  }

  private var currentItem: ChatMediaItem? {
    guard currentIndex >= 0, currentIndex < items.count else {
      return nil
    }
    return items[currentIndex]
  }

  @ViewBuilder
  private func mediaPage(for item: ChatMediaItem) -> some View {
    switch item.kind {
    case .image:
      imagePage(for: item)
    case .video:
      videoPage(for: item)
    }
  }

  private func imagePage(for item: ChatMediaItem) -> some View {
    Group {
      if let displayURL = item.media.displayURL {
        ChatCachedAsyncImage(
          url: displayURL,
          fallbackURL: item.media.thumbnailURL,
          contentMode: .fit
        ) { image in
          image
            .resizable()
            .scaledToFit()
        } placeholder: {
            NEChatCommonPresentation.inlineLoadingView(token: token)
              .foregroundColor(.white)
        }
        .mediaZoomable { direction in
          switch direction {
          case .previous:
            return selectAdjacentImage(offset: -1)
          case .next:
            return selectAdjacentImage(offset: 1)
          }
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
          closePreview()
        })
      } else {
        unavailableImage(message: NEChatUIKitSwiftUIBundle.localized("chat_image_unavailable", value: "Image unavailable"))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func closePreview() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  private func videoPage(for item: ChatMediaItem) -> some View {
    Group {
      if let url = item.media.playableURL {
        ChatVideoPlayerPage(url: url, token: token)
      } else {
        unavailableMedia(
          imageName: "chat_video",
          message: NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func unavailableImage(message: String) -> some View {
    VStack(spacing: 12) {
      Image(NEChatCommonPresentation.mediaPlaceholderImageName(token: token),
            bundle: NECommonUIKitSwiftUIBundle.bundle)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: 84, height: 84)
        .accessibilityLabel(message)
      Text(message)
        .font(.system(size: 14))
        .foregroundColor(.white.opacity(0.6))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func unavailableMedia(imageName: String, message: String) -> some View {
    VStack(spacing: 12) {
      NEChatCommonPresentation.iconView(
        imageName: imageName,
        token: token,
        renderingMode: .original,
        size: CGSize(width: 48, height: 48),
        font: .system(size: 44),
        foregroundColor: .white.opacity(0.6),
        accessibilityLabel: message
      )
      Text(message)
        .font(.system(size: 14))
        .foregroundColor(.white.opacity(0.6))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func saveCurrentImage() {
    guard let item = currentItem else {
      return
    }
    let hasMediaURL = item.kind == .image
      ? item.media.displayURL != nil
      : item.media.playableURL != nil
    guard hasMediaURL else {
      showToast(
        message: item.kind == .image
          ? NEChatUIKitSwiftUIBundle.localized("chat_image_unavailable", value: "Image unavailable")
          : NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable"),
        style: .error
      )
      return
    }
    guard let onSaveImage else {
      return
    }

    isSavingImage = true
    Task {
      do {
        try await onSaveImage(item)
        await MainActor.run {
          isSavingImage = false
          showToast(
            message: NEChatUIKitSwiftUIBundle.localized("chat_image_saved", value: "Saved to album"),
            style: .success
          )
        }
      } catch {
        await MainActor.run {
          isSavingImage = false
          showToast(
            message: saveFailureMessage(for: error, item: item),
            style: .error
          )
        }
      }
    }
  }

  private func selectAdjacentImage(offset: Int) -> Bool {
    let nextIndex = currentIndex + offset
    guard items.indices.contains(nextIndex) else {
      return false
    }
    withAnimation(.easeOut(duration: 0.2)) {
      currentIndex = nextIndex
    }
    return true
  }

  private func saveFailureMessage(for error: Error, item: ChatMediaItem) -> String {
    if let userVisibleError = error as? ChatUserVisibleError {
      return userVisibleError.userVisibleMessage
    }
    return item.kind == .image
      ? NEChatUIKitSwiftUIBundle.localized("saveImageError", value: "Failed to save image")
      : NEChatUIKitSwiftUIBundle.localized("saveVideoError", value: "Failed to save video")
  }

  private func showToast(message: String, style: ChatToastState.Style) {
    toast = ChatToastState(message: message, style: style)
  }
}

private extension MessageMediaState {
  var displayURL: URL? {
    imageDownloadURL
  }

  var playableURL: URL? {
    if let localPath = existingLocalPath {
      return URL(fileURLWithPath: localPath)
    }
    return url
  }
}

private struct ChatVideoPlayerPage: View {
  var url: URL
  var token: ChatThemeToken

  @State private var player: AVPlayer?
  @State private var statusTask: Task<Void, Never>?
  @State private var timeControlTask: Task<Void, Never>?
  @State private var loadingFallbackTask: Task<Void, Never>?
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isVisible = false
  @State private var isCallKitInterruptionActive = false
  @State private var isAudioSessionInterruptionActive = false
  @State private var shouldResumeAfterInterruption = false

  var body: some View {
    ZStack {
      if let player {
        VideoPlayer(player: player)
          .ignoresSafeArea()
      }

      if isLoading {
        NEChatCommonPresentation.inlineLoadingView(token: token)
          .foregroundColor(.white)
      }

      if let errorMessage {
        VStack(spacing: 12) {
          NEChatCommonPresentation.iconView(
            imageName: "chat_video",
            token: token,
            renderingMode: .original,
            size: CGSize(width: 48, height: 48),
            font: .system(size: 44),
            foregroundColor: .white.opacity(0.6),
            accessibilityLabel: errorMessage
          )
          Text(errorMessage)
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.6))
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .onAppear {
      isVisible = true
      startPlayback()
    }
    .onDisappear {
      isVisible = false
      stopPlayback()
    }
    .onReceive(NotificationCenter.default.publisher(for: .neChatMediaPlaybackShouldStop)) { _ in
      stopPlayback()
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kCallKitShowNoti"))) { _ in
      beginInterruption(source: .callKit)
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kCallKitDismissNoti"))) { _ in
      endCallKitInterruption()
    }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
      handleAudioSessionInterruption(notification)
    }
  }

  private func startPlayback() {
    guard playableURLExists else {
      isLoading = false
      errorMessage = videoUnavailableText
      return
    }

    guard player == nil else {
      isLoading = false
      errorMessage = nil
      if !isPlaybackInterrupted {
        player?.play()
      }
      return
    }

    isLoading = true
    errorMessage = nil
    configureAudioSession()
    let item = AVPlayerItem(url: url)
    let nextPlayer = AVPlayer(playerItem: item)
    player = nextPlayer

    statusTask = Task { @MainActor in
      for await status in item.publisher(for: \.status, options: [.initial, .new]).values {
        handlePlayerItemStatus(status, item: item, player: nextPlayer)
      }
    }
    timeControlTask = Task { @MainActor in
      for await status in nextPlayer.publisher(for: \.timeControlStatus, options: [.initial, .new]).values {
        if status == .playing || isPlaybackLikelyStarted(nextPlayer) {
          isLoading = false
          errorMessage = nil
        }
      }
    }
    loadingFallbackTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else {
        return
      }
      if isPlaybackLikelyStarted(nextPlayer) {
        isLoading = false
        errorMessage = nil
        return
      }
      try? await Task.sleep(nanoseconds: 1_650_000_000)
      guard !Task.isCancelled else {
        return
      }
      handlePlayerItemStatus(item.status, item: item, player: nextPlayer)
      if url.isFileURL, item.status == .unknown, isLoading {
        isLoading = false
        errorMessage = videoUnavailableText
      }
    }

    if !isPlaybackInterrupted {
      nextPlayer.play()
    }
    if url.isFileURL {
      isLoading = false
    }
  }

  private func handlePlayerItemStatus(_ status: AVPlayerItem.Status,
                                      item: AVPlayerItem,
                                      player: AVPlayer) {
    switch status {
    case .readyToPlay:
      isLoading = false
      errorMessage = nil
      if !isPlaybackInterrupted {
        player.play()
      }
    case .failed:
      isLoading = false
      if let error = item.error {
        NEChatSwiftUILogger.log("video playback failed: \(error.localizedDescription)")
      }
      errorMessage = videoUnavailableText
    case .unknown:
      break
    @unknown default:
      break
    }
  }

  private func isPlaybackLikelyStarted(_ player: AVPlayer) -> Bool {
    player.timeControlStatus == .playing ||
      player.rate > 0 ||
      player.currentTime().seconds > 0
  }

  private func stopPlayback() {
    statusTask?.cancel()
    statusTask = nil
    timeControlTask?.cancel()
    timeControlTask = nil
    loadingFallbackTask?.cancel()
    loadingFallbackTask = nil
    player?.pause()
    player = nil
    isCallKitInterruptionActive = false
    isAudioSessionInterruptionActive = false
    shouldResumeAfterInterruption = false
  }

  private enum PlaybackInterruptionSource {
    case callKit
    case audioSession
  }

  private var isPlaybackInterrupted: Bool {
    isCallKitInterruptionActive || isAudioSessionInterruptionActive
  }

  private func beginInterruption(source: PlaybackInterruptionSource) {
    let wasAlreadyInterrupted = isPlaybackInterrupted
    switch source {
    case .callKit:
      isCallKitInterruptionActive = true
    case .audioSession:
      isAudioSessionInterruptionActive = true
    }
    if !wasAlreadyInterrupted, let player {
      shouldResumeAfterInterruption = player.rate > 0 || player.timeControlStatus == .playing
    }
    player?.pause()
  }

  private func endCallKitInterruption() {
    isCallKitInterruptionActive = false
    resumePlaybackAfterInterruptionIfNeeded()
  }

  private func handleAudioSessionInterruption(_ notification: Notification) {
    guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
      return
    }
    switch type {
    case .began:
      beginInterruption(source: .audioSession)
    case .ended:
      isAudioSessionInterruptionActive = false
      let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      if !options.contains(.shouldResume) {
        shouldResumeAfterInterruption = false
      }
      resumePlaybackAfterInterruptionIfNeeded()
    @unknown default:
      break
    }
  }

  private func resumePlaybackAfterInterruptionIfNeeded() {
    guard !isPlaybackInterrupted,
          isVisible,
          shouldResumeAfterInterruption,
          let player else {
      return
    }
    shouldResumeAfterInterruption = false
    configureAudioSession()
    player.play()
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      NEChatSwiftUILogger.log("video audio session configuration failed: \(error.localizedDescription)")
    }
  }

  private var playableURLExists: Bool {
    guard url.isFileURL else {
      return true
    }
    guard FileManager.default.fileExists(atPath: url.path),
          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
      return false
    }
    return true
  }

  private var videoUnavailableText: String {
    NEChatUIKitSwiftUIBundle.localized("chat_video_unavailable", value: "Video unavailable")
  }
}

public extension Notification.Name {
  static let neChatMediaPlaybackShouldStop = Notification.Name("NEChatMediaPlaybackShouldStop")
}
