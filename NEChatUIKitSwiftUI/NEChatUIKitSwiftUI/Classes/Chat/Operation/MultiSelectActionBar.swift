// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import SwiftUI

public struct MultiSelectActionBar: View {
  public var state: MultiSelectState
  public var token: ChatThemeToken
  public var onSingleForward: () -> Void
  public var onMergedForward: () -> Void
  public var onDelete: () -> Void
  public var onCancel: () -> Void

  public init(state: MultiSelectState,
              token: ChatThemeToken,
              onSingleForward: @escaping () -> Void,
              onMergedForward: @escaping () -> Void,
              onDelete: @escaping () -> Void,
              onCancel: @escaping () -> Void) {
    self.state = state
    self.token = token
    self.onSingleForward = onSingleForward
    self.onMergedForward = onMergedForward
    self.onDelete = onDelete
    self.onCancel = onCancel
  }

  public var body: some View {
    HStack(spacing: 56) {
      actionButton(
        title: NEChatUIKitSwiftUIBundle.localized("select_multi", value: "Merge forward"),
        action: onMergedForward,
        selectedImageName: token.styleMode == .fun ? "fun_select_multiForward" : "select_multiForward",
        unselectedImageName: token.styleMode == .fun ? "fun_unselect_multiForward" : "unselect_multiForward"
      )

      actionButton(
        title: NEChatUIKitSwiftUIBundle.localized("select_per_item", value: "Forward one by one"),
        action: onSingleForward,
        selectedImageName: token.styleMode == .fun ? "fun_select_singleForward" : "select_singleForward",
        unselectedImageName: token.styleMode == .fun ? "fun_unselect_singleForward" : "unselect_singleForward"
      )

      actionButton(
        title: NEChatUIKitSwiftUIBundle.localized("operation_delete", value: "Delete"),
        action: onDelete,
        selectedImageName: token.styleMode == .fun ? "fun_select_delete" : "select_delete",
        unselectedImageName: token.styleMode == .fun ? "fun_unselect_delete" : "unselect_delete"
      )
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .frame(height: 100, alignment: .top)
    .background(token.inputBackground)
  }

  private func actionButton(title: String,
                            action: @escaping () -> Void,
                            selectedImageName: String,
                            unselectedImageName: String) -> some View {
    let isEnabled = state.selection.count > 0
    return Button(action: action) {
      VStack(spacing: 3) {
        actionIcon(
          selectedImageName: selectedImageName,
          unselectedImageName: unselectedImageName,
          accessibilityLabel: title,
          isEnabled: isEnabled
        )
        Text(title)
          .font(.system(size: 11))
          .foregroundColor(isEnabled ? token.secondaryTextColor : token.secondaryTextColor.opacity(0.45))
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(height: 28, alignment: .top)
      }
    }
    .disabled(!isEnabled)
    .frame(width: 68)
    .padding(.top, 12)
  }

  @ViewBuilder
  private func actionIcon(selectedImageName: String,
                          unselectedImageName: String,
                          accessibilityLabel: String,
                          isEnabled: Bool) -> some View {
    let imageName = isEnabled ? selectedImageName : unselectedImageName
    if let image = NEChatUIKitSwiftUIBundle.loadImage(imageName) {
      // UIKit resolves these assets across the module and host bundles.
      Image(uiImage: image)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .opacity(isEnabled ? 1 : 0.45)
        .frame(width: 48, height: 48)
        .accessibilityLabel(accessibilityLabel)
    } else {
      NEChatCommonPresentation.iconView(
        imageName: imageName,
        token: token,
        renderingMode: .original,
        isEnabled: isEnabled,
        size: CGSize(width: 48, height: 48),
        accessibilityLabel: accessibilityLabel
      )
    }
  }
}
