// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct MoreActionGridView: View {
  public var actions: [ChatMoreActionState]
  public var token: ChatThemeToken
  public var styleMode: ChatStyleMode
  public var onSelect: (ChatMoreActionState) -> Void
  private let funTopInset: CGFloat = 10

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 0),
    count: NEChatUIKitSwiftUIConstants.morePanelColumnCount
  )

  public init(actions: [ChatMoreActionState],
              token: ChatThemeToken,
              styleMode: ChatStyleMode? = nil,
              onSelect: @escaping (ChatMoreActionState) -> Void) {
    self.actions = actions
    self.token = token
    self.styleMode = styleMode ?? token.styleMode
    self.onSelect = onSelect
  }

  public var body: some View {
    let actions = displayedActions
    VStack(spacing: 0) {
      if styleMode == .fun {
        Rectangle()
          .fill(Color(hex: 0xDDDDDD))
          .frame(height: 1)
        Spacer()
          .frame(height: funTopInset - 1)
      }
      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(actions) { action in
          Button {
            onSelect(action)
          } label: {
            VStack(spacing: 0) {
              actionIcon(for: action)

              Text(action.title)
                .font(.system(size: 10))
                .foregroundColor(token.secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .top)
          }
          .disabled(!action.isEnabled)
          .buttonStyle(.plain)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var displayedActions: [ChatMoreActionState] {
    actions.filter { action in
      !(styleMode == .normal && action.id == .photo)
    }
  }

  @ViewBuilder
  private func actionIcon(for action: ChatMoreActionState) -> some View {
    if let imageName = imageName(for: action) {
      NEChatCommonPresentation.iconView(
        imageName: imageName,
        token: token,
        renderingMode: .original,
        isEnabled: action.isEnabled,
        size: CGSize(width: 56, height: 56),
        foregroundColor: token.incomingTextColor,
        accessibilityLabel: action.title
      )
    } else {
      NEChatCommonPresentation.iconView(
        systemImageName: action.systemImageName,
        token: token,
        isEnabled: action.isEnabled,
        size: CGSize(width: 56, height: 56),
        font: .system(size: 22, weight: .medium),
        foregroundColor: token.incomingTextColor,
        accessibilityLabel: action.title
      )
    }
  }

  private func imageName(for action: ChatMoreActionState) -> String? {
    if let imageName = action.imageName, !imageName.isEmpty {
      if action.id == .photo, styleMode == .fun {
        return "fun_chat_photo"
      }
      return imageName
    }

    switch action.id {
    case .photo:
      return styleMode == .fun ? "fun_chat_photo" : "photo"
    case .takePicture:
      return "chat_takePicture"
    case .file:
      return "chat_file"
    case .location:
      return "chat_location"
    case .rtc:
      return "chat_rtc"
    case .translate:
      return "chat_translation"
    }
  }
}
