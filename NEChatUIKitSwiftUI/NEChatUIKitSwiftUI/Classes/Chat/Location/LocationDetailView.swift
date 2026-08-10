// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct LocationDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.neChatChildRouteBackAction) private var chatRouteBackAction
  public var location: MessageLocationState
  public var token: ChatThemeToken

  public init(location: MessageLocationState,
              token: ChatThemeToken = .normal) {
    self.location = location
    self.token = token
  }

  public var body: some View {
    VStack(spacing: 0) {
      NEChatCommonPresentation.navigationBar(
        title: NEChatUIKitSwiftUIBundle.localized("chat_location_detail", value: "Location Details"),
        token: token,
        backAction: {
          if let chatRouteBackAction {
            chatRouteBackAction()
          } else {
            dismiss()
          }
        }
      )

      Text(NEChatUIKitSwiftUIBundle.localized(
        "chat_map_module_unavailable",
        value: "The map module is not included in this example. Location features are unavailable."
      ))
      .font(.system(size: 15))
      .foregroundColor(token.secondaryTextColor)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .background(token.pageBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .environment(\.neChatChildRouteBackAction, nil)
  }
}
