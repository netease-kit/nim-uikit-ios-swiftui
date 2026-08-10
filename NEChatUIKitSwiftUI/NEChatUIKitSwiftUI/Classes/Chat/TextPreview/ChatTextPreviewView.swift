// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct ChatTextPreviewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  @State private var browserRoute: ChatTextPreviewBrowserRoute?
  public var preview: ChatTextPreviewState
  public var token: ChatThemeToken
  public var browserDestination: ((URL, String) -> AnyView)?
  public var onOpenURL: (URL, String, ChatTextPreviewState) -> Void

  public init(preview: ChatTextPreviewState,
              token: ChatThemeToken,
              browserDestination: ((URL, String) -> AnyView)? = nil,
              onOpenURL: @escaping (URL, String, ChatTextPreviewState) -> Void = { _, _, _ in }) {
    self.preview = preview
    self.token = token
    self.browserDestination = browserDestination
    self.onOpenURL = onOpenURL
  }

  public var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          dismissSpacer

          previewContent
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

          dismissSpacer
        }
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
      .background(
        token.pageBackground
          .contentShape(Rectangle())
      )
    }
    .background(token.pageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(isPresented: browserRouteIsPresentedBinding) {
      if let browserRoute,
         let browserDestination {
        browserDestination(browserRoute.url, browserRoute.title)
      } else {
        EmptyView()
      }
    }
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var dismissSpacer: some View {
    Color.clear
      .frame(maxWidth: .infinity, minHeight: 20)
      .contentShape(Rectangle())
      .onTapGesture {
        if let chatRouteBackAction {
          chatRouteBackAction()
        } else {
          dismiss()
        }
      }
  }

  private var previewContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title = preview.title?.trimmingCharacters(in: .whitespacesAndNewlines),
         !title.isEmpty {
        MessageEmoticonTextView(text: title, token: token, baseColor: token.incomingTextColor)
          .font(.system(size: 24, weight: .semibold))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      previewBody(preview.body.isEmpty ? " " : preview.body)
        .font(.system(size: 24))
        .foregroundColor(token.incomingTextColor)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func previewBody(_ text: String) -> some View {
    switch ChatMessageTextRenderClassifier.kind(for: text) {
    case .link:
      ChatLinkTextView(text: text, token: token) { url, displayText in
        handleLinkTap(url, displayText: displayText)
      }
    case .emoticon:
      MessageEmoticonTextView(text: text, token: token)
    case .markdown:
      MarkdownMessageRenderer(text: text, token: token) { url, displayText in
        handleLinkTap(url, displayText: displayText)
      }
    case .plain:
      Text(text)
    }
  }

  private func handleLinkTap(_ url: URL, displayText: String) {
    if let scheme = url.scheme?.lowercased(),
       ["http", "https"].contains(scheme),
       browserDestination != nil {
      browserRoute = ChatTextPreviewBrowserRoute(
        title: displayText.isEmpty ? url.absoluteString : displayText,
        url: url
      )
      return
    }
    onOpenURL(url, displayText, preview)
  }

  private var browserRouteIsPresentedBinding: Binding<Bool> {
    Binding(
      get: { browserRoute != nil },
      set: { isPresented in
        if !isPresented {
          browserRoute = nil
        }
      }
    )
  }
}

private struct ChatTextPreviewBrowserRoute: Identifiable {
  let id = UUID()
  var title: String
  var url: URL
}
