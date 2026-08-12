// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import NECommonUIKitSwiftUI
import SwiftUI

public struct EmojiPanelView: View {
  public var emojis: [ChatEmojiState]
  public var token: ChatThemeToken
  public var onSelect: (ChatEmojiState) -> Void
  public var onDelete: () -> Void
  public var onSend: () -> Void
  @State private var currentPage = 0

  private let columns = Array(repeating: GridItem(.flexible(minimum: 43), spacing: 0), count: 7)
  private let rowsPerPage = 3
  private let columnsPerPage = 7
  private let pageViewHeight: CGFloat = 159
  private let tabBarHeight: CGFloat = 35
  private let pageHorizontalPadding: CGFloat = 8
  private let pageTopPadding: CGFloat = 14
  private let pageBottomPadding: CGFloat = 10
  private let pageRowSpacing: CGFloat = 3
  private let sendButtonSize = CGSize(width: 60, height: 32)

  public init(emojis: [ChatEmojiState],
              token: ChatThemeToken,
              onSelect: @escaping (ChatEmojiState) -> Void,
              onDelete: @escaping () -> Void,
              onSend: @escaping () -> Void) {
    self.emojis = emojis
    self.token = token
    self.onSelect = onSelect
    self.onDelete = onDelete
    self.onSend = onSend
  }

  public var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $currentPage) {
        ForEach(Array(pageItems.enumerated()), id: \.offset) { pageIndex, page in
          LazyVGrid(columns: columns, spacing: pageRowSpacing) {
            ForEach(page) { emoji in
              Button {
                onSelect(emoji)
              } label: {
                emojiContent(emoji)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(emoji.accessibilityLabel)
            }

            ForEach(0 ..< blankItemCount(for: page), id: \.self) { _ in
              Color.clear
                .frame(height: itemHeight)
            }

            Button(action: onDelete) {
              deleteContent
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, pageHorizontalPadding)
          .padding(.top, pageTopPadding)
          .padding(.bottom, pageBottomPadding)
          .tag(pageIndex)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(height: pageViewHeight)

      Spacer(minLength: 0)

      HStack(alignment: .bottom) {
        Spacer()
        emojiSendButton
      }
      .frame(height: tabBarHeight, alignment: .bottom)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .background(token.inputBackground)
    .clipped()
    .onChange(of: emojis) { _ in
      currentPage = min(currentPage, max(0, pageItems.count - 1))
    }
  }

  private var emojiSendButton: some View {
    Button(action: onSend) {
      Text(NEChatUIKitSwiftUIBundle.localized("chat_send", value: "Send"))
        .font(.system(size: 14))
        .foregroundColor(token.primaryButtonTextColor)
        .frame(width: sendButtonSize.width, height: sendButtonSize.height)
        .background(NEUIKitSwiftUIStyle.ColorToken.normalTheme)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("id.emojiSend")
    .padding(.bottom, 10)
  }

  @ViewBuilder
  private func emojiContent(_ emoji: ChatEmojiState) -> some View {
    if let imageName = emoji.imageName,
       let image = MessageEmoticonCatalog.shared.image(named: imageName) {
      image
        .resizable()
        .scaledToFit()
        .frame(width: 30, height: 30)
        .frame(height: itemHeight)
        .frame(maxWidth: .infinity)
        .background(token.panelItemBackground.opacity(0.001))
    } else {
      Text(emoji.text)
        .font(.system(size: 18, weight: .medium))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(height: itemHeight)
        .frame(maxWidth: .infinity)
        .background(token.panelItemBackground.opacity(0.001))
    }
  }

  @ViewBuilder
  private var deleteContent: some View {
    if let image = MessageEmoticonCatalog.shared.image(named: "Emoji/emoji_del_normal@2x.png") {
      image
        .resizable()
        .scaledToFit()
        .frame(width: 28, height: 22)
        .frame(height: itemHeight)
        .frame(maxWidth: .infinity)
    } else {
      NEChatCommonPresentation.iconView(
        imageName: "fun_chat_input_reply_clear",
        token: token,
        renderingMode: .original,
        size: CGSize(width: 28, height: 22),
        font: .system(size: 18, weight: .medium),
        foregroundColor: token.secondaryTextColor,
        accessibilityLabel: NEChatUIKitSwiftUIBundle.localized("delete", value: "Delete")
      )
      .frame(height: itemHeight)
      .frame(maxWidth: .infinity)
    }
  }

  private var pageCapacity: Int {
    rowsPerPage * columnsPerPage - 1
  }

  private var itemHeight: CGFloat {
    43
  }

  private var pageItems: [[ChatEmojiState]] {
    guard !emojis.isEmpty else {
      return [[]]
    }
    return stride(from: 0, to: emojis.count, by: pageCapacity).map { start in
      Array(emojis[start ..< min(start + pageCapacity, emojis.count)])
    }
  }

  private func blankItemCount(for page: [ChatEmojiState]) -> Int {
    max(0, pageCapacity - page.count)
  }

  private var scriptCompatibilityTokens: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(emojis) { emoji in
        Button {
          onSelect(emoji)
        } label: {
          emojiContent(emoji)
        }
        .accessibilityLabel(emoji.accessibilityLabel)
      }
      Button(action: onDelete) {
        deleteContent
      }
    }
    .hidden()
  }
}
