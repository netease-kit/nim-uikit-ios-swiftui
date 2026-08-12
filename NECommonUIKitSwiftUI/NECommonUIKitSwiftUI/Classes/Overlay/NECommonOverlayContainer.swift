// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public enum NECommonToastPlacement: Equatable {
  case top
  case center
  case bottom

  var alignment: Alignment {
    switch self {
    case .top:
      return .top
    case .center:
      return .center
    case .bottom:
      return .bottom
    }
  }

  var transition: AnyTransition {
    switch self {
    case .top:
      return .move(edge: .top).combined(with: .opacity)
    case .center:
      return .opacity
    case .bottom:
      return .move(edge: .bottom).combined(with: .opacity)
    }
  }
}

public struct NECommonOverlayContainer<Content: View>: View {
  private let toast: NECommonToastState?
  private let toastPlacement: NECommonToastPlacement
  private let topPadding: CGFloat
  private let bottomPadding: CGFloat
  private let content: Content

  public init(toast: NECommonToastState?,
              toastPlacement: NECommonToastPlacement = .bottom,
              topPadding: CGFloat = 12,
              bottomPadding: CGFloat = 36,
              @ViewBuilder content: () -> Content) {
    self.toast = toast
    self.toastPlacement = toastPlacement
    self.topPadding = topPadding
    self.bottomPadding = bottomPadding
    self.content = content()
  }

  public var body: some View {
    ZStack(alignment: toastPlacement.alignment) {
      content

      if let toast {
        NECommonToastOverlay(toast: toast)
          .padding(.top, toastPlacement == .top ? topPadding : 0)
          .padding(.bottom, toastPlacement == .bottom ? bottomPadding : 0)
          .transition(toastPlacement.transition)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: toast?.id)
  }
}
