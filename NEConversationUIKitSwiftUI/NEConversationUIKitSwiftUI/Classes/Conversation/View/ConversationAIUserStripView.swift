// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

struct ConversationAIUserStripView: View {
  let aiUsers: [ConversationAIUserState]
  let token: ConversationThemeToken
  let onSelect: (ConversationAIUserState) -> Void

  var body: some View {
    if !aiUsers.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: token.styleMode == .fun ? 16 : 12) {
          ForEach(aiUsers) { aiUser in
            Button {
              onSelect(aiUser)
            } label: {
              VStack(spacing: 6) {
                NECommonAvatarView(
                  imageURL: aiUser.avatar.imageURL,
                  initials: aiUser.avatar.initials,
                  size: token.styleMode == .fun ? 48 : 42,
                  cornerRadius: token.styleMode == .fun ? 8 : 21,
                  hashID: aiUser.avatar.hashID
                )
                .neCommonTheme(NEConversationCommonPresentation.commonTheme(for: token))

                Text(aiUser.title)
                  .font(.system(size: 12))
                  .foregroundColor(token.secondaryTextColor)
                  .lineLimit(1)
                  .truncationMode(.tail)
                  .frame(width: 58)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
      }
      .background(token.pageBackground)
    }
  }
}
