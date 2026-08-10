// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct ChatFilePreviewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  public var preview: ChatFilePreviewState
  public var token: ChatThemeToken

  public init(preview: ChatFilePreviewState,
              token: ChatThemeToken = .normal) {
    self.preview = preview
    self.token = token
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: preview.file.name,
        token: token,
        backAction: {
          if let chatRouteBackAction {
            chatRouteBackAction()
          } else {
            dismiss()
          }
        }
      )

      VStack(spacing: 14) {
        NEChatCommonPresentation.iconView(
          imageName: ChatFileIconResource.imageName(for: preview.file),
          token: token,
          size: CGSize(width: 52, height: 52),
          foregroundColor: token.accentColor,
          accessibilityLabel: preview.file.name
        )

        Text(preview.file.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(token.incomingTextColor)
          .multilineTextAlignment(.center)

        if let sizeText = preview.file.sizeText {
          Text(sizeText)
            .font(.system(size: 14))
            .foregroundColor(token.secondaryTextColor)
        }

        Text(fileLocationText)
          .font(.system(size: 12))
          .foregroundColor(token.secondaryTextColor)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 80)
      .padding(.horizontal, 16)
    }
    .background(token.pageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .environment(\.neChatChildRouteBackAction, nil)
  }

  private var fileLocationText: String {
    if let localPath = preview.file.localPath, !localPath.isEmpty {
      return localPath
    }
    if let url = preview.file.url {
      return url.absoluteString
    }
    return NEChatUIKitSwiftUIBundle.localized("chat_file_unavailable", value: "File unavailable")
  }

}
