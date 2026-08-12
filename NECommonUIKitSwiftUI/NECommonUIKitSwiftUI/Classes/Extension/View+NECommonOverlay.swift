// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public extension View {
  func neCommonToastOverlay(_ toast: NECommonToastState?,
                            placement: NECommonToastPlacement = .bottom,
                            topPadding: CGFloat = 12,
                            bottomPadding: CGFloat = 36,
                            onDismiss: ((NECommonToastState) -> Void)? = nil) -> some View {
    modifier(
      NECommonToastOverlayModifier(
        toast: toast,
        placement: placement,
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        onDismiss: onDismiss
      )
    )
  }

  func neCommonTransientOverlay<Item: Identifiable, Overlay: View>(
    _ item: Item?,
    placement: NECommonToastPlacement = .bottom,
    topPadding: CGFloat = 12,
    bottomPadding: CGFloat = 36,
    duration: TimeInterval = 2,
    onDismiss: ((Item) -> Void)? = nil,
    @ViewBuilder overlay: @escaping (Item) -> Overlay
  ) -> some View {
    modifier(
      NECommonTransientOverlayModifier(
        item: item,
        placement: placement,
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        duration: duration,
        onDismiss: onDismiss,
        overlay: overlay
      )
    )
  }

  func neCommonBlockingLoadingOverlay(_ state: NECommonBlockingLoadingState?) -> some View {
    modifier(NECommonBlockingLoadingOverlayModifier(state: state))
  }

  func neCommonBlockingLoadingOverlay(isPresented: Bool,
                                      id: String = "commonBlockingLoading",
                                      textKey: String? = "common_loading",
                                      fallbackText: String? = "Loading",
                                      showsScrim: Bool = true,
                                      blocksInteraction: Bool = true) -> some View {
    neCommonBlockingLoadingOverlay(
      isPresented
        ? NECommonBlockingLoadingState(
          id: id,
          textKey: textKey,
          fallbackText: fallbackText,
          showsScrim: showsScrim,
          blocksInteraction: blocksInteraction
        )
        : nil
    )
  }
}

private struct NECommonTransientOverlayModifier<Item: Identifiable, Overlay: View>: ViewModifier {
  var item: Item?
  var placement: NECommonToastPlacement
  var topPadding: CGFloat
  var bottomPadding: CGFloat
  var duration: TimeInterval
  var onDismiss: ((Item) -> Void)?
  var overlay: (Item) -> Overlay

  func body(content: Content) -> some View {
    ZStack(alignment: placement.alignment) {
      content

      if let item {
        overlay(item)
          .padding(.top, placement == .top ? topPadding : 0)
          .padding(.bottom, placement == .bottom ? bottomPadding : 0)
          .transition(placement.transition)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: item?.id)
    .task(id: item?.id) {
      guard let item, let onDismiss else {
        return
      }
      let duration = max(0, duration)
      if duration > 0 {
        let nanoseconds = UInt64(duration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
      }
      guard !Task.isCancelled else {
        return
      }
      await MainActor.run {
        onDismiss(item)
      }
    }
  }
}

private struct NECommonToastOverlayModifier: ViewModifier {
  var toast: NECommonToastState?
  var placement: NECommonToastPlacement
  var topPadding: CGFloat
  var bottomPadding: CGFloat
  var onDismiss: ((NECommonToastState) -> Void)?

  func body(content: Content) -> some View {
    NECommonOverlayContainer(
      toast: toast,
      toastPlacement: placement,
      topPadding: topPadding,
      bottomPadding: bottomPadding
    ) {
      content
    }
    .task(id: toast?.id) {
      guard let toast, let onDismiss else {
        return
      }
      let duration = max(0, toast.duration)
      if duration > 0 {
        let nanoseconds = UInt64(duration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
      }
      guard !Task.isCancelled else {
        return
      }
      await MainActor.run {
        onDismiss(toast)
      }
    }
  }
}

private struct NECommonBlockingLoadingOverlayModifier: ViewModifier {
  var state: NECommonBlockingLoadingState?

  func body(content: Content) -> some View {
    content
      .overlay {
        if let state {
          NECommonBlockingLoadingOverlay(state: state)
            .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: state?.id)
  }
}
